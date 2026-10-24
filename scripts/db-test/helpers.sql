-- Helpers for the pgTAP tests. Installed into the throwaway test database only, never into a
-- migration: they impersonate users by setting the JWT claims the API gateway would set.
create schema if not exists tests;
grant usage on schema tests to anon, authenticated, service_role;

-- Impersonate a seeded user. p_aal = 'aal2' simulates a second-factor sign-in.
create or replace function tests.login(p_email text, p_aal text default 'aal2') returns void
  language plpgsql as $$
declare
  v_id uuid;
begin
  reset role;
  select id into v_id from auth.users where email = p_email;
  if v_id is null then
    raise exception 'no such test user %', p_email;
  end if;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_id, 'role', 'authenticated', 'aal', p_aal, 'email', p_email)::text, true);
  set local role authenticated;
end $$;

create or replace function tests.anon() returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  set local role anon;
end $$;

-- The platform path: service key, no signed-in user.
create or replace function tests.service() returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  set local role service_role;
end $$;

create or replace function tests.superuser() returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', '', true);
end $$;

-- Ids of seeded rows, by tenant key ('a' or 'b').
create or replace function tests.tenant_id(p_key text) returns uuid language sql stable as $$
  select id from public.tenant where code = 'sandbox-' || p_key $$;
create or replace function tests.user_id(p_name text, p_key text) returns uuid language sql stable as $$
  select u.id from public.app_user u where u.email = p_name || '.' || p_key || '@example.test' $$;
create or replace function tests.role_id(p_code text, p_key text) returns uuid language sql stable as $$
  select r.id from public.role r where r.tenant_id = tests.tenant_id(p_key) and r.code = p_code $$;

grant execute on all functions in schema tests to anon, authenticated, service_role;

-- AT-13 matrix, generated from the catalog so that new tables are covered automatically.
-- Run it signed in as a user of one tenant, passing the id of another tenant. It returns one
-- row for every way the signed-in user could see or change the other tenant's data.
-- A probe is blocked when it raises insufficient_privilege (42501: privilege or RLS) or
-- affects no row. Platform-owned rows are the documented exception for reads.
create or replace function tests.isolation_violations(p_other uuid)
  returns table (tbl text, probe text)
  language plpgsql as $$
declare
  t record;
  n bigint;
begin
  for t in
    select c.relname
    from pg_class c
    join pg_namespace ns on ns.oid = c.relnamespace
    where ns.nspname = 'public' and c.relkind in ('r', 'p')
    order by c.relname
  loop
    -- reads: nothing of the other tenant, and nothing outside own tenant and platform
    begin
      execute format('select count(*) from public.%I where tenant_id = $1', t.relname) into n using p_other;
      if n > 0 then tbl := t.relname; probe := 'select returns other tenant rows'; return next; end if;
      execute format(
        'select count(*) from public.%I where tenant_id not in (private.current_tenant_id(), private.platform_tenant_id())',
        t.relname) into n;
      if n > 0 then tbl := t.relname; probe := 'select returns rows outside own tenant'; return next; end if;
    exception when insufficient_privilege then null;
    end;
    -- writes aimed at the other tenant: must be refused or touch nothing
    begin
      execute format('update public.%I set tenant_id = default where tenant_id = $1', t.relname) using p_other;
      get diagnostics n = row_count;
      if n > 0 then tbl := t.relname; probe := 'update changed other tenant rows'; return next; end if;
    exception when insufficient_privilege then null;
    end;
    begin
      execute format('delete from public.%I where tenant_id = $1', t.relname) using p_other;
      get diagnostics n = row_count;
      if n > 0 then tbl := t.relname; probe := 'delete removed other tenant rows'; return next; end if;
    exception when insufficient_privilege then null;
    end;
    begin
      -- tenant.tenant_id is generated from id, so that table is probed through id.
      execute format('insert into public.%I (%I) values ($1)', t.relname,
        case when exists (
          select 1 from pg_attribute a
          where a.attrelid = ('public.' || quote_ident(t.relname))::regclass
            and a.attname = 'tenant_id' and a.attgenerated <> '') then 'id' else 'tenant_id' end)
        using p_other;
      tbl := t.relname; probe := 'insert for other tenant succeeded'; return next;
    exception
      when insufficient_privilege then null;
      when others then
        tbl := t.relname; probe := 'insert for other tenant failed past the security layer: ' || sqlerrm;
        return next;
    end;
  end loop;
end $$;

-- Same idea for the anonymous role: it may see nothing and change nothing.
create or replace function tests.anon_violations()
  returns table (tbl text, probe text)
  language plpgsql as $$
declare
  t record;
  n bigint;
begin
  for t in
    select c.relname from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
    where ns.nspname = 'public' and c.relkind in ('r', 'p') order by c.relname
  loop
    begin
      execute format('select count(*) from public.%I', t.relname) into n;
      if n > 0 then tbl := t.relname; probe := 'anon select returned rows'; return next; end if;
    exception when insufficient_privilege then null;
    end;
    begin
      execute format('insert into public.%I (tenant_id) values (''00000000-0000-0000-0000-000000000001'')', t.relname);
      tbl := t.relname; probe := 'anon insert succeeded'; return next;
    exception when others then null;
    end;
  end loop;
end $$;

grant execute on all functions in schema tests to anon, authenticated, service_role;

-- A draft rule version for the tenant with one passing example of each kind (written as the
-- table owner; the runner path is covered by its own test).
create or replace function tests.passing_rule_version(
  p_key text, p_type text, p_effective date, p_params jsonb default '{"rate":"0.120000"}'
) returns uuid language plpgsql as $$
declare
  v_id uuid;
  v_tenant uuid := tests.tenant_id(p_key);
  v_kind public.example_kind_t;
  v_ex uuid;
begin
  reset role;
  insert into public.rule_version (tenant_id, rule_type, scope, params, effective_from)
  values (v_tenant, p_type, 'tenant', p_params, p_effective) returning id into v_id;
  foreach v_kind in array enum_range(null::public.example_kind_t) loop
    insert into public.worked_example (tenant_id, rule_version_id, code, kind, inputs, expected)
    values (v_tenant, v_id, upper(p_type) || '-' || v_kind, v_kind, '{"i":"1"}', '{"o":"1"}')
    returning id into v_ex;
    perform public.record_worked_example_result(
      v_ex, true, '{"o":"1"}', '{}',
      (select params_hash from public.rule_version where id = v_id), 'test-lib@0');
  end loop;
  return v_id;
end $$;

-- Full approved activation as the seeded accountant (maker), GM (checker), accountant (executor).
create or replace function tests.activate_rule_version(p_id uuid, p_key text default 'a')
  returns void language plpgsql as $$
declare
  v_req uuid;
begin
  perform tests.login('accountant.' || p_key || '@example.test');
  v_req := public.submit_rule_version(p_id);
  perform tests.login('gm.' || p_key || '@example.test');
  perform public.decide_approval_request(v_req, 'approve');
  perform tests.login('accountant.' || p_key || '@example.test');
  perform public.execute_approval_request(v_req);
  perform tests.superuser();
end $$;

grant execute on all functions in schema tests to anon, authenticated, service_role;
