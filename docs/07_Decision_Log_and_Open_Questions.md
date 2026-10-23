# iCOOPs — Decision Log & Open Questions

Created 18 Oct 2026 at handoff install. Status values: OPEN · PROPOSED (Claude) · DECIDED (Jun) · SUPERSEDED.

> Public-repo note: candidate customer names in D11 are generalised here. The full log is kept in the private Claude Project.

## A. Decisions needed from Jun (smallest set to fix the baseline)

| # | Decision | Options seen in sources | Claude recommendation | Status |
|---|---|---|---|---|
| D1 | Is the rebuild greenfield SaaS or a port of existing code? | No repo found; 2024 proposal implies an existing MMIS somewhere | Greenfield SaaS; legacy only as data-migration source | DECIDED (Jun, 18 Oct 2026): greenfield SaaS rebuild |
| D2 | Product line: one platform vs separate products (EZ-COOPS was earlier branding, now iCOOPs) | back-office vs member fintech/community | One multi-tenant core, two editions/feature tiers | DECIDED (Jun, 23 Oct 2026): one product, iCOOPs (EZ-COOPS is retired branding); one codebase, multi-tenant; member extras via feature flags; R1 is back-office only |
| D3 | Controlling functional baseline | DRV-017 vs DRV-018 (2025) | DRV-018 annotated, with PSMB/PNP fields moved to a configurable customer profile | DECIDED (Jun, 23 Oct 2026): accepted as recommended |
| D4 | Front end | Blazor or React (PWA) | Decide with stack D5; React/Next.js PWA if aligning with Claude-first dev and shared SaaS DevOps across iLogistics/Malasakit | DECIDED (Jun, 18 Oct 2026): Next.js + React |
| D5 | Back end & DB | .NET Core + SQL Server (2025); ASP.NET/C# + SQL Server + SSRS (2024); AWS EC2/RDS (earlier EZ-COOPS build) | Decide on team skill + licence cost per tenant; Postgres removes SQL Server licence drag in SaaS economics | DECIDED (Jun, 18 Oct 2026): Supabase PostgreSQL; JSON APIs; Python where necessary |
| D6 | Tenancy model | "Multi-coop/unit structure… multi-tenant" (PSMB note) | Shared app, tenant_id + row-level security; dedicated DB option for large/gov tenants | DECIDED (Jun, 23 Oct 2026): accepted as recommended |
| D7 | Accounting/GL | Separate ERP, integrate | Ship a minimal coop subledger→GL posting engine in core; integrate to full ERP optional (coops need CDA FS out of the box) | DECIDED (Jun, 23 Oct 2026): minimal subledger-to-GL posting engine in core; external ERP export in R2 |
| D8 | E-wallet | Internal wallet (2025 design) vs gateway integration | Gateway/partner integration only (GCash/Maya/banks); avoid stored-value wallet (BSP EMI licensing) | DECIDED (Jun, 23 Oct 2026): accepted as recommended |
| D9 | Mobile | PWA Phase 1; MAUI/native Phase 2 | PWA with offline queue first; native only on proven demand | DECIDED (Jun, 23 Oct 2026): accepted as recommended |
| D10 | Hosting & data residency | On-prem, Azure, AWS, "AWS GovCloud" | AWS/Azure PH-accessible regions; drop GovCloud (US-only); DPA/NPC compliance posture documented | DECIDED (Jun, 23 Oct 2026): accepted as recommended |
| D11 | First anchor customer / design partner | Several candidate organisations appear in history | Pick ONE paying design-partner coop before building beyond MVP | DECIDED (Jun, 23 Oct 2026) approach: one design partner, chosen by who can supply the open-items checklist within ~2 weeks and commit to a parallel run; design partner is referred to as PARTNER-S1 in this repo (name kept out) |
| D12 | Pricing model | One-time build + AMC + managed services (2024) | Onboarding fee + per-active-member/month with tier floors; managed services as add-on | DECIDED (Jun, 23 Oct 2026) approach: fixed-fee pilot with the design partner; list prices set after the pilot; pricing stays out of this public repo |
| D13 | Repository visibility | Public vs private | Public acceptable only while it holds engineering docs; commercial material stays out | DECIDED (Jun, 23 Oct 2026): repo stays public; business case, pricing and named prospects stay out |
| D14 | Segment and tenancy configuration | One codebase for every customer type; behaviour differs by configuration | DECIDED (Jun, 23 Oct 2026, from meeting): (1) private companies: one tenant per company, codebase standardised across companies, payroll deduction normally OFF; (2) LGU/government and/or federation: multi-tenant capability, payroll deduction ON. Clarified (Jun, 23 Oct 2026): every customer, private included, is a tenant on the shared multi-tenant SaaS platform; no per-company dedicated deployments by default. OPEN: how the federation-to-member hierarchy is modelled; ~~which segment the design partner belongs to~~ (answered: S1) |
| D15 | R1 scope for segment S1 | Cut R1 for private co-ops; payroll deduction to R2 (S2); digital payments stay R2 | DECIDED (Jun, 23 Oct 2026): digital payments stay R2 (needs wallet and gateway connections); R1 collects by teller, direct payment and loan follow-up; payroll deduction built behind a flag and released in R2 |
| D16 | Configurability and library standard | Parameter-based libraries; four-tier configurable rules (docs/08) | DECIDED (Jun, 23 Oct 2026): all libraries parameter-based; all business rules configurable, open and dynamic within the tiers and invariants in docs/08. Four-tier model (T0 invariants, T1 parameters, T2 strategies, T3 expressions) confirmed by Jun 23 Oct 2026; canonical library language DECIDED (Jun, 23 Oct 2026): TypeScript with a decimal library; Python for orchestration and report jobs only, running the shared vectors in CI; open: T3 expression language (R2) |

## B. Conflicts to keep visible (do not silently merge)

1. 2025 demo files are byte-identical to 2020/2023 files → no demo proves 2025 functionality.
2. Broad A–N list vs annotations delegating G/J/M to separate systems and H to Phase 2.
3. 2026 brochure promises portal/mobile while requiring release confirmation.
4. "ISO 27001-ready", "BIR-compliant", "CDA-compliant" are design wording, not certifications.
5. PSMB/PNP-specific fields embedded in generic membership spec.

## C. Questions for Jun (short list)

1. Do you have any surviving source code, database backups or schema for the legacy iCOOPs/MMIS? Where?
2. Which cooperative is the first target (and is there budget/LOI)?
3. ~~Are iCOOPs and EZ-COOPS one product family?~~ — ANSWERED 23 Oct 2026: EZ-COOPS was branding; now iCOOPs.
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

## E. Partner segments (DECIDED by Jun, 23 Oct 2026, part of D14)

A partner segment is the customer category a cooperative falls into. It fixes how the co-op collects repayments, how its tenant is shaped and which profile pack it starts from. It is not a customer name and not the same thing as a profile pack.

| Segment | Members | Tenant shape | Payroll deduction | Starting profile pack |
|---|---|---|---|---|
| S1 Private | Employees of a private company, or an open community | One tenant per co-op on the shared platform | Normally OFF (teller, direct pay, later digital payments) | Private |
| S2 LGU / government | Government employees (e.g. DepEd, PNP, LGU offices) | One tenant, several payroll offices and units | ON | Government |
| S3 Federation | Member co-ops of a federation | Parent tenant plus child co-op tenants, consolidated reporting | Set per member co-op | Federation, on top of the member's own pack |

Rules:
1. The collection channel decides the segment, not the employer type. A private co-op that does collect by payroll deduction stays S1 with the payroll-deduction flag ON; that is configuration, not a new segment.
2. A segment never changes the code; it changes only the profile pack, feature flags and tenant hierarchy.
3. Placing a prospect: who deducts from salary, if anyone; one tenant or a group of co-ops; where the member pays.

PARTNER-S1 is the design partner and belongs to segment S1 (private, payroll deduction normally OFF). R1 is therefore cut for S1; S2 (government) and S3 (federation) follow.

Open: federation hierarchy design.
