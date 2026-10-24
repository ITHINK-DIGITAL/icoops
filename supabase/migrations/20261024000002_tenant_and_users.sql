-- 0002 tenant and app_user, with the helpers that resolve "who is calling".
-- One sign-in identity belongs to exactly one tenant in R1 (decision D23).

create table public.tenant (
  id uuid primary key default gen_random_uuid(),
  -- tenant_id mirrors id so that the row-level security template applies uniformly.
  tenant_id uuid generated always as (id) stored not null,
  code text not null unique check (code ~ '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$'),
  name text not null check (length(btrim(name)) > 0),
  segment public.segment_t not null,
  parent_tenant_id uuid references public.tenant (id),
  features jsonb not null default '{}'::jsonb,
  status public.tenant_status_t not null default 'active',
  is_sandbox boolean not null default false,
  cda_reg_no text,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  row_version integer not null default 1,
  constraint tenant_not_own_parent check (parent_tenant_id is distinct from id),
  constraint tenant_features_valid check (private.features_valid(features)),
  constraint tenant_platform_segment check (
    (segment = 'platform') = (id = '00000000-0000-0000-0000-000000000001'::uuid)
  )
);
comment on table public.tenant is
  'One row per cooperative plus the reserved platform tenant. Segment and features carry all customer differences (D14).';

-- A federation (S3) is the only kind of parent; its children are member co-ops (S1 or S2) and
-- the hierarchy is one level deep (PL-007, schema only in R1).
create function private.validate_tenant_parent() returns trigger
  language plpgsql set search_path = ''
  as $$
declare
  v_parent public.tenant%rowtype;
begin
  if new.parent_tenant_id is null then
    return new;
  end if;
  select * into v_parent from public.tenant where id = new.parent_tenant_id;
  if v_parent.segment <> 's3_federation' then
    raise exception 'parent tenant must be a federation (s3_federation)';
  end if;
  if v_parent.parent_tenant_id is not null then
    raise exception 'tenant hierarchy is one level deep';
  end if;
  if new.segment not in ('s1_private', 's2_government') then
    raise exception 'only member co-ops (s1_private, s2_government) can have a parent tenant';
  end if;
  return new;
end
$$;

create trigger tenant_validate_parent
  before insert or update of parent_tenant_id, segment on public.tenant
  for each row execute function private.validate_tenant_parent();

create table public.app_user (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenant (id),
  auth_user_id uuid not null unique references auth.users (id),
  display_name text not null check (length(btrim(display_name)) > 0),
  email text not null check (email = lower(email) and position('@' in email) > 1),
  mobile text,
  status public.user_status_t not null default 'active',
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  row_version integer not null default 1,
  unique (tenant_id, id),
  unique (tenant_id, email)
);
comment on table public.app_user is
  'Staff account. One sign-in identity belongs to exactly one tenant (D23).';

-- ---------------------------------------------------------------------------
-- Who is calling. Looked up on every statement, never read from a token claim, so disabling a
-- user or suspending a tenant takes effect immediately.
-- ---------------------------------------------------------------------------
create function private.current_app_user_id() returns uuid
  language sql stable security definer set search_path = ''
  as $$
    select u.id
    from public.app_user u
    join public.tenant t on t.id = u.tenant_id
    where u.auth_user_id = auth.uid()
      and u.status = 'active'
      and t.status = 'active'
  $$;

create function private.current_tenant_id() returns uuid
  language sql stable security definer set search_path = ''
  as $$
    select u.tenant_id
    from public.app_user u
    join public.tenant t on t.id = u.tenant_id
    where u.auth_user_id = auth.uid()
      and u.status = 'active'
      and t.status = 'active'
  $$;

-- ---------------------------------------------------------------------------
-- Row-level security, privileges and generic triggers
-- ---------------------------------------------------------------------------
select private.apply_tenant_rls('public.tenant');
select private.apply_tenant_rls('public.app_user');

-- The API can read; every write goes through a guarded function or the platform path.
grant select on public.tenant, public.app_user to authenticated;

create trigger tenant_touch before insert or update on public.tenant
  for each row execute function private.touch_row();
create trigger tenant_no_delete before delete on public.tenant
  for each row execute function private.block_delete();
create trigger app_user_touch before insert or update on public.app_user
  for each row execute function private.touch_row();
create trigger app_user_no_delete before delete on public.app_user
  for each row execute function private.block_delete();
