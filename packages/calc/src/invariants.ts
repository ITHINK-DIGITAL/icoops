// T0 invariants (docs/08): constants that protect money, data and audit. They are NOT business
// rules and are never configurable per customer. This is the only file in packages/calc allowed to
// hold literals; it is listed in CODEOWNERS, so every change needs the product owner's review.

/** Working precision (significant digits) of the decimal library; far above numeric(18,2). */
export const WORKING_PRECISION = 40;

/** Exponent limits: values print in plain notation, never as 1e+31 or 1e-7, when serialised. */
export const EXPONENT_LIMIT = 40;

/** Identity recorded with every result so any past figure can be reproduced (L5). */
export const LIBRARY_NAME = "@icoops/calc";
export const LIBRARY_VERSION = "0.0.0";

/** Pattern for a decimal given as a string: JSON numbers are never accepted (NF-012, L4). */
export const DECIMAL_STRING_PATTERN = /^-?(0|[1-9][0-9]*)(\.[0-9]+)?$/;

export const ERROR_NOT_A_STRING = "decimal values must be given as strings, never as numbers";
export const ERROR_NOT_A_DECIMAL = "not a valid decimal string";
