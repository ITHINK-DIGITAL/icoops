# Software Requirements Specification

The SRS states what iCOOPs shall do, module by module; each requirement has an ID, priority and release so it can be traced to design and tests.

## Purpose, scope and conventions

This SRS covers all 21 modules of iCOOPs across releases R1–R3; the Functional Spec tab details only R1.

- **In scope:** multi-tenant SaaS for Philippine cooperatives — platform services, cooperative operations (membership through compliance), member self-service and payments via licensed partners.
- **Out of scope:** stored-value e-wallet, HRIS and staff payroll, full document management, native mobile apps, client-specific code.
- **References:** iCOOPs Module and Feature Map; iCOOPs SaaS Business Case; RA 9520 (Cooperative Code); RA 10173 (Data Privacy Act); RA 9510 (CISA); RA 11765 and CDA MC 2025-08 (FCPAMS); CDA MC 2025-02 (reports and COC); CDA MC 2024-07 (credit services); DepEd APDS orders.

| Field | Meaning |
|---|---|
| ID | Module prefix + number (PL = platform, MB = membership, SC = share capital, SV = savings, LN = loans, PD = payroll deduction, TL = teller, DV = dividends, BN = benefits, AC = accounting, CP = compliance, MS = member self-service, PY = payments, GV = governance, RP = reports, AI = AI assist) |
| Priority | Must = R1 cannot ship without it; Should = expected, may slip one release; Could = valuable, optional |
| Release | R1 MVP, R2 repeatable product, R3 scale |

## Platform requirements (P1–P6)

The platform requirements make every tenant isolated, configurable and auditable before any cooperative feature is built on top.

| ID | Requirement | Priority | Release |
|---|---|---|---|
| PL-001 | The system shall isolate each cooperative's data by tenant using database row-level security on every table. | Must | R1 |
| PL-002 | The system shall let an iThink administrator create a tenant with branches/units, fiscal year, logo and default settings. | Must | R1 |
| PL-003 | The system shall provide a sandbox tenant per prospect with synthetic data. | Should | R1 |
| PL-004 | The system shall bill tenants by subscription tier based on active members, with add-ons and invoices. | Should | R2 |
| PL-005 | The system shall enable or disable modules and profile packs per tenant through feature flags. | Must | R1 |
| PL-010 | The system shall let authorized tenant users define savings, loan, CBU and benefit products from templates without code. | Must | R1 |
| PL-011 | The system shall store each rule and formula with a version and effective date, and apply the version in force on the transaction date. | Must | R1 |
| PL-012 | The system shall run a rule against saved worked examples and block activation if any expected result differs. | Must | R1 |
| PL-013 | The system shall let tenants add custom member fields and required-document lists. | Must | R1 |
| PL-014 | The system shall route approvals through configurable chains by transaction type, amount and role. | Must | R1 |
| PL-015 | The system shall generate member, account, OR and voucher numbers from tenant-defined patterns without gaps. | Must | R1 |
| PL-016 | The system shall install profile packs (PNP-PSMB, DepEd, LGU, corporate) as configuration bundles. | Should | R2 |
| PL-020 | The system shall authenticate staff by email or mobile with password and OTP-based 2FA. | Must | R1 |
| PL-021 | The system shall enforce role-based permissions per module, action and amount limit. | Must | R1 |
| PL-022 | The system shall require a second user (maker-checker) to approve money movements, reversals, back-dating and rate changes. | Must | R1 |
| PL-023 | The system shall log every create, update, approve and view of sensitive records with user, time, before and after values. | Must | R1 |
| PL-024 | The system shall capture data-privacy consent and support access, correction and erasure requests within legal retention limits. | Must | R1 |
| PL-030 | The system shall import members, accounts and transactions from validated CSV/Excel templates with error reports. | Must | R1 |
| PL-031 | The system shall expose JSON APIs and webhooks for core entities and events. | Should | R2 |
| PL-040 | The system shall send SMS, email and in-app notifications from bilingual tenant templates on configured triggers. | Must | R1 |
| PL-050 | The system shall load opening balances and reconcile them to the legacy trial balance, with sign-off before go-live. | Must | R1 |
| PL-051 | The system shall support a parallel run comparing iCOOPs outputs with the legacy system for at least one cycle. | Should | R1 |

## Membership and share capital requirements

These requirements support process P1 and give every other module one trusted member record.

| ID | Requirement | Priority | Release |
|---|---|---|---|
| MB-001 | The system shall accept membership applications from the branch and the member PWA, with required documents per member type. | Must | R1 |
| MB-002 | The system shall record PMES attendance and block approval without it. | Must | R1 |
| MB-003 | The system shall flag possible duplicate members by name, birthdate and government ID. | Must | R1 |
| MB-004 | The system shall screen applicants against a tenant-maintained watchlist and PEP list. | Should | R1 |
| MB-005 | The system shall route applications for approval and support batch approval by the Board with resolution reference. | Must | R1 |
| MB-006 | The system shall maintain member type (regular, associate) and status (applicant, active, inactive, suspended, resigned, deceased, terminated) with effective dates and reasons. | Must | R1 |
| MB-007 | The system shall store employment details including employer and payroll office, used by payroll deduction. | Must | R1 |
| MB-008 | The system shall store beneficiaries and dependents with relationship and share percentage totaling 100%. | Must | R1 |
| MB-009 | The system shall show a Member 360 view of capital, savings, loans, co-maker exposure, deductions and benefits. | Must | R1 |
| MB-010 | The system shall process resignation, retirement and death with a clearance checklist across all accounts. | Must | R1 |
| MB-011 | The system shall print membership ID cards with QR code. | Could | R2 |
| SC-001 | The system shall record subscribed and paid-up share capital per member with par value from by-laws. | Must | R1 |
| SC-002 | The system shall apply CBU plans by member type and include required CBU in the deduction schedule. | Must | R1 |
| SC-003 | The system shall keep a capital ledger of contributions, dividend transfers, share transfers and withdrawals. | Must | R1 |
| SC-004 | The system shall enforce minimum paid-up, maximum holding and lock-in rules from configuration. | Must | R1 |
| SC-005 | The system shall process capital refunds on exit, offsetting outstanding loans before payout. | Must | R1 |
| SC-006 | The system shall record member-to-member share transfers with Board approval. | Should | R2 |
| SC-007 | The system shall generate share certificates and the share register. | Should | R2 |

## Savings and loan requirements

Savings and loans carry most of the money; every computation here must match owner-approved worked examples to the centavo.

| ID | Requirement | Priority | Release |
|---|---|---|---|
| SV-001 | The system shall open multiple savings accounts per member from configured products (regular, special, youth, time deposit). | Must | R1 |
| SV-002 | The system shall post deposits, withdrawals, transfers and adjustments with maker-checker above configured limits. | Must | R1 |
| SV-003 | The system shall compute interest by the product's method (average daily balance or minimum monthly balance) and post at the configured frequency, net of withholding tax. | Must | R1 |
| SV-004 | The system shall manage time deposits: placement, certificate, maturity, rollover and pre-termination rate. | Should | R1 |
| SV-005 | The system shall apply holds (legal, collateral, deceased) and mark accounts dormant after a configured inactivity period. | Must | R1 |
| SV-006 | The system shall produce passbook prints, statements and mini-statements. | Must | R1 |
| LN-001 | The system shall define loan products with rate, method (diminishing, flat, add-on), terms, fees, penalties, limits and required documents. | Must | R1 |
| LN-002 | The system shall accept loan applications from branch and PWA, with co-maker consent captured electronically. | Must | R1 (PWA in R2) |
| LN-003 | The system shall check eligibility: membership age, capital and savings multiples, existing loans, past-due status and co-maker exposure. | Must | R1 |
| LN-004 | The system shall check net take-home pay after the new amortization against the payroll office's floor and block or warn per configuration. | Must | R1 |
| LN-005 | The system shall record credit evaluation notes, CIC report reference and recommended amount. | Must | R1 |
| LN-006 | The system shall route approval by the tenant's amount matrix and record committee decisions with reasons. | Must | R1 |
| LN-007 | The system shall compute the amortization schedule and release deductions (fees, insurance, documentary stamp tax, CBU, prior-loan payoff). | Must | R1 |
| LN-008 | The system shall release by cash, check, bank transfer or e-wallet, generating a disbursement voucher. | Must | R1 |
| LN-009 | The system shall add amortizations to the member's deduction schedule on release. | Must | R1 |
| LN-010 | The system shall allocate payments in the configured order (default penalty, interest, principal) and handle advance and partial payments. | Must | R1 |
| LN-011 | The system shall compute penalties on past-due amounts per product rule and grace period. | Must | R1 |
| LN-012 | The system shall support renewal, top-up and restructuring with configured minimum-paid rules. | Must | R1 |
| LN-013 | The system shall age the portfolio, tag past-due loans and compute allowance for probable losses. | Must | R1 |
| LN-014 | The system shall generate demand letters by aging bucket. | Should | R2 |
| LN-015 | The system shall maintain a collateral register and release collateral on full payment. | Should | R2 |
| LN-016 | The system shall process write-off with Board approval and track recoveries. | Should | R2 |

## Payroll deduction and teller requirements

These requirements implement processes P3 and P4, the daily and monthly cash cycles of an employee cooperative.

| ID | Requirement | Priority | Release |
|---|---|---|---|
| PD-001 | The system shall register payroll offices with file format, cut-off date, remittance account and service-fee rule. | Must | R1 |
| PD-002 | The system shall keep a deduction schedule per member and item (CBU, savings, loan amortization, benefit dues) with start and stop dates. | Must | R1 |
| PD-003 | The system shall generate the monthly deduction file per payroll office, plus change lists of new, stopped and amended deductions. | Must | R1 |
| PD-004 | The system shall flag members whose total deductions would breach the net take-home-pay floor before the file is approved. | Must | R1 |
| PD-005 | The system shall import remittance files and auto-match lines by member identifier and deduction item. | Must | R1 |
| PD-006 | The system shall classify each line as matched, partial, zero-pay, unknown member or excess, and queue exceptions for review. | Must | R1 |
| PD-007 | The system shall allocate short remittances by the tenant's allocation order. | Must | R1 |
| PD-008 | The system shall carry forward or bill shortfalls and notify affected members. | Must | R1 |
| PD-009 | The system shall reconcile expected vs received by payroll office and month, and age unremitted amounts. | Must | R1 |
| PD-010 | The system shall compute and post payroll office service fees deducted from remittances. | Should | R1 |
| PD-011 | The system shall support field collectors with routes and receipts for direct-pay members. | Could | R3 |
| TL-001 | The system shall open and close teller sessions with cash limits and opening cash. | Must | R1 |
| TL-002 | The system shall post one payment across several accounts of a member and issue one official receipt. | Must | R1 |
| TL-003 | The system shall post withdrawals, loan releases and refunds against vouchers with required approvals. | Must | R1 |
| TL-004 | The system shall record end-of-day cash count by denomination and compute over or short. | Must | R1 |
| TL-005 | The system shall require head-teller approval to close the day and lock postings for that date. | Must | R1 |
| TL-006 | The system shall correct posted transactions only by approved reversal with reason. | Must | R1 |
| TL-007 | The system shall record vault transfers between tellers and the vault. | Should | R1 |

## Dividends, patronage, benefits and claims requirements

These R2 requirements cover processes P5 and P6; both are approval-heavy and must leave a complete audit trail.

| ID | Requirement | Priority | Release |
|---|---|---|---|
| DV-001 | The system shall allocate net surplus to statutory and optional funds by the percentages in the tenant's by-laws. | Must | R2 |
| DV-002 | The system shall compute interest on share capital per member by the configured method (default: average share months). | Must | R2 |
| DV-003 | The system shall compute patronage refund per member from qualifying transactions (e.g. loan interest paid) and the rate per service. | Must | R2 |
| DV-004 | The system shall simulate multiple rate scenarios showing total payout and per-member results before approval. | Must | R2 |
| DV-005 | The system shall lock an approved run and version any rerun with reason and approver. | Must | R2 |
| DV-006 | The system shall credit results to savings or capital, offset past-due loans, or prepare cash/check payout, per member choice or policy. | Must | R2 |
| DV-007 | The system shall track unclaimed dividends and refunds. | Should | R2 |
| DV-008 | The system shall produce member dividend and refund slips. | Must | R2 |
| BN-001 | The system shall define benefit plans with eligibility, contribution and benefit amount rules. | Must | R2 |
| BN-002 | The system shall collect benefit contributions through deductions or teller and track arrears. | Must | R2 |
| BN-003 | The system shall accept claims from branch or PWA with required documents per claim type. | Must | R2 |
| BN-004 | The system shall check claim eligibility against member status, contributions and beneficiaries, and flag duplicates. | Must | R2 |
| BN-005 | The system shall route claims for approval and record denial reasons. | Must | R2 |
| BN-006 | The system shall compute the benefit, offset outstanding obligations if policy allows, and generate the payout voucher. | Must | R2 |
| BN-007 | The system shall track claims forwarded to partner insurers and their status. | Should | R2 |

## Accounting and compliance requirements

Accounting is inside the core so that every module transaction lands in the GL the moment it is posted (process P7).

| ID | Requirement | Priority | Release |
|---|---|---|---|
| AC-001 | The system shall provide a cooperative chart of accounts template aligned with CDA reporting, editable per tenant, with branch segments. | Must | R1 |
| AC-002 | The system shall post every financial transaction to the GL through configurable posting rules and reject unbalanced entries. | Must | R1 |
| AC-003 | The system shall support manual journal vouchers with attachments, approval and recurring templates. | Must | R1 |
| AC-004 | The system shall keep cash receipts and cash disbursement books. | Must | R1 |
| AC-005 | The system shall reconcile bank accounts from uploaded statements. | Should | R1 |
| AC-006 | The system shall compare member subledgers with GL control accounts daily and list differences. | Must | R1 |
| AC-007 | The system shall produce trial balance, statement of financial condition, statement of operations, cash flows and changes in equity. | Must | R1 |
| AC-008 | The system shall lock a period on close and allow reopening only by logged override. | Must | R1 |
| AC-009 | The system shall run year-end closing and transfer net surplus to the allocation module. | Must | R2 |
| AC-010 | The system shall export GL to an external ERP. | Could | R2 |
| CP-001 | The system shall generate the CIC/CISA submission file from loan data in the required format. | Must | R1 |
| CP-002 | The system shall produce the CDA annual reporting set required for the Certificate of Compliance. | Must | R2 (basic in R1) |
| CP-003 | The system shall log financial-consumer complaints with SLA tracking and resolution, per CDA FCPAMS guidelines. | Must | R1 |
| CP-004 | The system shall flag transactions above configured AMLA thresholds and patterns for review. | Should | R2 |
| CP-005 | The system shall produce BIR schedules and certificates the cooperative needs for withholding on interest and dividends. | Should | R2 |
| CP-006 | The system shall keep a compliance calendar with owners, reminders and proof of submission. | Should | R2 |
| CP-007 | The system shall compute standard financial ratios (e.g. PEARLS-type) for management and federation reporting. | Should | R2 |

## Member channels, governance, analytics and AI requirements

Most of these arrive in R2–R3; R1 needs only the standard reports and dashboards that management uses daily.

| ID | Requirement | Priority | Release |
|---|---|---|---|
| MS-001 | The system shall provide an installable member web app (PWA) with login by member number or mobile plus OTP. | Must | R2 |
| MS-002 | The system shall show members their capital, savings, loans, upcoming deductions and benefits. | Must | R2 |
| MS-003 | The system shall let members download statements, schedules, dividend slips and certificates. | Must | R2 |
| MS-004 | The system shall let members apply for loans, upload documents, track status and give co-maker consent. | Must | R2 |
| MS-005 | The system shall accept withdrawal, profile, beneficiary and complaint requests routed to staff queues. | Must | R2 |
| MS-006 | The system shall cache views and queue requests when connectivity is poor. | Should | R2 |
| PY-001 | The system shall accept loan payments and savings top-ups through licensed gateways (InstaPay, PESONet, QR Ph, e-wallets). | Must | R2 |
| PY-002 | The system shall post confirmed gateway payments automatically and reconcile gateway settlements. | Must | R2 |
| PY-003 | The system shall disburse loan proceeds and refunds to bank or e-wallet accounts via partners. | Should | R2 |
| PY-004 | The system shall not hold member funds in a stored-value wallet. | Must | All |
| GV-001 | The system shall record committees, meetings, minutes and resolutions linked to the approvals they authorize. | Should | R2 |
| GV-002 | The system shall manage General Assembly notices, attendance and quorum. | Should | R2 |
| GV-003 | The system shall run election eligibility checks and tallies; e-voting in R3. | Could | R3 |
| RP-001 | The system shall provide standard operational reports: member lists, ledgers, aging, collections, deductions, cash position, daily journal. | Must | R1 |
| RP-002 | The system shall provide an executive dashboard of membership, capital, deposits, loans, past-due ratio and collection efficiency. | Must | R1 |
| RP-003 | The system shall let users filter, group, schedule and export reports to Excel and PDF. | Should | R2 |
| RP-004 | The system shall consolidate reports across member co-ops for federations. | Could | R3 |
| AI-001 | The system shall extract data from IDs, payslips and claim documents and flag mismatches for staff review. | Should | R2 |
| AI-002 | The system shall summarize a loan applicant's capacity and history for the loan officer without making the decision. | Could | R3 |
| AI-003 | The system shall answer member questions in English or Filipino using only that member's own data and published policies. | Could | R3 |
| AI-004 | The system shall flag anomalies in withdrawals, claims and deductions. | Could | R3 |

## Non-functional requirements

The non-functional targets are sized for 40 tenants and 200,000 members by end of Year 3 (assumed), with headroom.

| ID | Area | Requirement | Target |
|---|---|---|---|
| NF-001 | Availability | Staff and member apps available during business hours | 99.5% monthly, excluding announced maintenance |
| NF-002 | Performance | Screen loads and single postings | p95 ≤ 2 s |
| NF-003 | Performance | Batch jobs (deduction file, interest posting, remittance matching) for a 20,000-member tenant | ≤ 5 minutes |
| NF-004 | Scalability | Tenants and members without redesign | 100 tenants, 500,000 members |
| NF-005 | Security | Encryption | TLS 1.2+ in transit; AES-256 at rest |
| NF-006 | Security | Secure development | OWASP Top 10 controls; dependency scanning in CI; annual penetration test |
| NF-007 | Tenancy | Isolation | Row-level security on every tenant table; automated cross-tenant access tests in CI |
| NF-008 | Privacy | Data Privacy Act compliance | DPO-ready records of processing, breach response within 72 hours, NPC registration support |
| NF-009 | Audit | Immutable audit log | Append-only; retained 10 years |
| NF-010 | Backup and DR | Recovery objectives | RPO ≤ 15 minutes; RTO ≤ 4 hours; restore test quarterly |
| NF-011 | Data retention | Financial records | Configurable; default 10 years |
| NF-012 | Accuracy | Financial computations | Match approved worked examples to the centavo; decimal arithmetic only, no floating point |
| NF-013 | Usability | Staff learning curve | Teller productive after 1 day of training |
| NF-014 | Accessibility | Member app | WCAG 2.1 AA |
| NF-015 | Localization | Language and formats | English with Filipino member messages; PHP currency; Asia/Manila time |
| NF-016 | Compatibility | Clients | Latest two versions of Chrome, Edge, Safari; Android 10+ PWA |
| NF-017 | Connectivity | Low-bandwidth branches | Core screens usable at 1 Mbps |
| NF-018 | Observability | Monitoring | Error tracking, job monitoring and per-tenant usage metrics |

## Integration and data requirements

R1 integrates by file, which every payroll office and regulator already accepts; APIs to partners follow in R2.

| Interface | Direction | Method | Release |
|---|---|---|---|
| Payroll offices (DepEd APDS, PNP, LGU, company HR) | Out: deduction file · In: remittance report | Files in each office's format | R1 |
| Banks | In: statement for reconciliation | CSV/Excel upload | R1 |
| CIC (credit information) | Out: credit data submission | File per CIC specification | R1 |
| SMS and email providers | Out: notifications | API | R1 |
| Legacy systems / Excel | In: migration | Validated templates | R1 |
| Payment gateways (InstaPay, PESONet, QR Ph, e-wallets) | In: payments · Out: disbursements | API + webhooks | R2 |
| Partner insurers | Out: claims and enrolments | File or API | R2 |
| External ERP | Out: GL | File or API | R2 |
| Federations | Out: consolidated reports | API | R3 |

Data requirements:

- Every table carries tenant_id, created/updated by and timestamps; money stored as numeric(18,2) with rates as numeric(9,6).
- Personal data (IDs, contact, beneficiaries) is classified sensitive: masked in lists, logged on view, excluded from non-production copies.
- Development and testing use synthetic data only; no real member records leave production.
- Each migration load is repeatable, idempotent and reversible until sign-off.

## Assumptions, constraints and open items

These items must be settled with the design partner before the R1 build starts.

- **Assumption:** the design partner is a payroll-deduction cooperative with 1,000–20,000 members and one to five payroll offices.
- **Assumption:** members accept PWA rather than native apps.
- **Constraint:** iThink standard stack — Next.js, Supabase PostgreSQL, Vercel, GitHub; Python only for batch and computation jobs.
- **Constraint:** no client-specific code; differences go into configuration or profile packs.
- **Open:** the design partner's payroll file formats and remittance report layouts (samples needed).
- **Open:** approved formulas and worked examples for interest, loans, penalties, dividends and patronage refunds.
- **Open:** the cooperative's current chart of accounts and CDA report set.
- **Open:** approval matrix and role mapping for the partner's staff.
- **Open:** whether DST, insurance and other release deductions vary by loan product.
