-- AT-13 (catalog layer): every table in public follows the tenant template, so a table added
-- later that skips it fails the build by itself. Also locks the money and rate precision rules.
begin;
select plan(12);

create temp view app_tables as
  select c.oid, c.relname
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r', 'p');

select cmp_ok((select count(*) from app_tables)::int, '>=', 13, 'the schema has tables to check');

select is_empty(
  $$ select t.relname from app_tables t
     where not exists (
       select 1 from pg_attribute a
       where a.attrelid = t.oid and a.attname = 'tenant_id' and a.attnotnull and not a.attisdropped) $$,
  'every table has a non-null tenant_id');

select is_empty(
  $$ select t.relname from app_tables t join pg_class c on c.oid = t.oid
     where not c.relrowsecurity $$,
  'every table has row-level security enabled');

select is_empty(
  $$ select t.relname from app_tables t
     where not exists (select 1 from pg_policy p where p.polrelid = t.oid) $$,
  'every table has at least one policy');

select is_empty(
  $$ select t.relname, p.polname from app_tables t join pg_policy p on p.polrelid = t.oid
     where (pg_get_expr(p.polqual, p.polrelid) = 'true' or pg_get_expr(p.polwithcheck, p.polrelid) = 'true')
       and (p.polroles = '{0}' or p.polroles @> array[
              (select oid from pg_roles where rolname = 'authenticated'),
              (select oid from pg_roles where rolname = 'anon')]::oid[]) $$,
  'no policy opens a table to everyone with using (true)');

select is_empty(
  $$ select t.relname, p.polname from app_tables t join pg_policy p on p.polrelid = t.oid
     where not (pg_get_expr(p.polqual, p.polrelid) ~ 'tenant_id|private\.' or p.polqual is null)
        or (p.polqual is null and p.polwithcheck is null) $$,
  'every policy is scoped by tenant or by a private helper');

select is_empty(
  $$ select t.relname, r.rolname, priv from app_tables t
     cross join (values ('anon'), ('authenticated')) r(rolname)
     cross join (values ('DELETE'), ('TRUNCATE')) p(priv)
     where has_table_privilege(r.rolname, t.oid, priv) $$,
  'the API roles hold no delete or truncate privilege anywhere');

select is_empty(
  $$ select t.relname from app_tables t
     where has_table_privilege('anon', t.oid, 'SELECT')
        or has_any_column_privilege('anon', t.oid, 'INSERT')
        or has_any_column_privilege('anon', t.oid, 'UPDATE') $$,
  'anonymous holds no privilege on any table');

select is_empty(
  $$ select t.relname from app_tables t
     where t.relname <> 'audit_log'
       and not exists (
         select 1 from pg_trigger g
         where g.tgrelid = t.oid and not g.tgisinternal
           and (g.tgtype & 2) = 2 and (g.tgtype & 8) = 8) $$,
  'every table (but the audit log) has a before-delete guard');

select is_empty(
  $$ select t.relname from app_tables t
     where t.relname <> 'audit_log'
       and not exists (
         select 1 from pg_trigger g join pg_proc f on f.oid = g.tgfoid
         where g.tgrelid = t.oid and not g.tgisinternal and f.proname = 'audit_row') $$,
  'every table (but the audit log) is audited');

select is_empty(
  $$ select table_name, column_name from information_schema.columns
     where table_schema = 'public' and data_type in ('double precision', 'real') $$,
  'no floating-point column exists anywhere');

select is_empty(
  $$ select table_name, column_name, numeric_precision, numeric_scale
     from information_schema.columns
     where table_schema = 'public' and data_type = 'numeric'
       and (numeric_precision, numeric_scale) not in ((18, 2), (9, 6)) $$,
  'every numeric column is money numeric(18,2) or a rate numeric(9,6)');

select * from finish();
rollback;
