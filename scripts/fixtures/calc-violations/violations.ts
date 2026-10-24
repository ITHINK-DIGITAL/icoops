// Deliberate violations: the self-test of scripts/check-calc-literals.mjs must catch every one.
// This directory is a fixture, outside packages/calc, and is excluded from every other check.
export const a = "tenant";
export const b = "s1_private";
export const c = "private co-op profile";
export const d = "PNP";
export const e = "partner";
export const f = "123e4567-e89b-12d3-a456-426614174000";
export const g = process.env.X;
export const h = parseFloat("1.5");
