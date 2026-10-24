-- 0003 append-only audit log (NF-009, PL-023). Rows are written only by the audit trigger and
-- the sensitive-view function; nobody, including the platform key, can update or delete them.

create table public.audit_log (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.tenant (id),
  occurred_at timestamptz not null default now(),
  actor_user_id uuid,
  actor_kind text not null check (actor_kind in ('user', 'service', 'system')),
  action text not null check (length(action) > 0),
  entity text not null,
  entity_id uuid,
  before jsonb,
  after jsonb,
  reason text,
  request_id text,
  txid bigint not null default txid_current()
);
comment on table public.audit_log is
  'Append-only. Written by private.audit_row() and public.log_sensitive_view() only.';

create index audit_log_tenant_entity_idx on public.audit_log (tenant_id, entity, entity_id);
create index audit_log_tenant_time_idx on public.audit_log (tenant_id, occurred_at desc);

-- Append-only: no update, no delete, no truncate, for any role.
create trigger audit_log_no_update before update or delete on public.audit_log
  for each row execute function private.block_update();
create function private.block_truncate() returns trigger
  language plpgsql set search_path = ''
  as $$
begin
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end
$$;
create trigger audit_log_no_truncate before truncate on public.audit_log
  for each statement execute function private.block_truncate();

-- ---------------------------------------------------------------------------
-- Row trigger that records before and after images for every audited table.
-- ---------------------------------------------------------------------------
create function private.audit_row() returns trigger
  language plpgsql security definer set search_path = ''
  as $$
declare
  v_old jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_new jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
  v_row jsonb := coalesce(v_new, v_old);
  v_actor uuid := private.current_app_user_id();
begin
  insert into public.audit_log
    (tenant_id, actor_user_id, actor_kind, action, entity, entity_id, before, after, reason, request_id)
  values (
    (v_row ->> 'tenant_id')::uuid,
    v_actor,
    case
      when v_actor is not null then 'user'
      when private.jwt_role() = 'service_role' then 'service'
      else 'system'
    end,
    lower(tg_op),
    tg_table_name,
    (v_row ->> 'id')::uuid,
    v_old,
    v_new,
    nullif(current_setting('icoops.reason', true), ''),
    nullif(current_setting('icoops.request_id', true), '')
  );
  return null;
end
$$;

-- Convenience: attach the standard trigger set (audit) to a table. touch_row and block_delete
-- are attached per table in each migration so that their column needs stay visible there.
create function private.audit_table(p_table regclass) returns void
  language plpgsql set search_path = ''
  as $$
declare
  v_name text := (select c.relname from pg_class c where c.oid = p_table);
begin
  execute format(
    'create trigger %I after insert or update or delete on %s for each row execute function private.audit_row()',
    v_name || '_audit', p_table);
end
$$;

select private.apply_tenant_rls('public.audit_log');
-- The generic update policy is meaningless on an append-only table; drop it and the insert one.
drop policy audit_log_tenant_ins on public.audit_log;
drop policy audit_log_tenant_upd on public.audit_log;
-- Reading the log needs the audit_log:view permission on top of tenant membership
-- (policy replaced once permissions exist, in 0004).
grant select on public.audit_log to authenticated;

select private.audit_table('public.tenant');
select private.audit_table('public.app_user');

-- ---------------------------------------------------------------------------
-- Views of sensitive records are logged by an explicit call (triggers cannot see reads).
-- ---------------------------------------------------------------------------
create function public.log_sensitive_view(p_entity text, p_entity_id uuid, p_reason text default null)
  returns void
  language plpgsql security definer set search_path = ''
  as $$
declare
  v_tenant uuid := private.current_tenant_id();
  v_found boolean;
begin
  if v_tenant is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  if not exists (
    select 1
    from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = p_entity and c.column_name = 'tenant_id'
  ) then
    raise exception 'unknown entity %', p_entity;
  end if;
  execute format('select exists (select 1 from public.%I where id = $1 and tenant_id = $2)', p_entity)
    into v_found using p_entity_id, v_tenant;
  if not v_found then
    raise exception 'record not found';
  end if;
  insert into public.audit_log (tenant_id, actor_user_id, actor_kind, action, entity, entity_id, reason)
  values (v_tenant, private.current_app_user_id(), 'user', 'view', p_entity, p_entity_id, p_reason);
end
$$;
revoke execute on function public.log_sensitive_view(text, uuid, text) from public, anon;
grant execute on function public.log_sensitive_view(text, uuid, text) to authenticated;
