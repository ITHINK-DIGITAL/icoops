import { z } from "zod";

/** Decimal values travel as strings, never JSON numbers (NF-012). Money is numeric(18,2). */
export const moneyString = z
  .string()
  .regex(/^-?\d{1,16}(\.\d{1,2})?$/, "money: at most 16 integer and 2 decimal digits");

/** Rates are numeric(9,6): at most 3 integer and 6 decimal digits. */
export const rateString = z
  .string()
  .regex(/^-?\d{1,3}(\.\d{1,6})?$/, "rate: at most 3 integer and 6 decimal digits");

export const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "date: yyyy-mm-dd");

export const ISO_DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
