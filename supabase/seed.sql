-- Synthetic sandbox data for local development and CI only (CLAUDE.md: synthetic data only).
-- Never applied to a hosted project. Emails use the reserved .test domain; the password below
-- is a published development placeholder, not a secret.
--
-- Two sandbox co-ops (S1) so that isolation can be tested, and six users in each:
--   admin (Tenant administrator), accountant, gm, teller, auditor, board.

do $$
declare
  c_password constant text := 'local-dev-only-password';
  v_tenants jsonb := jsonb_build_array(
    jsonb_build_object('key', 'a', 'code', 'sandbox-a', 'name', 'Sandbox Co-op A',
                       'features', '{"payroll_deduction": true}'::jsonb),
    jsonb_build_object('key', 'b', 'code', 'sandbox-b', 'name', 'Sandbox Co-op B',
                       'features', '{"payroll_deduction": false}'::jsonb)
  );
  v_users jsonb := jsonb_build_array(
    jsonb_build_array('admin', 'Admin', 'tenant_admin', 1),
    jsonb_build_array('accountant', 'Accountant', 'accountant', 2),
    jsonb_build_array('gm', 'General Manager', 'gm', 3),
    jsonb_build_array('teller', 'Teller', 'teller', 4),
    jsonb_build_array('auditor', 'Auditor', 'auditor', 5),
    jsonb_build_array('board', 'Board Member', 'board', 6)
  );
  v_tenant jsonb;
  v_user jsonb;
  v_tenant_id uuid;
  v_auth_id uuid;
  v_email text;
begin
  for v_tenant in select * from jsonb_array_elements(v_tenants) loop
    v_tenant_id := public.admin_create_tenant(
      v_tenant ->> 'code', v_tenant ->> 'name', 's1_private', null,
      v_tenant -> 'features', true);
    for v_user in select * from jsonb_array_elements(v_users) loop
      -- Stable ids so tests can refer to users: a1.. for tenant a, b1.. for tenant b.
      v_auth_id := (
        (case v_tenant ->> 'key' when 'a' then 'aaaaaaaa' else 'bbbbbbbb' end)
        || '-0000-0000-0000-00000000000' || (v_user ->> 3)
      )::uuid;
      v_email := (v_user ->> 0) || '.' || (v_tenant ->> 'key') || '@example.test';
      insert into auth.users
        (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
         raw_app_meta_data, raw_user_meta_data, confirmation_token, recovery_token,
         email_change_token_new, email_change, created_at, updated_at)
      values
        (v_auth_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         v_email, extensions.crypt(c_password, extensions.gen_salt('bf')), now(),
         '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, '', '', '', '',
         now(), now());
      insert into auth.identities (user_id, provider_id, provider, identity_data)
      values (v_auth_id, v_auth_id::text, 'email',
              jsonb_build_object('sub', v_auth_id::text, 'email', v_email));
      perform public.admin_bootstrap_user(
        v_tenant_id, v_auth_id, (v_user ->> 1) || ' (' || upper(v_tenant ->> 'key') || ')', v_email,
        array[v_user ->> 2]);
    end loop;
  end loop;
end
$$;
