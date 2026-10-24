import { LIBRARY_NAME, LIBRARY_VERSION } from "@icoops/calc";
import { currentUserCan, recordWorkedExampleResult } from "@icoops/db";
import type { Db } from "@icoops/db";
import { RuleError, runExamples } from "@icoops/rules";
import type { Example, ExampleResult, RuleRegistry } from "@icoops/rules";

export interface RunDeps {
  /** The caller's own session: every read here runs under their row-level security. */
  readonly user: Db;
  /** Service key: the only writer of worked-example results. Server-side only. */
  readonly service: Db;
  readonly registry: RuleRegistry;
}

export type RunOutcome =
  | {
      readonly ok: true;
      readonly total: number;
      readonly passed: number;
      readonly results: readonly ExampleResult[];
    }
  | {
      readonly ok: false;
      readonly status: 403 | 404 | 409 | 422 | 500;
      readonly message: string;
      readonly issues?: readonly string[];
    };

interface RuleVersionRow {
  id: string;
  tenant_id: string;
  rule_type: string;
  schema_version: number;
  params: Record<string, unknown>;
  params_hash: string;
  status: string;
}

/**
 * Runs the worked examples of a draft rule version and records the results (PL-012). The calling
 * user needs product_rule_config:create; the results are written with the service key because no
 * user may mark an example as passed. A run is recorded against the version's current parameter
 * hash, so changing the parameters afterwards invalidates it. The database refuses activation
 * unless every example has a passing run for the exact parameters (the gate in migration 0006).
 */
export async function runRuleVersion(deps: RunDeps, ruleVersionId: string): Promise<RunOutcome> {
  const { user, service, registry } = deps;

  if (!(await currentUserCan(user, "product_rule_config", "create"))) {
    return { ok: false, status: 403, message: "You are not allowed to run rule examples." };
  }
  const { data: tenant } = await user.from("tenant").select("id").maybeSingle();
  const { data: version } = await user
    .from("rule_version")
    .select("id, tenant_id, rule_type, schema_version, params, params_hash, status")
    .eq("id", ruleVersionId)
    .maybeSingle<RuleVersionRow>();
  // Row-level security also shows platform defaults; those are released by migration, never run here.
  if (!tenant || !version || version.tenant_id !== tenant.id) {
    return { ok: false, status: 404, message: "Rule version not found." };
  }
  if (version.status !== "draft") {
    return {
      ok: false,
      status: 409,
      message: `Only a draft can be run; this version is ${version.status}.`,
    };
  }

  try {
    registry.validate(version.rule_type, version.schema_version, version.params);
  } catch (error) {
    if (error instanceof RuleError) {
      return { ok: false, status: 422, message: error.message, issues: error.issues };
    }
    throw error;
  }

  const { data: rows, error } = await service
    .from("worked_example")
    .select("id, code, kind, inputs, expected")
    .eq("rule_version_id", version.id)
    .eq("tenant_id", version.tenant_id);
  if (error || !rows) {
    return { ok: false, status: 500, message: "Could not read the worked examples." };
  }
  const examples = rows as Example[];
  const results = runExamples({
    registry,
    ruleType: version.rule_type,
    params: version.params,
    examples,
  });

  const library = `${LIBRARY_NAME}@${LIBRARY_VERSION}`;
  for (const result of results) {
    await recordWorkedExampleResult(service, {
      exampleId: result.id,
      passed: result.passed,
      actual: result.actual,
      diff: result.diff,
      paramsHash: version.params_hash,
      library,
    });
  }
  return {
    ok: true,
    total: results.length,
    passed: results.filter((r) => r.passed).length,
    results,
  };
}
