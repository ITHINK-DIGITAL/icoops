-- 0001 foundations: schemas, enums, generic helpers and the row-level security template.
-- Conventions (CLAUDE.md, docs/08 T0): every table has tenant_id and row-level security;
-- money numeric(18,2), rates numeric(9,6); nothing is ever deleted; every change is audited.

create schema if not exists private;
create schema if not exists extensions;
create extension if not exists btree_gist with schema extensions;

-- The private schema is never exposed through the API (config.toml exposes public only).
revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;
-- Function privileges in private are tightened in the closing migration (execute revoked from
-- public, granted back only to the helpers that row-level security policies call).

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type public.segment_t as enum ('platform', 's1_private', 's2_government', 's3_federation');
create type public.tenant_status_t as enum ('active', 'suspended', 'closed');
create type public.user_status_t as enum ('active', 'locked', 'disabled');

-- Function and action pairs follow the FS security matrix (docs/04, "Security: roles and permissions").
create type public.function_t as enum (
  'member_record', 'membership_approval', 'payment_posting', 'withdrawal_above_limit',
  'loan_application', 'loan_approval', 'loan_release_voucher', 'teller_eod',
  'deduction_batch', 'journal_voucher', 'period_close', 'product_rule_config',
  'users_roles', 'audit_log', 'reports'
);
create type public.action_t as enum ('create', 'approve', 'view');

create type public.scope_t as enum ('platform', 'pack', 'tenant', 'product', 'account');
create type public.config_status_t as enum (
  'draft', 'submitted', 'active', 'rejected', 'withdrawn', 'retired'
);
create type public.example_kind_t as enum ('normal', 'boundary', 'exception');
create type public.approval_status_t as enum (
  'pending', 'approved', 'rejected', 'cancelled', 'executed'
);

-- ---------------------------------------------------------------------------
-- Constants and generic helpers
-- ---------------------------------------------------------------------------

-- The reserved platform tenant owns platform defaults and the shared vectors (decision D23).
create function private.platform_tenant_id() returns uuid
  language sql immutable parallel safe
  as $$ select '00000000-0000-0000-0000-000000000001'::uuid $$;

-- JWT role claim as set by the API gateway; empty when no request context exists.
create function private.jwt_role() returns text
  language sql stable set search_path = ''
  as $$
    select coalesce(
      nullif(current_setting('request.jwt.claim.role', true), ''),
      nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
      ''
    )
  $$;

-- True when a jsonb value holds no fractional number anywhere: decimal values are stored as
-- strings (as in docs/worked_examples/starter.json), never as JSON floats (NF-012).
create function private.json_has_no_fractions(j jsonb) returns boolean
  language sql immutable set search_path = ''
  as $$
    select not jsonb_path_exists(j, '$.** ? (@.type() == "number" && @ != @.floor())')
  $$;

-- Feature flags are an object of lower_snake keys with boolean values.
create function private.features_valid(f jsonb) returns boolean
  language sql immutable set search_path = ''
  as $$
    select jsonb_typeof(f) = 'object'
      and not exists (
        select 1 from jsonb_each(f) e
        where jsonb_typeof(e.value) <> 'boolean' or e.key !~ '^[a-z][a-z0-9_]*$'
      )
  $$;

-- ---------------------------------------------------------------------------
-- Generic triggers
-- ---------------------------------------------------------------------------

-- Maintains created_*, updated_* and row_version. Clients cannot set them.
create function private.touch_row() returns trigger
  language plpgsql security definer set search_path = ''
  as $$
declare
  v_user uuid := private.current_app_user_id();
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
    new.created_by := v_user;
    new.row_version := 1;
  else
    new.created_at := old.created_at;
    new.created_by := old.created_by;
    new.row_version := old.row_version + 1;
  end if;
  new.updated_at := now();
  new.updated_by := v_user;
  return new;
end
$$;

-- T0 invariant: corrections are reversals, never deletes.
create function private.block_delete() returns trigger
  language plpgsql set search_path = ''
  as $$
begin
  raise exception 'rows in % are never deleted; record a correction instead', tg_table_name
    using errcode = '42501';
end
$$;

-- For append-only tables (audit_log, approval_decision, approval_request_step).
create function private.block_update() returns trigger
  language plpgsql set search_path = ''
  as $$
begin
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end
$$;

-- ---------------------------------------------------------------------------
-- Row-level security template
-- ---------------------------------------------------------------------------
-- Applies to every table in public that carries tenant_id. A catalog test (AT-13) fails the
-- build for any table that skips it. Privileges stay minimal: the grants below only remove
-- everything; each migration then grants back exactly what the API role needs.
create function private.apply_tenant_rls(p_table regclass) returns void
  language plpgsql set search_path = ''
  as $$
declare
  v_name text := (select c.relname from pg_class c where c.oid = p_table);
  v_generated boolean := (
    select a.attgenerated <> ''
    from pg_attribute a
    where a.attrelid = p_table and a.attname = 'tenant_id' and not a.attisdropped
  );
begin
  if v_generated is null then
    raise exception 'table % has no tenant_id column', p_table;
  end if;

  execute format('alter table %s enable row level security', p_table);
  execute format('revoke all on table %s from anon, authenticated', p_table);

  if not v_generated then
    execute format(
      'alter table %s alter column tenant_id set default private.current_tenant_id()', p_table);
  end if;

  execute format(
    'create policy %I on %s for select to authenticated using (tenant_id = (select private.current_tenant_id()))',
    v_name || '_tenant_sel', p_table);
  execute format(
    'create policy %I on %s for insert to authenticated with check (tenant_id = (select private.current_tenant_id()))',
    v_name || '_tenant_ins', p_table);
  execute format(
    'create policy %I on %s for update to authenticated using (tenant_id = (select private.current_tenant_id())) with check (tenant_id = (select private.current_tenant_id()))',
    v_name || '_tenant_upd', p_table);
  -- No delete policy and no delete grant: deletes are impossible through the API.
end
$$;
