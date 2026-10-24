# iCOOPs

Multi-tenant cooperative management SaaS for Philippine cooperatives, by iThink Digital Technology Solutions.

**Status:** slice 1 (skeleton) built and awaiting review: tenants, roles, row-level security, audit log, maker-checker and rule versions with the activation gate, plus a staff app shell and CI. Calculation libraries start in slice 2. Docs are v0.1 drafts. See [docs/12](docs/12_Slice1_Skeleton.md).

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
| [docs/08_Configurability_and_Library_Standard.md](docs/08_Configurability_and_Library_Standard.md) | Rule tiers, parameter-based library contract, parameter inventory |
| [docs/10_S1_Reference_Profile.md](docs/10_S1_Reference_Profile.md) | Expert reference answers for the S1 open items (illustrative parameters, not partner facts) |
| [docs/09_PARTNER-S1_Input_Request.md](docs/09_PARTNER-S1_Input_Request.md) | Adopted conventions C3 to C5, working assumptions and input request for the design partner |
| [docs/07_Decision_Log_and_Open_Questions.md](docs/07_Decision_Log_and_Open_Questions.md) | Decisions made and still open |
| [docs/11_Claude_Code_Kickoff.md](docs/11_Claude_Code_Kickoff.md) | How development works in Claude Code: slices and working agreements |
| [docs/12_Slice1_Skeleton.md](docs/12_Slice1_Skeleton.md) | Slice 1 reference: layout, schema, row-level security, maker-checker, CI, running locally |

## Demo

[demo/r1-demo.html](demo/r1-demo.html) is a single-file R1 clickable prototype. It uses synthetic data only; thresholds, fees and limits shown are illustrative placeholders, not approved product rules. Open it in a browser.

## Develop

Node 22 and pnpm. `pnpm install`, then `pnpm lint`, `pnpm typecheck`, `pnpm test`. The database tests, the local stack and the API tests are described in [docs/12](docs/12_Slice1_Skeleton.md) section 6. Never commit secrets or `.env` files; the repository is public and CI checks for them.

Working with Claude Code? Start with [CLAUDE.md](CLAUDE.md).

All documents are working drafts and not yet owner-approved. Diagrams were exported from the source documents as images.
