# CLAUDE.md — iCOOPs

Read this first in every session. The repo is the handoff: everything needed to continue is here or linked from here.

## What this is
iCOOPs: greenfield multi-tenant SaaS for Philippine cooperatives (iThink Digital). Segment S1 (private co-ops, payroll deduction OFF) first, built to the standard S1 profile in docs/10 (label PARTNER-S1; no design partner is signed, D18); the first tenant collects through payroll, so a thin single-office payroll slice is in R1 (D19); full multi-office payroll deduction (S2, government) in R2; federation (S3) in R3. One codebase, all tenants on the shared multi-tenant platform (D14, D15). Product owner: Jun Mercader.

## Status (24 Oct 2026)
Design complete enough to build. **Slice 1 (skeleton) is built on branch `slice-1-skeleton` and awaiting Jun's review in one pull request (D22).** It delivers tenants (segment, parent, features), users, roles and permissions, row-level security on every table with a catalog test, an append-only audit log, the maker-checker primitive (AT-14), the approval matrix, rule versions with worked examples and the activation gate, a staff app shell and CI. Reference: `docs/12_Slice1_Skeleton.md`. Decisions D23 to D27 are in docs/07 (D27 is Claude's proposal, for review).

Not built yet: calculation formulas (`packages/calc` holds guardrails only, slice 2), members, loans, teller, GL, products. **No Supabase project or Vercel project exists** (D24): slice 1 runs on a local Supabase stack; creating the hosted projects needs Jun's approval.

Next: Jun reviews and merges the slice 1 pull request. Before merging, Jun sets the `FORBIDDEN_TERMS` Actions secret (D26), confirms the CODEOWNERS handle and turns on secret scanning; after the first green CI run, branch protection with the five checks (docs/07 question 9). Then slice 2 (calculation libraries), which starts by fixing the vector gaps in docs/07 question 7. Slice 1 verification status, including what only CI can confirm, is in docs/12 section 8.

Working notes: the database tests run locally without Docker (docs/12 section 6). The API tests need the real Supabase stack and run in CI (`supabase db lint` and the pgTAP suite also pass there). Rules of the road are unchanged below.

## Decided stack (docs/07, section D)
Next.js + React (PWA) · Supabase PostgreSQL (RLS on `tenant_id`) · JSON APIs · Python only for batch/computation jobs · Vercel · GitHub org ITHINK-DIGITAL. Same pattern as iLogistics / Malasakit.

## Source of truth (read in this order)
0. `docs/11_Claude_Code_Kickoff.md` — how to start building, slices, working agreements; `docs/12_Slice1_Skeleton.md` — what slice 1 built and how it works
1. `docs/07_Decision_Log_and_Open_Questions.md` — what is decided vs open
   (also read `docs/08_Configurability_and_Library_Standard.md` before writing any calculation or rule code, and `docs/09_PARTNER-S1_Input_Request.md` for the adopted conventions and the partner input list)
2. `docs/05_Worked_Examples_Starter.md` + `docs/worked_examples/starter.json` — synthetic engine test vectors (pending approval); load them in the rule tester
3. `docs/04_Functional_Spec_R1.md` — data model, rules, formulas, posting, roles, tests (R1)
4. `docs/03_SRS.md` — requirement IDs (e.g. LN-012), priority, release
5. `docs/02_BPR_and_Swimlanes.md` — 7 core processes, KPIs
6. `docs/01_Module_and_Feature_Map.md` — 21 modules, R1/R2/R3 tags

If documents conflict, the Decision Log wins, then FS, then SRS. Status of every doc is v0.1 draft: nothing is owner-approved yet.

## Non-negotiable engineering rules
- Configurability standard (`docs/08_Configurability_and_Library_Standard.md`): every calculation library is a pure, parameter-based TypeScript function (decimal library, no floats; Python never re-implements a calculation); no business constant, tenant name or segment branch in calculation code; every business rule is a typed, versioned, effective-dated parameter set (tiers T0 to T3) tested against worked examples before activation.
- No client-specific code. Differences live in tenant configuration or profile packs (PNP-PSMB, DepEd, LGU, corporate).
- Every table has `tenant_id` and row-level security; automated cross-tenant access tests run in CI.
- Money: `numeric(18,2)`, rates `numeric(9,6)`, decimal arithmetic only, 2-dp half-up unless a product rule says otherwise. No floats.
- Rules and formulas are versioned with effective dates and tested against owner-approved worked examples before activation.
- Money movements need maker-checker; corrections are reversals, never deletes; every sensitive change is audit-logged.
- Synthetic data only. Never commit real member data, credentials, `.env` files or production exports. This repo is public.
- No stored-value wallet; payments go through licensed partners.

## Gate before building
D2, D7, D11 and D12 are decided (23 Oct 2026); all PROPOSED items were accepted. The design partner is referred to as PARTNER-S1 only (never named in this public repo). Jun approved the standard S1 profile (docs/10), conventions C1 to C8 and the synthetic worked examples as owner on 23 Oct 2026 (D18), so the engine may implement those formulas as parameter defaults. Dividend, patronage refund and deduction-file examples are not yet approved: do not hard-code those. The first paying S1 customer validates the standard in a parallel run. Jun moved development to Claude Code on 24 Oct 2026 (D21), so slice 1 may start in the first Claude Code session; later slices follow the order in docs/11.

## Suggested first build slice (after gate)
Tenant + auth + RLS skeleton → membership → loan product config + rule tester → loan release (amortisation, dues schedule) → teller/EOD and direct payments → loan follow-up and aging → GL posting → core reports. A thin single-office payroll-deduction slice (file out, remittance in, matching, allocation, shortfalls) follows teller/EOD behind the `payroll_deduction` flag (D19); multi-office formats and take-home-pay checks are R2. Full slice list and acceptance tests are in docs/11. Release tags: R1 MVP, R2 repeatable, R3 scale.

## Where context lives outside the repo
Private Claude Project "ITHINK iCoops" holds the original handoff brief, source inventory, 2023 module map, 2024 proposal reference and brochure draft. Commercial material (business case, pricing) is deliberately kept out of this public repo.
