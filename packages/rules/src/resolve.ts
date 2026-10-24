import { RuleError, SCOPE_RANK } from "./types.js";
import type { Params, RuleVersionLike, Scope } from "./types.js";

export interface ParameterLayer {
  readonly scope: Scope;
  readonly versionId: string;
  readonly params: Params;
}

export interface ResolvedParameters {
  readonly params: Params;
  /** Which scope and rule version supplied each top-level key, for audit and reproduction (L5). */
  readonly provenance: Readonly<
    Record<string, { readonly scope: Scope; readonly versionId: string }>
  >;
}

/**
 * Precedence resolver (PL-025): platform default, profile pack, tenant, product, then member or
 * account override; the most specific layer wins, key by key. Values are replaced as a whole:
 * a nested object in a more specific layer replaces the less specific one rather than merging.
 */
export function resolveParameters(layers: readonly ParameterLayer[]): ResolvedParameters {
  const seen = new Set<Scope>();
  for (const layer of layers) {
    if (seen.has(layer.scope)) {
      throw new RuleError("duplicate_scope", `more than one layer for scope ${layer.scope}`);
    }
    seen.add(layer.scope);
  }
  const ordered = [...layers].sort((a, b) => SCOPE_RANK[a.scope] - SCOPE_RANK[b.scope]);
  const params: Params = {};
  const provenance: Record<string, { scope: Scope; versionId: string }> = {};
  for (const layer of ordered) {
    for (const [key, value] of Object.entries(layer.params)) {
      params[key] = value;
      provenance[key] = { scope: layer.scope, versionId: layer.versionId };
    }
  }
  return { params, provenance };
}

export function layersFromVersions(versions: readonly RuleVersionLike[]): ParameterLayer[] {
  return versions.map((v) => ({ scope: v.scope, versionId: v.id, params: v.params }));
}
