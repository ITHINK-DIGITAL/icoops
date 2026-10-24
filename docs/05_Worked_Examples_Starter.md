# Worked Examples — Starter Set (v0.1)

**Status: SYNTHETIC. Pending owner approval.** These reference vectors test the *calculation engine*. Every rate, fee and limit below is an illustrative placeholder, not a product rule, and nothing here is advice on DST, withholding tax or exemption status. PARTNER-S1's real product parameters will replace the inputs; the formulas and conventions are what these vectors lock down.

Machine-readable copy: [worked_examples/starter.json](worked_examples/starter.json). The rule tester (PL-012) should load it and fail the build on any mismatch.

## Conventions assumed (parameter defaults, per docs/08)

C1 to C8 are default values of configurable parameters, not fixed rules. Each tenant can set a different rounding mode, installment rounding, last-installment adjustment, rounding order, day-count basis or penalty divisor. The vectors below use the defaults; alternative parameter values need their own vectors.

| # | Convention | Why it matters |
|---|---|---|
| C1 | Money numeric(18,2), rates numeric(9,6), decimal arithmetic only, rounding half-up | NF-012 |
| C2 | Loan monthly rate i = annual rate / 12 (30/360 style), no compounding beyond the schedule | FS Loans |
| C3 | Diminishing: installment rounded half-up to 2 dp; each interest = balance x i rounded half-up; the last installment clears the remaining balance exactly | Rounding drift must land somewhere; last-installment adjustment is the common choice |
| C4 | Savings: daily end-of-day balances, interest = ADB x r / 365 x D; gross rounded first, then withholding tax rounded on the rounded gross | Order of rounding changes centavos |
| C5 | Penalty = past-due amount x monthly rate x (days late − grace) / 30, capped at a % of the past-due amount | FS Loans |
| C6 | Payment allocation default: penalty, then interest, then principal; any excess goes to savings unless the member chooses advance principal | LN-010 |
| C7 | Short remittance allocation order: loan, then CBU, then savings (benefit dues sit between loan and CBU when present) | PD-007 |
| C8 | Take-home-pay check passes when take-home after the new amortization is greater than or equal to the floor | LN-004, PD-004 |

Applicability: section 7 (remittance allocation) is in the R1 thin payroll slice and runs for tenants with the payroll_deduction flag ON (D19). Section 8 (take-home-pay floor) stays in R2. Sections 1 to 6 apply to every tenant in R1.

C3, C4 and C5 are business rules, not math; a different choice produces different centavos. Recommended defaults adopted by Jun on 23 Oct 2026 (D17, docs/09). PARTNER-S1's real ledgers will confirm or change the parameter values.

## 1. Loan interest — diminishing balance (LN-007)

Formula: A = P x i / (1 − (1+i)^−n).

**LN-DIM-01 (normal):** P = 100,000.00, r = 12.000000%, n = 12. Installment = **8,884.88**, total interest = **6,618.53**, last installment = **8,884.85**.

| k | Payment | Interest | Principal | Balance |
|---|---|---|---|---|
| 1 | 8,884.88 | 1,000.00 | 7,884.88 | 92,115.12 |
| 2 | 8,884.88 | 921.15 | 7,963.73 | 84,151.39 |
| 3 | 8,884.88 | 841.51 | 8,043.37 | 76,108.02 |
| 4 | 8,884.88 | 761.08 | 8,123.80 | 67,984.22 |
| 5 | 8,884.88 | 679.84 | 8,205.04 | 59,779.18 |
| 6 | 8,884.88 | 597.79 | 8,287.09 | 51,492.09 |
| 7 | 8,884.88 | 514.92 | 8,369.96 | 43,122.13 |
| 8 | 8,884.88 | 431.22 | 8,453.66 | 34,668.47 |
| 9 | 8,884.88 | 346.68 | 8,538.20 | 26,130.27 |
| 10 | 8,884.88 | 261.30 | 8,623.58 | 17,506.69 |
| 11 | 8,884.88 | 175.07 | 8,709.81 | 8,796.88 |
| 12 | 8,884.85 | 87.97 | 8,796.88 | 0.00 |

**LN-DIM-02 (boundary):** n = 1 → installment 101,000.00, interest 1,000.00.

**LN-DIM-03 (exception):** zero rate, P = 12,000.00, n = 12 → installment 1,000.00, total interest 0.00.

## 2. Loan interest — flat / add-on and advance interest

Flat: I = P x r x n / 12; A = (P + I) / n. Advance (discounted): I is deducted from proceeds; A = P / n.

| ID | Kind | Inputs | Expected |
|---|---|---|---|
| LN-FLAT-01 | normal | principal=50000.00; annual_rate=0.120000; term_months=10 | total_interest=5,000.00; installment=5,500.00 |
| LN-FLAT-02 | boundary | principal=50000.00; annual_rate=0.120000; term_months=1 | total_interest=500.00; installment=50,500.00 |
| LN-FLAT-03 | exception | principal=10000.00; annual_rate=0.115000; term_months=7 | total_interest=670.83; installment=1,524.40 |
| LN-DISC-01 | normal | principal=60000.00; annual_rate=0.120000; term_months=6 | advance_interest=3,600.00; installment=10,000.00; net_before_other_deductions=56,400.00 |

LN-FLAT-03 note: 10,000.00 at 11.5% for 7 months gives I = 670.83 and A = 1,524.40; 7 x 1,524.40 = 10,670.80, so the last installment must adjust by the rounding difference (rule C3 applied to flat loans).

## 3. Release deductions and GL balance (LN-007, AC-002)

Inputs (placeholders): P = 100,000.00; service fee 2.0%; insurance 0.5%; DST 0.00 (pending the co-op's tax adviser); CBU retention 2.0%; prior-loan payoff 10,000.00.

| Item | Amount |
|---|---|
| Principal (debit Loans receivable) | 100,000.00 |
| Service fee | 2,000.00 |
| Insurance | 500.00 |
| DST | 0.00 |
| CBU retention | 2,000.00 |
| Prior-loan payoff | 10,000.00 |
| **Net proceeds (credit Cash/Bank)** | 85,500.00 |

GL check: debit 100,000.00 = credits 100,000.00 (cash 85,500.00 + fee income 2,000.00 + insurance payable 500.00 + DST payable 0.00 + share capital 2,000.00 + loans receivable payoff 10,000.00). Entry must balance to the centavo.

## 4. Savings interest (SV-003)

Balances: days 1–10 at 10,000.00, days 11–20 at 15,000.00, days 21–30 at 5,000.00. r = 3.000000%, D = 30, withholding 20% (placeholder).

| ID | Kind | Expected |
|---|---|---|
| SV-ADB-01 | normal | adb=10000.00; gross_interest=24.66; withholding=4.93; net_interest=19.73 |
| SV-MMB-01 | normal | min_balance=5000; gross_interest=12.33; withholding=2.47; net_interest=9.86 |
| SV-ADB-02 | boundary | adb=10000.00; gross_interest=24.66; note=ADB equals minimum: earns |
| SV-ADB-03 | exception | gross_interest=0.00; withholding=0.00; net_interest=0.00 |

SV-ADB-02/03 inputs: minimum balance to earn 10,000.00; ADB exactly at the minimum earns, one centavo below earns nothing.

## 5. Penalty (LN-011)

Past due 8,884.88, monthly rate 3%, grace 5 days, cap 10% of past-due (888.49).

| ID | Kind | Days late | Expected |
|---|---|---|---|
| LN-PEN-01 | normal | 45 | days_beyond_grace=40; uncapped=355.40; cap=888.49; penalty=355.40 |
| LN-PEN-02 | boundary | 5 | days_beyond_grace=0; uncapped=0.00; cap=888.49; penalty=0.00 |
| LN-PEN-03 | exception | 400 | days_beyond_grace=395; uncapped=3509.53; cap=888.49; penalty=888.49 |

## 6. Payment allocation (LN-010)

Due: penalty 355.40, interest 1,000.00, principal 7,884.88.

| ID | Kind | Payment | Expected |
|---|---|---|---|
| LN-ALLOC-01 | normal | 5000.00 | penalty=355.40; interest=1000; principal=3644.60; excess=0.00 |
| LN-ALLOC-02 | exception | 10000.00 | penalty=355.40; interest=1000; principal=7884.88; excess=759.72; note=excess to savings unless member chooses advance principal |
| LN-ALLOC-03 | boundary | 300.00 | penalty=300; interest=0; principal=0; excess=0 |

## 7. Remittance allocation (PD-006, PD-007)

Expected deductions for one member: loan 3,000.00, CBU 500.00, savings 500.00 (total 4,000.00). Order: loan, CBU, savings.

| ID | Kind | Received | Expected |
|---|---|---|---|
| PD-REM-01 | normal | 4000.00 | loan=3000; cbu=500; savings=500; shortfall=0; excess=0 |
| PD-REM-02 | boundary | 3200.00 | loan=3000; cbu=200; savings=0; shortfall=800; excess=0 |
| PD-REM-03 | exception | 0.00 (zero-pay) | loan=0; cbu=0; savings=0; shortfall=4000; excess=0 |
| PD-REM-04 | exception | 4150.00 (excess) | loan=3000; cbu=500; savings=500; shortfall=0; excess=150 |

## 8. Take-home-pay floor (LN-004, PD-004)

Take-home before the new amortization 14,000.00; floor 5,000.00 (placeholder).

| ID | Kind | New amortization | Expected |
|---|---|---|---|
| PD-NTHP-01 | normal | 8884.88 | take_home_after=5115.12; result=pass |
| PD-NTHP-02 | boundary | 9000.00 | take_home_after=5000.00; result=pass |
| PD-NTHP-03 | exception | 9000.01 | take_home_after=4999.99; result=fail |

## Not covered yet

- Dividend on share capital and patronage refund (DV-002, DV-003): R2; method and rates depend on the by-laws and PARTNER-S1's approved practice.
- Time-deposit pre-termination, restructuring and renewal rules (LN-012): need product parameters.
- Net surplus allocation percentages: by-laws.

## Approval

| Item | Owner | Status |
|---|---|---|
| Conventions C1–C8 | Jun / PARTNER-S1 finance | Approved by Jun as owner (D17, D18); first S1 customer validates in parallel run |
| Vector inputs replaced with the first S1 customer's parameters | First S1 customer | Pending |
| Vectors independently recomputed (spreadsheet or PARTNER-S1 accountant) | independent accountant or first S1 customer | Pending |
