import { z } from "zod";

/**
 * Calculation conventions C1 to C8 as parameters (docs/08 section 5, first row; docs/05).
 * The values in docs/worked_examples/starter.json "parameter_defaults" are the platform defaults:
 * they are data held in a platform rule version, not constants in code.
 *
 * Every field is required and unknown keys are rejected: an incomplete or unexpected parameter
 * set is an error, never silently defaulted (docs/08 L3).
 */
export const roundingMode = z.enum(["half_up", "half_even", "down", "up", "ceiling", "floor"]);

export const calculationConventionsSchema = z
  .object({
    rounding_mode: roundingMode,
    money_precision: z.number().int().min(0).max(4),
    rate_precision: z.number().int().min(0).max(9),
    installment_rounding: roundingMode,
    last_installment_adjust: z.boolean(),
    rounding_order: z.enum(["round_gross_then_tax", "round_net"]),
    loan_day_count: z.enum(["30/360", "actual/365", "actual/360"]),
    savings_day_count_basis: z.union([z.literal(360), z.literal(365), z.literal("actual")]),
    penalty_day_divisor: z.number().int().min(1).max(366),
  })
  .strict();

export type CalculationConventions = z.infer<typeof calculationConventionsSchema>;

export const CALCULATION_CONVENTIONS_TYPE = "calculation_conventions";
