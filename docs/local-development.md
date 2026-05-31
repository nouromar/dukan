# Local development

Use the Supabase CLI local stack for app testing. It runs Postgres, Auth, REST, Storage, Studio, and related services in Docker so Flutter can exercise the same RLS/Auth paths used in production.

## Start Supabase

```bash
cd /Users/nouromar/dukan
supabase start
supabase db reset
```

Useful local URLs:

- Studio: <http://127.0.0.1:54323>
- API: <http://127.0.0.1:54321>
- Database: `postgresql://postgres:postgres@127.0.0.1:54322/postgres`

Print local keys when needed:

```bash
supabase status -o env
```

## Local phone OTP

Local Auth is configured for fixed SMS OTP testing:

- Phone: `+252612345678`
- OTP code: `123456`

The SMS provider values in `supabase/config.toml` are fake local-only Twilio settings. They exist only so Supabase Auth enables phone login while the fixed test OTP bypasses real SMS/WhatsApp delivery.

## Production notes

- The fake Twilio values and fixed `auth.sms.test_otp` entry are local-development only. Production must use the Meta/WhatsApp OTP delivery path or real provider-backed values; do not deploy the placeholder Twilio credentials as production secrets.
- The `0015_rls_storage.sql` migration intentionally does **not** run `alter table storage.objects enable row level security`. Supabase owns and manages the Storage table in both local and hosted projects. This is not a local-only workaround to undo for production; the standalone Docker migration test harness enables RLS only because it creates a mock `storage.objects` table itself.

## Run Flutter against local Supabase

```bash
cd /Users/nouromar/dukan/app/dukan

flutter run \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=<ANON_KEY from supabase status -o env>
```

## Stop Supabase

```bash
cd /Users/nouromar/dukan
supabase stop
```

For a clean reset of local containers and data:

```bash
supabase stop --no-backup
supabase start
supabase db reset
```
