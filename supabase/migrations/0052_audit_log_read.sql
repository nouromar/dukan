-- 0052_audit_log_read.sql
--
-- Mobile read path into audit_log: per-entity recent entries for
-- the inline "last edited {time} ago" cues on Product detail's
-- price tile and Party detail's header.
--
-- Returns actor_user_id but NOT a resolved display name -- phone-OTP
-- signup doesn't capture a name, so the mobile UI shows the relative
-- time only for v1. When a staff-profile feature lands we can join
-- on a future profile table without changing this signature.
--
-- The "voided {time} ago" cue does NOT come from audit_log; it
-- reads voided_at off the existing get_sale / list_sales output.
-- No backend change there.

create or replace function public.list_audit_entries_for_entity(
  p_shop_id     uuid,
  p_entity_type text,
  p_entity_id   uuid,
  p_limit       int default 5
)
returns table (
  id            uuid,
  actor_user_id uuid,
  action_code   text,
  occurred_at   timestamptz,
  reason        text,
  source        text
)
language plpgsql
security definer
set search_path = ''
stable
as $$
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to view audit log for this shop';
  end if;
  if not public.auth_user_has_capability('audit.view', p_shop_id) then
    raise exception 'Missing audit.view capability';
  end if;

  return query
  select
    a.id,
    a.actor_user_id,
    a.action_code,
    a.occurred_at,
    a.reason,
    a.source
  from public.audit_log a
  where a.shop_id = p_shop_id
    and a.entity_type = p_entity_type
    and a.entity_id = p_entity_id
  order by a.occurred_at desc
  limit greatest(p_limit, 1);
end;
$$;

revoke all on function public.list_audit_entries_for_entity(uuid, text, uuid, int) from public;
grant execute on function public.list_audit_entries_for_entity(uuid, text, uuid, int) to authenticated;
