-- NF-009, PL-023: the audit log is append-only for every role, records who did what with before
-- and after images, and is readable only with the audit_log:view permission.
begin;
select * from no_plan();

-- ---------------------------------------------------------------------------
-- 1. The platform path is audited as 'service'.
-- ---------------------------------------------------------------------------
select tests.service();
select set_config('t.new_tenant',
  public.admin_create_tenant('audit-co', 'Audit Co', 's1_private', null, '{"payroll_deduction": false}', true)::text, true);
select tests.superuser();
select is(
  (select count(*)::int from public.audit_log
   where entity = 'tenant' and entity_id = current_setting('t.new_tenant')::uuid
     and action = 'insert' and actor_kind = 'service' and actor_user_id is null
     and before is null and after ->> 'code' = 'audit-co'),
  1, 'tenant creation by the platform path is audited with actor_kind service');
select is(
  (select count(*)::int from public.audit_log
   where entity = 'role' and tenant_id = current_setting('t.new_tenant')::uuid),
  10, 'the ten template roles created with the tenant are audited too');

-- ---------------------------------------------------------------------------
-- 2. User changes carry the actor and before/after images.
-- ---------------------------------------------------------------------------
select tests.login('accountant.a@example.test');
with rv as (
  insert into public.rule_version (rule_type, scope, params, effective_from)
  values ('audit_test', 'tenant', '{"rate":"0.120000"}', current_date + 10) returning id
) select set_config('t.rv', id::text, true) from rv;
update public.rule_version set params = '{"rate":"0.130000"}' where id = current_setting('t.rv')::uuid;

select is(
  (select count(*)::int from public.audit_log
   where entity = 'rule_version' and entity_id = current_setting('t.rv')::uuid
     and action = 'insert' and actor_kind = 'user' and actor_user_id = tests.user_id('accountant', 'a')),
  1, 'a user insert is audited with the user as actor');
select is(
  (select (before -> 'params' ->> 'rate') || ' -> ' || (after -> 'params' ->> 'rate')
   from public.audit_log
   where entity = 'rule_version' and entity_id = current_setting('t.rv')::uuid and action = 'update'),
  '0.120000 -> 0.130000', 'an update records the before and after images');
select is(
  (select tenant_id from public.audit_log
   where entity = 'rule_version' and entity_id = current_setting('t.rv')::uuid and action = 'insert'),
  tests.tenant_id('a'), 'audit rows carry the tenant of the row they describe');

-- reasons travel with the change
select tests.login('teller.a@example.test');
select set_config('t.req',
  public.create_approval_request('withdrawal_above_limit', 'txn', gen_random_uuid(), 60000, '{"w":"1"}')::text, true);
select public.cancel_approval_request(current_setting('t.req')::uuid, 'duplicate entry');
select tests.superuser();
select is(
  (select reason from public.audit_log
   where entity = 'approval_request' and entity_id = current_setting('t.req')::uuid and action = 'update'
   order by id desc limit 1),
  'duplicate entry', 'the reason given for a change is stored in the audit log');

-- ---------------------------------------------------------------------------
-- 3. Reading the log needs audit_log:view on top of tenant membership.
-- ---------------------------------------------------------------------------
select tests.login('teller.a@example.test');
select is_empty($$ select 1 from public.audit_log $$, 'a teller sees no audit rows');
select tests.login('auditor.a@example.test');
select isnt_empty($$ select 1 from public.audit_log where entity = 'rule_version' $$,
  'an auditor sees the tenant''s audit rows');
select is_empty($$ select 1 from public.audit_log where tenant_id <> tests.tenant_id('a') $$,
  'an auditor sees no other tenant''s audit rows');

-- ---------------------------------------------------------------------------
-- 4. Append-only for everyone.
-- ---------------------------------------------------------------------------
select throws_ok($$ insert into public.audit_log (tenant_id, actor_kind, action, entity)
                    values (tests.tenant_id('a'), 'user', 'insert', 'forged') $$,
  '42501', null, 'a signed-in user cannot write an audit row');
select throws_ok($$ update public.audit_log set reason = 'edited' $$,
  '42501', null, 'a signed-in user cannot update audit rows');
select throws_ok($$ delete from public.audit_log $$,
  '42501', null, 'a signed-in user cannot delete audit rows');
select tests.service();
select throws_ok($$ delete from public.audit_log $$,
  '42501', null, 'the service key cannot delete audit rows');
select tests.superuser();
select throws_like($$ update public.audit_log set reason = 'edited' $$,
  '%append-only%', 'even the table owner cannot update audit rows');
select throws_like($$ delete from public.audit_log $$,
  '%append-only%', 'even the table owner cannot delete audit rows');
select throws_like($$ truncate public.audit_log $$,
  '%append-only%', 'even the table owner cannot truncate the audit log');

-- ---------------------------------------------------------------------------
-- 5. Views of sensitive records are logged by explicit call.
-- ---------------------------------------------------------------------------
select tests.login('auditor.a@example.test');
select lives_ok(
  $$ select public.log_sensitive_view('rule_version', current_setting('t.rv')::uuid, 'quarterly review') $$,
  'a view can be logged');
select is(
  (select count(*)::int from public.audit_log
   where action = 'view' and entity = 'rule_version' and entity_id = current_setting('t.rv')::uuid
     and actor_user_id = tests.user_id('auditor', 'a') and reason = 'quarterly review'),
  1, 'the view is recorded with the viewer and the reason');
select throws_ok($$ select public.log_sensitive_view('not_a_table', gen_random_uuid()) $$,
  'P0001', 'unknown entity not_a_table', 'only real tenant tables can be named');

select * from finish();
rollback;
