# WhatsApp OTP login (setup + operations)

DukanPro delivers the phone-login one-time code over the **WhatsApp Cloud API**
instead of SMS. The shopkeeper's world already lives in WhatsApp, and it avoids
SMS deliverability/cost problems across Somali networks.

## How it fits together — nothing bespoke

We use Supabase Auth's **Send SMS Hook**, not a hand-rolled OTP system:

```
app: signInWithOtp(phone, channel: sms)
      → GoTrue GENERATES the code, stores it, applies rate limits
      → GoTrue POSTs { user:{phone}, sms:{otp} } to our hook  (Standard Webhooks signed)
      → whatsapp-otp-hook sends the `dukan_otp` auth template via Graph API
app: verifyOTP(phone, code)
      → GoTrue VERIFIES natively → issues a real Supabase session + refresh token
```

**GoTrue owns generation and verification.** The Edge Function only *delivers*.
That means sessions, refresh, rate limiting, and expiry are all standard — there
is no custom JWT minting and no OTP table of our own.

- Function: `supabase/functions/whatsapp-otp-hook/index.ts` (+ `index.test.ts`).
- Config: `[functions.whatsapp-otp-hook]` and the `[auth.hook.send_sms]` template
  in `supabase/config.toml`.
- App: **no change** — it already calls `signInWithOtp` / `verifyOTP` on
  `OtpChannel.sms` (`lib/auth/auth_controller.dart`).

## Local development — unchanged

`[auth.sms.test_otp]` pins `+252612345678 → 123456`. GoTrue short-circuits that
number **before** the hook fires, so local login needs no WhatsApp round-trip and
the hook stays disabled locally. (`SEND_SMS_HOOK_BYPASS_NUMBERS` is a second,
defensive guard if you do wire the hook up locally.)

## One-time Meta setup

1. **App**: a Meta app of type **Business** with the **WhatsApp** product added,
   connected to a **verified** Business portfolio. (A test number works for dev;
   a registered real number is required for production.)
2. **Auth template** — WhatsApp Manager → **Message templates → Create**:
   - Category **Authentication**; it builds the body + a **Copy code** button.
   - Name it **`dukan_otp`**, language **`en_US`** (add `so` later as a second
     language variant under the same name).
   - Submit — authentication templates usually approve within minutes.
3. **System User token (permanent)** — Business Settings → **Users → System
   Users** → assign the **app** and the **WABA** as assets → generate a token
   with `whatsapp_business_messaging` + `whatsapp_business_management`. This is
   `WHATSAPP_TOKEN` (the API-Setup page token is temporary — do not use it in
   the backend).

## Secrets (never committed)

Set on the deployed project:

```bash
supabase secrets set \
  WHATSAPP_TOKEN='<system-user-token>' \
  WHATSAPP_PHONE_NUMBER_ID='<phone-number-id>' \
  WHATSAPP_OTP_TEMPLATE='dukan_otp' \
  WHATSAPP_OTP_LANG='en_US' \
  WHATSAPP_GRAPH_VERSION='v22.0' \
  SEND_SMS_HOOK_SECRET='v1,whsec_...'   # from the dashboard hook (below)
```

Defaults if unset: template `dukan_otp`, lang `en_US`, version `v22.0`. If
`SEND_SMS_HOOK_SECRET` is unset the function skips signature verification —
**always set it in production.**

## Deploy + enable

```bash
supabase functions deploy whatsapp-otp-hook
```

Then **Dashboard → Authentication → Hooks → Send SMS**: enable, point it at the
deployed `whatsapp-otp-hook` function URL, and copy the generated signing secret
(`v1,whsec_...`) into `SEND_SMS_HOOK_SECRET` above. GoTrue now routes every
phone OTP through the hook.

## Verify end-to-end

1. Add your number as a **verified recipient** (dev/test number) or use the
   registered production number.
2. In the app, request a code for that number → a WhatsApp message with the code
   arrives → enter it → you get a session.
3. Failures are logged server-side; the user sees a generic "could not send"
   and can retry.

## Notes / gotchas

- **Template language must match exactly.** `WHATSAPP_OTP_LANG` has to equal an
  approved language of `dukan_otp` (`en_US` ≠ `en`).
- **The code appears twice in the send** — body parameter + copy-code button
  parameter — WhatsApp rejects auth templates otherwise. `buildWhatsappPayload`
  handles this.
- **Test number limits**: can only message pre-verified recipients; production
  needs the real number registered and the display name approved.
- **Tests**: `deno test supabase/functions/whatsapp-otp-hook` (no network).
