// supabase/functions/whatsapp-otp-hook/index.ts
//
// Supabase Auth "Send SMS Hook". GoTrue owns the OTP: it generates the code,
// stores it, and verifies it natively on verifyOTP — so sessions / refresh
// tokens are 100% standard and nothing bespoke mints them. This hook only
// *delivers* the code, over WhatsApp Cloud API instead of an SMS provider.
//
// Flow:  signInWithOtp(phone) → GoTrue → POST here { user, sms:{otp} }
//        → we send the `dukan_otp` authentication template to the number.
//        verifyOTP(phone, code) stays entirely inside GoTrue.
//
// The local [auth.sms.test_otp] fixture short-circuits inside GoTrue *before*
// this hook is ever called, so `+252612345678 → 123456` keeps working with no
// WhatsApp round-trip. BYPASS_NUMBERS is a second, defensive guard for anyone
// who wires the hook up locally.
//
// Requests are signed by GoTrue with the Standard Webhooks scheme; we verify
// the HMAC before trusting the body. The pure functions (verifySignature,
// parseHookPayload, buildWhatsappPayload, handleRequest) take injectable deps
// so they unit-test with no network — see index.test.ts.

import { decodeBase64, encodeBase64 } from "jsr:@std/encoding@1/base64";

const GRAPH_HOST = "https://graph.facebook.com";

// ---------------------------------------------------------------------------
// Standard Webhooks signature (https://www.standardwebhooks.com/). Supabase
// hands you a secret shaped `v1,whsec_<base64>`; the signed content is
// `${id}.${timestamp}.${body}` and the header carries space-separated
// `v1,<base64sig>` entries. We also enforce a replay window on the timestamp.
// ---------------------------------------------------------------------------
export interface WebhookHeaders {
  id: string | null;
  timestamp: string | null;
  signature: string | null;
}

function timingSafeEqualStr(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export async function verifySignature(
  secret: string,
  headers: WebhookHeaders,
  body: string,
  opts?: { now?: number; toleranceSec?: number },
): Promise<boolean> {
  if (!headers.id || !headers.timestamp || !headers.signature) return false;

  // Replay guard: reject stale/future-dated timestamps.
  const tolerance = opts?.toleranceSec ?? 300;
  const nowSec = Math.floor((opts?.now ?? Date.now()) / 1000);
  const ts = Number(headers.timestamp);
  if (!Number.isFinite(ts) || Math.abs(nowSec - ts) > tolerance) return false;

  // Accept `v1,whsec_<b64>`, `whsec_<b64>`, or a bare base64 key.
  const keyB64 = secret.replace(/^v1,/, "").replace(/^whsec_/, "");
  let keyBytes: Uint8Array;
  try {
    keyBytes = decodeBase64(keyB64);
  } catch {
    return false;
  }
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    keyBytes as BufferSource,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signed = `${headers.id}.${headers.timestamp}.${body}`;
  const mac = await crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(signed) as BufferSource);
  const expected = encodeBase64(new Uint8Array(mac));

  // The header may list several signatures (key rotation); any match passes.
  const provided = headers.signature
    .split(" ")
    .map((p) => (p.includes(",") ? p.slice(p.indexOf(",") + 1) : p));
  return provided.some((sig) => timingSafeEqualStr(sig, expected));
}

// ---------------------------------------------------------------------------
// Payload + WhatsApp message shaping (pure).
// ---------------------------------------------------------------------------
export function parseHookPayload(raw: string): { phone: string; otp: string } {
  let j: Record<string, unknown>;
  try {
    j = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    throw new Error("body is not valid JSON");
  }
  const user = j.user as Record<string, unknown> | undefined;
  const sms = j.sms as Record<string, unknown> | undefined;
  const phone = user?.phone;
  const otp = sms?.otp;
  if (typeof phone !== "string" || phone.length === 0) throw new Error("missing user.phone");
  if (typeof otp !== "string" || otp.length === 0) throw new Error("missing sms.otp");
  return { phone, otp };
}

// WhatsApp authentication templates require the code in BOTH the body and the
// copy-code (url) button — same value in each — or the API rejects the send.
export function buildWhatsappPayload(args: {
  to: string;
  template: string;
  lang: string;
  otp: string;
}): Record<string, unknown> {
  return {
    messaging_product: "whatsapp",
    to: args.to.replace(/^\+/, ""), // Graph wants E.164 digits, no leading '+'
    type: "template",
    template: {
      name: args.template,
      language: { code: args.lang },
      components: [
        { type: "body", parameters: [{ type: "text", text: args.otp }] },
        {
          type: "button",
          sub_type: "url",
          index: "0",
          parameters: [{ type: "text", text: args.otp }],
        },
      ],
    },
  };
}

// ---------------------------------------------------------------------------
// Orchestration with injectable deps.
// ---------------------------------------------------------------------------
export interface HookConfig {
  template: string;
  lang: string;
  hookSecret: string | null;
  bypass: Set<string>; // numbers (digits, no '+') to ack without sending
}

export interface HookDeps {
  config: HookConfig;
  verify: (secret: string, headers: WebhookHeaders, body: string) => Promise<boolean>;
  send: (payload: Record<string, unknown>) => Promise<unknown>;
  log?: (...a: unknown[]) => void;
}

function json(obj: unknown, status: number): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json" },
  });
}

export async function handleRequest(req: Request, deps: HookDeps): Promise<Response> {
  const raw = await req.text();

  if (deps.config.hookSecret) {
    const ok = await deps.verify(deps.config.hookSecret, {
      id: req.headers.get("webhook-id"),
      timestamp: req.headers.get("webhook-timestamp"),
      signature: req.headers.get("webhook-signature"),
    }, raw);
    if (!ok) return json({ error: { http_code: 401, message: "invalid signature" } }, 401);
  }

  let phone: string, otp: string;
  try {
    ({ phone, otp } = parseHookPayload(raw));
  } catch (e) {
    return json({ error: { http_code: 400, message: String(e instanceof Error ? e.message : e) } }, 400);
  }

  const to = phone.replace(/^\+/, "");
  if (deps.config.bypass.has(to)) {
    deps.log?.("bypass number, not sending WhatsApp:", to);
    return json({}, 200);
  }

  try {
    await deps.send(buildWhatsappPayload({ to, template: deps.config.template, lang: deps.config.lang, otp }));
    return json({}, 200);
  } catch (e) {
    // Non-2xx tells GoTrue delivery failed; it surfaces a generic error to the
    // client and the user can retry. We log the detail server-side only.
    deps.log?.("whatsapp send failed:", String(e instanceof Error ? e.message : e));
    return json({ error: { http_code: 502, message: "otp delivery failed" } }, 502);
  }
}

// ---------------------------------------------------------------------------
// Real deps: build the WhatsApp sender + config from env. Secrets are set via
// `supabase secrets set`, never committed. verify_jwt is off (config.toml) —
// auth here is the Standard Webhooks signature, not a Supabase JWT.
// ---------------------------------------------------------------------------
function realDeps(): HookDeps {
  const token = Deno.env.get("WHATSAPP_TOKEN") ?? "";
  const phoneNumberId = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID") ?? "";
  const version = Deno.env.get("WHATSAPP_GRAPH_VERSION") ?? "v22.0";
  const template = Deno.env.get("WHATSAPP_OTP_TEMPLATE") ?? "dukan_otp";
  const lang = Deno.env.get("WHATSAPP_OTP_LANG") ?? "en_US";
  const hookSecret = Deno.env.get("SEND_SMS_HOOK_SECRET") || null;
  const bypass = new Set(
    (Deno.env.get("SEND_SMS_HOOK_BYPASS_NUMBERS") ?? "")
      .split(",")
      .map((s) => s.trim().replace(/^\+/, ""))
      .filter((s) => s.length > 0),
  );

  return {
    config: { template, lang, hookSecret, bypass },
    verify: verifySignature,
    send: async (payload) => {
      const resp = await fetch(`${GRAPH_HOST}/${version}/${phoneNumberId}/messages`, {
        method: "POST",
        headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
        body: JSON.stringify(payload),
      });
      if (!resp.ok) {
        const text = await resp.text().catch(() => "");
        throw new Error(`whatsapp ${resp.status}: ${text.slice(0, 300)}`);
      }
      return await resp.json();
    },
    log: console.log,
  };
}

if (import.meta.main) {
  const deps = realDeps();
  Deno.serve((req) => handleRequest(req, deps));
}
