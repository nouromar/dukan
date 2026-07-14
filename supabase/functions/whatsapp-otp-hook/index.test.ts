// Deno unit tests for the whatsapp-otp-hook edge function. No network — the
// WhatsApp sender and (where useful) the verifier are mocked; the real HMAC is
// exercised against a locally-computed signature.
// Run: `deno test supabase/functions/whatsapp-otp-hook`.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { encodeBase64 } from "jsr:@std/encoding@1/base64";
import {
  buildWhatsappPayload,
  handleRequest,
  type HookDeps,
  parseHookPayload,
  verifySignature,
} from "./index.ts";

const SECRET = "v1,whsec_" + encodeBase64(new TextEncoder().encode("super-secret-key-abc"));

function hookBody(phone = "252612345678", otp = "123456"): string {
  return JSON.stringify({ user: { id: "u1", phone }, sms: { otp } });
}

// Produce a valid Standard Webhooks signature for `body` using the same scheme
// the function verifies, so we test the real crypto path end-to-end.
async function sign(id: string, ts: string, body: string): Promise<string> {
  const keyB64 = SECRET.replace(/^v1,/, "").replace(/^whsec_/, "");
  const key = await crypto.subtle.importKey(
    "raw",
    Uint8Array.from(atob(keyB64), (c) => c.charCodeAt(0)) as BufferSource,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${id}.${ts}.${body}`) as BufferSource);
  return "v1," + encodeBase64(new Uint8Array(mac));
}

// ---------- parseHookPayload ----------
Deno.test("parseHookPayload extracts phone + otp", () => {
  assertEquals(parseHookPayload(hookBody()), { phone: "252612345678", otp: "123456" });
});

Deno.test("parseHookPayload rejects missing fields / bad JSON", () => {
  for (const bad of ['{"user":{},"sms":{"otp":"1"}}', '{"user":{"phone":"1"}}', "not json"]) {
    let threw = false;
    try { parseHookPayload(bad); } catch { threw = true; }
    assert(threw, `should have thrown for: ${bad}`);
  }
});

// ---------- buildWhatsappPayload ----------
Deno.test("buildWhatsappPayload carries the code in body + button and strips '+'", () => {
  const p = buildWhatsappPayload({ to: "+252612345678", template: "dukan_otp", lang: "en_US", otp: "987654" });
  assertEquals(p.to, "252612345678");
  const t = p.template as Record<string, unknown>;
  assertEquals(t.name, "dukan_otp");
  assertEquals((t.language as Record<string, unknown>).code, "en_US");
  const comps = t.components as Array<Record<string, unknown>>;
  const body = comps.find((c) => c.type === "body")!;
  const button = comps.find((c) => c.type === "button")!;
  assertEquals((body.parameters as Array<Record<string, string>>)[0].text, "987654");
  assertEquals(button.sub_type, "url");
  assertEquals((button.parameters as Array<Record<string, string>>)[0].text, "987654");
});

// ---------- verifySignature ----------
Deno.test("verifySignature accepts a valid signature", async () => {
  const body = hookBody();
  const id = "msg_1";
  const ts = String(Math.floor(Date.now() / 1000));
  const sig = await sign(id, ts, body);
  assertEquals(await verifySignature(SECRET, { id, timestamp: ts, signature: sig }, body), true);
});

Deno.test("verifySignature rejects a tampered body", async () => {
  const id = "msg_1";
  const ts = String(Math.floor(Date.now() / 1000));
  const sig = await sign(id, ts, hookBody());
  const ok = await verifySignature(SECRET, { id, timestamp: ts, signature: sig }, hookBody("252700000000", "999999"));
  assertEquals(ok, false);
});

Deno.test("verifySignature rejects a stale timestamp (replay window)", async () => {
  const body = hookBody();
  const id = "msg_1";
  const ts = String(Math.floor(Date.now() / 1000) - 3600); // 1h old
  const sig = await sign(id, ts, body);
  assertEquals(await verifySignature(SECRET, { id, timestamp: ts, signature: sig }, body), false);
});

Deno.test("verifySignature rejects missing headers", async () => {
  assertEquals(await verifySignature(SECRET, { id: null, timestamp: null, signature: null }, hookBody()), false);
});

// ---------- handleRequest ----------
function depsWith(overrides: Partial<HookDeps> = {}): { deps: HookDeps; sent: Array<Record<string, unknown>> } {
  const sent: Array<Record<string, unknown>> = [];
  const deps: HookDeps = {
    config: { template: "dukan_otp", lang: "en_US", hookSecret: null, bypass: new Set() },
    verify: () => Promise.resolve(true),
    send: (p) => { sent.push(p); return Promise.resolve({ messages: [{ id: "wamid.X" }] }); },
    ...overrides,
  };
  return { deps, sent };
}

function req(body: string): Request {
  return new Request("http://localhost/whatsapp-otp-hook", { method: "POST", body });
}

Deno.test("handleRequest sends the OTP and returns 200", async () => {
  const { deps, sent } = depsWith();
  const resp = await handleRequest(req(hookBody()), deps);
  assertEquals(resp.status, 200);
  assertEquals(sent.length, 1);
  assertEquals((sent[0].template as Record<string, unknown>).name, "dukan_otp");
});

Deno.test("handleRequest bypass number acks without sending", async () => {
  const { deps, sent } = depsWith({
    config: { template: "dukan_otp", lang: "en_US", hookSecret: null, bypass: new Set(["252612345678"]) },
  });
  const resp = await handleRequest(req(hookBody()), deps);
  assertEquals(resp.status, 200);
  assertEquals(sent.length, 0);
});

Deno.test("handleRequest returns 401 on invalid signature", async () => {
  const { deps, sent } = depsWith({
    config: { template: "dukan_otp", lang: "en_US", hookSecret: SECRET, bypass: new Set() },
    verify: () => Promise.resolve(false),
  });
  const resp = await handleRequest(req(hookBody()), deps);
  assertEquals(resp.status, 401);
  assertEquals(sent.length, 0);
});

Deno.test("handleRequest returns 502 when WhatsApp send fails", async () => {
  const { deps } = depsWith({ send: () => Promise.reject(new Error("whatsapp 400: bad")) });
  const resp = await handleRequest(req(hookBody()), deps);
  assertEquals(resp.status, 502);
});

Deno.test("handleRequest returns 400 on malformed payload", async () => {
  const { deps } = depsWith();
  const resp = await handleRequest(req('{"user":{}}'), deps);
  assertEquals(resp.status, 400);
});
