#!/usr/bin/env bash
# Rebuild a throwaway local database: Supabase stub, all migrations, then the seed.
# Usage: PGHOST=/tmp PGPORT=54329 PGUSER=postgres scripts/local-db/reset.sh [dbname]
set -euo pipefail
cd "$(dirname "$0")/../.."
DB="${1:-icoops_test}"
psql -v ON_ERROR_STOP=1 -q -d postgres -c "drop database if exists ${DB} with (force)" -c "create database ${DB}"
# Roles are cluster-wide: the stub's role creation is skipped when they already exist.
if psql -tA -d postgres -c "select 1 from pg_roles where rolname='anon'" | grep -q 1; then
  sed -e '/^create role /d' scripts/local-db/supabase_stub.sql | psql -v ON_ERROR_STOP=1 -q -d "$DB"
else
  psql -v ON_ERROR_STOP=1 -q -d "$DB" -f scripts/local-db/supabase_stub.sql
fi
for f in supabase/migrations/*.sql; do
  echo "migration: $f"
  psql -v ON_ERROR_STOP=1 -q -d "$DB" -f "$f"
done
if [ -f supabase/seed.sql ]; then
  echo "seed: supabase/seed.sql"
  psql -v ON_ERROR_STOP=1 -q -d "$DB" -f supabase/seed.sql
fi
# Supabase puts the extensions schema on the default search_path; do the same here (pgTAP).
psql -v ON_ERROR_STOP=1 -q -d postgres -c "alter database ${DB} set search_path to public, extensions"
echo "database ${DB} ready"
