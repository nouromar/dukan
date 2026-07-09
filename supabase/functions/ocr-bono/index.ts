// supabase/functions/ocr-bono/index.ts
//
// Bono OCR edge worker. Invoked by the pg_net kick (fast path) or the pg_cron
// poller, each carrying { job_id, lease_token? }. It claims the job (or trusts
// the poller's lease), signs a short-lived Storage URL, primes Claude with shop
// context, forces a single `record_bono` tool call, defensively re-validates +
// runs the hallucination guard, then writes the result back through the
// token-guarded _ocr_complete_job RPC.
//
// The pure functions (validateBono, applyHallucinationGuard, buildUserPrompt,
// resolveConfig, callAnthropic, processJob) take injectable deps so they can be
// unit-tested with a mocked Anthropic + fake DB — see index.test.ts. Nothing
// here can run in the SQL harness; the AI + Storage + net paths are smoke-only.

import { encodeBase64 } from "jsr:@std/encoding@1/base64";
// NOTE: supabase-js is imported lazily inside realDeps() (dynamic import) so the
// unit tests can import this module's pure functions without pulling the client's
// npm/realtime dependency graph.

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

// Config defaults — every one is overridable via platform_config (design §6a)
// so scaling / model swaps are config, not a redeploy.
export const CONFIG_DEFAULTS = {
  ocr_model: "claude-haiku-4-5-20251001",
  ocr_model_max_tokens: 4096,
  ocr_hallucination_tolerance: 0.10,
  ocr_backoff_seconds: [1, 4, 12],
  ocr_upstream_timeout_ms: 25000,
  ocr_locale: "so",
};

// The tool schema Claude must fill. Also the shape validateBono re-checks —
// tool_choice constrains the model, but we never trust a single layer.
export const BONO_SCHEMA = {
  type: "object",
  required: ["supplier", "lines"],
  properties: {
    supplier: {
      type: "object",
      properties: {
        raw_name: { type: "string" },
        raw_phone: { type: ["string", "null"] },
        confidence: { type: "number", minimum: 0, maximum: 1 },
      },
    },
    bono_date: { type: ["string", "null"] },
    bono_total: { type: ["number", "null"] },
    lines: {
      type: "array",
      maxItems: 50,
      items: {
        type: "object",
        required: ["raw_text", "quantity", "confidence"],
        properties: {
          raw_text: { type: "string" },
          quantity: { type: "number" },
          unit_price: { type: ["number", "null"] },
          line_total: { type: ["number", "null"] },
          confidence: { type: "number", minimum: 0, maximum: 1 },
          notes: { type: ["string", "null"] },
          // Optional classification (used downstream ONLY for lines that don't
          // match an existing item). Codes MUST come from the provided lists;
          // the suggest RPC re-snaps them and drops anything unknown.
          suggested_category_code: { type: ["string", "null"] },
          suggested_base_unit_code: { type: ["string", "null"] },
          suggested_pack_unit_code: { type: ["string", "null"] },
          suggested_pack_size: { type: ["number", "null"] },
        },
      },
    },
    unparseable_sections: { type: "array", items: { type: "string" } },
  },
} as const;

const SYSTEM_PROMPT =
  `You are extracting line items from a "bono" — a supplier's invoice for a small ` +
  `grocery shop in Somalia. The shop's primary language is Somali; many suppliers ` +
  `write in mixed Somali/English shorthand.\n\n` +
  `The bono MAY be: printed on a thermal receipt printer, laser-printed on plain ` +
  `paper, handwritten in pen, photocopied or stamped and possibly skewed, or mixed ` +
  `Latin / Arabic script.\n\n` +
  `For each line item extract: raw_text (as written, do not translate), quantity, ` +
  `unit_price, line_total, and your confidence 0-1.\n\n` +
  `Be conservative. If a line is illegible, set confidence < 0.5. Do NOT invent ` +
  `items. Do NOT match to specific shop products — that step is downstream. Your job ` +
  `is faithful transcription + light structuring. Put anything you cannot read into ` +
  `unparseable_sections rather than guessing.\n\n` +
  `You MAY also propose, per line, a category and packaging (suggested_category_code, ` +
  `suggested_base_unit_code, suggested_pack_unit_code, suggested_pack_size) to help set ` +
  `up items the shop does not stock yet. Pick codes ONLY from the lists given in the ` +
  `user message; if unsure, use null. NEVER invent a category or unit code.`;

export interface BonoContext {
  shop_name?: string | null;
  currency_code?: string | null;
  top_items?: string[] | null;
  top_suppliers?: string[] | null;
  categories?: Array<{ code: string; name: string }> | null;
  units?: Array<{ code: string; label: string }> | null;
}

export function buildUserPrompt(ctx: BonoContext): string {
  const suppliers = (ctx.top_suppliers ?? []).join(", ");
  const items = (ctx.top_items ?? []).join(", ");
  const categories = (ctx.categories ?? []).map((c) => `${c.code} (${c.name})`).join(", ");
  const units = (ctx.units ?? []).map((u) => `${u.code} (${u.label})`).join(", ");
  return (
    `Shop name: "${ctx.shop_name ?? ""}"\n` +
    `Currency: ${ctx.currency_code ?? ""}\n` +
    `Known suppliers in this shop (you may see one of these in the header):\n  ${suppliers}\n` +
    `Common items in this shop's catalog (for spelling reference only, do NOT ` +
    `force-match to these):\n  ${items}\n` +
    `Category codes (choose suggested_category_code ONLY from these, else null):\n  ${categories}\n` +
    `Unit codes (choose suggested_base_unit_code / suggested_pack_unit_code ONLY from ` +
    `these, else null):\n  ${units}\n` +
    `For each line, suggested_base_unit_code is the smallest unit the item is counted ` +
    `in, suggested_pack_unit_code is the pack it's received in, and suggested_pack_size ` +
    `is how many base units per pack (e.g. 25 for a 25 kg bag).`
  );
}

// Structural re-validation of the tool output. Focused, not a full JSON-schema
// engine — just the invariants the downstream matching RPC relies on.
export function validateBono(obj: unknown): { ok: boolean; errors: string[] } {
  const errors: string[] = [];
  const o = obj as Record<string, unknown> | null;
  if (!o || typeof o !== "object") return { ok: false, errors: ["not an object"] };
  if (!o.supplier || typeof o.supplier !== "object") errors.push("supplier missing");
  if (!Array.isArray(o.lines)) {
    errors.push("lines is not an array");
  } else {
    if (o.lines.length > 50) errors.push("lines exceeds 50");
    o.lines.forEach((l: unknown, i: number) => {
      const line = l as Record<string, unknown>;
      if (!line || typeof line !== "object") { errors.push(`line ${i} not an object`); return; }
      if (typeof line.raw_text !== "string" || line.raw_text.length === 0) errors.push(`line ${i} raw_text`);
      if (typeof line.quantity !== "number") errors.push(`line ${i} quantity`);
      if (typeof line.confidence !== "number" || line.confidence < 0 || line.confidence > 1) errors.push(`line ${i} confidence`);
    });
  }
  return { ok: errors.length === 0, errors };
}

// Hallucination guard (design §6.2 step 7): if the line totals don't add up to
// the stated bono_total within tolerance, the "invented line pads the sum" shape
// is present — stamp a warning and downgrade EVERY line so the review sheet
// leaves them unchecked. Returns a new object; never mutates the input.
export function applyHallucinationGuard(
  result: Record<string, unknown>,
  tolerance: number,
): Record<string, unknown> {
  const total = result.bono_total;
  const lines = result.lines;
  if (typeof total === "number" && total > 0 && Array.isArray(lines)) {
    const sum = lines.reduce(
      (a: number, l: Record<string, unknown>) => a + (typeof l.line_total === "number" ? l.line_total : 0),
      0,
    );
    if (Math.abs(sum - total) / total > tolerance) {
      return {
        ...result,
        result_warning: `line total sum ${sum} vs bono_total ${total} exceeds ${Math.round(tolerance * 100)}% tolerance; all lines downgraded`,
        lines: lines.map((l: Record<string, unknown>) => ({
          ...l,
          confidence: Math.min(typeof l.confidence === "number" ? l.confidence : 0, 0.3),
        })),
      };
    }
  }
  return result;
}

export function resolveConfig(rows: Array<{ key: string; value: unknown }>, orgId: string | null) {
  // rows may hold org-scoped + platform-default entries; prefer org over default.
  const byKey = new Map<string, { def?: unknown; org?: unknown }>();
  for (const r of rows) {
    const slot = byKey.get(r.key) ?? {};
    // value shape from a platform_config select includes org_id; but we pass the
    // already-scoped merged rows here. Keep it simple: last write wins per key.
    slot.def = r.value;
    byKey.set(r.key, slot);
  }
  const get = <T>(k: keyof typeof CONFIG_DEFAULTS): T => {
    const hit = byKey.get(k as string);
    return (hit?.org ?? hit?.def ?? CONFIG_DEFAULTS[k]) as T;
  };
  return {
    model: get<string>("ocr_model"),
    maxTokens: Number(get<number>("ocr_model_max_tokens")),
    tolerance: Number(get<number>("ocr_hallucination_tolerance")),
    backoff: get<number[]>("ocr_backoff_seconds"),
    timeoutMs: Number(get<number>("ocr_upstream_timeout_ms")),
    locale: get<string>("ocr_locale"),
  };
}

export class TransientError extends Error {}
export class PermanentError extends Error {}

// Call Anthropic with tool_choice forcing record_bono. Retries 429/503/529 +
// network/timeout with configured backoff; a non-retryable HTTP error throws
// PermanentError. Returns the `record_bono` tool input.
export async function callAnthropic(
  deps: { anthropicFetch: (body: unknown) => Promise<Response>; sleep: (ms: number) => Promise<void>; log?: (...a: unknown[]) => void },
  args: { system: string; user: string; imageBase64: string; mediaType: string; model: string; maxTokens: number; backoff: number[] },
): Promise<Record<string, unknown>> {
  const body = {
    model: args.model,
    max_tokens: args.maxTokens,
    system: args.system,
    tools: [{ name: "record_bono", description: "Record the transcribed bono line items.", input_schema: BONO_SCHEMA }],
    tool_choice: { type: "tool", name: "record_bono" },
    messages: [
      {
        role: "user",
        content: [
          { type: "image", source: { type: "base64", media_type: args.mediaType, data: args.imageBase64 } },
          { type: "text", text: args.user },
        ],
      },
    ],
  };

  const maxTries = args.backoff.length + 1;
  let lastErr: unknown;
  for (let attempt = 0; attempt < maxTries; attempt++) {
    if (attempt > 0) await deps.sleep(args.backoff[attempt - 1] * 1000);
    try {
      const resp = await deps.anthropicFetch(body);
      if (resp.status === 429 || resp.status === 503 || resp.status === 529) {
        lastErr = new TransientError(`anthropic ${resp.status}`);
        continue;
      }
      if (!resp.ok) {
        const text = await resp.text().catch(() => "");
        throw new PermanentError(`anthropic ${resp.status}: ${text.slice(0, 200)}`);
      }
      const json = await resp.json();
      const block = (json.content ?? []).find(
        (c: Record<string, unknown>) => c.type === "tool_use" && c.name === "record_bono",
      );
      if (!block) throw new PermanentError("no record_bono tool_use in response");
      return block.input as Record<string, unknown>;
    } catch (e) {
      if (e instanceof PermanentError) throw e;
      lastErr = e; // network / abort / TransientError → retry
    }
  }
  throw new TransientError(`anthropic exhausted retries: ${String(lastErr)}`);
}

export interface JobContext {
  document_id: string;
  shop_id: string;
  storage_bucket: string;
  storage_path: string;
  mime_type: string;
  organization_id: string | null;
  lease_token: string;
  attempts: number;
}

export interface ProcessDeps {
  beginJob: (jobId: string) => Promise<JobContext | null>;
  readContext: (jobId: string, leaseToken: string) => Promise<JobContext | null>;
  loadConfig: (orgId: string | null) => Promise<ReturnType<typeof resolveConfig>>;
  loadPromptContext: (shopId: string, locale: string) => Promise<BonoContext>;
  signImage: (bucket: string, path: string) => Promise<{ base64: string; mediaType: string }>;
  anthropicFetch: (body: unknown) => Promise<Response>;
  complete: (jobId: string, token: string, status: "success" | "failed", result: Record<string, unknown> | null, error: string | null, retryable: boolean) => Promise<boolean>;
  sleep: (ms: number) => Promise<void>;
  log?: (...a: unknown[]) => void;
}

// Orchestrates one job end-to-end. Returns an outcome tag for observability/tests.
export async function processJob(
  deps: ProcessDeps,
  payload: { job_id: string; lease_token?: string | null },
): Promise<{ outcome: "success" | "failed" | "skipped"; error?: string }> {
  if (!payload.job_id) return { outcome: "skipped", error: "no job_id" };

  // Claim (fast path) or trust the poller's lease.
  const ctx = payload.lease_token
    ? await deps.readContext(payload.job_id, payload.lease_token)
    : await deps.beginJob(payload.job_id);
  if (!ctx) return { outcome: "skipped", error: "not claimable" };

  const token = ctx.lease_token;
  try {
    const config = await deps.loadConfig(ctx.organization_id);
    const [img, promptCtx] = await Promise.all([
      deps.signImage(ctx.storage_bucket, ctx.storage_path),
      deps.loadPromptContext(ctx.shop_id, config.locale),
    ]);

    const raw = await callAnthropic(deps, {
      system: SYSTEM_PROMPT,
      user: buildUserPrompt(promptCtx),
      imageBase64: img.base64,
      mediaType: img.mediaType,
      model: config.model,
      maxTokens: config.maxTokens,
      backoff: config.backoff,
    });

    const check = validateBono(raw);
    if (!check.ok) {
      // Model produced a bad shape — retryable up to the attempt cap.
      await deps.complete(payload.job_id, token, "failed", null, `schema: ${check.errors.join("; ")}`, true);
      return { outcome: "failed", error: check.errors.join("; ") };
    }

    const guarded = applyHallucinationGuard(raw, config.tolerance);
    await deps.complete(payload.job_id, token, "success", guarded, null, false);
    return { outcome: "success" };
  } catch (e) {
    const retryable = e instanceof TransientError;
    await deps.complete(payload.job_id, token, "failed", null, String(e instanceof Error ? e.message : e), retryable);
    return { outcome: "failed", error: String(e) };
  }
}

// ---------------------------------------------------------------------------
// Real-deps handler. verify_jwt is off (see config.toml) — auth is the shared
// dispatch token the pg_net kick carries in the Authorization header.
// ---------------------------------------------------------------------------
async function realDeps(): Promise<ProcessDeps> {
  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY")!;
  const { createClient } = await import("jsr:@supabase/supabase-js@2");
  const supabase = createClient(url, serviceKey, { auth: { persistSession: false } });

  return {
    beginJob: async (jobId) => {
      const { data, error } = await supabase.rpc("_ocr_begin_job", { p_job_id: jobId });
      if (error) throw new PermanentError(`begin_job: ${error.message}`);
      const row = Array.isArray(data) ? data[0] : data;
      return row ? { ...row, attempts: 0 } as JobContext : null;
    },
    readContext: async (jobId, leaseToken) => {
      const { data: job } = await supabase.from("ocr_job")
        .select("status,lease_token,shop_id,document_id,attempts").eq("id", jobId).maybeSingle();
      if (!job || job.status !== "processing" || job.lease_token !== leaseToken) return null;
      const { data: doc } = await supabase.from("document")
        .select("storage_bucket,storage_path,mime_type").eq("id", job.document_id).maybeSingle();
      const { data: shop } = await supabase.from("shop")
        .select("organization_id").eq("id", job.shop_id).maybeSingle();
      if (!doc) return null;
      return {
        document_id: job.document_id, shop_id: job.shop_id,
        storage_bucket: doc.storage_bucket, storage_path: doc.storage_path, mime_type: doc.mime_type,
        organization_id: shop?.organization_id ?? null, lease_token: leaseToken, attempts: job.attempts,
      };
    },
    loadConfig: async (orgId) => {
      const { data } = await supabase.from("platform_config")
        .select("key,value,org_id")
        .in("key", Object.keys(CONFIG_DEFAULTS))
        .or(`org_id.is.null,org_id.eq.${orgId ?? "00000000-0000-0000-0000-000000000000"}`);
      // Prefer org-scoped rows over platform defaults.
      const merged = new Map<string, unknown>();
      for (const r of data ?? []) if (r.org_id === null && !merged.has(r.key)) merged.set(r.key, r.value);
      for (const r of data ?? []) if (r.org_id !== null) merged.set(r.key, r.value);
      return resolveConfig([...merged].map(([key, value]) => ({ key, value })), orgId);
    },
    loadPromptContext: async (shopId, locale) => {
      const { data } = await supabase.rpc("ocr_bono_context", { p_shop_id: shopId, p_locale: locale });
      return (data ?? {}) as BonoContext;
    },
    signImage: async (bucket, path) => {
      const { data, error } = await supabase.storage.from(bucket).createSignedUrl(path, 60);
      if (error || !data) throw new PermanentError(`sign url: ${error?.message}`);
      const resp = await fetch(data.signedUrl);
      if (!resp.ok) throw new PermanentError(`image fetch ${resp.status}`);
      const bytes = new Uint8Array(await resp.arrayBuffer());
      const mediaType = resp.headers.get("content-type") ?? "image/jpeg";
      return { base64: encodeBase64(bytes), mediaType };
    },
    anthropicFetch: (body) => {
      const ctrl = new AbortController();
      const t = setTimeout(() => ctrl.abort(), Number(CONFIG_DEFAULTS.ocr_upstream_timeout_ms));
      return fetch(ANTHROPIC_URL, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-api-key": anthropicKey,
          "anthropic-version": ANTHROPIC_VERSION,
        },
        body: JSON.stringify(body),
        signal: ctrl.signal,
      }).finally(() => clearTimeout(t));
    },
    complete: async (jobId, token, status, result, error, retryable) => {
      const { data, error: e } = await supabase.rpc("_ocr_complete_job", {
        p_job_id: jobId, p_lease_token: token, p_status: status,
        p_result: result, p_error: error, p_retryable: retryable,
      });
      if (e) throw new PermanentError(`complete_job: ${e.message}`);
      return data === true;
    },
    sleep: (ms) => new Promise((r) => setTimeout(r, ms)),
    log: console.log,
  };
}

export async function handleRequest(req: Request): Promise<Response> {
  // Shared-secret auth: the kick carries the dispatch token, not a JWT.
  const expected = Deno.env.get("OCR_DISPATCH_TOKEN");
  const auth = req.headers.get("authorization") ?? "";
  if (expected && auth !== `Bearer ${expected}`) {
    return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401 });
  }
  let payload: { job_id?: string; lease_token?: string | null };
  try {
    payload = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "bad json" }), { status: 400 });
  }
  if (!payload.job_id) {
    return new Response(JSON.stringify({ error: "job_id required" }), { status: 400 });
  }
  const result = await processJob(await realDeps(), { job_id: payload.job_id, lease_token: payload.lease_token ?? null });
  return new Response(JSON.stringify(result), {
    status: result.outcome === "failed" ? 502 : 200,
    headers: { "content-type": "application/json" },
  });
}

// Only bind the server when run as the entrypoint — importing this module for
// unit tests must not start a listener.
if (import.meta.main) {
  Deno.serve(handleRequest);
}
