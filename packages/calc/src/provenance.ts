import { LIBRARY_NAME, LIBRARY_VERSION } from "./invariants.js";

/** Every calculation result carries the library, its version and the rule version used (L5). */
export interface Provenance {
  readonly library: string;
  readonly libraryVersion: string;
  /** Id of the rule_version whose parameters produced the result (null in pure tests). */
  readonly ruleVersionId: string | null;
}

export interface Calculated<T> {
  readonly value: T;
  readonly provenance: Provenance;
}

export function withProvenance<T>(value: T, ruleVersionId: string | null): Calculated<T> {
  return {
    value,
    provenance: { library: LIBRARY_NAME, libraryVersion: LIBRARY_VERSION, ruleVersionId },
  };
}
