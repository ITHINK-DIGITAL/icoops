-- PL-011, PL-012: a rule version cannot activate unless its worked examples exist and pass for
-- the exact parameters, and an approved maker-checker request authorises it. Content freezes on
-- submission; the effective-date lookup returns the version in force on a date.
begin;
select * from no_plan();

-- ---------------------------------------------------------------------------
-- 1. Drafts: examples are required, and only the runner can record results.
-- ---------------------------------------------------------------------------
select tests.login('accountant.a@example.test');
with rv as (
  insert into public.rule_version (rule_type, scope, params, effective_from)
  values ('gate_test', 'tenant', '{"rate":"0.120000"}', current_date + 1) returning id
) select set_config('t.rv', id::text, true) from rv;

select throws_like($$ select public.submit_rule_version(current_setting('t.rv')::uuid) $$,
  '%at least one normal worked example%', 'a draft without examples cannot be submitted');

insert into public.worked_example (rule_version_id, code, kind, inputs, expected)
values (current_setting('t.rv')::uuid, 'G-N', 'normal', '{"i":"1"}', '{"o":"1"}'),
       (current_setting('t.rv')::uuid, 'G-B', 'boundary', '{"i":"0"}', '{"o":"0"}');
select throws_like($$ select public.submit_rule_version(current_setting('t.rv')::uuid) $$,
  '%at least one exception worked example%', 'normal and boundary alone are not enough');

insert into public.worked_example (rule_version_id, code, kind, inputs, expected)
values (current_setting('t.rv')::uuid, 'G-E', 'exception', '{"i":"-1"}', '{"o":"err"}');
select throws_like($$ select public.submit_rule_version(current_setting('t.rv')::uuid) $$,
  '%3 worked example(s) have not passed%', 'examples that have never run block submission');

select throws_ok(
  $$ update public.worked_example set last_result = 'pass' where rule_version_id = current_setting('t.rv')::uuid $$,
  '42501', null, 'a user cannot mark an example as passed');
select throws_ok(
  $$ select public.record_worked_example_result(
       (select id from public.worked_example where code = 'G-N' limit 1), true, '{}', '{}', 'h', 'lib') $$,
  '42501', null, 'a user cannot call the run recorder');
select throws_ok($$ select public.record_worked_example_result(gen_random_uuid(), true, '{}', '{}', 'h', 'l') $$,
  '42501', null, 'anonymous-style callers are refused too');

-- the runner (service key) records results
select tests.service();
select throws_like(
  $$ select public.record_worked_example_result(
       (select id from public.worked_example where code = 'G-N' and rule_version_id = current_setting('t.rv')::uuid),
       true, '{"o":"1"}', '{}', 'not-the-current-hash', 'lib@1') $$,
  '%stale run%', 'a run against stale parameters is refused');
select tests.superuser();
select set_config('t.hash', (select params_hash from public.rule_version where id = current_setting('t.rv')::uuid), true);
select tests.service();
select public.record_worked_example_result(id, code <> 'G-E', '{}', '{}', current_setting('t.hash'), 'lib@1')
from public.worked_example where rule_version_id = current_setting('t.rv')::uuid;
select tests.login('accountant.a@example.test');
select throws_like($$ select public.submit_rule_version(current_setting('t.rv')::uuid) $$,
  '%1 worked example(s) have not passed%', 'one failing example blocks submission');

-- changing parameters invalidates every earlier run
update public.rule_version set params = '{"rate":"0.125000"}' where id = current_setting('t.rv')::uuid;
select throws_like($$ select public.submit_rule_version(current_setting('t.rv')::uuid) $$,
  '%3 worked example(s) have not passed%', 'new parameters need new runs');
select throws_ok(
  $$ update public.rule_version set params = '{"rate":0.125}' where id = current_setting('t.rv')::uuid $$,
  '23514', null, 'a fractional JSON number is rejected: decimals are strings');
select throws_ok(
  $$ update public.worked_example set expected = '{"o":1.5}' where code = 'G-N' $$,
  '23514', null, 'fractional numbers are rejected in examples too');

select tests.superuser();
select set_config('t.hash', (select params_hash from public.rule_version where id = current_setting('t.rv')::uuid), true);
select tests.service();
select public.record_worked_example_result(id, true, '{}', '{}', current_setting('t.hash'), 'lib@1')
from public.worked_example where rule_version_id = current_setting('t.rv')::uuid;

-- editing an example discards its result
select tests.login('accountant.a@example.test');
update public.worked_example set expected = '{"o":"2"}' where code = 'G-B' and rule_version_id = current_setting('t.rv')::uuid;
select is((select last_result from public.worked_example where code = 'G-B' and rule_version_id = current_setting('t.rv')::uuid),
  null, 'editing an example clears its last result');
select throws_like($$ select public.submit_rule_version(current_setting('t.rv')::uuid) $$,
  '%1 worked example(s) have not passed%', 'an edited example must run again');
select tests.service();
select public.record_worked_example_result(id, true, '{}', '{}', current_setting('t.hash'), 'lib@1')
from public.worked_example where code = 'G-B' and rule_version_id = current_setting('t.rv')::uuid;

-- ---------------------------------------------------------------------------
-- 2. Submission freezes the version and opens a maker-checker request.
-- ---------------------------------------------------------------------------
select tests.login('accountant.a@example.test');
select set_config('t.req', public.submit_rule_version(current_setting('t.rv')::uuid)::text, true);
select is((select request_type from public.approval_request where id = current_setting('t.req')::uuid),
  'rule_version_activation', 'a future-dated version opens an activation request');
select is((select status::text from public.rule_version where id = current_setting('t.rv')::uuid),
  'submitted', 'the version is submitted');
select throws_like(
  $$ update public.rule_version set params = '{"rate":"0.999999"}' where id = current_setting('t.rv')::uuid $$,
  '%frozen%', 'parameters are frozen once submitted');
select throws_like(
  $$ update public.worked_example set expected = '{"o":"9"}' where code = 'G-N' and rule_version_id = current_setting('t.rv')::uuid $$,
  '%only while the rule version is a draft%', 'examples are frozen once submitted');
select throws_like(
  $$ insert into public.worked_example (rule_version_id, code, kind, inputs, expected)
     values (current_setting('t.rv')::uuid, 'G-X', 'normal', '{}', '{}') $$,
  '%only while the rule version is a draft%', 'no examples can be added once submitted');
select throws_ok(
  $$ update public.rule_version set status = 'active' where id = current_setting('t.rv')::uuid $$,
  '42501', null, 'a user cannot set a version active directly');
select tests.superuser();
select throws_like(
  $$ update public.rule_version set status = 'active' where id = current_setting('t.rv')::uuid $$,
  '%only through its approved request%', 'even the owner cannot skip the approved request');
select throws_like(
  $$ update public.rule_version set status = 'draft' where id = current_setting('t.rv')::uuid $$,
  '%invalid rule version status change%', 'a submitted version cannot go back to draft');

-- ---------------------------------------------------------------------------
-- 3. The gate is checked again at execution, after approval.
-- ---------------------------------------------------------------------------
select tests.login('accountant.a@example.test');
select throws_like($$ select public.decide_approval_request(current_setting('t.req')::uuid, 'approve') $$,
  '%maker-checker%', 'the configurator who submitted cannot approve');
select tests.login('gm.a@example.test');
select lives_ok($$ select public.decide_approval_request(current_setting('t.req')::uuid, 'approve') $$,
  'a GM approves the activation');

-- a failing re-run between approval and execution stops the activation
select tests.service();
select public.record_worked_example_result(id, false, '{}', '{"diff":"x"}', current_setting('t.hash'), 'lib@2')
from public.worked_example where code = 'G-N' and rule_version_id = current_setting('t.rv')::uuid;
select tests.login('accountant.a@example.test');
select throws_like($$ select public.execute_approval_request(current_setting('t.req')::uuid) $$,
  '%cannot activate%', 'an approved version still cannot activate while an example fails');
select is((select status::text from public.rule_version where id = current_setting('t.rv')::uuid),
  'submitted', 'the version stays submitted');
select tests.service();
select public.record_worked_example_result(id, true, '{}', '{}', current_setting('t.hash'), 'lib@2')
from public.worked_example where code = 'G-N' and rule_version_id = current_setting('t.rv')::uuid;
select tests.login('accountant.a@example.test');
select lives_ok($$ select public.execute_approval_request(current_setting('t.req')::uuid) $$,
  'once every example passes again, the approved version activates');
select is((select status::text from public.rule_version where id = current_setting('t.rv')::uuid),
  'active', 'the version is active');
select is((select activated_by from public.rule_version where id = current_setting('t.rv')::uuid),
  tests.user_id('gm', 'a'), 'the approver is recorded as the activator');
select is((select last_run_library from public.worked_example where code = 'G-N' and rule_version_id = current_setting('t.rv')::uuid),
  'lib@2', 'the library that produced the result is recorded (L5)');
select throws_like($$ select public.execute_approval_request(current_setting('t.req')::uuid) $$,
  '%only approved requests execute%', 'a request executes once');

-- ---------------------------------------------------------------------------
-- 4. Editors of the subject cannot approve even when someone else submitted it.
-- ---------------------------------------------------------------------------
select tests.superuser();
insert into public.user_role (tenant_id, user_id, role_id)
values (tests.tenant_id('a'), tests.user_id('accountant', 'a'), tests.role_id('gm', 'a'));
select tests.login('accountant.a@example.test');
with rv as (
  insert into public.rule_version (rule_type, scope, params, effective_from)
  values ('gate_editor', 'tenant', '{"rate":"0.100000"}', current_date + 2) returning id
) select set_config('t.rv2', id::text, true) from rv;
insert into public.worked_example (rule_version_id, code, kind, inputs, expected)
select current_setting('t.rv2')::uuid, 'E-' || k, k, '{}', '{}' from unnest(enum_range(null::public.example_kind_t)) k;
select tests.superuser();
select set_config('t.hash2', (select params_hash from public.rule_version where id = current_setting('t.rv2')::uuid), true);
select tests.service();
select public.record_worked_example_result(id, true, '{}', '{}', current_setting('t.hash2'), 'lib@1')
from public.worked_example where rule_version_id = current_setting('t.rv2')::uuid;
select tests.login('admin.a@example.test');
select set_config('t.req2', public.submit_rule_version(current_setting('t.rv2')::uuid)::text, true);
select tests.login('accountant.a@example.test');
select throws_like($$ select public.decide_approval_request(current_setting('t.req2')::uuid, 'approve') $$,
  '%maker-checker%', 'the person who drafted the version cannot approve it, though they hold the GM role');
select tests.login('gm.a@example.test');
select lives_ok($$ select public.decide_approval_request(current_setting('t.req2')::uuid, 'reject', 'wrong rate') $$,
  'a rejection is recorded');
select is((select status::text from public.rule_version where id = current_setting('t.rv2')::uuid),
  'rejected', 'a rejected request closes its rule version');

-- ---------------------------------------------------------------------------
-- 5. Back-dating needs its own approval type; cancelling withdraws the version.
-- ---------------------------------------------------------------------------
select tests.superuser();
select set_config('t.rv3', tests.passing_rule_version('a', 'gate_back', current_date - 5)::text, true);
select tests.login('accountant.a@example.test');
select set_config('t.req3', public.submit_rule_version(current_setting('t.rv3')::uuid)::text, true);
select is((select request_type from public.approval_request where id = current_setting('t.req3')::uuid),
  'rule_version_backdating', 'a past effective date opens a back-dating request');
select lives_ok($$ select public.cancel_approval_request(current_setting('t.req3')::uuid, 'not needed') $$,
  'the maker withdraws the request');
select is((select status::text from public.rule_version where id = current_setting('t.rv3')::uuid),
  'withdrawn', 'a cancelled request withdraws its rule version');

-- ---------------------------------------------------------------------------
-- 6. Only one active version per type, scope and effective date.
-- ---------------------------------------------------------------------------
select tests.superuser();
select set_config('t.same', tests.passing_rule_version('a', 'gate_dup', current_date + 40)::text, true);
select tests.activate_rule_version(current_setting('t.same')::uuid);
select set_config('t.same2', tests.passing_rule_version('a', 'gate_dup', current_date + 40, '{"rate":"0.2"}')::text, true);
select throws_ok($$ select tests.activate_rule_version(current_setting('t.same2')::uuid) $$,
  '23505', null, 'a second active version for the same type and date is refused');

-- ---------------------------------------------------------------------------
-- 7. Effective-date lookup: the version in force on a date; platform defaults are separate.
-- ---------------------------------------------------------------------------
select tests.superuser();
select set_config('t.v1', tests.passing_rule_version('a', 'lookup_test', current_date + 100, '{"rate":"0.100000"}')::text, true);
select set_config('t.v2', tests.passing_rule_version('a', 'lookup_test', current_date + 200, '{"rate":"0.150000"}')::text, true);
select tests.activate_rule_version(current_setting('t.v1')::uuid);
select tests.activate_rule_version(current_setting('t.v2')::uuid);
select tests.login('teller.a@example.test');
select is((select params ->> 'rate' from public.rule_version_in_force('lookup_test', 'tenant', null, current_date + 99)),
  null, 'before the first effective date nothing is in force');
select is((select params ->> 'rate' from public.rule_version_in_force('lookup_test', 'tenant', null, current_date + 100)),
  '0.100000', 'on the first effective date the first version applies');
select is((select params ->> 'rate' from public.rule_version_in_force('lookup_test', 'tenant', null, current_date + 199)),
  '0.100000', 'the day before the second version the first still applies');
select is((select params ->> 'rate' from public.rule_version_in_force('lookup_test', 'tenant', null, current_date + 200)),
  '0.150000', 'on the second effective date the new version applies');
select tests.login('teller.b@example.test');
select is_empty($$ select 1 from public.rule_version_in_force('lookup_test', 'tenant', null, current_date + 300) $$,
  'another tenant''s versions are not in force for me');

-- platform defaults: released by the table owner after the gate, never through the API roles
select tests.superuser();
with rv as (
  insert into public.rule_version (tenant_id, rule_type, scope, params, effective_from)
  values (private.platform_tenant_id(), 'plat_release', 'platform', '{"rate":"0.050000"}', current_date) returning id
) select set_config('t.plat2', id::text, true) from rv;
select throws_like(
  $$ update public.rule_version set status = 'active' where id = current_setting('t.plat2')::uuid $$,
  '%cannot activate%', 'a platform release is gated too: no examples, no activation');
select tests.service();
select throws_like(
  $$ update public.rule_version set status = 'active' where id = current_setting('t.plat2')::uuid $$,
  '%invalid rule version status change%', 'the service key cannot release platform defaults');

select * from finish();
rollback;
