-- AT-13: a user of tenant A cannot read or write any row of tenant B through the database
-- API, and the reverse. The matrix is generated from the catalog (tests.isolation_violations),
-- then specific cases cover the tables with direct write grants, the guarded functions, the
-- platform-tenant exception, disabled users and suspended tenants.
begin;
select * from no_plan();

-- Data for both tenants, written as the table owner. Each tenant gets one of everything that
-- carries tenant data in slice 1, so the matrix has rows to (fail to) reach.
select tests.superuser();
insert into public.rule_version (tenant_id, rule_type, scope, params, effective_from)
values
  (tests.tenant_id('a'), 'iso_test', 'tenant', '{"k":"a"}', current_date + 30),
  (tests.tenant_id('b'), 'iso_test', 'tenant', '{"k":"b"}', current_date + 30);
insert into public.worked_example (tenant_id, rule_version_id, code, kind, inputs, expected)
select rv.tenant_id, rv.id, 'ISO-01', 'normal', '{"x":"1"}', '{"y":"1"}'
from public.rule_version rv where rv.rule_type = 'iso_test';
insert into public.approval_matrix (tenant_id, txn_type, min_amount, max_amount, effective_from)
values
  (tests.tenant_id('a'), 'withdrawal_above_limit', 0, 1000, current_date),
  (tests.tenant_id('b'), 'withdrawal_above_limit', 0, 1000, current_date);

select tests.login('teller.a@example.test');
select public.create_approval_request('withdrawal_above_limit', 'txn', gen_random_uuid(), 60000, '{"n":"a"}');
select tests.login('teller.b@example.test');
select public.create_approval_request('withdrawal_above_limit', 'txn', gen_random_uuid(), 60000, '{"n":"b"}');

select tests.superuser();
select set_config('t.rv_a', (select id::text from public.rule_version where tenant_id = tests.tenant_id('a') and rule_type = 'iso_test'), true);
select set_config('t.rv_b', (select id::text from public.rule_version where tenant_id = tests.tenant_id('b') and rule_type = 'iso_test'), true);
select set_config('t.ex_b', (select id::text from public.worked_example where tenant_id = tests.tenant_id('b')), true);
select set_config('t.mx_b', (select id::text from public.approval_matrix where tenant_id = tests.tenant_id('b')), true);
select set_config('t.req_b', (select id::text from public.approval_request where tenant_id = tests.tenant_id('b')), true);

-- ---------------------------------------------------------------------------
-- 1. Generated matrix, every table, both directions, for several roles.
-- ---------------------------------------------------------------------------
select tests.login('admin.a@example.test');
select is_empty($$ select * from tests.isolation_violations(tests.tenant_id('b')) $$,
  'A tenant administrator of A cannot reach any B row on any table');
select tests.login('gm.a@example.test');
select is_empty($$ select * from tests.isolation_violations(tests.tenant_id('b')) $$,
  'A general manager of A cannot reach any B row on any table');
select tests.login('accountant.a@example.test');
select is_empty($$ select * from tests.isolation_violations(tests.tenant_id('b')) $$,
  'A configurator of A cannot reach any B row on any table');
select tests.login('auditor.b@example.test');
select is_empty($$ select * from tests.isolation_violations(tests.tenant_id('a')) $$,
  'An auditor of B cannot reach any A row on any table');
select tests.login('teller.b@example.test');
select is_empty($$ select * from tests.isolation_violations(tests.tenant_id('a')) $$,
  'A teller of B cannot reach any A row on any table');

select tests.anon();
select is_empty($$ select * from tests.anon_violations() $$,
  'The anonymous role sees and changes nothing on any table');

-- ---------------------------------------------------------------------------
-- 2. Tables with direct write grants: rows of the other tenant stay out of reach.
-- ---------------------------------------------------------------------------
select tests.login('accountant.a@example.test');
select is_empty(
  $$ update public.rule_version set effective_from = effective_from
     where id = current_setting('t.rv_b')::uuid returning id $$,
  'A cannot update B''s rule version');
select is_empty(
  $$ update public.worked_example set note = 'x'
     where id = current_setting('t.ex_b')::uuid returning id $$,
  'A cannot update B''s worked example');
select is_empty(
  $$ update public.approval_matrix set max_amount = 5000
     where id = current_setting('t.mx_b')::uuid returning id $$,
  'A cannot update B''s approval matrix band');
select is_empty(
  $$ select id from public.rule_version where id = current_setting('t.rv_b')::uuid $$,
  'A cannot read B''s rule version');
select throws_ok(
  $$ insert into public.worked_example (rule_version_id, code, kind, inputs, expected)
     values (current_setting('t.rv_b')::uuid, 'X', 'normal', '{}', '{}') $$,
  'P0001', 'rule version not found',
  'A cannot attach an example to B''s rule version');
select throws_ok(
  $$ insert into public.approval_matrix_step (matrix_id, step_no, role_id)
     values (current_setting('t.mx_b')::uuid, 1, tests.role_id('gm', 'a')) $$,
  'P0001', 'approval matrix band not found',
  'A cannot add a step to B''s approval matrix band');
select throws_ok(
  $$ insert into public.rule_version (tenant_id, rule_type, scope, params, effective_from)
     values (tests.tenant_id('b'), 'x', 'tenant', '{}', current_date) $$,
  '42501', null, 'A cannot write a rule version for B by naming tenant_id');

-- ---------------------------------------------------------------------------
-- 3. Guarded functions called with the other tenant's ids.
-- ---------------------------------------------------------------------------
select throws_ok($$ select public.submit_rule_version(current_setting('t.rv_b')::uuid) $$,
  'P0001', 'rule version not found', 'submit_rule_version refuses B''s version');
select throws_ok($$ select public.submit_approval_matrix(current_setting('t.mx_b')::uuid) $$,
  'P0001', 'approval matrix band not found', 'submit_approval_matrix refuses B''s band');
select throws_ok(
  $$ select public.request_user_role_grant(tests.user_id('teller', 'b'), tests.role_id('gm', 'a')) $$,
  'P0001', 'user not found', 'role grant refuses B''s user');
select throws_ok(
  $$ select public.request_user_role_grant(tests.user_id('teller', 'a'), tests.role_id('gm', 'b')) $$,
  'P0001', 'role not found', 'role grant refuses B''s role');
select throws_ok($$ select public.log_sensitive_view('rule_version', current_setting('t.rv_b')::uuid) $$,
  'P0001', 'record not found', 'log_sensitive_view refuses B''s row');
select throws_ok(
  $$ select public.record_worked_example_result(current_setting('t.ex_b')::uuid, true, '{}', '{}', 'h', 'lib') $$,
  '42501', null, 'the run recorder is closed to signed-in users');
select throws_ok(
  $$ select public.admin_create_tenant('intruder', 'Intruder', 's1_private') $$,
  '42501', null, 'tenant creation is closed to signed-in users');

select tests.login('gm.a@example.test');
select throws_ok($$ select public.decide_approval_request(current_setting('t.req_b')::uuid, 'approve') $$,
  'P0001', 'approval request not found', 'A cannot decide B''s approval request');
select throws_ok($$ select public.execute_approval_request(current_setting('t.req_b')::uuid) $$,
  'P0001', 'approval request not found', 'A cannot execute B''s approval request');
select tests.login('teller.a@example.test');
select throws_ok($$ select public.cancel_approval_request(current_setting('t.req_b')::uuid) $$,
  'P0001', 'approval request not found', 'A cannot cancel B''s approval request');

select tests.anon();
select throws_ok($$ select public.submit_rule_version(gen_random_uuid()) $$,
  '42501', null, 'anonymous cannot call guarded functions');
select throws_ok($$ select public.log_sensitive_view('rule_version', gen_random_uuid()) $$,
  '42501', null, 'anonymous cannot log views');

-- ---------------------------------------------------------------------------
-- 4. Cross-tenant references are impossible even for the platform path.
-- ---------------------------------------------------------------------------
select tests.superuser();
select throws_ok(
  $$ insert into public.user_role (tenant_id, user_id, role_id)
     values (tests.tenant_id('a'), tests.user_id('teller', 'a'), tests.role_id('gm', 'b')) $$,
  '23503', null, 'a role of B cannot be given to a user of A');
select throws_ok(
  $$ insert into public.approval_request
       (tenant_id, request_type, subject_table, subject_id, payload, payload_hash, maker_user_id)
     values (tests.tenant_id('a'), 'withdrawal_above_limit', 'txn', gen_random_uuid(), '{}',
             encode(sha256(convert_to('{}', 'UTF8')), 'hex'), tests.user_id('teller', 'b')) $$,
  '23503', null, 'a user of B cannot be the maker of a request of A');

-- ---------------------------------------------------------------------------
-- 5. Platform-owned rows: readable by every tenant, writable by none.
-- ---------------------------------------------------------------------------
insert into public.rule_version (tenant_id, rule_type, scope, params, effective_from)
values (private.platform_tenant_id(), 'iso_platform', 'platform', '{"default":"1"}', current_date);
insert into public.worked_example (tenant_id, rule_version_id, code, kind, inputs, expected)
select tenant_id, id, 'PLAT-01', 'normal', '{}', '{}' from public.rule_version where rule_type = 'iso_platform';

select tests.login('accountant.a@example.test');
select isnt_empty($$ select 1 from public.rule_version where rule_type = 'iso_platform' $$,
  'A can read the platform rule version');
select isnt_empty($$ select 1 from public.worked_example where code = 'PLAT-01' $$,
  'A can read the platform worked example');
select is_empty(
  $$ update public.rule_version set effective_from = effective_from
     where rule_type = 'iso_platform' returning id $$,
  'A cannot update a platform rule version');
select is_empty($$ select 1 from public.tenant where id = private.platform_tenant_id() $$,
  'A cannot read the platform tenant row');
select tests.login('accountant.b@example.test');
select isnt_empty($$ select 1 from public.rule_version where rule_type = 'iso_platform' $$,
  'B can read the platform rule version too');

-- ---------------------------------------------------------------------------
-- 6. Disabled users and suspended tenants see nothing immediately.
-- ---------------------------------------------------------------------------
select tests.superuser();
update public.app_user set status = 'disabled' where id = tests.user_id('gm', 'a');
select tests.login('gm.a@example.test');
select is_empty($$ select 1 from public.tenant $$, 'a disabled user sees no tenant');
select is_empty($$ select 1 from public.role $$, 'a disabled user sees no roles');
select throws_ok($$ select public.submit_rule_version(current_setting('t.rv_a')::uuid) $$,
  'P0001', 'rule version not found', 'a disabled user cannot call guarded functions');

select tests.superuser();
update public.tenant set status = 'suspended' where id = tests.tenant_id('b');
select tests.login('admin.b@example.test');
select is_empty($$ select 1 from public.app_user $$, 'users of a suspended tenant see nothing');
select tests.login('admin.a@example.test');
select isnt_empty($$ select 1 from public.app_user $$, 'other tenants are unaffected by a suspension');

select * from finish();
rollback;
