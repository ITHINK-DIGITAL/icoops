-- AT-14: the creator of a withdrawal above limit cannot approve it. Also covers every other
-- rule of the maker-checker primitive: second factor, role and amount limit, multi-step bands,
-- one decision per person, rejection, cancellation, immutability and guarded execution.
begin;
select * from no_plan();

-- helper: status of a request by setting name
create function pg_temp.req_status(p_setting text) returns text language sql stable as $$
  select status::text from public.approval_request where id = current_setting(p_setting)::uuid $$;
grant execute on function pg_temp.req_status(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 1. The maker cannot approve their own request, however many roles they hold.
-- ---------------------------------------------------------------------------
select tests.login('teller.a@example.test');
select set_config('t.r1',
  public.create_approval_request('withdrawal_above_limit', 'txn', gen_random_uuid(), 60000, '{"w":"1"}')::text, true);
select is(pg_temp.req_status('t.r1'), 'pending', 'a withdrawal above limit starts pending');
select throws_like(
  $$ select public.decide_approval_request(current_setting('t.r1')::uuid, 'approve') $$,
  '%maker-checker%', 'the maker (a teller) cannot approve');

-- Give the same person the GM role too: holding both roles must not let them self-approve.
select tests.superuser();
insert into public.user_role (tenant_id, user_id, role_id)
values (tests.tenant_id('a'), tests.user_id('teller', 'a'), tests.role_id('gm', 'a'));
select tests.login('teller.a@example.test');
select throws_like(
  $$ select public.decide_approval_request(current_setting('t.r1')::uuid, 'approve') $$,
  '%maker-checker%', 'a maker who also holds the GM role still cannot approve their own request');
select is(pg_temp.req_status('t.r1'), 'pending', 'the request is still pending after the refused approvals');

-- ---------------------------------------------------------------------------
-- 2. Every other condition for a decider.
-- ---------------------------------------------------------------------------
select tests.login('gm.a@example.test', 'aal1');
select throws_like(
  $$ select public.decide_approval_request(current_setting('t.r1')::uuid, 'approve') $$,
  '%second-factor%', 'a password-only sign-in cannot approve');

select tests.login('accountant.a@example.test');
select throws_like(
  $$ select public.decide_approval_request(current_setting('t.r1')::uuid, 'approve') $$,
  '%missing permission%', 'a user without the approve permission cannot approve');

select tests.login('gm.b@example.test');
select throws_ok(
  $$ select public.decide_approval_request(current_setting('t.r1')::uuid, 'approve') $$,
  'P0001', 'approval request not found', 'a GM of another tenant cannot approve');

select tests.login('gm.a@example.test');
select throws_ok(
  $$ insert into public.approval_decision (request_id, step_no, decided_by, decision)
     values (current_setting('t.r1')::uuid, 1, tests.user_id('teller', 'a'), 'approve') $$,
  '42501', null, 'nobody can write a decision directly, so decided_by cannot be forged');
select throws_ok(
  $$ update public.approval_request set status = 'approved' where id = current_setting('t.r1')::uuid $$,
  '42501', null, 'nobody can set a request status directly');
select throws_like(
  $$ select public.execute_approval_request(current_setting('t.r1')::uuid) $$,
  '%only approved requests execute%', 'a pending request cannot be executed');

-- ---------------------------------------------------------------------------
-- 3. A valid approval by a different person with a second factor.
-- ---------------------------------------------------------------------------
select lives_ok(
  $$ select public.decide_approval_request(current_setting('t.r1')::uuid, 'approve') $$,
  'a GM with a second factor can approve someone else''s request');
select is(pg_temp.req_status('t.r1'), 'approved', 'the request is approved');
select is(
  (select decided_by from public.approval_decision where request_id = current_setting('t.r1')::uuid),
  tests.user_id('gm', 'a'), 'the decision records the signed-in user, not a client value');
select throws_like(
  $$ select public.decide_approval_request(current_setting('t.r1')::uuid, 'approve') $$,
  '%already approved%', 'a decided request cannot be decided again');
-- no executor for this type until withdrawals exist: it must refuse rather than pretend
select tests.login('teller.a@example.test');
select throws_like(
  $$ select public.execute_approval_request(current_setting('t.r1')::uuid) $$,
  '%no executor yet%', 'a type without an executor cannot be executed');

-- Decisions and steps are append-only; requests cannot be edited after creation.
select tests.superuser();
select throws_like($$ update public.approval_decision set decision = 'reject' $$,
  '%append-only%', 'decisions cannot be updated');
select throws_like($$ delete from public.approval_decision $$,
  '%append-only%', 'decisions cannot be deleted');
select throws_like($$ update public.approval_request_step set required_approvals = 5 $$,
  '%append-only%', 'frozen steps cannot be updated');
select throws_like(
  $$ update public.approval_request set payload = '{"w":"2"}' where id = current_setting('t.r1')::uuid $$,
  '%cannot be edited%', 'the payload cannot change after creation');
select throws_like(
  $$ update public.approval_request set status = 'pending' where id = current_setting('t.r1')::uuid $$,
  '%invalid request status change%', 'status cannot move backwards');
select throws_like($$ delete from public.approval_request $$,
  '%never deleted%', 'requests are never deleted');

-- ---------------------------------------------------------------------------
-- 4. Rejection needs a reason; the maker can cancel only a pending request.
-- ---------------------------------------------------------------------------
select tests.login('teller.a@example.test');
select set_config('t.r2',
  public.create_approval_request('withdrawal_above_limit', 'txn', gen_random_uuid(), 70000, '{"w":"2"}')::text, true);
select set_config('t.r3',
  public.create_approval_request('withdrawal_above_limit', 'txn', gen_random_uuid(), 80000, '{"w":"3"}')::text, true);
select tests.login('board.a@example.test');
select throws_like(
  $$ select public.cancel_approval_request(current_setting('t.r2')::uuid) $$,
  '%only the maker%', 'someone else cannot cancel the request');
select tests.login('gm.a@example.test');
select throws_ok(
  $$ select public.decide_approval_request(current_setting('t.r2')::uuid, 'reject') $$,
  '23514', null, 'a rejection without a reason is refused');
select lives_ok(
  $$ select public.decide_approval_request(current_setting('t.r2')::uuid, 'reject', 'over policy limit') $$,
  'a rejection with a reason is recorded');
select is(pg_temp.req_status('t.r2'), 'rejected', 'the request is rejected');
select tests.login('teller.a@example.test');
select throws_like($$ select public.cancel_approval_request(current_setting('t.r2')::uuid) $$,
  '%already rejected%', 'a rejected request cannot be cancelled');
select lives_ok($$ select public.cancel_approval_request(current_setting('t.r3')::uuid, 'duplicate') $$,
  'the maker can cancel a pending request');
select is(pg_temp.req_status('t.r3'), 'cancelled', 'the request is cancelled');
select tests.login('gm.a@example.test');
select throws_like(
  $$ select public.decide_approval_request(current_setting('t.r3')::uuid, 'approve') $$,
  '%already cancelled%', 'a cancelled request cannot be approved');

-- ---------------------------------------------------------------------------
-- 5. Amount limits on the approve permission.
-- ---------------------------------------------------------------------------
select tests.superuser();
update public.role_permission set amount_limit = 50000
where role_id = tests.role_id('gm', 'a') and function_code = 'withdrawal_above_limit' and action = 'approve';
select tests.login('teller.a@example.test');
select set_config('t.big',
  public.create_approval_request('withdrawal_above_limit', 'txn', gen_random_uuid(), 60000, '{"w":"big"}')::text, true);
select set_config('t.small',
  public.create_approval_request('withdrawal_above_limit', 'txn', gen_random_uuid(), 40000, '{"w":"small"}')::text, true);
select tests.login('gm.a@example.test');
select throws_like(
  $$ select public.decide_approval_request(current_setting('t.big')::uuid, 'approve') $$,
  '%for this amount%', 'a GM with a 50,000 limit cannot approve 60,000');
select lives_ok(
  $$ select public.decide_approval_request(current_setting('t.small')::uuid, 'approve') $$,
  'the same GM can approve 40,000');

-- ---------------------------------------------------------------------------
-- 6. Amount bands: a band routes large amounts through two steps (GM, then Board).
-- ---------------------------------------------------------------------------
select tests.login('accountant.a@example.test');
with m as (
  insert into public.approval_matrix (txn_type, min_amount, effective_from)
  values ('withdrawal_above_limit', 50000, current_date) returning id
) select set_config('t.mx', id::text, true) from m;
insert into public.approval_matrix_step (matrix_id, step_no, role_id)
values (current_setting('t.mx')::uuid, 1, tests.role_id('gm', 'a')),
       (current_setting('t.mx')::uuid, 2, tests.role_id('board', 'a'));
select throws_like(
  $$ update public.approval_matrix set status = 'active' where id = current_setting('t.mx')::uuid $$,
  '%permission denied%', 'a configurator cannot activate a band directly');
select set_config('t.mxreq', public.submit_approval_matrix(current_setting('t.mx')::uuid)::text, true);
select throws_like(
  $$ update public.approval_matrix set max_amount = 90000 where id = current_setting('t.mx')::uuid $$,
  '%frozen%', 'a submitted band is frozen');
select tests.login('accountant.a@example.test');
select throws_like(
  $$ select public.decide_approval_request(current_setting('t.mxreq')::uuid, 'approve') $$,
  '%maker-checker%', 'the configurator who drafted the band cannot approve it');
select tests.login('gm.a@example.test');
select lives_ok($$ select public.decide_approval_request(current_setting('t.mxreq')::uuid, 'approve') $$,
  'a GM approves the new band');
select tests.login('accountant.a@example.test');
select lives_ok($$ select public.execute_approval_request(current_setting('t.mxreq')::uuid) $$,
  'the approved band is executed');
select is((select status::text from public.approval_matrix where id = current_setting('t.mx')::uuid),
  'active', 'the band is now active');

select tests.login('teller.a@example.test');
select set_config('t.m1',
  public.create_approval_request('withdrawal_above_limit', 'txn', gen_random_uuid(), 60000, '{"w":"m1"}')::text, true);
select set_config('t.m2',
  public.create_approval_request('withdrawal_above_limit', 'txn', gen_random_uuid(), 10000, '{"w":"m2"}')::text, true);
select is((select count(*)::int from public.approval_request_step where request_id = current_setting('t.m1')::uuid),
  2, 'an amount in the band gets two steps');
select is((select count(*)::int from public.approval_request_step where request_id = current_setting('t.m2')::uuid),
  1, 'an amount below the band gets one open step');

-- restore the GM's unlimited approval for the multi-step walk-through. A step role must also hold
-- the function's approve permission: the template gives withdrawals to the GM only, so a tenant
-- that wants a Board step grants it explicitly.
select tests.superuser();
update public.role_permission set amount_limit = null
where role_id = tests.role_id('gm', 'a') and function_code = 'withdrawal_above_limit' and action = 'approve';
insert into public.role_permission (tenant_id, role_id, function_code, action)
values (tests.tenant_id('a'), tests.role_id('board', 'a'), 'withdrawal_above_limit', 'approve');

select tests.login('board.a@example.test');
select throws_like($$ select public.decide_approval_request(current_setting('t.m1')::uuid, 'approve') $$,
  '%needs a role you do not hold%', 'step 1 needs the GM role; the Board cannot jump the queue');
select tests.login('gm.a@example.test');
select lives_ok($$ select public.decide_approval_request(current_setting('t.m1')::uuid, 'approve') $$,
  'the GM approves step 1');
select is(pg_temp.req_status('t.m1'), 'pending', 'the request waits for step 2');
select is((select current_step from public.approval_request where id = current_setting('t.m1')::uuid),
  2, 'the request moved to step 2');
select throws_like($$ select public.decide_approval_request(current_setting('t.m1')::uuid, 'approve') $$,
  '%already decided%', 'the same person cannot decide a second step');
select tests.login('board.a@example.test');
select lives_ok($$ select public.decide_approval_request(current_setting('t.m1')::uuid, 'approve') $$,
  'the Board approves step 2');
select is(pg_temp.req_status('t.m1'), 'approved', 'both steps done: approved');

-- A later change to the matrix never alters a request already in progress.
select tests.superuser();
select is((select count(*)::int from public.approval_request_step where request_id = current_setting('t.m1')::uuid),
  2, 'the steps stay frozen on the request');

-- ---------------------------------------------------------------------------
-- 7. Role grants: the person receiving a role cannot approve their own grant.
-- ---------------------------------------------------------------------------
select tests.superuser();
insert into public.user_role (tenant_id, user_id, role_id)
values (tests.tenant_id('a'), tests.user_id('accountant', 'a'), tests.role_id('gm', 'a'));
select tests.login('admin.a@example.test');
select set_config('t.grant',
  public.request_user_role_grant(tests.user_id('gm', 'a'), tests.role_id('auditor', 'a'))::text, true);
select tests.login('gm.a@example.test');
select throws_like($$ select public.decide_approval_request(current_setting('t.grant')::uuid, 'approve') $$,
  '%maker-checker%', 'a GM cannot approve a role grant to themselves');
select tests.login('accountant.a@example.test');
select lives_ok($$ select public.decide_approval_request(current_setting('t.grant')::uuid, 'approve') $$,
  'another approver can approve the grant');
select tests.login('admin.a@example.test');
select lives_ok($$ select public.execute_approval_request(current_setting('t.grant')::uuid) $$,
  'the grant executes');
select is(
  (select count(*)::int from public.user_role
   where user_id = tests.user_id('gm', 'a') and role_id = tests.role_id('auditor', 'a')
     and approval_request_id = current_setting('t.grant')::uuid),
  1, 'the role is granted and linked to its approval request');
select is(pg_temp.req_status('t.grant'), 'executed', 'the request is marked executed');
select tests.login('teller.a@example.test');
select throws_ok($$ select public.request_user_role_grant(tests.user_id('teller', 'a'), tests.role_id('gm', 'a')) $$,
  '42501', null, 'a teller cannot even ask for a role grant (no users_roles:create)');

select * from finish();
rollback;
