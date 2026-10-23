# iCOOPs — Decision Log & Open Questions

Created 18 Oct 2026 at handoff install. Status values: OPEN · PROPOSED (Claude) · DECIDED (Jun) · SUPERSEDED.

> Public-repo note: candidate customer names in D11 are generalised here. The full log is kept in the private Claude Project.

## A. Decisions needed from Jun (smallest set to fix the baseline)

| # | Decision | Options seen in sources | Claude recommendation | Status |
|---|---|---|---|---|
| D1 | Is the rebuild greenfield SaaS or a port of existing code? | No repo found; 2024 proposal implies an existing MMIS somewhere | Greenfield SaaS; legacy only as data-migration source | DECIDED (Jun, 18 Oct 2026): greenfield SaaS rebuild |
| D2 | Product line: one platform vs iCOOPs + EZ-COOPS separate | iCOOPs (back-office) vs EZ-COOPS (member fintech/community) | One multi-tenant core, two editions/feature tiers | DECIDED (Jun, 23 Oct 2026): one codebase, one multi-tenant platform; editions and member extras via feature flags; R1 is iCOOPs back-office only |
| D3 | Controlling functional baseline | DRV-017 vs DRV-018 (2025) | DRV-018 annotated, with PSMB/PNP fields moved to a configurable customer profile | PROPOSED |
| D4 | Front end | Blazor or React (PWA) | Decide with stack D5; React/Next.js PWA if aligning with Claude-first dev and shared SaaS DevOps across iLogistics/Malasakit | DECIDED (Jun, 18 Oct 2026): Next.js + React |
| D5 | Back end & DB | .NET Core + SQL Server (2025); ASP.NET/C# + SQL Server + SSRS (2024); AWS EC2/RDS (EZ-COOPS) | Decide on team skill + licence cost per tenant; Postgres removes SQL Server licence drag in SaaS economics | DECIDED (Jun, 18 Oct 2026): Supabase PostgreSQL; JSON APIs; Python where necessary |
| D6 | Tenancy model | "Multi-coop/unit structure… multi-tenant" (PSMB note) | Shared app, tenant_id + row-level security; dedicated DB option for large/gov tenants | PROPOSED |
| D7 | Accounting/GL | Separate ERP, integrate | Ship a minimal coop subledger→GL posting engine in core; integrate to full ERP optional (coops need CDA FS out of the box) | DECIDED (Jun, 23 Oct 2026): minimal subledger-to-GL posting engine in core; external ERP export in R2 |
| D8 | E-wallet | Internal wallet (2025 design) vs gateway integration | Gateway/partner integration only (GCash/Maya/banks); avoid stored-value wallet (BSP EMI licensing) | PROPOSED |
| D9 | Mobile | PWA Phase 1; MAUI/native Phase 2 | PWA with offline queue first; native only on proven demand | PROPOSED |
| D10 | Hosting & data residency | On-prem, Azure, AWS, "AWS GovCloud" | AWS/Azure PH-accessible regions; drop GovCloud (US-only); DPA/NPC compliance posture documented | PROPOSED |
| D11 | First anchor customer / design partner | Several candidate organisations appear in history | Pick ONE paying design-partner coop before building beyond MVP | DECIDED (Jun, 23 Oct 2026) approach: one design partner, chosen by who can supply the open-items checklist within ~2 weeks and commit to a parallel run; partner not yet named (kept out of this public repo) |
| D12 | Pricing model | One-time build + AMC + managed services (2024) | Onboarding fee + per-active-member/month with tier floors; managed services as add-on | DECIDED (Jun, 23 Oct 2026) approach: fixed-fee pilot with the design partner; list prices set after the pilot; pricing stays out of this public repo |
| D13 | Repository visibility | Public vs private | Public acceptable only while it holds engineering docs; commercial material stays out | DECIDED (Jun, 23 Oct 2026): repo stays public; business case, pricing and named prospects stay out |

## B. Conflicts to keep visible (do not silently merge)

1. 2025 demo files are byte-identical to 2020/2023 files → no demo proves 2025 functionality.
2. Broad A–N list vs annotations delegating G/J/M to separate systems and H to Phase 2.
3. 2026 brochure promises portal/mobile while requiring release confirmation.
4. "ISO 27001-ready", "BIR-compliant", "CDA-compliant" are design wording, not certifications.
5. PSMB/PNP-specific fields embedded in generic membership spec.

## C. Questions for Jun (short list)

1. Do you have any surviving source code, database backups or schema for the legacy iCOOPs/MMIS? Where?
2. Which cooperative is the first target (and is there budget/LOI)?
3. Are iCOOPs and EZ-COOPS one product family going forward?
4. Who is the product owner and technical lead on the iThink side (you, your son, a dev team)?
5. ~~Preferred build approach~~ — ANSWERED 18 Oct 2026: iThink standard SaaS stack (see section D).
6. Any CDA/BIR/AMLA report formats or worked financial examples (loan amortization, dividend/patronage) from a real coop to use as acceptance tests?

## D. iThink standard SaaS stack (DECIDED by Jun, 18 Oct 2026)

iCOOPs follows the same stack and DevOps pattern as iLogistics, Malasakit, GAD and the other iThink SaaS products:

- Delivery model: multi-tenant SaaS
- Source control: GitHub (org ITHINK-DIGITAL)
- Hosting/CI: Vercel (team iThink)
- Database/auth/storage: Supabase PostgreSQL (org iThink Technologies)
- App: Next.js + React; JSON APIs; Python where necessary (e.g., batch jobs, computations, reports)

Status: build NOT started. Next step = revisit iCOOPs design / BPR / SRS / FS in a separate session before any repo, Supabase project or Vercel project is created.
