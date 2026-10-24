import type { Params } from "./types.js";

export type Segment = "s1_private" | "s2_government" | "s3_federation";

/**
 * Default feature flags per partner segment (docs/07 section E, D14): a segment changes only the
 * profile pack, the flags and the tenant hierarchy, never the code. These are starting values
 * applied when a tenant is created; the tenant's own flags then govern. S3 is set per member co-op.
 */
export const SEGMENT_DEFAULT_FEATURES: Readonly<
  Record<Segment, Readonly<Record<string, boolean>>>
> = {
  s1_private: { payroll_deduction: false },
  s2_government: { payroll_deduction: true },
  s3_federation: { payroll_deduction: false },
};

export function defaultFeatures(segment: Segment, overrides: Params = {}): Record<string, boolean> {
  const merged: Record<string, boolean> = { ...SEGMENT_DEFAULT_FEATURES[segment] };
  for (const [key, value] of Object.entries(overrides)) {
    if (typeof value !== "boolean") {
      throw new TypeError(`feature flag ${key} must be true or false`);
    }
    merged[key] = value;
  }
  return merged;
}
