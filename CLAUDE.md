# CLAUDE.md — iCOOPs

Read this first in every session. The repo is the handoff: everything needed to continue is here or linked from here.

## What this is
iCOOPs: greenfield multi-tenant SaaS for Philippine cooperatives (iThink Digital). Payroll-deduction (employee-based) co-ops first. Product owner: Jun Mercader.

## Status (23 Oct 2026)
Design phase. **No app code, Supabase project or Vercel project exists yet.** Do not scaffold until Jun confirms the design review is done (see "Gate" below).

## Decided stack (docs/07, section D)
Next.js + React (PWA) · Supabase PostgreSQL (RLS on `tenant_id`) · JSON APIs · Python only for batch/computation jobs · Vercel · GitHub org ITHINK-DIGITAL. Same pattern as iLogistics / Malasakit.

## Source of truth (read in this order)
1. `docs/07_Decision_Log_and_Open_Questions.md` — what is decided vs open
2. `docs/05_Worked_Examples_Starter.md` + `docs/worked_examples/starter.json` — synthetic engine test vectors (pending approval); load them in the rule tester
3. `docs/04_Functional_Spec_R1.md` — data model, rules, formulas, posting, roles, tests (R1)
4. `docs/03_SRS.md` — requirement IDs (e.g. LN-012), priority, release
5. `docs/02_BPR_and_Swimlanes.md` — 7 core processes, KPIs
6. `docs/01_Module_and_Feature_Map.md` — 21 modules, R1/R2/R3 tags

If documents conflict, the Decision Log wins, then FS, then SRS. Status of every doc is v0.1 draft: nothing is owner-approved yet.

## Non-negotiable engineering rules
- No client-specific code. Differences live in tenant configuration or profile packs (PNP-PSMB, DepEd, LGU, corporate).
- Every table has `tenant_id` and row-level security; automated cross-tenant access tests run in CI.
- Money: `numeric(18,2)`, rates `numeric(9,6)`, decimal arithmetic only, 2-dp half-up unless a product rule says otherwise. No floats.
- Rules and formulas are versioned with effective dates and tested against owner-approved worked examples before activation.
- Money movements need maker-checker; corrections are reversals, never deletes; every sensitive change is audit-logged.
- Synthetic data only. Never commit real member data, credentials, `.env` files or production exports. This repo is public.
- No stored-value wallet; payments go through licensed partners.

## Gate before building
D2, D7, D11 and D12 are decided (23 Oct 2026); all PROPOSED items were accepted. The design partner is referred to as PARTNER-S1 only (never named in this public repo). Absent owner-approved worked examples (loan, savings interest, dividend, patronage refund, deduction file), do not hard-code financial formulas; build the rule engine and mark examples as pending.

## Suggested first build slice (after gate)
Tenant + auth + RLS skeleton → membership → loan product config + rule tester → loan release (amortisation) → payroll-deduction file + remittance matching → teller/EOD → GL posting → core reports. Release tags: R1 MVP, R2 repeatable, R3 scale.

## Where context lives outside the repo
Private Claude Project "ITHINK iCoops" holds the original handoff brief, source inventory, 2023 module map, 2024 proposal reference and brochure draft. Commercial material (business case, pricing) is deliberately kept out of this public repo.
