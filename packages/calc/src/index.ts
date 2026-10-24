// Calculation libraries (docs/08 L1 to L7). Slice 1 ships only the guardrails: the decimal class,
// the result envelope and the lint rules that keep business literals out. The formulas (loan,
// savings, penalty, allocation, disclosure) arrive in slice 2, each as a pure function of
// (input, params) that returns a Calculated<T>.
export { D, parseDecimal } from "./decimal.js";
export type { Dec } from "./decimal.js";
export { withProvenance } from "./provenance.js";
export type { Calculated, Provenance } from "./provenance.js";
export { LIBRARY_NAME, LIBRARY_VERSION } from "./invariants.js";
