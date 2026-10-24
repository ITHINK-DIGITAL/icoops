-- 0005 approval matrix and the maker-checker primitive (PL-014, PL-022, AT-14).
--
-- Rules enforced by database triggers, not configurable (docs/08 T0):
--   * the decider is not the maker and not anyone who created or edited the subject;
--   * nobody decides two steps of the same request;
--   * the decider holds the step's role, valid now, and the approve permission with an amount
--     limit that covers the request;
--   * the decider signed in with a second factor (aal2);
--   * the request is still pending, and its payload can never change after creation.
-- The maker and the decider are always taken from the signed-in user, never from the client.

-- ---------------------------------------------------------------------------
-- Approval matrix: amount band -> ordered role steps, per transaction type.
-- ---------------------------------------------------------------------------
create table public.approval_matrix (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenant (id),
  txn_type text not null check (txn_type ~ '^[a-z][a-z0-9_]*$'),
  -- Product-specific bands arrive with products in slice 4 (the foreign key is added then).
  product_id uuid,
  min_amount numeric(18, 2) not null default 0 check (min_amount >= 0),
  max_amount numeric(18, 2) check (max_amount is null or max_amount > min_amount),
  effective_from date not null,
  status public.config_status_t not null default 'draft',
  supersedes_id uuid,
  activation_request_id uuid,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  row_version integer not null default 1,
  unique (tenant_id, id),
  foreign key (tenant_id, supersedes_id) references public.approval_matrix (tenant_id, id),
  -- No two active bands for the same transaction type and product may overlap.
  constraint approval_matrix_no_overlap exclude using gist (
    tenant_id extensions.gist_uuid_ops with =,
    txn_type with =,
    (coalesce(product_id, '00000000-0000-0000-0000-000000000000'::uuid)) extensions.gist_uuid_ops with =,
    numrange(min_amount, max_amount, '[)') with &&
  ) where (status = 'active')
);

create table public.approval_matrix_step (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenant (id),
  matrix_id uuid not null,
  step_no integer not null check (step_no >= 1),
  role_id uuid not null,
  required_approvals integer not null default 1 check (required_approvals >= 1),
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  row_version integer not null default 1,
  unique (tenant_id, id),
  unique (matrix_id, step_no),
  foreign key (tenant_id, matrix_id) references public.approval_matrix (tenant_id, id),
  foreign key (tenant_id, role_id) references public.role (tenant_id, id)
);

-- ---------------------------------------------------------------------------
-- Requests, their frozen steps, and the decisions.
-- ---------------------------------------------------------------------------
create table public.approval_request (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenant (id),
  request_type text not null,
  subject_table text not null,
  subject_id uuid not null,
  amount numeric(18, 2) check (amount is null or amount >= 0),
  payload jsonb not null,
  payload_hash text not null,
  maker_user_id uuid not null,
  -- The maker plus everyone who created or edited the subject: none of them may decide.
  excluded_user_ids uuid[] not null default '{}',
  current_step integer not null default 1,
  status public.approval_status_t not null default 'pending',
  decided_at timestamptz,
  executed_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  row_version integer not null default 1,
  unique (tenant_id, id),
  foreign key (tenant_id, maker_user_id) references public.app_user (tenant_id, id),
  constraint approval_request_payload_hash_ok check (
    payload_hash = encode(sha256(convert_to(payload::text, 'UTF8')), 'hex')
  ),
  constraint approval_request_no_fractions check (private.json_has_no_fractions(payload))
);

-- The steps are copied from the matrix when the request is created, so a later matrix change
-- never alters an approval already in progress.
create table public.approval_request_step (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenant (id),
  request_id uuid not null,
  step_no integer not null check (step_no >= 1),
  -- null: any holder of the approve permission may decide (used when no matrix band applies).
  role_id uuid,
  required_approvals integer not null default 1 check (required_approvals >= 1),
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  row_version integer not null default 1,
  unique (tenant_id, id),
  unique (request_id, step_no),
  foreign key (tenant_id, request_id) references public.approval_request (tenant_id, id),
  foreign key (tenant_id, role_id) references public.role (tenant_id, id)
);

create table public.approval_decision (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenant (id),
  request_id uuid not null,
  step_no integer not null,
  decided_by uuid not null,
  decision text not null check (decision in ('approve', 'reject')),
  reason text,
  decided_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  row_version integer not null default 1,
  unique (tenant_id, id),
  -- Nobody decides two steps of the same request.
  unique (request_id, decided_by),
  foreign key (tenant_id, request_id) references public.approval_request (tenant_id, id),
  foreign key (tenant_id, decided_by) references public.app_user (tenant_id, id),
  check (decision = 'approve' or length(btrim(coalesce(reason, ''))) > 0)
);

-- Link role grants and (in 0006) rule versions back to the request that authorised them.
alter table public.user_role
  add constraint user_role_approval_request_fk
  foreign key (tenant_id, approval_request_id) references public.approval_request (tenant_id, id);
alter table public.approval_matrix
  add constraint approval_matrix_activation_request_fk
  foreign key (tenant_id, activation_request_id) references public.approval_request (tenant_id, id);

select private.apply_tenant_rls('public.approval_matrix');
select private.apply_tenant_rls('public.approval_matrix_step');
select private.apply_tenant_rls('public.approval_request');
select private.apply_tenant_rls('public.approval_request_step');
select private.apply_tenant_rls('public.approval_decision');
grant select on public.approval_request, public.approval_request_step, public.approval_decision,
  public.approval_matrix, public.approval_matrix_step to authenticated;

-- Configurators (product_rule_config:create) draft matrix bands directly; status and request
-- links change only through the guarded functions below.
drop policy approval_matrix_tenant_ins on public.approval_matrix;
drop policy approval_matrix_tenant_upd on public.approval_matrix;
create policy approval_matrix_tenant_ins on public.approval_matrix for insert to authenticated
  with check (
    tenant_id = (select private.current_tenant_id())
    and (select private.has_permission('product_rule_config', 'create'))
  );
create policy approval_matrix_tenant_upd on public.approval_matrix for update to authenticated
  using (
    tenant_id = (select private.current_tenant_id())
    and (select private.has_permission('product_rule_config', 'create'))
  )
  with check (
    tenant_id = (select private.current_tenant_id())
    and (select private.has_permission('product_rule_config', 'create'))
  );
drop policy approval_matrix_step_tenant_ins on public.approval_matrix_step;
drop policy approval_matrix_step_tenant_upd on public.approval_matrix_step;
create policy approval_matrix_step_tenant_ins on public.approval_matrix_step for insert to authenticated
  with check (
    tenant_id = (select private.current_tenant_id())
    and (select private.has_permission('product_rule_config', 'create'))
  );
create policy approval_matrix_step_tenant_upd on public.approval_matrix_step for update to authenticated
  using (
    tenant_id = (select private.current_tenant_id())
    and (select private.has_permission('product_rule_config', 'create'))
  )
  with check (
    tenant_id = (select private.current_tenant_id())
    and (select private.has_permission('product_rule_config', 'create'))
  );
grant insert (txn_type, product_id, min_amount, max_amount, effective_from, supersedes_id)
  on public.approval_matrix to authenticated;
grant update (min_amount, max_amount, effective_from) on public.approval_matrix to authenticated;
grant insert (matrix_id, step_no, role_id, required_approvals) on public.approval_matrix_step to authenticated;
grant update (step_no, role_id, required_approvals) on public.approval_matrix_step to authenticated;

-- Triggers: audit columns, no deletes, append-only where it applies.
create trigger approval_matrix_touch before insert or update on public.approval_matrix
  for each row execute function private.touch_row();
create trigger approval_matrix_no_delete before delete on public.approval_matrix
  for each row execute function private.block_delete();
create trigger approval_matrix_step_touch before insert or update on public.approval_matrix_step
  for each row execute function private.touch_row();
create trigger approval_matrix_step_no_delete before delete on public.approval_matrix_step
  for each row execute function private.block_delete();
create trigger approval_request_touch before insert or update on public.approval_request
  for each row execute function private.touch_row();
create trigger approval_request_no_delete before delete on public.approval_request
  for each row execute function private.block_delete();
create trigger approval_request_step_touch before insert on public.approval_request_step
  for each row execute function private.touch_row();
create trigger approval_request_step_append_only before update or delete on public.approval_request_step
  for each row execute function private.block_update();
create trigger approval_decision_touch before insert on public.approval_decision
  for each row execute function private.touch_row();
create trigger approval_decision_append_only before update or delete on public.approval_decision
  for each row execute function private.block_update();
select private.audit_table('public.approval_matrix');
select private.audit_table('public.approval_matrix_step');
select private.audit_table('public.approval_request');
select private.audit_table('public.approval_request_step');
select private.audit_table('public.approval_decision');

-- ---------------------------------------------------------------------------
-- Matrix drafts are editable only while draft; bands and steps freeze on submission.
-- ---------------------------------------------------------------------------
create function private.guard_approval_matrix() returns trigger
  language plpgsql security definer set search_path = ''
  as $$
declare
  v_executing text := nullif(current_setting('icoops.executing_request', true), '');
begin
  if tg_op = 'INSERT' then
    if new.status <> 'draft' then
      raise exception 'a matrix band is created as a draft';
    end if;
    return new;
  end if;
  if old.status <> 'draft' and (
    new.txn_type, new.product_id, new.min_amount, new.max_amount, new.effective_from, new.supersedes_id
  ) is distinct from (
    old.txn_type, old.product_id, old.min_amount, old.max_amount, old.effective_from, old.supersedes_id
  ) then
    raise exception 'approval matrix band is frozen once submitted';
  end if;
  if new.status is distinct from old.status then
    if not (
      (old.status = 'draft' and new.status = 'submitted')
      or (old.status = 'submitted' and new.status in ('rejected', 'withdrawn'))
      or (old.status = 'submitted' and new.status = 'active')
      or (old.status = 'active' and new.status = 'retired')
    ) then
      raise exception 'invalid matrix status change % -> %', old.status, new.status;
    end if;
    -- Activation and retirement happen only inside the executor of an approved request.
    if new.status = 'active' and v_executing is distinct from new.activation_request_id::text then
      raise exception 'a matrix band becomes active only through its approved request';
    end if;
    if new.status = 'retired' and v_executing is null then
      raise exception 'a matrix band is retired only by the approved request that supersedes it';
    end if;
  end if;
  return new;
end
$$;
create trigger approval_matrix_guard before insert or update on public.approval_matrix
  for each row execute function private.guard_approval_matrix();

create function private.guard_approval_matrix_step() returns trigger
  language plpgsql security definer set search_path = ''
  as $$
declare
  v_status public.config_status_t;
begin
  select status into v_status from public.approval_matrix
  where id = new.matrix_id and tenant_id = new.tenant_id;
  if v_status is null then
    raise exception 'approval matrix band not found';
  end if;
  if v_status <> 'draft' then
    raise exception 'steps can change only while the matrix band is a draft';
  end if;
  if tg_op = 'UPDATE' and new.matrix_id <> old.matrix_id then
    raise exception 'a step cannot move to another band';
  end if;
  return new;
end
$$;
create trigger approval_matrix_step_guard before insert or update on public.approval_matrix_step
  for each row execute function private.guard_approval_matrix_step();

-- ---------------------------------------------------------------------------
-- Request types are a T0 catalogue held in code: each maps to the function whose permissions
-- govern it. Later slices add their types here.
-- ---------------------------------------------------------------------------
create function private.approval_type_function(p_type text) returns public.function_t
  language sql immutable set search_path = ''
  as $$
    select case p_type
      when 'rule_version_activation' then 'product_rule_config'
      when 'rule_version_backdating' then 'product_rule_config'
      when 'approval_matrix_activation' then 'product_rule_config'
      when 'user_role_grant' then 'users_roles'
      when 'withdrawal_above_limit' then 'withdrawal_above_limit'
    end::public.function_t
  $$;

-- Amount band lookup: the steps for a transaction type and amount, or one open step when no
-- band applies. Bands are half-open [min, max).
create function private.resolve_approval_steps(p_tenant uuid, p_type text, p_amount numeric)
  returns table (step_no integer, role_id uuid, required_approvals integer)
  language plpgsql stable security definer set search_path = ''
  as $$
declare
  v_matrix uuid;
begin
  select m.id into v_matrix
  from public.approval_matrix m
  where m.tenant_id = p_tenant
    and m.status = 'active'
    and m.txn_type = p_type
    and m.product_id is null
    and m.effective_from <= current_date
    and m.min_amount <= coalesce(p_amount, 0)
    and (m.max_amount is null or coalesce(p_amount, 0) < m.max_amount);
  if v_matrix is null then
    return query select 1, null::uuid, 1;
  else
    return query
      select s.step_no, s.role_id, s.required_approvals
      from public.approval_matrix_step s
      where s.matrix_id = v_matrix
      order by s.step_no;
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- Creating a request (internal; the public entry points check the maker's permission).
-- ---------------------------------------------------------------------------
create function private.create_request(
  p_type text,
  p_subject_table text,
  p_subject_id uuid,
  p_amount numeric,
  p_payload jsonb,
  p_extra_excluded uuid[] default '{}'
) returns uuid
  language plpgsql security definer set search_path = ''
  as $$
declare
  v_tenant uuid := private.current_tenant_id();
  v_maker uuid := private.current_app_user_id();
  v_function public.function_t := private.approval_type_function(p_type);
  v_excluded uuid[];
  v_id uuid;
begin
  if v_maker is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  if v_function is null then
    raise exception 'unknown approval request type %', p_type;
  end if;
  if not private.user_can(v_maker, v_function, 'create') then
    raise exception 'missing permission %:create', v_function using errcode = '42501';
  end if;

  select coalesce(array_agg(distinct a.actor_user_id), '{}') into v_excluded
  from public.audit_log a
  where a.tenant_id = v_tenant
    and a.entity = p_subject_table
    and a.entity_id = p_subject_id
    and a.actor_user_id is not null;
  v_excluded := (select array_agg(distinct x) from unnest(v_excluded || p_extra_excluded || array[v_maker]) x);

  insert into public.approval_request
    (tenant_id, request_type, subject_table, subject_id, amount, payload, payload_hash,
     maker_user_id, excluded_user_ids)
  values
    (v_tenant, p_type, p_subject_table, p_subject_id, p_amount, p_payload,
     encode(sha256(convert_to(p_payload::text, 'UTF8')), 'hex'), v_maker, v_excluded)
  returning id into v_id;

  insert into public.approval_request_step (tenant_id, request_id, step_no, role_id, required_approvals)
  select v_tenant, v_id, s.step_no, s.role_id, s.required_approvals
  from private.resolve_approval_steps(v_tenant, p_type, p_amount) s;

  return v_id;
end
$$;

-- Public entry point for request types whose subject is owned by a later slice. Types with
-- their own submit function (rule versions, matrix bands, role grants) are not creatable here.
create function public.create_approval_request(
  p_type text, p_subject_table text, p_subject_id uuid, p_amount numeric, p_payload jsonb
) returns uuid
  language plpgsql security definer set search_path = ''
  as $$
begin
  if p_type is distinct from 'withdrawal_above_limit' then
    raise exception 'request type % is created through its own function', p_type;
  end if;
  return private.create_request(p_type, p_subject_table, p_subject_id, p_amount, p_payload);
end
$$;

-- ---------------------------------------------------------------------------
-- Deciding. All the rules live in the BEFORE INSERT trigger so that no route bypasses them.
-- ---------------------------------------------------------------------------
create function private.check_approval_decision() returns trigger
  language plpgsql security definer set search_path = ''
  as $$
declare
  v_user uuid := private.current_app_user_id();
  v_req public.approval_request%rowtype;
  v_step public.approval_request_step%rowtype;
  v_function public.function_t;
begin
  if v_user is null then
    raise exception 'approval decisions need a signed-in active user' using errcode = '42501';
  end if;
  select * into v_req from public.approval_request where id = new.request_id for update;
  if not found or v_req.tenant_id <> private.current_tenant_id() then
    raise exception 'approval request not found';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'request is already %', v_req.status;
  end if;

  -- The maker, the step and the time are never taken from the client.
  new.tenant_id := v_req.tenant_id;
  new.decided_by := v_user;
  new.decided_at := now();
  new.step_no := v_req.current_step;

  if v_user = v_req.maker_user_id or v_user = any (v_req.excluded_user_ids) then
    raise exception 'maker-checker: the maker or an editor of the subject cannot decide'
      using errcode = '42501';
  end if;
  if exists (select 1 from public.approval_decision d where d.request_id = v_req.id and d.decided_by = v_user) then
    raise exception 'maker-checker: you already decided a step of this request'
      using errcode = '42501';
  end if;
  if coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
    raise exception 'approvals need a second-factor sign-in (aal2)' using errcode = '42501';
  end if;

  select * into v_step from public.approval_request_step
  where request_id = v_req.id and step_no = v_req.current_step;
  if v_step.role_id is not null and not exists (
    select 1 from public.user_role ur
    where ur.user_id = v_user and ur.role_id = v_step.role_id
      and ur.valid_from <= now() and (ur.valid_to is null or ur.valid_to > now())
  ) then
    raise exception 'step % needs a role you do not hold', v_step.step_no using errcode = '42501';
  end if;

  v_function := private.approval_type_function(v_req.request_type);
  if not private.user_can(v_user, v_function, 'approve', v_req.amount) then
    raise exception 'missing permission %:approve for this amount', v_function using errcode = '42501';
  end if;
  return new;
end
$$;
create trigger approval_decision_check before insert on public.approval_decision
  for each row execute function private.check_approval_decision();

-- Advances (or closes) the request after a decision.
create function private.advance_approval_request() returns trigger
  language plpgsql security definer set search_path = ''
  as $$
declare
  v_req public.approval_request%rowtype;
  v_step public.approval_request_step%rowtype;
  v_approvals integer;
begin
  select * into v_req from public.approval_request where id = new.request_id for update;
  if new.decision = 'reject' then
    update public.approval_request set status = 'rejected', decided_at = now() where id = v_req.id;
    perform private.on_request_closed(v_req.id, 'rejected');
    return null;
  end if;
  select * into v_step from public.approval_request_step
  where request_id = v_req.id and step_no = v_req.current_step;
  select count(*) into v_approvals from public.approval_decision d
  where d.request_id = v_req.id and d.step_no = v_req.current_step and d.decision = 'approve';
  if v_approvals >= v_step.required_approvals then
    if exists (select 1 from public.approval_request_step s
               where s.request_id = v_req.id and s.step_no = v_req.current_step + 1) then
      update public.approval_request set current_step = current_step + 1 where id = v_req.id;
    else
      update public.approval_request set status = 'approved', decided_at = now() where id = v_req.id;
    end if;
  end if;
  return null;
end
$$;
create trigger approval_decision_advance after insert on public.approval_decision
  for each row execute function private.advance_approval_request();

-- Requests are immutable except for their progress columns, and status moves one way.
create function private.guard_approval_request() returns trigger
  language plpgsql set search_path = ''
  as $$
declare
  v_progress text[] := array[
    'status', 'current_step', 'decided_at', 'executed_at', 'updated_at', 'updated_by', 'row_version'
  ];
begin
  if (to_jsonb(old) - v_progress) is distinct from (to_jsonb(new) - v_progress) then
    raise exception 'an approval request cannot be edited after creation';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'pending' and new.status in ('approved', 'rejected', 'cancelled'))
    or (old.status = 'approved' and new.status = 'executed')
  ) then
    raise exception 'invalid request status change % -> %', old.status, new.status;
  end if;
  return new;
end
$$;
create trigger approval_request_guard before update on public.approval_request
  for each row execute function private.guard_approval_request();

create function public.decide_approval_request(p_request_id uuid, p_decision text, p_reason text default null)
  returns void
  language plpgsql security definer set search_path = ''
  as $$
begin
  -- The trigger on approval_decision enforces every rule and fills decided_by, step and time.
  insert into public.approval_decision (tenant_id, request_id, step_no, decided_by, decision, reason)
  values (private.current_tenant_id(), p_request_id, 0, private.current_app_user_id(), p_decision, p_reason);
end
$$;

-- The maker may withdraw a pending request.
create function public.cancel_approval_request(p_request_id uuid, p_reason text default null)
  returns void
  language plpgsql security definer set search_path = ''
  as $$
declare
  v_req public.approval_request%rowtype;
begin
  select * into v_req from public.approval_request
  where id = p_request_id and tenant_id = private.current_tenant_id() for update;
  if not found then
    raise exception 'approval request not found';
  end if;
  if v_req.maker_user_id is distinct from private.current_app_user_id() then
    raise exception 'only the maker can cancel a request' using errcode = '42501';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'request is already %', v_req.status;
  end if;
  perform set_config('icoops.reason', coalesce(p_reason, ''), true);
  update public.approval_request set status = 'cancelled', decided_at = now() where id = v_req.id;
  perform private.on_request_closed(v_req.id, 'cancelled');
  perform set_config('icoops.reason', '', true);
end
$$;

-- Hook for the subjects that track their request: filled in 0006 (rule versions, matrix bands).
create function private.on_request_closed(p_request uuid, p_status text) returns void
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
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- Dedicated submit functions for the types whose subject lives in this migration.
-- ---------------------------------------------------------------------------
create function public.submit_approval_matrix(p_matrix_id uuid) returns uuid
  language plpgsql security definer set search_path = ''
  as $$
declare
  v_tenant uuid := private.current_tenant_id();
  v_matrix public.approval_matrix%rowtype;
  v_request uuid;
begin
  select * into v_matrix from public.approval_matrix
  where id = p_matrix_id and tenant_id = v_tenant for update;
  if not found then
    raise exception 'approval matrix band not found';
  end if;
  if v_matrix.status <> 'draft' then
    raise exception 'only a draft band can be submitted';
  end if;
  if not exists (select 1 from public.approval_matrix_step where matrix_id = v_matrix.id) then
    raise exception 'a band needs at least one step';
  end if;
  v_request := private.create_request(
    'approval_matrix_activation', 'approval_matrix', v_matrix.id, null,
    jsonb_build_object('matrix_id', v_matrix.id, 'txn_type', v_matrix.txn_type));
  update public.approval_matrix
  set status = 'submitted', activation_request_id = v_request
  where id = v_matrix.id;
  return v_request;
end
$$;

create function public.request_user_role_grant(
  p_user_id uuid, p_role_id uuid, p_valid_from timestamptz default now(), p_valid_to timestamptz default null
) returns uuid
  language plpgsql security definer set search_path = ''
  as $$
declare
  v_tenant uuid := private.current_tenant_id();
begin
  if not exists (select 1 from public.app_user where id = p_user_id and tenant_id = v_tenant) then
    raise exception 'user not found';
  end if;
  if not exists (select 1 from public.role where id = p_role_id and tenant_id = v_tenant) then
    raise exception 'role not found';
  end if;
  -- The person receiving the role can never approve their own grant.
  return private.create_request(
    'user_role_grant', 'app_user', p_user_id, null,
    jsonb_build_object(
      'user_id', p_user_id, 'role_id', p_role_id,
      'valid_from', p_valid_from, 'valid_to', p_valid_to),
    array[p_user_id]);
end
$$;

-- ---------------------------------------------------------------------------
-- Execution: the only way an approved request changes anything. Re-verifies the payload hash
-- and runs the executor for the request type. A type with no executor yet cannot be executed.
-- ---------------------------------------------------------------------------
create function private.exec_matrix_activation(p_req public.approval_request) returns void
  language plpgsql security definer set search_path = ''
  as $$
declare
  v_matrix public.approval_matrix%rowtype;
begin
  select * into v_matrix from public.approval_matrix
  where id = p_req.subject_id and tenant_id = p_req.tenant_id
    and activation_request_id = p_req.id and status = 'submitted' for update;
  if not found then
    raise exception 'matrix band is not awaiting this request';
  end if;
  if v_matrix.supersedes_id is not null then
    update public.approval_matrix set status = 'retired'
    where id = v_matrix.supersedes_id and tenant_id = p_req.tenant_id and status = 'active';
  end if;
  update public.approval_matrix set status = 'active' where id = v_matrix.id;
end
$$;

create function private.exec_user_role_grant(p_req public.approval_request) returns void
  language plpgsql security definer set search_path = ''
  as $$
begin
  insert into public.user_role (tenant_id, user_id, role_id, valid_from, valid_to, granted_by, approval_request_id)
  values (
    p_req.tenant_id,
    (p_req.payload ->> 'user_id')::uuid,
    (p_req.payload ->> 'role_id')::uuid,
    coalesce((p_req.payload ->> 'valid_from')::timestamptz, now()),
    (p_req.payload ->> 'valid_to')::timestamptz,
    p_req.maker_user_id,
    p_req.id
  );
end
$$;

create function public.execute_approval_request(p_request_id uuid) returns void
  language plpgsql security definer set search_path = ''
  as $$
declare
  v_me uuid := private.current_app_user_id();
  v_req public.approval_request%rowtype;
  v_function public.function_t;
begin
  select * into v_req from public.approval_request
  where id = p_request_id and tenant_id = private.current_tenant_id() for update;
  if not found then
    raise exception 'approval request not found';
  end if;
  v_function := private.approval_type_function(v_req.request_type);
  if v_me is null or not (
    v_me = v_req.maker_user_id
    or private.user_can(v_me, v_function, 'approve')
    or private.user_can(v_me, v_function, 'create')
  ) then
    raise exception 'not allowed to execute this request' using errcode = '42501';
  end if;
  if v_req.status <> 'approved' then
    raise exception 'request is %, only approved requests execute', v_req.status;
  end if;
  if v_req.payload_hash <> encode(sha256(convert_to(v_req.payload::text, 'UTF8')), 'hex') then
    raise exception 'payload does not match the approved hash';
  end if;

  -- Tells the guard triggers that the change comes from an approved request.
  perform set_config('icoops.executing_request', v_req.id::text, true);
  case v_req.request_type
    when 'approval_matrix_activation' then perform private.exec_matrix_activation(v_req);
    when 'user_role_grant' then perform private.exec_user_role_grant(v_req);
    when 'rule_version_activation', 'rule_version_backdating' then
      perform private.exec_rule_version_activation(v_req);
    else raise exception 'request type % has no executor yet', v_req.request_type;
  end case;
  update public.approval_request set status = 'executed', executed_at = now() where id = v_req.id;
  perform set_config('icoops.executing_request', '', true);
end
$$;

-- Public functions: signed-in users only.
revoke execute on function
  public.create_approval_request(text, text, uuid, numeric, jsonb),
  public.decide_approval_request(uuid, text, text),
  public.cancel_approval_request(uuid, text),
  public.submit_approval_matrix(uuid),
  public.request_user_role_grant(uuid, uuid, timestamptz, timestamptz),
  public.execute_approval_request(uuid)
  from public, anon;
grant execute on function
  public.create_approval_request(text, text, uuid, numeric, jsonb),
  public.decide_approval_request(uuid, text, text),
  public.cancel_approval_request(uuid, text),
  public.submit_approval_matrix(uuid),
  public.request_user_role_grant(uuid, uuid, timestamptz, timestamptz),
  public.execute_approval_request(uuid)
  to authenticated;
