# S1 Reference Profile (expert answers to the docs/09 section 2 table) v0.1

Status: PROPOSED by Claude from experience with Philippine cooperatives, requested by Jun on 23 Oct 2026. These are **reference answers, not PARTNER-S1 facts**. They let the Functional Spec, the rule tester and the demo be completed now. Every value is a synthetic, illustrative parameter default; PARTNER-S1's real policy replaces it through configuration. Regulatory and tax items are marked CONFIRM and must not be treated as legal advice.

## 1. Answers by open item

| # | Item | Reference answer | Real fact still needed? |
|---|---|---|---|
| 1 | Loan products | **Regular loan**: diminishing, 12.0% p.a., 6 to 36 months, 5,000 to 300,000, limit 3x (paid-up capital + savings). Release deductions: service fee 1.0%, credit life insurance 0.6%, CBU retention 2.0% until the minimum paid-up is reached, prior-loan payoff on renewal, DST per CONFIRM. Penalty 2.0% per month, grace 5 days, cap 10% of the past-due amount. **Emergency loan**: diminishing, 12.0% p.a., 1 to 6 months, up to 20,000 or 1x savings, no CBU retention. **Multipurpose loan**: diminishing, 14.4% p.a., 12 to 48 months, larger limit, co-maker required. Flat/add-on stays available as a method but is not used by the reference products | Yes: rates, fees and limits are PARTNER-S1's policy |
| 2 | How members pay | Both channels from day one: teller (cash, check) and bank deposit or transfer with a reference. Assume salary-linked members mostly pay by bank deposit. Bank statement import with reference matching, and an unmatched-deposit queue, are the key R1 features. No gateway until R2 | Yes: actual channel mix and bank statement layout |
| 3 | Savings | **Regular savings**: 3.0% p.a., average daily balance, posted monthly, minimum balance to earn 1,000, withholding tax 20% as a parameter. **Time deposit** moves to R2 unless PARTNER-S1 offers it today. Dormancy flag after 12 months | Yes: rate, minimums and tax treatment |
| 4 | Chart of accounts and FS | Start from the CDA-aligned template; map PARTNER-S1's accounts during migration. No custom COA design in R1 | Yes: their current COA and last audited FS |
| 5 | Legacy data | Size the build for 5,000 members and 2,000 open loans. Migrate by validated CSV: members, share capital, savings balances, open loans with remaining schedule, opening trial balance. Two trial loads, reconcile to the legacy trial balance, then cut over at a month-end. Expect messy names, duplicate members and loan histories without schedules | Yes: counts, source system, quality |
| 6 | Approval matrix | Loans: loan officer to 20,000; GM to 100,000; credit committee above 100,000; Board for 300,000 and up. Withdrawals above 50,000: GM. Day close: head teller. Reversal after day lock: manager override with reason. Maker-checker on every money movement, not configurable | Yes: their limits and role names |
| 7 | By-laws: CBU, cap, lock-in | Capital holding cap 10% (regulatory flag). Monthly CBU plan as a parameter by member type. Minimum paid-up, lock-in months and refund approval threshold left as parameters with no default until the by-laws are read. Surplus allocation is R2 | Yes: by-laws |
| 8 | Overdue follow-up | Reminder 5 days before due, then 1, 7, 15 and 30 days after (SMS first, email second). Day 1 to 30: collections officer calls. Day 31 to 60: co-maker contacted, promise to pay recorded. Day 61 to 90: written notice and credit committee review. Over 90: demand letter (R2) and restructure or write-off review. Buckets 1-30, 31-60, 61-90, 91-180, over 180 | Partly: their actual routine and templates |
| 9 | Tax: DST, withholding, exemption | No rate hard-coded anywhere. Withholding tax, DST and any exemption are tenant parameters with effective dates. Posting rules route each to its own payable account | Yes: tax adviser's written position (CONFIRM) |
| 10 | Loan-loss history | Allowance by aging bucket as parameters; use the regulator's prescribed rates if any (CONFIRM) and otherwise PARTNER-S1's policy. Not needed to build, only to set the allowance parameters | Yes, but late: not blocking |

## 2. Recommendations that go beyond the table

| Recommendation | Why | Proposed handling |
|---|---|---|
| Disclosure statement at loan release showing principal, finance charges, net proceeds and effective interest rate | The Truth in Lending Act (RA 3765) requires borrowers to be told finance charges and the effective rate; matters most if a tenant uses flat or add-on pricing (effective rate is far above the quoted rate). Reduces complaint exposure under the financial-consumer rules | Add as a new requirement (proposed LN-019, R1, Must) after Jun approves |
| Reference products use diminishing balance only | Easier to explain and defend; flat rates hide the true cost | Keep flat/add-on as a selectable strategy |
| Reference penalty 2.0% per month with a cap | Excessive penalty rates get reduced by courts and attract complaints | Note: the synthetic vectors in docs/05 use 3.0% as a test value; the reference product uses 2.0% |
| Sequence the build on items 1 to 3 | Loan and savings engines are the core of R1 and the only items that block coding | See docs/09 section 4 |

## 3. How to use this profile

1. Load the reference products into the rule tester and the demo as the sandbox tenant (synthetic data only).
2. Send PARTNER-S1 the docs/09 table. Each reference answer becomes a "confirm or correct" question, which is faster for them than a blank form.
3. When PARTNER-S1 replies, create a new rule version per product. Nothing in code changes.
