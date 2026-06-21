-- 0068_audit_original_actor.sql
--
-- Phase 5A of the offline + caching plan: preserve the cashier who
-- ORIGINATED a posting when the queue is drained by a DIFFERENT
-- user (e.g. cashier A rang up sales offline, signed out without
-- syncing, owner B signs in and drains the queue — audit currently
-- says owner B was the actor, which is technically true at the
-- RPC layer but loses the "who initiated this work" trail).
--
-- Design choice: rather than change the signature of every posting
-- RPC (DROP + CREATE on 4 large functions, ~700 lines), we add a
-- thin SECOND RPC `set_audit_original_actor` that the mobile queue
-- executor calls after each successful drain to backfill the
-- originator on the most-recent audit row for that (shop, entity).
--
-- Direct (non-queued) posting paths don't need any change — actor
-- == originator naturally, and original_actor_user_id stays NULL
-- (the audit log UI treats NULL as "same as actor").

-- ---------------------------------------------------------------
-- 1. New column on the audit_log partitioned table.
-- ---------------------------------------------------------------

alter table public.audit_log
  add column if not exists original_actor_user_id uuid;

-- Note: NOT adding a FK to auth.users because the test harness
-- mocks auth schema. The column is semantically a user_id but the
-- FK isn't load-bearing for any business logic; the audit-log UI
-- joins to user_profile / auth.users defensively (treats missing
-- as "(unknown)").

create index if not exists audit_log_original_actor_idx
  on public.audit_log (shop_id, original_actor_user_id, occurred_at desc)
  where original_actor_user_id is not null;

-- ---------------------------------------------------------------
-- 2. set_audit_original_actor RPC.
--
-- Called by the mobile queue executor after each successful drain
-- when post.originalActorUserId != auth.uid(). Finds the most-
-- recent audit row matching (shop_id, entity_id) and stamps the
-- original_actor_user_id column.
--
-- Idempotent: re-calling with the same value is a no-op. Re-
-- calling with a different value overwrites — the executor only
-- calls once per drained post so this isn't reachable in practice,
-- but the behavior is defined.
-- ---------------------------------------------------------------

create or replace function public.set_audit_original_actor(
  p_shop_id                uuid,
  p_entity_id              uuid,
  p_original_actor_user_id uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id          uuid;
  v_occurred_at timestamptz;
begin
  -- Authorization: caller must be a member of the shop. We DON'T
  -- enforce that p_original_actor_user_id is a known user — the
  -- audit_log UI handles "(unknown)" gracefully and we want this
  -- to keep working if a user is later deleted.
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to set audit actor for this shop';
  end if;

  -- Most-recent audit row for this entity in this shop. Audit_log
  -- is partitioned by occurred_at — the index audit_log_shop_recent
  -- supports this lookup.
  select id, occurred_at
    into v_id, v_occurred_at
  from public.audit_log
  where shop_id = p_shop_id
    and entity_id = p_entity_id
  order by occurred_at desc
  limit 1;

  if v_id is null then
    -- No audit row to update — silently no-op rather than raise.
    -- The executor calls this AFTER the post succeeded; if the
    -- post didn't emit audit (e.g. post_inventory_adjustment),
    -- there's nothing to set.
    return;
  end if;

  -- The composite primary key is (occurred_at, id) on the
  -- partitioned table — UPDATE must include occurred_at to hit
  -- the right partition.
  update public.audit_log
     set original_actor_user_id = p_original_actor_user_id
   where id = v_id
     and occurred_at = v_occurred_at;
end;
$$;

revoke all on function public.set_audit_original_actor(uuid, uuid, uuid) from public;
grant execute on function public.set_audit_original_actor(uuid, uuid, uuid) to authenticated;
