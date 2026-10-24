#!/usr/bin/env bash
# Run the pgTAP database tests against a database that already has migrations and the seed.
# Usage: DATABASE_URL=postgres://... scripts/db-test.sh      (CI, local Supabase stack)
#        PGHOST=/tmp PGPORT=54329 PGUSER=postgres scripts/db-test.sh icoops_test   (local stub)
set -euo pipefail
cd "$(dirname "$0")/.."
TARGET="${DATABASE_URL:-${1:-icoops_test}}"
# pgTAP ships with the Supabase database image but is not enabled by default.
psql -v ON_ERROR_STOP=1 -q "$TARGET" -c "create extension if not exists pgtap with schema extensions"
psql -v ON_ERROR_STOP=1 -q "$TARGET" -f scripts/db-test/helpers.sql
pg_prove --verbose --recurse --ext .sql --dbname "$TARGET" supabase/tests/database
