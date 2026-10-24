-- PL-005, PL-006, PL-007, PL-021: segments, feature flags, the one-level federation hierarchy,
-- the FS role templates, permission checks, and the platform path.
begin;
select * from no_plan();

-- ---------------------------------------------------------------------------
-- Tenants: segment, features, hierarchy
-- ---------------------------------------------------------------------------
select tests.service();
select set_config('t.fed',
  public.admin_create_tenant('fed-one', 'Federation One', 's3_federation', null, '{}', true)::text, true);
select set_config('t.child',
  public.admin_create_tenant('member-one', 'Member One', 's1_private', current_setting('t.fed')::uuid, '{"payroll_deduction": true}', true)::text, true);
select tests.superuser();
select is((select parent_tenant_id from public.tenant where id = current_setting('t.child')::uuid),
  current_setting('t.fed')::uuid, 'a member co-op can sit under a federation');
select is((select (features ->> 'payroll_deduction')::boolean from public.tenant where id = current_setting('t.child')::uuid),
  true, 'feature flags are stored per tenant');

select tests.service();
select throws_like(
  $$ select public.admin_create_tenant('bad-parent', 'x', 's1_private', tests.tenant_id('a')) $$,
  '%must be a federation%', 'only a federation can be a parent');
select lives_ok(
  $$ select public.admin_create_tenant('member-two', 'Member Two', 's2_government', current_setting('t.fed')::uuid) $$,
  'a federation can have several member co-ops, S1 or S2');
select throws_like(
  $$ select public.admin_create_tenant('fed-in-fed', 'x', 's3_federation', current_setting('t.fed')::uuid) $$,
  '%only member co-ops%', 'a federation cannot sit under a federation');
select throws_like(
  $$ select public.admin_create_tenant('plat-2', 'x', 'platform') $$,
  '%reserved%', 'the platform tenant is reserved');
select throws_ok(
  $$ select public.admin_create_tenant('BAD CODE', 'x', 's1_private') $$,
  '23514', null, 'tenant codes are lower-case slugs');
select throws_ok(
  $$ select public.admin_create_tenant('flag-bad', 'x', 's1_private', null, '{"payroll_deduction": "yes"}') $$,
  '23514', null, 'feature flags must be booleans');
select throws_ok(
  $$ select public.admin_create_tenant('sandbox-a', 'dup', 's1_private') $$,
  '23505', null, 'tenant codes are unique');

-- ---------------------------------------------------------------------------
-- Role templates follow the FS security matrix
-- ---------------------------------------------------------------------------
select tests.superuser();
select is((select count(*)::int from public.role where tenant_id = tests.tenant_id('a')), 10,
  'a new tenant gets the ten template roles');
select ok(private.user_can(tests.user_id('teller', 'a'), 'payment_posting', 'create'), 'a teller posts payments');
select ok(not private.user_can(tests.user_id('teller', 'a'), 'payment_posting', 'approve'), 'a teller cannot approve payments');
select ok(private.user_can(tests.user_id('gm', 'a'), 'withdrawal_above_limit', 'approve'), 'the GM approves withdrawals above limit');
select ok(not private.user_can(tests.user_id('teller', 'a'), 'withdrawal_above_limit', 'approve'),
  'the teller who creates a withdrawal cannot approve it by role either');
select ok(private.user_can(tests.user_id('auditor', 'a'), 'audit_log', 'view'), 'an auditor views the audit log');
select ok(not private.user_can(tests.user_id('auditor', 'a'), 'journal_voucher', 'create'), 'an auditor creates nothing');
select ok(not private.user_can(tests.user_id('admin', 'a'), 'payment_posting', 'view'), 'the tenant admin sees no money screens');
select ok(private.user_can(tests.user_id('admin', 'a'), 'users_roles', 'create'), 'the tenant admin manages users');
select ok(not private.user_can(tests.user_id('admin', 'a'), 'users_roles', 'approve'), 'but cannot approve their own role changes');
select is_empty(
  $$ select r.code from public.role r
     join public.role_permission p on p.role_id = r.id
     where r.tenant_id = tests.tenant_id('a') and p.action = 'approve'
       and exists (select 1 from public.role_permission c
                   where c.role_id = r.id and c.function_code = p.function_code and c.action = 'create'
                     and p.function_code in ('payment_posting', 'withdrawal_above_limit', 'journal_voucher',
                                             'loan_release_voucher', 'teller_eod')) $$,
  'no template role both creates and approves a money movement (segregation of duties)');

-- the signed-in user can ask what they may do
select tests.login('teller.a@example.test');
select ok(public.current_user_can('payment_posting', 'create'), 'current_user_can: a teller may post payments');
select ok(not public.current_user_can('users_roles', 'create'), 'current_user_can: a teller may not manage users');
select tests.anon();
select throws_ok($$ select public.current_user_can('payment_posting', 'create') $$,
  '42501', null, 'current_user_can is closed to anonymous callers');
select tests.superuser();

-- amount limits apply, and an expired role grants nothing
update public.role_permission set amount_limit = 1000
where role_id = tests.role_id('teller', 'a') and function_code = 'payment_posting' and action = 'create';
select ok(private.user_can(tests.user_id('teller', 'a'), 'payment_posting', 'create', 1000), 'at the limit is allowed');
select ok(not private.user_can(tests.user_id('teller', 'a'), 'payment_posting', 'create', 1000.01), 'above the limit is not');
update public.user_role set valid_to = now() - interval '1 second', valid_from = now() - interval '1 day'
where user_id = tests.user_id('teller', 'a');
select ok(not private.user_can(tests.user_id('teller', 'a'), 'payment_posting', 'create'), 'an expired role grants nothing');

select throws_ok(
  $$ insert into public.user_role (tenant_id, user_id, role_id, valid_from)
     values (tests.tenant_id('a'), tests.user_id('gm', 'a'), tests.role_id('gm', 'a'), now()) $$,
  '23P01', null, 'the same role cannot be held twice over the same period');

-- ---------------------------------------------------------------------------
-- Platform path and platform tenant
-- ---------------------------------------------------------------------------
select tests.login('admin.a@example.test');
select throws_ok($$ select public.admin_bootstrap_user(tests.tenant_id('a'), gen_random_uuid(), 'x', 'x@example.test') $$,
  '42501', null, 'a tenant admin cannot create users through the platform path');
select tests.service();
select throws_ok(
  $$ select public.admin_bootstrap_user(tests.tenant_id('b'), (select auth_user_id from public.app_user limit 1), 'x', 'dup@example.test') $$,
  '23505', null, 'one sign-in identity can belong to only one user (D23)');
select throws_like(
  $$ select public.admin_bootstrap_user(tests.tenant_id('b'), gen_random_uuid(), 'x', 'nobody@example.test') $$,
  '%violates foreign key%', 'bootstrapping needs a real sign-in identity');

-- a platform release succeeds for the table owner once the gate passes
select tests.superuser();
with rv as (
  insert into public.rule_version (tenant_id, rule_type, scope, params, effective_from)
  values (private.platform_tenant_id(), 'plat_ok', 'platform', '{"rate":"0.050000"}', current_date) returning id
) select set_config('t.plat', id::text, true) from rv;
insert into public.worked_example (tenant_id, rule_version_id, code, kind, inputs, expected)
select private.platform_tenant_id(), current_setting('t.plat')::uuid, 'P-' || k, k, '{}', '{}'
from unnest(enum_range(null::public.example_kind_t)) k;
select public.record_worked_example_result(id, true, '{}', '{}',
  (select params_hash from public.rule_version where id = current_setting('t.plat')::uuid), 'lib@1')
from public.worked_example where rule_version_id = current_setting('t.plat')::uuid;
select lives_ok(
  $$ update public.rule_version set status = 'active' where id = current_setting('t.plat')::uuid $$,
  'a platform release by the owner activates once its examples pass');
select tests.login('teller.b@example.test');
select is((select params ->> 'rate' from public.rule_version_in_force('plat_ok', 'platform', null, current_date)),
  '0.050000', 'every tenant sees the released platform default');

select * from finish();
rollback;
