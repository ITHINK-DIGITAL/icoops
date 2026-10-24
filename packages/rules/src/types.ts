/** Parameter precedence, least to most specific (docs/08 section 2, PL-025). */
export const SCOPES = ["platform", "pack", "tenant", "product", "account"] as const;
export type Scope = (typeof SCOPES)[number];

export const SCOPE_RANK: Readonly<Record<Scope, number>> = {
  platform: 0,
  pack: 1,
  tenant: 2,
  product: 3,
  account: 4,
};

export type ConfigStatus = "draft" | "submitted" | "active" | "rejected" | "withdrawn" | "retired";

export type Params = Record<string, unknown>;

/** The fields of a rule_version row that the resolver needs. Dates are ISO yyyy-mm-dd strings. */
export interface RuleVersionLike {
  readonly id: string;
  readonly ruleType: string;
  readonly scope: Scope;
  readonly scopeRef: string | null;
  readonly schemaVersion: number;
  readonly params: Params;
  readonly status: ConfigStatus;
  readonly effectiveFrom: string;
}

export class RuleError extends Error {
  constructor(
    readonly code:
      | "unknown_rule_type"
      | "schema_version_mismatch"
      | "invalid_params"
      | "invalid_date"
      | "ambiguous_version"
      | "duplicate_scope",
    message: string,
    readonly issues: readonly string[] = [],
  ) {
    super(message);
    this.name = "RuleError";
  }
}
