import { ISO_DATE_PATTERN } from "./common.js";
import { RuleError, SCOPE_RANK, SCOPES } from "./types.js";
import type { RuleVersionLike, Scope } from "./types.js";

function assertDate(value: string): void {
  if (!ISO_DATE_PATTERN.test(value)) {
    throw new RuleError("invalid_date", `not an ISO date (yyyy-mm-dd): ${value}`);
  }
}

/**
 * The version in force on a date (PL-011): the active version with the latest effective_from that
 * is not after the date. Earlier versions stay for historical transactions, so a back-dated
 * posting passes its own transaction date and gets the old version.
 */
export function selectInForce<T extends RuleVersionLike>(
  versions: readonly T[],
  onDate: string,
): T | null {
  assertDate(onDate);
  let best: T | null = null;
  let tie = false;
  for (const version of versions) {
    assertDate(version.effectiveFrom);
    if (version.status !== "active" || version.effectiveFrom > onDate) {
      continue;
    }
    if (best === null || version.effectiveFrom > best.effectiveFrom) {
      best = version;
      tie = false;
    } else if (version.effectiveFrom === best.effectiveFrom) {
      tie = true;
    }
  }
  if (tie && best) {
    throw new RuleError(
      "ambiguous_version",
      `two active versions of ${best.ruleType} share ${best.effectiveFrom}`,
    );
  }
  return best;
}

/** References that pick the pack, product and account layers; platform and tenant need none. */
export interface ScopeContext {
  readonly pack?: string;
  readonly product?: string;
  readonly account?: string;
}

/** The version in force for each scope of a rule type, least specific first. */
export function versionsInForceByScope<T extends RuleVersionLike>(
  versions: readonly T[],
  ruleType: string,
  onDate: string,
  context: ScopeContext,
): T[] {
  const picked: T[] = [];
  for (const scope of [...SCOPES].sort((a, b) => SCOPE_RANK[a] - SCOPE_RANK[b])) {
    const ref = scopeRef(scope, context);
    if (ref === undefined) {
      continue; // no reference given for this scope: the layer does not apply
    }
    const candidates = versions.filter(
      (v) => v.ruleType === ruleType && v.scope === scope && (v.scopeRef ?? null) === ref,
    );
    const inForce = selectInForce(candidates, onDate);
    if (inForce) {
      picked.push(inForce);
    }
  }
  return picked;
}

function scopeRef(scope: Scope, context: ScopeContext): string | null | undefined {
  switch (scope) {
    case "platform":
    case "tenant":
      return null;
    case "pack":
      return context.pack;
    case "product":
      return context.product;
    case "account":
      return context.account;
  }
}
