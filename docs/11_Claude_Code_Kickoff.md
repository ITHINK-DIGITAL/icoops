# Claude Code Kickoff (v0.1)

Status: PREPARED 24 Oct 2026 at Jun's instruction (D21): all development happens in Claude Code from this repo. Read CLAUDE.md, docs/07 and docs/08 first.

## 1. How to start

1. Open the repo `ITHINK-DIGITAL/icoops` in Claude Code. CLAUDE.md loads automatically.
2. Paste the kickoff prompt in section 7.
3. Work in slices (section 4). Finish and merge one slice before starting the next.

## 2. Accounts and access Jun provides (never committed to the repo)

| Item | Owner | Notes |
|---|---|---|
| Supabase project (org iThink Technologies), one for dev | Jun approves creation | Staging and production projects come later |
| Vercel project (team iThink) linked to the GitHub repo | Jun approves | Preview deploys per pull request |
| GitHub: branch protection on main once code exists | Jun | Require CI green and one review |
| Secrets | Jun | Stored in Vercel and Supabase settings only. Never `.env` files in git |

## 3. Proposed repo layout (confirm in slice 1)

| Path | Purpose |
|---|---|
| apps/web | Next.js + React PWA (staff app first) |
| packages/calc | Pure TypeScript calculation libraries with decimal.js (loan, savings, penalty, allocation, disclosure). No database, clock or tenant access (docs/08 L1 to L7) |
| packages/rules | Parameter schemas (for example zod), precedence resolver, rule-version lookup by effective date |
| packages/vectors | Loader and runner for docs/worked_examples/starter.json |
| supabase/migrations | SQL migrations: every table has tenant_id and row-level security |
| supabase/tests | Database tests, including cross-tenant access tests (AT-13) |
| .github/workflows | CI: lint, type check, unit tests, vectors, literal lint, RLS tests |

## 4. Build slices (in order)

| Slice | Scope | Done when |
|---|---|---|
| 1 Skeleton | Tenant (segment, parent_tenant_id, features), users, roles, audit log (append-only), maker-checker primitive, rule_version and worked_example tables, parameter resolver, CI with RLS tests | AT-13 and AT-14 pass in CI; a rule version cannot activate if its examples fail |
| 2 Calc libraries | Loan (diminishing, flat, discounted), savings ADB, penalty, allocation, disclosure, all parameter-based | Every vector in starter.json passes; CI fails on business literals in packages/calc |
| 3 Membership | Application, duplicate check, Board batch approval, Member 360, beneficiaries | AT-01 (without payroll items) and AT-02 pass |
| 4 Loan products and rule tester | Product editor, rule versions, tester, reference products from docs/10 | AT-10 passes |
| 5 Loan release | Schedule, release deductions, voucher, disclosure statement (LN-019), dues schedule | AT-03 and AT-17 pass |
| 6 Teller, EOD, direct payments | Sessions, split receipts, EOD, reversals, bank-reference matching | AT-07, AT-08, AT-16 pass |
| 7 Thin payroll deduction | One payroll office, one configurable file format, change list, remittance import, matching, allocation, shortfalls, reconciliation (D19) | AT-05 and AT-06 pass; PD-REM vectors pass |
| 8 Follow-up and aging | Reminders, overdue queue, tasks, promises to pay, aging buckets | AT-15 passes |
| 9 GL posting and reports | Posting rules, subledger checks, period close, the R1 reports | AT-09, AT-11 pass; the R1 reports in the FS run |

## 5. Review roles in the sandbox tenant (D20)

| Role | Maps to | Access |
|---|---|---|
| Treasurer-1 | Treasurer / head teller template | Read-only on teller, loan, savings and reports |
| Accountant-1 | Accountant template | Read-only on GL, posting rules and reports |
| Tax-Adviser-1 | Auditor template | Read-only on tax parameters and posting rules |

Create these as sandbox users with synthetic data. No names or real emails in the repo.

## 6. Working agreements

- Code changes go through pull requests with CI green; documentation may go straight to main.
- Any decision goes in docs/07 in the same commit. Any change to a rule or convention updates docs/05, docs/08 and the vectors together.
- Never hard-code dividend, patronage refund or deduction-file formulas: their examples are not approved (R2).
- Update the Status section of CLAUDE.md at the end of every session.
- Mirror to the Drive folder once per milestone (end of slice 2, then every third slice); the repo stays canonical.
- Keep the repo public-safe: no partner or employer names, no real data, no pricing.

## 7. Kickoff prompt

> Read CLAUDE.md, docs/07, docs/08 and docs/11. Start slice 1 (skeleton). Propose the repo layout and the database schema for the tenant, user, role, audit_log, rule_version and worked_example tables with row-level security, then wait for my approval before writing migrations. Follow the engineering rules in CLAUDE.md. Do not touch calculation formulas until slice 2.
