-- 0007 least-privilege function grants.
-- Postgres grants EXECUTE to PUBLIC by default. The API roles get no access to the private
-- schema except the few helpers that row-level security policies, column defaults and check
-- constraints evaluate as the calling user. Everything else in private runs only inside
-- security definer functions (as the owner) or triggers.

revoke execute on all functions in schema private from public, anon, authenticated;

grant execute on function
  private.current_tenant_id(),
  private.has_permission(public.function_t, public.action_t),
  private.platform_tenant_id(),
  private.json_has_no_fractions(jsonb)
  to authenticated;

-- The platform path and the vector runner use the service key.
grant execute on all functions in schema private to service_role;

-- Anything created later in public must opt in to API access explicitly: no implicit grants.
alter default privileges in schema public revoke execute on functions from anon, authenticated;
