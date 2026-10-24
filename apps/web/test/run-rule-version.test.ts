import { describe, expect, it, vi } from "vitest";
import type { Db } from "@icoops/db";
import { RuleRegistry, calculationConventionsSchema } from "@icoops/rules";
import { runRuleVersion } from "../src/lib/run-rule-version";

const TENANT = "tenant-a";
const VALID_PARAMS = {
  rounding_mode: "half_up",
  money_precision: 2,
  rate_precision: 6,
  installment_rounding: "half_up",
  last_installment_adjust: true,
  rounding_order: "round_gross_then_tax",
  loan_day_count: "30/360",
  savings_day_count_basis: 365,
  penalty_day_divisor: 30,
};

interface Fixture {
  can?: boolean;
  version?: Record<string, unknown> | null;
  examples?: Record<string, unknown>[];
  tenant?: { id: string } | null;
}

/** A tiny stand-in for the two Supabase clients: only the calls the runner makes. */
function fakes(fixture: Fixture) {
  const recorded: Record<string, unknown>[] = [];
  const user = {
    rpc: vi.fn(async (fn: string) => ({
      data: fn === "current_user_can" ? (fixture.can ?? true) : null,
      error: null,
    })),
    from: (table: string) => ({
      select: () => ({
        maybeSingle: async () => ({
          data:
            table === "tenant"
              ? fixture.tenant === undefined
                ? { id: TENANT }
                : fixture.tenant
              : null,
        }),
        eq: () => ({ maybeSingle: async () => ({ data: fixture.version ?? null }) }),
      }),
    }),
  } as unknown as Db;
  const service = {
    rpc: vi.fn(async (_fn: string, args: Record<string, unknown>) => {
      recorded.push(args);
      return { data: null, error: null };
    }),
    from: () => ({
      select: () => ({
        eq: () => ({ eq: async () => ({ data: fixture.examples ?? [], error: null }) }),
      }),
    }),
  } as unknown as Db;
  return { user, service, recorded };
}

const version = (over: Record<string, unknown> = {}) => ({
  id: "rv1",
  tenant_id: TENANT,
  rule_type: "adder",
  schema_version: 1,
  params: VALID_PARAMS,
  params_hash: "hash-1",
  status: "draft",
  ...over,
});
const example = (id: string, expected: Record<string, unknown>) => ({
  id,
  code: id,
  kind: "normal",
  inputs: { a: "2" },
  expected,
});
const registryWith = (handler?: (i: Record<string, unknown>) => Record<string, unknown>) =>
  new RuleRegistry().register({
    ruleType: "adder",
    schemaVersion: 1,
    schema: calculationConventionsSchema,
    handler,
  });

describe("runRuleVersion", () => {
  it("runs the examples and records each result against the version's parameter hash", async () => {
    const { user, service, recorded } = fakes({
      version: version(),
      examples: [example("e1", { out: "4" }), example("e2", { out: "5" })],
    });
    const outcome = await runRuleVersion(
      { user, service, registry: registryWith((i) => ({ out: String(Number(i.a) * 2) })) },
      "rv1",
    );
    expect(outcome).toMatchObject({ ok: true, total: 2, passed: 1 });
    expect(recorded).toHaveLength(2);
    expect(recorded[0]).toMatchObject({
      p_example_id: "e1",
      p_passed: true,
      p_params_hash: "hash-1",
      p_library: "@icoops/calc@0.0.0",
    });
    expect(recorded[1]).toMatchObject({ p_example_id: "e2", p_passed: false });
  });

  it("records every example as failed when the rule type has no calculation yet", async () => {
    const { user, service, recorded } = fakes({
      version: version(),
      examples: [example("e1", { out: "4" })],
    });
    const outcome = await runRuleVersion({ user, service, registry: registryWith() }, "rv1");
    expect(outcome).toMatchObject({ ok: true, passed: 0 });
    expect(recorded.every((r) => r.p_passed === false)).toBe(true);
  });

  it("refuses a caller without product_rule_config:create and records nothing", async () => {
    const { user, service, recorded } = fakes({ can: false, version: version() });
    expect(await runRuleVersion({ user, service, registry: registryWith() }, "rv1")).toMatchObject({
      ok: false,
      status: 403,
    });
    expect(recorded).toHaveLength(0);
  });

  it("does not run another tenant's or the platform's version", async () => {
    const { user, service, recorded } = fakes({ version: version({ tenant_id: "platform" }) });
    expect(await runRuleVersion({ user, service, registry: registryWith() }, "rv1")).toMatchObject({
      ok: false,
      status: 404,
    });
    expect(recorded).toHaveLength(0);
  });

  it("returns 404 for a version the user cannot see", async () => {
    const { user, service } = fakes({ version: null });
    expect(await runRuleVersion({ user, service, registry: registryWith() }, "nope")).toMatchObject(
      { ok: false, status: 404 },
    );
  });

  it("runs drafts only", async () => {
    const { user, service } = fakes({ version: version({ status: "submitted" }) });
    expect(await runRuleVersion({ user, service, registry: registryWith() }, "rv1")).toMatchObject({
      ok: false,
      status: 409,
    });
  });

  it("rejects invalid parameters and unknown rule types without recording", async () => {
    const bad = fakes({ version: version({ params: { rounding_mode: "banker" } }) });
    const invalid = await runRuleVersion(
      { user: bad.user, service: bad.service, registry: registryWith() },
      "rv1",
    );
    expect(invalid).toMatchObject({ ok: false, status: 422 });
    const unknown = fakes({ version: version({ rule_type: "mystery" }) });
    expect(
      await runRuleVersion(
        { user: unknown.user, service: unknown.service, registry: registryWith() },
        "rv1",
      ),
    ).toMatchObject({ ok: false, status: 422 });
    expect(bad.recorded).toHaveLength(0);
    expect(unknown.recorded).toHaveLength(0);
  });
});
