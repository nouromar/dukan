-- 0062_audit_action_code_select_policy.sql
--
-- audit_action_code is a reference table (the catalog of legal
-- audit action codes). 0050 granted SELECT to authenticated but
-- never enabled RLS or added a policy. In hosted Supabase, the
-- dashboard often turns on RLS for any table that doesn't already
-- have it explicitly disabled, leaving the table reachable via the
-- grant but returning zero rows because no policy authorizes the
-- select.
--
-- Make the policy explicit so this works regardless of how RLS
-- was set on hosted at table-creation time. Idempotent via DROP +
-- CREATE.

alter table public.audit_action_code enable row level security;

drop policy if exists audit_action_code_select on public.audit_action_code;

create policy audit_action_code_select
on public.audit_action_code
for select
to authenticated
using (true);
