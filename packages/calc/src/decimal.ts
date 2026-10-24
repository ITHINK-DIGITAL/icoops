import Decimal from "decimal.js";
import {
  DECIMAL_STRING_PATTERN,
  ERROR_NOT_A_DECIMAL,
  ERROR_NOT_A_STRING,
  EXPONENT_LIMIT,
  WORKING_PRECISION,
} from "./invariants.js";

/**
 * The one Decimal class every calculation library uses. A clone, so that no other code in the
 * process can change its precision. Rounding is NOT fixed here: it is a parameter passed to each
 * operation by the caller (docs/08 L2).
 */
export const D = Decimal.clone({
  precision: WORKING_PRECISION,
  toExpNeg: -EXPONENT_LIMIT,
  toExpPos: EXPONENT_LIMIT,
});
export type Dec = InstanceType<typeof D>;

/** Parse a decimal from a string. Numbers are refused so that no float can enter a calculation. */
export function parseDecimal(value: string): Dec {
  if (typeof value !== "string") {
    throw new TypeError(ERROR_NOT_A_STRING);
  }
  if (!DECIMAL_STRING_PATTERN.test(value)) {
    throw new RangeError(ERROR_NOT_A_DECIMAL);
  }
  return new D(value);
}
