-- 0004 roles, permissions and role assignments, the FS role templates, the platform tenant and
-- the platform-only admin functions (tenant creation and user bootstrap, decision D25).

create table public.role (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenant (id),
  code text not null check (code ~ '^[a-z][a-z0-9_]*$'),
  name text not null check (length(btrim(name)) > 0),
  is_system boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  row_version integer not null default 1,
  unique (tenant_id, id),
  unique (tenant_id, code)
);

create table public.role_permission (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenant (id),
  role_id uuid not null,
  function_code public.function_t not null,
  action public.action_t not null,
  -- null means no amount limit for this role and action (PL-021).
  amount_limit numeric(18, 2) check (amount_limit >= 0),
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  row_version integer not null default 1,
  unique (tenant_id, id),
  unique (role_id, function_code, action),
  foreign key (tenant_id, role_id) references public.role (tenant_id, id)
);

create table public.user_role (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenant (id),
  user_id uuid not null,
  role_id uuid not null,
  valid_from timestamptz not null default now(),
  -- A role is withdrawn by giving it an end time; the row stays for the audit trail.
  valid_to timestamptz,
  granted_by uuid,
  approval_request_id uuid,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  row_version integer not null default 1,
  unique (tenant_id, id),
  foreign key (tenant_id, user_id) references public.app_user (tenant_id, id),
  foreign key (tenant_id, role_id) references public.role (tenant_id, id),
  check (valid_to is null or valid_to > valid_from),
  -- The same role cannot be held twice over the same period.
  constraint user_role_no_overlap exclude using gist (
    user_id extensions.gist_uuid_ops with =,
    role_id extensions.gist_uuid_ops with =,
    tstzrange(valid_from, valid_to) with &&
  )
);

select private.apply_tenant_rls('public.role');
select private.apply_tenant_rls('public.role_permission');
select private.apply_tenant_rls('public.user_role');
grant select on public.role, public.role_permission, public.user_role to authenticated;

create trigger role_touch before insert or update on public.role
  for each row execute function private.touch_row();
create trigger role_no_delete before delete on public.role
  for each row execute function private.block_delete();
create trigger role_permission_touch before insert or update on public.role_permission
  for each row execute function private.touch_row();
create trigger role_permission_no_delete before delete on public.role_permission
  for each row execute function private.block_delete();
create trigger user_role_touch before insert or update on public.user_role
  for each row execute function private.touch_row();
create trigger user_role_no_delete before delete on public.user_role
  for each row execute function private.block_delete();
select private.audit_table('public.role');
select private.audit_table('public.role_permission');
select private.audit_table('public.user_role');

-- ---------------------------------------------------------------------------
-- Permission checks (PL-021). Role changes take effect on the next statement.
-- ---------------------------------------------------------------------------
create function private.user_can(
  p_user uuid, p_function public.function_t, p_action public.action_t, p_amount numeric default null
) returns boolean
  language sql stable security definer set search_path = ''
  as $$
    select exists (
      select 1
      from public.user_role ur
      join public.role_permission rp
        on rp.role_id = ur.role_id and rp.tenant_id = ur.tenant_id
      where ur.user_id = p_user
        and ur.valid_from <= now()
        and (ur.valid_to is null or ur.valid_to > now())
        and rp.function_code = p_function
        and rp.action = p_action
        and (p_amount is null or rp.amount_limit is null or rp.amount_limit >= p_amount)
    )
  $$;

create function private.has_permission(p_function public.function_t, p_action public.action_t)
  returns boolean
  language sql stable security definer set search_path = ''
  as $$ select coalesce(private.user_can(private.current_app_user_id(), p_function, p_action), false) $$;

-- For the staff app and the rule runner: may the signed-in user do this? The database still
-- enforces every rule itself; this only lets the UI hide what would be refused.
create function public.current_user_can(p_function public.function_t, p_action public.action_t)
  returns boolean
  language sql stable security definer set search_path = ''
  as $$ select private.has_permission(p_function, p_action) $$;
revoke execute on function public.current_user_can(public.function_t, public.action_t) from public, anon;
grant execute on function public.current_user_can(public.function_t, public.action_t) to authenticated;

-- Reading the audit log needs the audit_log:view permission on top of tenant membership.
drop policy audit_log_tenant_sel on public.audit_log;
create policy audit_log_tenant_sel on public.audit_log for select to authenticated
  using (
    tenant_id = (select private.current_tenant_id())
    and (select private.has_permission('audit_log', 'view'))
  );

-- ---------------------------------------------------------------------------
-- The reserved platform tenant (D23). No user signs in to it.
-- ---------------------------------------------------------------------------
insert into public.tenant (id, code, name, segment, features)
values ('00000000-0000-0000-0000-000000000001', 'platform', 'iCOOPs platform', 'platform', '{}'::jsonb);

-- ---------------------------------------------------------------------------
-- Default role templates, from the FS security matrix. C implies view, A implies view.
-- Amount limits start empty; approval bands live in approval_matrix.
-- ---------------------------------------------------------------------------
create function private.install_role_templates(p_tenant uuid) returns void
  language plpgsql set search_path = ''
  as $$
begin
  insert into public.role (tenant_id, code, name, is_system)
  values
    (p_tenant, 'teller', 'Teller', true),
    (p_tenant, 'member_officer', 'Membership officer', true),
    (p_tenant, 'loan_officer', 'Loan officer', true),
    (p_tenant, 'collections', 'Collections officer', true),
    (p_tenant, 'bookkeeper', 'Bookkeeper', true),
    (p_tenant, 'accountant', 'Accountant', true),
    (p_tenant, 'gm', 'General manager', true),
    (p_tenant, 'board', 'Board', true),
    (p_tenant, 'auditor', 'Auditor', true),
    (p_tenant, 'tenant_admin', 'Tenant administrator', true);

  with matrix (role_code, function_code, letter) as (
    values
      ('teller', 'member_record', 'V'), ('member_officer', 'member_record', 'C'),
      ('loan_officer', 'member_record', 'V'), ('collections', 'member_record', 'V'),
      ('bookkeeper', 'member_record', 'V'), ('accountant', 'member_record', 'V'),
      ('gm', 'member_record', 'A'), ('board', 'member_record', 'V'),
      ('auditor', 'member_record', 'V'),

      ('member_officer', 'membership_approval', 'C'), ('gm', 'membership_approval', 'V'),
      ('board', 'membership_approval', 'A'), ('auditor', 'membership_approval', 'V'),

      ('teller', 'payment_posting', 'C'), ('accountant', 'payment_posting', 'V'),
      ('gm', 'payment_posting', 'V'), ('auditor', 'payment_posting', 'V'),

      ('teller', 'withdrawal_above_limit', 'C'), ('gm', 'withdrawal_above_limit', 'A'),
      ('auditor', 'withdrawal_above_limit', 'V'),

      ('teller', 'loan_application', 'V'), ('loan_officer', 'loan_application', 'C'),
      ('gm', 'loan_application', 'V'), ('board', 'loan_application', 'V'),
      ('auditor', 'loan_application', 'V'),

      ('loan_officer', 'loan_approval', 'A'), ('gm', 'loan_approval', 'A'),
      ('board', 'loan_approval', 'A'), ('auditor', 'loan_approval', 'V'),

      ('teller', 'loan_release_voucher', 'C'), ('loan_officer', 'loan_release_voucher', 'C'),
      ('accountant', 'loan_release_voucher', 'A'), ('gm', 'loan_release_voucher', 'A'),
      ('auditor', 'loan_release_voucher', 'V'),

      ('teller', 'teller_eod', 'C'), ('accountant', 'teller_eod', 'V'),
      ('gm', 'teller_eod', 'A'), ('auditor', 'teller_eod', 'V'),

      ('collections', 'deduction_batch', 'C'), ('bookkeeper', 'deduction_batch', 'V'),
      ('accountant', 'deduction_batch', 'A'), ('gm', 'deduction_batch', 'V'),
      ('auditor', 'deduction_batch', 'V'),

      ('bookkeeper', 'journal_voucher', 'C'), ('accountant', 'journal_voucher', 'A'),
      ('gm', 'journal_voucher', 'V'), ('auditor', 'journal_voucher', 'V'),

      ('accountant', 'period_close', 'C'), ('gm', 'period_close', 'A'),
      ('auditor', 'period_close', 'V'),

      ('accountant', 'product_rule_config', 'C'), ('gm', 'product_rule_config', 'A'),
      ('board', 'product_rule_config', 'A'), ('auditor', 'product_rule_config', 'V'),
      ('tenant_admin', 'product_rule_config', 'C'),

      ('gm', 'users_roles', 'A'), ('auditor', 'users_roles', 'V'),
      ('tenant_admin', 'users_roles', 'C'),

      ('accountant', 'audit_log', 'V'), ('gm', 'audit_log', 'V'), ('board', 'audit_log', 'V'),
      ('auditor', 'audit_log', 'V'), ('tenant_admin', 'audit_log', 'V'),

      ('teller', 'reports', 'V'), ('member_officer', 'reports', 'V'),
      ('loan_officer', 'reports', 'V'), ('collections', 'reports', 'V'),
      ('bookkeeper', 'reports', 'V'), ('accountant', 'reports', 'V'), ('gm', 'reports', 'V'),
      ('board', 'reports', 'V'), ('auditor', 'reports', 'V')
  ),
  expanded as (
    select role_code, function_code, 'view' as action from matrix
    union
    select role_code, function_code, 'create' from matrix where letter = 'C'
    union
    select role_code, function_code, 'approve' from matrix where letter = 'A'
  )
  insert into public.role_permission (tenant_id, role_id, function_code, action)
  select p_tenant, r.id, e.function_code::public.function_t, e.action::public.action_t
  from expanded e
  join public.role r on r.tenant_id = p_tenant and r.code = e.role_code;
end
$$;

-- ---------------------------------------------------------------------------
-- Platform path (PL-002): creating tenants and bootstrapping their first users. Callable with
-- the service key only; every row it writes is audited with actor_kind = 'service'.
-- ---------------------------------------------------------------------------
create function public.admin_create_tenant(
  p_code text,
  p_name text,
  p_segment public.segment_t,
  p_parent_tenant_id uuid default null,
  p_features jsonb default '{}'::jsonb,
  p_is_sandbox boolean default false
) returns uuid
  language plpgsql security definer set search_path = ''
  as $$
declare
  v_id uuid;
begin
  if p_segment = 'platform' then
    raise exception 'the platform tenant is reserved';
  end if;
  insert into public.tenant (code, name, segment, parent_tenant_id, features, is_sandbox)
  values (p_code, p_name, p_segment, p_parent_tenant_id, p_features, p_is_sandbox)
  returning id into v_id;
  perform private.install_role_templates(v_id);
  return v_id;
end
$$;

create function public.admin_bootstrap_user(
  p_tenant_id uuid,
  p_auth_user_id uuid,
  p_display_name text,
  p_email text,
  p_role_codes text[] default '{}'
) returns uuid
  language plpgsql security definer set search_path = ''
  as $$
declare
  v_user uuid;
  v_code text;
  v_role uuid;
begin
  insert into public.app_user (tenant_id, auth_user_id, display_name, email)
  values (p_tenant_id, p_auth_user_id, p_display_name, lower(p_email))
  returning id into v_user;
  foreach v_code in array p_role_codes loop
    select id into v_role from public.role where tenant_id = p_tenant_id and code = v_code;
    if v_role is null then
      raise exception 'unknown role %', v_code;
    end if;
    insert into public.user_role (tenant_id, user_id, role_id) values (p_tenant_id, v_user, v_role);
  end loop;
  return v_user;
end
$$;

revoke execute on function public.admin_create_tenant(text, text, public.segment_t, uuid, jsonb, boolean)
  from public, anon, authenticated;
revoke execute on function public.admin_bootstrap_user(uuid, uuid, text, text, text[])
  from public, anon, authenticated;
grant execute on function public.admin_create_tenant(text, text, public.segment_t, uuid, jsonb, boolean)
  to service_role;
grant execute on function public.admin_bootstrap_user(uuid, uuid, text, text, text[])
  to service_role;
