# iCOOPs

Multi-tenant cooperative management SaaS for Philippine cooperatives, by iThink Digital Technology Solutions.

**Status:** design phase (docs v0.1 draft). No application code yet.

## Stack (decided 18 Oct 2026)

- Next.js + React (PWA)
- Supabase PostgreSQL with row-level security (`tenant_id`)
- JSON APIs; Python where necessary (batch jobs, computations, reports)
- Vercel for hosting and CI; GitHub org ITHINK-DIGITAL

## Documents

| File | Content |
|---|---|
| [docs/01_Module_and_Feature_Map.md](docs/01_Module_and_Feature_Map.md) | 21 modules in 3 layers, release tags R1/R2/R3 |
| [docs/02_BPR_and_Swimlanes.md](docs/02_BPR_and_Swimlanes.md) | Actors, as-is vs to-be, 7 core processes, KPIs |
| [docs/03_SRS.md](docs/03_SRS.md) | Software requirements for all modules and releases |
| [docs/04_Functional_Spec_R1.md](docs/04_Functional_Spec_R1.md) | R1 architecture, data model, rules, formulas, tests |
| [docs/05_Worked_Examples_Starter.md](docs/05_Worked_Examples_Starter.md) | Synthetic reference vectors for the calculation engine (pending approval) |
| [docs/07_Decision_Log_and_Open_Questions.md](docs/07_Decision_Log_and_Open_Questions.md) | Decisions made and still open |

## Demo

[demo/r1-demo.html](demo/r1-demo.html) is a single-file R1 clickable prototype. It uses synthetic data only; thresholds, fees and limits shown are illustrative placeholders, not approved product rules. Open it in a browser.

Working with Claude Code? Start with [CLAUDE.md](CLAUDE.md).

All documents are working drafts and not yet owner-approved. Diagrams were exported from the source documents as images.
