-- 0006 rule versions, worked examples and the activation gate (PL-011, PL-012, PL-018).
--
-- A rule version cannot become active unless: it was submitted, it has at least one normal,
-- one boundary and one exception example, every example's last run passed, every run used the
-- version's current params_hash, and an approved maker-checker request authorises it.
-- Calculations run in TypeScript, so the database cannot recompute them: it trusts only results
-- recorded through record_worked_example_result, which the service key alone can call.
-- Decimal values inside params, inputs and expected are strings; fractional JSON numbers are
-- rejected (NF-012).

create table public.rule_version (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenant (id),
  rule_type text not null check (rule_type ~ '^[a-z][a-z0-9_]*$'),
  scope public.scope_t not null,
  -- pack code, product id or account id, depending on the scope.
  scope_ref text,
  schema_version integer not null default 1 check (schema_version >= 1),
  params jsonb not null check (jsonb_typeof(params) = 'object' and private.json_has_no_fractions(params)),
  params_hash text not null,
  status public.config_status_t not null default 'draft',
  effective_from date not null,
  supersedes_id uuid,
  submitted_by uuid,
  submitted_at timestamptz,
  approval_request_id uuid,
  activated_by uuid,
  activated_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  row_version integer not null default 1,
  unique (tenant_id, id),
  foreign key (tenant_id, supersedes_id) references public.rule_version (tenant_id, id),
  foreign key (tenant_id, approval_request_id) references public.approval_request (tenant_id, id),
  constraint rule_version_scope_ref check (
    (scope in ('platform', 'tenant') and scope_ref is null)
    or (scope in ('pack', 'product', 'account') and scope_ref is not null)
  ),
  constraint rule_version_not_retired check (status <> 'retired')
);
comment on table public.rule_version is
  'Typed, versioned, effective-dated parameter set (docs/08). Platform defaults live under the platform tenant.';

-- One active version per rule type, scope and effective date.
create unique index rule_version_one_active
  on public.rule_version (tenant_id, rule_type, scope, coalesce(scope_ref, ''), effective_from)
  where status = 'active';
create index rule_version_lookup_idx
  on public.rule_version (tenant_id, rule_type, scope, effective_from desc) where status = 'active';

create table public.worked_example (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenant (id),
  rule_version_id uuid not null,
  code text not null check (length(btrim(code)) > 0),
  kind public.example_kind_t not null,
  inputs jsonb not null check (jsonb_typeof(inputs) = 'object' and private.json_has_no_fractions(inputs)),
  expected jsonb not null check (jsonb_typeof(expected) = 'object' and private.json_has_no_fractions(expected)),
  note text,
  -- Segment the vector applies to ('ALL' or a segment code) and the feature flag it needs.
  segment text not null default 'ALL',
  requires_flag text,
  source text not null default 'manual' check (source in ('manual', 'starter')),
  -- Result of the last run. Only the server-side runner writes these (record_worked_example_result).
  last_result text check (last_result in ('pass', 'fail')),
  last_actual jsonb,
  last_diff jsonb,
  last_run_at timestamptz,
  last_run_params_hash text,
  last_run_library text,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  row_version integer not null default 1,
  unique (tenant_id, id),
  unique (rule_version_id, code),
  foreign key (tenant_id, rule_version_id) references public.rule_version (tenant_id, id)
);

select private.apply_tenant_rls('public.rule_version');
select private.apply_tenant_rls('public.worked_example');

-- Platform defaults and the shared vectors are readable by every tenant, never writable (D23).
create policy rule_version_platform_sel on public.rule_version for select to authenticated
  using (tenant_id = private.platform_tenant_id());
create policy worked_example_platform_sel on public.worked_example for select to authenticated
  using (tenant_id = private.platform_tenant_id());

-- Configurators write drafts directly; status, request links and run results are never
-- writable by the API role.
drop policy rule_version_tenant_ins on public.rule_version;
drop policy rule_version_tenant_upd on public.rule_version;
create policy rule_version_tenant_ins on public.rule_version for insert to authenticated
  with check (
    tenant_id = (select private.current_tenant_id())
    and (select private.has_permission('product_rule_config', 'create'))
  );
create policy rule_version_tenant_upd on public.rule_version for update to authenticated
  using (
    tenant_id = (select private.current_tenant_id())
    and (select private.has_permission('product_rule_config', 'create'))
  )
  with check (
    tenant_id = (select private.current_tenant_id())
    and (select private.has_permission('product_rule_config', 'create'))
  );
drop policy worked_example_tenant_ins on public.worked_example;
drop policy worked_example_tenant_upd on public.worked_example;
create policy worked_example_tenant_ins on public.worked_example for insert to authenticated
  with check (
    tenant_id = (select private.current_tenant_id())
    and (select private.has_permission('product_rule_config', 'create'))
  );
create policy worked_example_tenant_upd on public.worked_example for update to authenticated
  using (
    tenant_id = (select private.current_tenant_id())
    and (select private.has_permission('product_rule_config', 'create'))
  )
  with check (
    tenant_id = (select private.current_tenant_id())
    and (select private.has_permission('product_rule_config', 'create'))
  );

grant select on public.rule_version, public.worked_example to authenticated;
grant insert (rule_type, scope, scope_ref, schema_version, params, effective_from, supersedes_id)
  on public.rule_version to authenticated;
grant update (params, effective_from, schema_version) on public.rule_version to authenticated;
grant insert (rule_version_id, code, kind, inputs, expected, note, segment, requires_flag, source)
  on public.worked_example to authenticated;
grant update (code, kind, inputs, expected, note, segment, requires_flag)
  on public.worked_example to authenticated;

create trigger rule_version_touch before insert or update on public.rule_version
  for each row execute function private.touch_row();
create trigger rule_version_no_delete before delete on public.rule_version
  for each row execute function private.block_delete();
create trigger worked_example_touch before insert or update on public.worked_example
  for each row execute function private.touch_row();
create trigger worked_example_no_delete before delete on public.worked_example
  for each row execute function private.block_delete();
select private.audit_table('public.rule_version');
select private.audit_table('public.worked_example');

-- ---------------------------------------------------------------------------
-- The gate: why a rule version may not activate (null reason = it may).
-- ---------------------------------------------------------------------------
create function private.rule_version_gate(p_rule_version uuid) returns text
  language plpgsql stable security definer set search_path = ''
  as $$
declare
  v_rv public.rule_version%rowtype;
  v_kind public.example_kind_t;
  v_bad integer;
begin
  select * into v_rv from public.rule_version where id = p_rule_version;
  if not found then
    return 'rule version not found';
  end if;
  foreach v_kind in array enum_range(null::public.example_kind_t) loop
    if not exists (
      select 1 from public.worked_example w
      where w.rule_version_id = v_rv.id and w.kind = v_kind
    ) then
      return format('needs at least one %s worked example', v_kind);
    end if;
  end loop;
  select count(*) into v_bad
  from public.worked_example w
  where w.rule_version_id = v_rv.id
    and (w.last_result is distinct from 'pass' or w.last_run_params_hash is distinct from v_rv.params_hash);
  if v_bad > 0 then
    return format('%s worked example(s) have not passed against the current parameters', v_bad);
  end if;
  return null;
end
$$;

-- SECURITY INVOKER on purpose: current_user is the caller's effective role, which tells a platform
-- release (migration, table owner) from the API roles. Platform defaults are released through a
-- reviewed migration (the pull request is their maker-checker); the service key, like every API
-- role, can never activate or change them.
create function private.guard_rule_version() returns trigger
  language plpgsql set search_path = ''
  as $$
declare
  v_executing text := nullif(current_setting('icoops.executing_request', true), '');
  v_platform_release boolean :=
    new.tenant_id = private.platform_tenant_id()
    and current_user not in ('anon', 'authenticated', 'service_role');
  v_reason text;
begin
  if tg_op = 'INSERT' then
    if new.status <> 'draft' then
      raise exception 'a rule version is created as a draft';
    end if;
    new.params_hash := encode(sha256(convert_to(new.params::text, 'UTF8')), 'hex');
    return new;
  end if;

  -- Content freezes once the version leaves draft: rollback is a new version, never an edit.
  if old.status <> 'draft' and (
    new.rule_type, new.scope, new.scope_ref, new.schema_version, new.params, new.effective_from, new.supersedes_id
  ) is distinct from (
    old.rule_type, old.scope, old.scope_ref, old.schema_version, old.params, old.effective_from, old.supersedes_id
  ) then
    raise exception 'a rule version is frozen once submitted; create a new version instead';
  end if;
  new.params_hash := encode(sha256(convert_to(new.params::text, 'UTF8')), 'hex');

  if new.status is distinct from old.status then
    if not (
      (old.status = 'draft' and new.status = 'submitted')
      or (old.status = 'submitted' and new.status in ('rejected', 'withdrawn', 'active'))
      or (v_platform_release and old.status = 'draft' and new.status = 'active')
    ) then
      raise exception 'invalid rule version status change % -> %', old.status, new.status;
    end if;
    if new.status = 'active' then
      if not v_platform_release
         and (v_executing is null or v_executing is distinct from new.approval_request_id::text) then
        raise exception 'a rule version becomes active only through its approved request';
      end if;
      v_reason := private.rule_version_gate(new.id);
      if v_reason is not null then
        raise exception 'rule version cannot activate: %', v_reason using errcode = '23514';
      end if;
    end if;
  end if;
  return new;
end
$$;
create trigger rule_version_guard before insert or update on public.rule_version
  for each row execute function private.guard_rule_version();

-- ---------------------------------------------------------------------------
-- Recording a run: service key only. A run against stale parameters is refused.
-- ---------------------------------------------------------------------------
create function public.record_worked_example_result(
  p_example_id uuid,
  p_passed boolean,
  p_actual jsonb,
  p_diff jsonb,
  p_params_hash text,
  p_library text
) returns void
  language plpgsql security definer set search_path = ''
  as $$
declare
  v_current text;
begin
  select rv.params_hash into v_current
  from public.worked_example w
  join public.rule_version rv on rv.id = w.rule_version_id and rv.tenant_id = w.tenant_id
  where w.id = p_example_id;
  if v_current is null then
    raise exception 'worked example not found';
  end if;
  if v_current <> p_params_hash then
    raise exception 'stale run: parameters changed since the example was run';
  end if;
  update public.worked_example
  set last_result = case when p_passed then 'pass' else 'fail' end,
      last_actual = p_actual,
      last_diff = p_diff,
      last_run_at = now(),
      last_run_params_hash = p_params_hash,
      last_run_library = p_library
  where id = p_example_id;
end
$$;
revoke execute on function public.record_worked_example_result(uuid, boolean, jsonb, jsonb, text, text)
  from public, anon, authenticated;
grant execute on function public.record_worked_example_result(uuid, boolean, jsonb, jsonb, text, text)
  to service_role;

-- Examples change only while the version is a draft. Recording a run (above) rewrites only the
-- result columns, so it passes; any change to inputs, expected or kind discards the old result.
create function private.guard_worked_example() returns trigger
  language plpgsql security definer set search_path = ''
  as $$
declare
  v_status public.config_status_t;
begin
  select status into v_status from public.rule_version
  where id = new.rule_version_id and tenant_id = new.tenant_id;
  if v_status is null then
    raise exception 'rule version not found';
  end if;
  if tg_op = 'INSERT' then
    if v_status <> 'draft' then
      raise exception 'worked examples can change only while the rule version is a draft';
    end if;
    new.last_result := null; new.last_actual := null; new.last_diff := null;
    new.last_run_at := null; new.last_run_params_hash := null; new.last_run_library := null;
    return new;
  end if;
  if new.rule_version_id <> old.rule_version_id then
    raise exception 'an example cannot move to another rule version';
  end if;
  if (new.code, new.inputs, new.expected, new.kind, new.segment, new.requires_flag, new.note)
     is distinct from
     (old.code, old.inputs, old.expected, old.kind, old.segment, old.requires_flag, old.note) then
    if v_status <> 'draft' then
      raise exception 'worked examples can change only while the rule version is a draft';
    end if;
    if (new.inputs, new.expected, new.kind) is distinct from (old.inputs, old.expected, old.kind) then
      new.last_result := null; new.last_actual := null; new.last_diff := null;
      new.last_run_at := null; new.last_run_params_hash := null; new.last_run_library := null;
    end if;
  end if;
  return new;
end
$$;

create trigger worked_example_guard before insert or update on public.worked_example
  for each row execute function private.guard_worked_example();

-- ---------------------------------------------------------------------------
-- Submitting and activating (PL-022: back-dating needs its own approval type).
-- ---------------------------------------------------------------------------
create function public.submit_rule_version(p_rule_version_id uuid) returns uuid
  language plpgsql security definer set search_path = ''
  as $$
declare
  v_tenant uuid := private.current_tenant_id();
  v_rv public.rule_version%rowtype;
  v_reason text;
  v_type text;
  v_request uuid;
begin
  select * into v_rv from public.rule_version
  where id = p_rule_version_id and tenant_id = v_tenant for update;
  if not found then
    raise exception 'rule version not found';
  end if;
  if v_rv.status <> 'draft' then
    raise exception 'only a draft can be submitted';
  end if;
  v_reason := private.rule_version_gate(v_rv.id);
  if v_reason is not null then
    raise exception 'cannot submit: %', v_reason using errcode = '23514';
  end if;
  v_type := case when v_rv.effective_from < current_date
                 then 'rule_version_backdating' else 'rule_version_activation' end;
  v_request := private.create_request(
    v_type, 'rule_version', v_rv.id, null,
    jsonb_build_object(
      'rule_version_id', v_rv.id, 'rule_type', v_rv.rule_type,
      'effective_from', v_rv.effective_from, 'params_hash', v_rv.params_hash));
  update public.rule_version
  set status = 'submitted', submitted_by = private.current_app_user_id(),
      submitted_at = now(), approval_request_id = v_request
  where id = v_rv.id;
  return v_request;
end
$$;
revoke execute on function public.submit_rule_version(uuid) from public, anon;
grant execute on function public.submit_rule_version(uuid) to authenticated;

create function private.exec_rule_version_activation(p_req public.approval_request) returns void
  language plpgsql security definer set search_path = ''
  as $$
declare
  v_rv public.rule_version%rowtype;
  v_approver uuid;
begin
  select * into v_rv from public.rule_version
  where id = p_req.subject_id and tenant_id = p_req.tenant_id
    and approval_request_id = p_req.id and status = 'submitted' for update;
  if not found then
    raise exception 'rule version is not awaiting this request';
  end if;
  if v_rv.params_hash <> p_req.payload ->> 'params_hash' then
    raise exception 'parameters changed since approval';
  end if;
  select d.decided_by into v_approver
  from public.approval_decision d
  where d.request_id = p_req.id and d.decision = 'approve'
  order by d.decided_at desc, d.id desc limit 1;
  -- The guard trigger re-checks the gate (examples present and passing for this hash).
  update public.rule_version
  set status = 'active', activated_by = v_approver, activated_at = now()
  where id = v_rv.id;
end
$$;

-- Rejected or cancelled requests close their rule version too.
create or replace function private.on_request_closed(p_request uuid, p_status text) returns void
  language plpgsql security definer set search_path = ''
  as $$
declare
  v_req public.approval_request%rowtype;
  v_new public.config_status_t :=
    (case p_status when 'rejected' then 'rejected' else 'withdrawn' end)::public.config_status_t;
begin
  select * into v_req from public.approval_request where id = p_request;
  if v_req.request_type = 'approval_matrix_activation' then
    update public.approval_matrix set status = v_new
    where id = v_req.subject_id and tenant_id = v_req.tenant_id and status = 'submitted';
  elsif v_req.request_type in ('rule_version_activation', 'rule_version_backdating') then
    update public.rule_version set status = v_new
    where id = v_req.subject_id and tenant_id = v_req.tenant_id and status = 'submitted';
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- Effective-date lookup (PL-011): the version in force on a date, most specific scope first is
-- resolved in packages/rules; this returns the candidates for one type, scope and reference.
-- ---------------------------------------------------------------------------
create function public.rule_version_in_force(
  p_rule_type text, p_scope public.scope_t, p_scope_ref text, p_on date
) returns setof public.rule_version
  language sql stable security invoker set search_path = ''
  as $$
    select rv.*
    from public.rule_version rv
    where rv.rule_type = p_rule_type
      and rv.scope = p_scope
      and coalesce(rv.scope_ref, '') = coalesce(p_scope_ref, '')
      and rv.status = 'active'
      and rv.effective_from <= p_on
    order by rv.effective_from desc
    limit 1
  $$;
revoke execute on function public.rule_version_in_force(text, public.scope_t, text, date) from public, anon;
grant execute on function public.rule_version_in_force(text, public.scope_t, text, date) to authenticated;
