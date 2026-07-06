// Deno unit tests for the ocr-bono edge worker. No network, no Storage, no DB —
// Anthropic + deps are mocked. Run: `deno test supabase/functions/ocr-bono`.
import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  applyHallucinationGuard,
  buildUserPrompt,
  callAnthropic,
  type JobContext,
  PermanentError,
  processJob,
  type ProcessDeps,
  resolveConfig,
  TransientError,
  validateBono,
} from "./index.ts";

const noSleep = () => Promise.resolve();

function toolResponse(input: unknown, status = 200): Response {
  const body = status === 200
    ? { content: [{ type: "tool_use", name: "record_bono", input }] }
    : { error: { type: "overloaded" } };
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

const validResult = () => ({
  supplier: { raw_name: "Hodan Beverages", confidence: 0.9 },
  bono_total: 100,
  lines: [
    { raw_text: "BSMTI 25KG", quantity: 4, unit_price: 20, line_total: 80, confidence: 0.9 },
    { raw_text: "SUGAR 50KG", quantity: 1, unit_price: 20, line_total: 20, confidence: 0.8 },
  ],
});

// ---------- validateBono ----------
Deno.test("validateBono accepts a well-formed result", () => {
  assertEquals(validateBono(validResult()).ok, true);
});

Deno.test("validateBono rejects missing/!array lines", () => {
  assertEquals(validateBono({ supplier: {} }).ok, false);
});

Deno.test("validateBono rejects a line missing raw_text / bad confidence", () => {
  const r = validateBono({ supplier: {}, lines: [{ quantity: 1, confidence: 2 }] });
  assertEquals(r.ok, false);
  assert(r.errors.some((e) => e.includes("raw_text")));
  assert(r.errors.some((e) => e.includes("confidence")));
});

Deno.test("validateBono rejects > 50 lines", () => {
  const lines = Array.from({ length: 51 }, () => ({ raw_text: "x", quantity: 1, confidence: 0.5 }));
  assertEquals(validateBono({ supplier: {}, lines }).ok, false);
});

// ---------- applyHallucinationGuard ----------
Deno.test("guard downgrades every line + warns when the sum is off", () => {
  const bad = { ...validResult(), bono_total: 500 }; // sum is 100, way off
  const out = applyHallucinationGuard(bad, 0.1);
  assert(typeof out.result_warning === "string");
  for (const l of out.lines as Array<Record<string, unknown>>) {
    assert((l.confidence as number) <= 0.3);
  }
});

Deno.test("guard leaves a consistent bono untouched", () => {
  const out = applyHallucinationGuard(validResult(), 0.1);
  assertEquals(out.result_warning, undefined);
  assertEquals((out.lines as Array<Record<string, unknown>>)[0].confidence, 0.9);
});

Deno.test("guard is inert when bono_total is null", () => {
  const r = { ...validResult(), bono_total: null };
  const out = applyHallucinationGuard(r, 0.1);
  assertEquals(out.result_warning, undefined);
});

// ---------- buildUserPrompt ----------
Deno.test("buildUserPrompt embeds shop name, suppliers, items", () => {
  const p = buildUserPrompt({ shop_name: "Suuqa", currency_code: "USD", top_suppliers: ["Hodan"], top_items: ["Bariis"] });
  assert(p.includes("Suuqa"));
  assert(p.includes("Hodan"));
  assert(p.includes("Bariis"));
  assert(p.includes("spelling reference only"));
});

// ---------- resolveConfig ----------
Deno.test("resolveConfig falls back to defaults then honors overrides", () => {
  const base = resolveConfig([], null);
  assertEquals(base.model, "claude-haiku-4-5-20251001");
  const over = resolveConfig([{ key: "ocr_model", value: "claude-sonnet-5" }], null);
  assertEquals(over.model, "claude-sonnet-5");
});

// ---------- callAnthropic retry/backoff ----------
Deno.test("callAnthropic returns the tool input on success", async () => {
  const deps = { anthropicFetch: () => Promise.resolve(toolResponse(validResult())), sleep: noSleep };
  const out = await callAnthropic(deps, { system: "s", user: "u", imageBase64: "b", mediaType: "image/jpeg", model: "m", maxTokens: 10, backoff: [1] });
  assertEquals((out.lines as unknown[]).length, 2);
});

Deno.test("callAnthropic retries a 529 then succeeds", async () => {
  let n = 0;
  const deps = {
    anthropicFetch: () => Promise.resolve(n++ === 0 ? toolResponse(null, 529) : toolResponse(validResult())),
    sleep: noSleep,
  };
  const out = await callAnthropic(deps, { system: "s", user: "u", imageBase64: "b", mediaType: "image/jpeg", model: "m", maxTokens: 10, backoff: [1, 4] });
  assertEquals(n, 2);
  assert(Array.isArray(out.lines));
});

Deno.test("callAnthropic throws PermanentError on a 400", async () => {
  const deps = { anthropicFetch: () => Promise.resolve(new Response("bad", { status: 400 })), sleep: noSleep };
  await assertRejects(
    () => callAnthropic(deps, { system: "s", user: "u", imageBase64: "b", mediaType: "image/jpeg", model: "m", maxTokens: 10, backoff: [1] }),
    PermanentError,
  );
});

Deno.test("callAnthropic throws TransientError after exhausting retries", async () => {
  const deps = { anthropicFetch: () => Promise.resolve(toolResponse(null, 529)), sleep: noSleep };
  await assertRejects(
    () => callAnthropic(deps, { system: "s", user: "u", imageBase64: "b", mediaType: "image/jpeg", model: "m", maxTokens: 10, backoff: [1] }),
    TransientError,
  );
});

// ---------- processJob (status machine) ----------
const ctx: JobContext = {
  document_id: "d", shop_id: "s", storage_bucket: "shop-documents", storage_path: "s/documents/d/image.jpg",
  mime_type: "image/jpeg", organization_id: "o", lease_token: "tok", attempts: 1,
};

function baseDeps(over: Partial<ProcessDeps>): { deps: ProcessDeps; completes: Array<Record<string, unknown>> } {
  const completes: Array<Record<string, unknown>> = [];
  const deps: ProcessDeps = {
    beginJob: () => Promise.resolve(ctx),
    readContext: () => Promise.resolve(ctx),
    loadConfig: () => Promise.resolve(resolveConfig([], null)),
    loadPromptContext: () => Promise.resolve({ shop_name: "S" }),
    signImage: () => Promise.resolve({ base64: "b", mediaType: "image/jpeg" }),
    anthropicFetch: () => Promise.resolve(toolResponse(validResult())),
    complete: (job, token, status, result, error, retryable) => {
      completes.push({ job, token, status, result, error, retryable });
      return Promise.resolve(true);
    },
    sleep: noSleep,
    ...over,
  };
  return { deps, completes };
}

Deno.test("processJob success writes a success completion", async () => {
  const { deps, completes } = baseDeps({});
  const out = await processJob(deps, { job_id: "j" });
  assertEquals(out.outcome, "success");
  assertEquals(completes.length, 1);
  assertEquals(completes[0].status, "success");
  assertEquals(completes[0].retryable, false);
});

Deno.test("processJob skips an unclaimable job without completing", async () => {
  const { deps, completes } = baseDeps({ beginJob: () => Promise.resolve(null) });
  const out = await processJob(deps, { job_id: "j" });
  assertEquals(out.outcome, "skipped");
  assertEquals(completes.length, 0);
});

Deno.test("processJob marks a bad schema failed+retryable", async () => {
  const { deps, completes } = baseDeps({ anthropicFetch: () => Promise.resolve(toolResponse({ supplier: {}, lines: "nope" })) });
  const out = await processJob(deps, { job_id: "j" });
  assertEquals(out.outcome, "failed");
  assertEquals(completes[0].status, "failed");
  assertEquals(completes[0].retryable, true);
});

Deno.test("processJob marks a transient AI error failed+retryable", async () => {
  const { deps, completes } = baseDeps({ anthropicFetch: () => Promise.resolve(toolResponse(null, 529)), loadConfig: () => Promise.resolve(resolveConfig([{ key: "ocr_backoff_seconds", value: [0] }], null)) });
  const out = await processJob(deps, { job_id: "j" });
  assertEquals(out.outcome, "failed");
  assertEquals(completes[0].retryable, true);
});

Deno.test("processJob marks a permanent AI error failed+non-retryable", async () => {
  const { deps, completes } = baseDeps({ anthropicFetch: () => Promise.resolve(new Response("bad", { status: 400 })) });
  const out = await processJob(deps, { job_id: "j" });
  assertEquals(out.outcome, "failed");
  assertEquals(completes[0].retryable, false);
});

Deno.test("processJob runs the hallucination guard on the persisted result", async () => {
  const { deps, completes } = baseDeps({ anthropicFetch: () => Promise.resolve(toolResponse({ ...validResult(), bono_total: 999 })) });
  const out = await processJob(deps, { job_id: "j" });
  assertEquals(out.outcome, "success");
  const result = completes[0].result as Record<string, unknown>;
  assert(typeof result.result_warning === "string");
});

Deno.test("processJob uses readContext on the poller path (lease_token present)", async () => {
  let beginCalled = false, readCalled = false;
  const { deps, completes } = baseDeps({
    beginJob: () => { beginCalled = true; return Promise.resolve(ctx); },
    readContext: () => { readCalled = true; return Promise.resolve(ctx); },
  });
  await processJob(deps, { job_id: "j", lease_token: "tok" });
  assertEquals(beginCalled, false);
  assertEquals(readCalled, true);
  assertEquals(completes[0].status, "success");
});
