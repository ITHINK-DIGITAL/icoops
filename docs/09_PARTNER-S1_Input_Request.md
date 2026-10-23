# PARTNER-S1 Input Request and Working Assumptions (v0.1)

Status: ADOPTED by Jun on 23 Oct 2026 (D17, D18). There is no signed partner, so this table is the validation checklist for the first S1 customer; the standard answers are in docs/10. Every assumption below is a parameter default, not a rule. PARTNER-S1's real data replaces it through configuration, never through code.

## 1. Conventions C3, C4, C5 (recommended defaults)

| # | Convention | Recommended default | Why | Alternative (parameter value) |
|---|---|---|---|---|
| C3 | Installment rounding | Round the installment half-up to 2 dp; the last installment clears the remaining balance exactly | Only choice that guarantees the schedule sums to the principal and the loan closes at zero. Member sees one regular amount and one slightly different last amount, which is normal practice | Spread residue across installments; no adjustment (leaves a few centavos open, creates tiny receivables) |
| C4 | Savings interest | ADB x r / 365 x days; round gross interest first, then compute withholding tax on the rounded gross, then net | Statement lines (gross, tax, net) must foot to the centavo and match the withholding certificate. Rounding tax on the unrounded figure can produce a 1-centavo mismatch | Actual/actual day-count; round net only; 360 basis |
| C5 | Penalty | Past-due installment (principal plus interest) x monthly rate x days beyond grace / 30; cap per installment at a percentage (default 10% of the past-due amount); no penalty on penalty | Simple to explain to a member, which matters for complaints under the financial-consumer rules. The cap protects against unconscionable-charge disputes (Philippine courts have reduced excessive penalty rates) | Penalty counted from the due date once grace expires (`penalty_from = due_date`); divisor 360; base = outstanding balance |

New parameter added to docs/08: **penalty accrual start** (after grace, default; or from due date).

Actual rates, grace days, cap and withholding-tax treatment come from PARTNER-S1's loan policy and tax adviser; the defaults above only fix the arithmetic.

## 2. S1 open items: working assumption, ask, and whether it blocks

Priority A = blocks the build of that slice. B = needed before the parallel run. C = default is safe until later.

| # | Open item | Working assumption (spec default) | What to ask PARTNER-S1 | Pri |
|---|---|---|---|---|
| 1 | Loan products and worked examples | Three starter templates: regular (diminishing, 12 to 36 months), emergency (short term), multipurpose. Methods diminishing and flat/add-on; release deductions as a configurable list | The top 3 products by volume with rate, method, term, fees, insurance, DST, CBU retention, penalty; and 3 de-identified real loan ledgers (normal, early payoff, late payer) | A |
| 2 | How members pay today | Teller cash or check, plus bank deposit or transfer with a reference; no gateway in R1 (D15) | Share of payments by channel; banks used; sample bank statement (CSV or PDF) | A |
| 3 | Savings products | Regular savings (ADB, monthly posting, withholding tax as parameter). Time deposit (SV-004) moves to R2 unless PARTNER-S1 offers it today | Product list, rate, method, minimum balance, tax treatment, 2 real posting examples | A |
| 4 | Chart of accounts and last audited FS | CDA-aligned template, mapped to PARTNER-S1's accounts at migration | Current chart of accounts (Excel) and last audited statements | B |
| 5 | Legacy data | Migration by validated CSV templates (PL-030, PL-050); biggest R1 schedule risk | Member count, open loans, source system, 100-row de-identified sample, known data quality problems | B |
| 6 | Approval matrix and staff roles | Default bands: officer, GM, credit committee (amounts are placeholders), maker-checker always on money movement | Approval limits by role, staff list by role, who closes the day | B |
| 7 | By-laws: CBU, capital cap, lock-in | Cap default 10% (regulatory flag); CBU minimum, lock-in months as parameters. Surplus allocation is R2 and not needed for R1 | CBU minimum and plan, subscription and par value, lock-in, refund approval threshold | B |
| 8 | Follow-up routine for overdue loans | Reminders 5 days before due, then 1, 7, 15, 30 days after; aging buckets 1-30, 31-60, 61-90, 91-180, over 180; all parameters | Current routine, who calls, templates, promise-to-pay practice | B |
| 9 | Tax: DST, withholding, exemption | Parameters only; no rate hard-coded | Written position from the co-op's tax adviser | B |
| 10 | Loan-loss history | Allowance percentages per aging bucket as parameters | Last 3 years: past-due ratio, write-offs, recoveries; current provisioning policy | C |

## 3. The test that settles most of this

Ask PARTNER-S1 for three real loan ledgers and one month of savings interest postings (de-identified). Load them as vectors. If the engine reproduces PARTNER-S1's figures with the C3 to C5 defaults, the conventions are confirmed. If it differs, the difference shows which parameter value PARTNER-S1 actually uses. This is better evidence than any recommendation, and the parallel run repeats the test at full scale.

## 4. Build-gate note

Items 1 to 3 gate the loan and savings engines. They do not gate the tenant, authentication, row-level-security and rule-engine skeleton, which depend on no partner figures. Starting that skeleton requires Jun's confirmation that the design review is done (CLAUDE.md gate).

## 5. Risk of building without a design partner (D18) and mitigations

| Risk | Mitigation |
|---|---|
| Financial rules never validated by a real co-op before first customer | Independent accountant recomputes every vector (docs/05 approval table); one hour of review by a practising co-op treasurer from Jun's network |
| Standard differs from how a real co-op works | All values are parameters; first customer's three ledgers become vectors in week one of onboarding |
| Regulatory misreads (tax, CDA, lending disclosure) | Mark every such value CONFIRM; tax and CDA positions confirmed by an adviser before the first go-live |
| No parallel-run partner for acceptance | Keep the one-month parallel run as a condition of the first customer contract |
