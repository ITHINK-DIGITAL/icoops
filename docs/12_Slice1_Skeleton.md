# Slice 1 — Skeleton (reference, v0.1)

Status: BUILT 24 Oct 2026 on branch `slice-1-skeleton`, one pull request for review (D22). Approved design: the slice 1 proposal accepted by Jun on 24 Oct 2026 (D23 to D26). Deviations from that proposal are listed in section 9 and recorded as D27 for review.

Done when (docs/11): AT-13 and AT-14 pass in CI, and a rule version cannot activate if its examples fail. All three are covered by database tests (section 8).

## 1. What slice 1 delivers, and what it does not

| Delivers | Does not deliver (later slice) |
|---|---|
| Tenant (segment, parent, feature flags), staff users, roles, permissions with amount limits | Members, accounts, loans, teller, GL (slices 3 to 9) |
| Row-level security on every table, with a catalog test that fails the build for a table that skips it | Calculation formulas: `packages/calc` holds guardrails only (slice 2) |
| Append-only audit log with before and after images | Products and the product foreign key on approval bands (slice 4) |
| Maker-checker primitive, approval matrix with amount bands | Withdrawals, the first real consumer of the `withdrawal_above_limit` type (slice 6) |
| Rule versions, worked examples, the activation gate, effective-date lookup, precedence resolver | Loading the starter vectors into the platform tenant (slice 2 and 4) |
| Staff app shell: sign-in, second factor, approvals inbox | Business screens, offline queue, service worker (R1 later) |
| CI: five required checks | Hosted Supabase and Vercel projects (D24) |

## 2. Repository layout

| Path | Contents |
|---|---|
| `apps/web` | Next.js 15 PWA shell. Pages: sign-in, home, approvals inbox, two-factor set-up. Route `POST /api/rules/{id}/run` runs a draft rule version's examples (service key, server only) |
| `packages/calc` | Pure TypeScript with decimal.js. In slice 1: the Decimal class (own precision, plain notation), the string-only `parseDecimal`, the result envelope with library and rule-version provenance (L5), and the lint rules that keep business literals out |
| `packages/rules` | zod parameter schemas (the calculation-conventions rule type), rule-type registry, precedence resolver (platform, pack, tenant, product, account), effective-date selection, worked-example runner, segment default feature flags |
| `packages/vectors` | Loader, schema and structural checks for `docs/worked_examples/starter.json`, vector runner, CI command |
| `packages/db` | Supabase client factories and typed wrappers for every guarded database function, the create-tenant admin script |
| `packages/config` | Shared ESLint base |
| `tests/isolation` | API-level AT-13 and AT-14 with real user tokens, including a TOTP second-factor sign-in |
| `supabase/migrations` | Seven migrations (section 3) |
| `supabase/tests/database` | pgTAP: catalog, isolation matrix, maker-checker, audit, rule gate, tenants and roles |
| `supabase/seed.sql` | Synthetic only: two sandbox co-ops, six users each |
| `scripts` | Forbidden-terms and calc-names checks (each with a self-test), pgTAP runner, local database harness, fixtures that prove the guards still fire |

## 3. Database

Every table has `tenant_id`, the row-level security template, an audit trigger and a delete guard. Money is `numeric(18,2)`, rates `numeric(9,6)`; a catalog test rejects any other numeric column and any float column.

| Migration | Adds |
|---|---|
| 0001 foundations | Enums, helpers, the RLS template function `private.apply_tenant_rls`, generic triggers |
| 0002 tenant and users | `tenant` (segment, parent, features, status, sandbox), `app_user`, the "who is calling" helpers |
| 0003 audit log | `audit_log` (append-only), the audit trigger, `log_sensitive_view` |
| 0004 roles and permissions | `role`, `role_permission`, `user_role`, the FS role templates, the platform tenant, `admin_create_tenant`, `admin_bootstrap_user`, `current_user_can` |
| 0005 approvals | `approval_matrix`, `approval_matrix_step`, `approval_request`, `approval_request_step`, `approval_decision`, the maker-checker triggers and functions |
| 0006 rule versions | `rule_version`, `worked_example`, the activation gate, run recorder, submit and execute functions, effective-date lookup |
| 0007 function privileges | Revokes the default public execute on `private` functions; grants back only what policies and defaults need |

### Row-level security and who may write

- Reads: every table has a policy `tenant_id = current_tenant_id()`. The tenant is looked up from `app_user` on every statement, never from a token claim, so disabling a user or suspending a tenant takes effect at once.
- Writes: the API role (`authenticated`) can read everything in its tenant but write almost nothing directly. Drafts of rule versions, worked examples and approval bands can be inserted and edited by holders of `product_rule_config:create` (column-level grants; status, hashes, links and run results are not writable). Everything else changes through security-definer functions that check the caller's tenant, permission and the T0 rules, then write.
- No table can be deleted from, for any role (revoked, plus a trigger that also stops the table owner). `audit_log`, `approval_decision` and `approval_request_step` are append-only for everyone.
- Composite foreign keys `(tenant_id, x_id)` stop a row of tenant A from pointing at a row of tenant B.
- The platform tenant (`00000000-0000-0000-0000-000000000001`) owns platform defaults and the shared vectors. Its `rule_version` and `worked_example` rows are readable by every tenant and writable by none through the API (D23).

### Maker-checker (PL-022, AT-14)

Enforced by a `before insert` trigger on `approval_decision`, so no route bypasses it (T0, not configurable):

1. the decider is not the maker and not anyone who created or edited the subject (taken from the audit log when the request is created, plus the maker; for a role grant, also the grantee);
2. nobody decides two steps of the same request;
3. the decider holds the step's role, valid now, and the `approve` permission with an amount limit that covers the request;
4. the decider's session is aal2 (second factor);
5. the request is pending; its payload, subject and maker can never change; its steps are frozen copies of the matrix at creation.

The maker and decider are always the signed-in user. The only way an approved request changes anything is `execute_approval_request`, which re-verifies the payload hash and runs the executor for the request type.

| Request type | Governed by | Executor |
|---|---|---|
| `rule_version_activation`, `rule_version_backdating` | `product_rule_config` | Activates the rule version (back-dated effective dates need their own type) |
| `approval_matrix_activation` | `product_rule_config` | Activates the band; retires the band it supersedes |
| `user_role_grant` | `users_roles` | Inserts the `user_role` row |
| `withdrawal_above_limit` | `withdrawal_above_limit` | None yet (slice 6). It can be created, decided and approved, and refuses to execute |

New request types are added in `private.approval_type_function` and `public.execute_approval_request`.

### Rule version gate (PL-011, PL-012)

`draft` → `submitted` → `active` (or `rejected`, `withdrawn`). A version activates only when all of these hold, checked at submission and again at execution:

- it has at least one normal, one boundary and one exception example;
- every example's last run passed, and used the version's current `params_hash`;
- an approved maker-checker request authorises it.

Parameters freeze on submission; examples change only while the version is a draft, and editing an example discards its result. Only the service key can record a run (`record_worked_example_result`), and a run against stale parameters is refused. Decimal values in parameters and examples are strings; the database rejects fractional JSON numbers. Platform defaults are released by a reviewed migration (the pull request is their maker-checker), never by an API role, the service key included.

## 4. Staff app

Sign-in (password), second factor (TOTP, needed to approve), approvals inbox showing the database's own message when it refuses. The app never decides whether something is allowed; `current_user_can` only lets it hide buttons. The service key exists only in server code (`/api/rules/{id}/run`, admin scripts); a check of the production client bundles found none.

## 5. CI (`.github/workflows/ci.yml`)

Required checks for branch protection on main (D22): `static`, `unit`, `vectors`, `build`, `db`.

| Job | Runs |
|---|---|
| static | Prettier, ESLint (including the calc literal guard and its self-test), type check, calc names guard and self-test, forbidden-terms check and self-test, `pnpm audit` (production, high and above) |
| unit | Vitest in every package |
| vectors | Validates `starter.json`; from slice 2 runs with `VECTORS_STRICT=1` so a pending or failing vector fails the build |
| build | `next build` of the staff app |
| db | Local Supabase stack, `db reset`, `db lint`, the pgTAP suite, then the API tests |

### The calc literal guard (docs/08 "CI enforcement")

In `packages/calc/src`, ESLint rejects numeric literals other than 0 and 1, string and template literals, and the globals `Date`, `process`, `fetch`, `Math`, `Number`, `parseFloat`; only `decimal.js`, type-only `@icoops/rules` and local files may be imported. Named constants live in `src/invariants.ts`, which the owner reviews through CODEOWNERS. A text check additionally fails on tenant, segment, profile-pack or partner names and on UUIDs, even in comments. Both guards have a self-test that feeds them a file full of violations and fails the build if they stay silent.

### Partner and employer names

Names cannot be listed in a public repo. The check reads them from the Actions secret `FORBIDDEN_TERMS` (one per line), reports file and line only, and is required on pushes to main. It also rejects secrets, key files, `.env` files and any email outside the reserved example domains.

## 6. Running it locally

With Docker:

```
pnpm install
supabase start && supabase db reset
scripts/db-test.sh "postgresql://postgres:postgres@127.0.0.1:54322/postgres"   # needs pg_prove
eval "$(supabase status -o env | sed 's/^/export /')"
SUPABASE_URL=$API_URL SUPABASE_ANON_KEY=$ANON_KEY SUPABASE_SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY pnpm test:isolation
```

Without Docker (what slice 1 was developed on): a plain Postgres 16 with pgTAP and a stub of Supabase's `auth` schema.

```
PGHOST=/tmp PGPORT=54329 PGUSER=postgres scripts/local-db/reset.sh icoops_test
PGHOST=/tmp PGPORT=54329 PGUSER=postgres scripts/db-test.sh icoops_test
```

The stub (`scripts/local-db/supabase_stub.sql`) is for local use only. The API tests and `supabase db lint` need the real stack and run in CI.

Seed users sign in as `<role>.<a|b>@example.test` with the published development password in `supabase/seed.sql`; the seed is never applied to a hosted project.

## 7. How to extend

- New table: add `tenant_id`, call `private.apply_tenant_rls`, grant only what the API needs, attach touch, delete-guard and audit triggers. The catalog test fails until all of that is done.
- New calculation: pure function of (input, params) in `packages/calc`, a parameter schema and handler in `packages/rules`, vectors in `starter.json`; no literal, no tenant name.
- New approval type: section 3, with an executor and tests.

## 8. Verification status at the time of writing

| Check | Where it was run |
|---|---|
| pgTAP suite (197 checks: catalog, isolation matrix, maker-checker, audit, gate, tenants and roles) | Locally on Postgres 16 with the auth stub. The catalog test and the isolation matrix were also shown to fail when a table and a policy were deliberately broken |
| `plpgsql_check` on all 21 plpgsql functions | Locally (the same check `supabase db lint` runs): no findings |
| Lint, type check, unit tests (63), vectors, `next build`, production smoke run, audit | Locally, all passing |
| `supabase start`, `db reset` with the seed, `supabase db lint`, and all 197 pgTAP checks on the real Supabase image | CI `db` job, first run on the pull request: all passed |
| API tests (`tests/isolation`) | Not runnable locally (no Docker in the build environment); CI `db` job. The first run failed on a configuration error (email provider disabled in `config.toml`), fixed in the next push |

## 9. Deviations from the approved proposal (D27)

| Proposal | As built | Why |
|---|---|---|
| `force row level security` on every table | Row-level security enabled, not forced | Believed unnecessary: Supabase's owner role holds BYPASSRLS (per its documentation; not verifiable in the local harness), so force would not bind it and would complicate the guarded functions. Those functions check the tenant explicitly and every API role is subject to the policies. Re-check against the hosted project when it exists |
| Insert and update policies on every table | None on `audit_log` | It is written only by trigger and the log function; the policies would only mislead |
| gitleaks job | Own scanner plus GitHub secret scanning | The gitleaks action needs a licence for organisation repositories; an unpinned binary is a supply-chain risk. Turn on secret scanning and push protection in the repository settings |
| Four required checks | Five (`build` added) | The app shell needs its own compile check |
| Test-only "withdrawal above limit" request type | A real type with no executor | A test-only type in production code is worse; it refuses to execute until slice 6 |
| Unit tests "with coverage" | Without | No coverage tool chosen yet; add when slice 2 gives the libraries something to measure |
| TypeScript, ESLint, Next | TypeScript 5.9, ESLint 9, Next 15.5 (not the newest majors) | Stable lines with known behaviour; zod is on 4.x because 3.x has an unpatched advisory; postcss is overridden for an advisory in a transitive dependency |
| Reviewer sandbox users (docs/11 section 5) | Not created | They need read-only role templates that arrive with the screens they review (slice 4) |

## 10. Findings for later slices

- `starter.json`: `loan_interest_advance`, `release_deductions` and `savings_interest_min_monthly` have only a normal example; the gate needs normal, boundary and exception per rule version. `vectors` reports this as a warning today.
- Several vector inputs are free text (for example `"balances": "d1-10: 10000.00; d11-20: 15000.00"`, `"expected": "loan 3000.00; cbu 500.00"`, `"received": "0.00 (zero-pay)"`). The calculation libraries need structured inputs; restructure them with docs/05 in slice 2 (docs/11: rule or convention changes update docs/05, docs/08 and the vectors together).
- Some `expected` objects carry a `note` key that is commentary, not an output; the runner ignores it.
- No slice in docs/11 covers savings products, deposits and withdrawals, yet slice 9 tests the savings interest run (AT-09) and slice 6's withdrawals depend on them.
- Multi-factor and password policy values (session timeout, lockout, OTP triggers) are Supabase project settings today; the FS wants them as parameters within platform floors.
