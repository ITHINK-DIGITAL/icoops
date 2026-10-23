# Configurability and Library Standard (v0.1)

Status: DECIDED by Jun, 23 Oct 2026 (D16). Applies to every module and every calculation library.

Two commitments:
1. Every calculation library is parameter-based.
2. Every business rule is configurable, open and dynamic, so it can be changed to a tenant's specific rule without code.

## 1. What "configurable" means here (four tiers)

"Configure everything" has a limit: a rule setup that can express anything becomes a programming language, and then nobody can test or audit it. So the standard has four tiers.

| Tier | What it is | Who changes it | Example |
|---|---|---|---|
| T0 Invariants | Not configurable. Protect money, data and audit. | Nobody (platform release only) | Tenant isolation, maker-checker on money movement, append-only audit, reversals not deletes, balanced journals, decimal arithmetic, no stored-value wallet |
| T1 Parameters | Typed values with defaults | Tenant configurator, approver activates | Rates, fees, limits, days, thresholds, rounding mode, allocation order, approval bands |
| T2 Strategies | Named methods built into the libraries, selected by a parameter | Tenant configurator selects; a new strategy needs a library release available to all tenants | Diminishing / flat / add-on interest; ADB / minimum monthly balance; day-count basis |
| T3 Expressions (R2) | Conditions and formulas written in a restricted, side-effect-free expression language | Tenant configurator, approver activates | Eligibility conditions, fee formulas, approval conditions |

Rule of thumb: a tenant difference goes to T1 first, T2 if a method is missing, T3 if a condition is unusual. It never goes into code for one tenant.

Regulatory and security parameters carry a floor or ceiling set by the platform (for example maximum session timeout, minimum OTP policy). A tenant may tighten them but not loosen them past the platform limit. Changing a regulatory parameter (for example the capital holding cap) requires a reason and an approver.

## 2. Parameter precedence

Most specific wins, and every level is versioned with an effective date:

platform default → profile pack (segment) → tenant → product → (optional) member or account override

## 3. Governance of every change

1. Draft with effective-from date (FS Configuration Studio lifecycle).
2. Attach worked examples: normal, boundary, exception.
3. System runs the examples; any mismatch blocks submission.
4. Impact preview: system recomputes a sample of live accounts under the new version and shows what changes before activation.
5. Approver activates; earlier versions stay for historical transactions.
6. Rollback is a new version, never an edit.
7. Everything is audit-logged with before and after values.

## 4. Library contract (parameter-based)

Every calculation library (interest, amortization, penalty, allocation, fees, posting, eligibility, approval routing) must meet all of these:

| # | Rule |
|---|---|
| L1 | Pure function: result = f(input, params). No reading of environment variables, database, clock, tenant ID or customer name inside the library. The caller passes the date and the parameters in. |
| L2 | No business constant in code. Any value a business could reasonably change (rate, rounding mode, day count, divisor, cap, order) is a parameter with a documented default. |
| L3 | Parameters are validated against a published schema (type, range, allowed values) before the library runs; an invalid parameter set is rejected, never silently defaulted. |
| L4 | Deterministic and decimal-only: the same input and parameters always give the same result to the centavo. |
| L5 | Every result records library name, library version and the rule-version ID used, so any past figure can be reproduced. |
| L6 | One canonical implementation per calculation. If the Python batch jobs and the Next.js app both compute the same thing, the shared vectors in `docs/worked_examples/` must pass in both languages on every build. |
| L7 | Libraries carry no segment or tenant branches. Segment differences arrive as parameters or feature flags. |

CI enforcement:
- A lint check fails the build on numeric or string business literals inside calculation packages (allowed: 0, 1 and named constants documented as invariants).
- A grep check fails the build if a calculation package mentions a tenant ID, customer name or segment name.
- The vectors in `docs/worked_examples/starter.json` run against the libraries on every build.
- Property tests with random valid parameters: schedule principal sums to the loan amount, journal debits equal credits, allocation never exceeds the payment.

## 5. Parameter inventory

Parameters already named in the Functional Spec, plus the ones found hard-coded in the current drafts (marked NEW).

| Area | Parameters |
|---|---|
| Calculation conventions (NEW) | Rounding mode and precision for money and rates; installment rounding; last-installment adjustment on or off; rounding order (round gross then tax, or the reverse); day-count basis for loans and for savings (365, 360, actual); penalty day divisor (default 30) |
| Savings interest | Annual rate, balance method, posting frequency, minimum balance to earn, withholding tax %, dormancy months |
| Loan interest | Annual rate, method, compounding, day-count |
| Terms and amounts | Min and max term and amount, multiples of capital and savings |
| Release deductions | Service fee %, insurance rate, DST rule, CBU %, prior-loan payoff flag, advance interest flag |
| Penalty | Monthly rate, grace days, cap %, divisor |
| Allocation order | Ordered list for loan payments and for remittances |
| Eligibility | Minimum membership months, maximum past-due days, co-maker count and exposure limit, take-home-pay floor |
| Capital (NEW as parameters) | Maximum holding %, minimum paid-up, lock-in months, refund approval threshold |
| Membership (NEW) | Inactivity months to flag inactive, required documents by member type, PMES required yes or no |
| Status guards (NEW) | Conditions that must be true for each status transition; the status list itself stays fixed (T0) |
| Approval matrix | Amount bands to role sequence, by transaction type and product |
| Posting rules | Debit and credit accounts per event, per product |
| Numbering | Patterns for member, account, OR and voucher numbers |
| Security policy (NEW) | Session timeout, failed-login lockout count, OTP triggers, within platform floors and ceilings |
| Collections follow-up (NEW, S1) | Reminder days before and after due date, aging buckets, follow-up task rules |
| Notifications | Templates, triggers, channels, language |
| Fiscal and locale | Fiscal year start, currency, time zone, language defaults |
| Payroll deduction (S2) | File format code, cut-off day, remittance account, service-fee rule, match passes, shortfall policy |

## 6. Where the current drafts conflict with this standard

| Draft says | Change |
|---|---|
| Savings interest uses r/365 (FS Savings) | Divisor is the savings day-count basis parameter (default 365) |
| Penalty divides by 30 (FS Loans) | Penalty day divisor parameter (default 30) |
| Session timeout 15 minutes, 5 failed logins lock (FS Security) | Defaults of the security policy parameters, within platform limits |
| Capital cap "typically 10%" (FS Membership) | Maximum holding % parameter, regulatory flag |
| Rounding half-up everywhere (conventions C1 to C8) | Rounding mode, installment rounding, last-installment adjustment and rounding order are parameters; C1 to C8 are the defaults, not rules |

The worked-examples conventions C1 to C8 are therefore defaults. That removes the question of which rounding rule PARTNER-S1 uses from the design: it is set per tenant, and the vectors run with the defaults and with each alternative.

## 7. Open items

- Choose the expression language for T3 (R2). It must be restricted, sandboxed, free of side effects and resource-limited.
- Choose the canonical language for the calculation libraries (TypeScript or Python) and how the other language consumes them, to limit drift (L6).
