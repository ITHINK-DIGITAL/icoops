import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import {
  RuleError,
  RuleRegistry,
  calculationConventionsSchema,
  compareExpected,
  createDefaultRegistry,
  layersFromVersions,
  resolveParameters,
  runExamples,
  selectInForce,
  valuesEqual,
  versionsInForceByScope,
} from "../src/index.js";
import type { Example, RuleVersionLike } from "../src/index.js";

const starter = JSON.parse(
  readFileSync(
    fileURLToPath(new URL("../../../docs/worked_examples/starter.json", import.meta.url)),
    "utf8",
  ),
) as { parameter_defaults: Record<string, unknown> };

function version(overrides: Partial<RuleVersionLike> & { id: string }): RuleVersionLike {
  return {
    ruleType: "calculation_conventions",
    scope: "tenant",
    scopeRef: null,
    schemaVersion: 1,
    params: {},
    status: "active",
    effectiveFrom: "2026-01-01",
    ...overrides,
  };
}

describe("calculation conventions schema (L3)", () => {
  it("accepts the platform defaults published in starter.json", () => {
    expect(calculationConventionsSchema.safeParse(starter.parameter_defaults).success).toBe(true);
  });

  it("rejects a missing key rather than defaulting it", () => {
    const { penalty_day_divisor: _omitted, ...rest } = starter.parameter_defaults;
    expect(calculationConventionsSchema.safeParse(rest).success).toBe(false);
  });

  it("rejects unknown keys", () => {
    expect(
      calculationConventionsSchema.safeParse({ ...starter.parameter_defaults, vat_rate: "0.12" })
        .success,
    ).toBe(false);
  });

  it("rejects out-of-range and mistyped values", () => {
    const bad = [
      { rounding_mode: "banker" },
      { money_precision: 2.5 },
      { penalty_day_divisor: 0 },
      { savings_day_count_basis: 364 },
      { last_installment_adjust: "yes" },
    ];
    for (const patch of bad) {
      expect(
        calculationConventionsSchema.safeParse({ ...starter.parameter_defaults, ...patch }).success,
      ).toBe(false);
    }
  });

  it("accepts the alternative strategies the tenant may choose", () => {
    const alternative = {
      ...starter.parameter_defaults,
      rounding_mode: "half_even",
      rounding_order: "round_net",
      loan_day_count: "actual/365",
      savings_day_count_basis: "actual",
    };
    expect(calculationConventionsSchema.safeParse(alternative).success).toBe(true);
  });
});

describe("registry", () => {
  it("validates and returns parameters", () => {
    const registry = createDefaultRegistry();
    expect(registry.validate("calculation_conventions", 1, starter.parameter_defaults)).toEqual(
      starter.parameter_defaults,
    );
  });

  it("explains every problem with invalid parameters", () => {
    const registry = createDefaultRegistry();
    try {
      registry.validate("calculation_conventions", 1, { rounding_mode: "banker" });
      expect.unreachable();
    } catch (error) {
      expect(error).toBeInstanceOf(RuleError);
      expect((error as RuleError).code).toBe("invalid_params");
      expect((error as RuleError).issues.some((issue) => issue.startsWith("rounding_mode"))).toBe(
        true,
      );
      expect((error as RuleError).issues.length).toBeGreaterThan(1);
    }
  });

  it("refuses unknown types and schema versions", () => {
    const registry = createDefaultRegistry();
    expect(() => registry.validate("nope", 1, {})).toThrow(/unknown rule type/);
    expect(() =>
      registry.validate("calculation_conventions", 2, starter.parameter_defaults),
    ).toThrow(/schema version/);
  });

  it("refuses duplicate registration", () => {
    expect(() =>
      createDefaultRegistry().register({
        ruleType: "calculation_conventions",
        schemaVersion: 1,
        schema: calculationConventionsSchema,
      }),
    ).toThrow(/already registered/);
  });
});

describe("version in force on a date (PL-011)", () => {
  const v1 = version({ id: "v1", effectiveFrom: "2026-01-01", params: { n: "1" } });
  const v2 = version({ id: "v2", effectiveFrom: "2026-07-01", params: { n: "2" } });

  it("returns nothing before the first effective date", () => {
    expect(selectInForce([v1, v2], "2025-12-31")).toBeNull();
  });

  it("switches exactly on the effective date", () => {
    expect(selectInForce([v1, v2], "2026-01-01")?.id).toBe("v1");
    expect(selectInForce([v1, v2], "2026-06-30")?.id).toBe("v1");
    expect(selectInForce([v1, v2], "2026-07-01")?.id).toBe("v2");
  });

  it("gives a back-dated posting the old version (AT-10)", () => {
    expect(selectInForce([v1, v2], "2026-03-15")?.params).toEqual({ n: "1" });
  });

  it("ignores versions that are not active", () => {
    const draft = version({ id: "d", effectiveFrom: "2026-02-01", status: "draft" });
    const submitted = version({ id: "s", effectiveFrom: "2026-02-01", status: "submitted" });
    expect(selectInForce([v1, draft, submitted], "2026-03-01")?.id).toBe("v1");
  });

  it("does not depend on the order of the input", () => {
    expect(selectInForce([v2, v1], "2026-08-01")?.id).toBe("v2");
  });

  it("refuses ambiguity and malformed dates", () => {
    expect(() =>
      selectInForce([v1, version({ id: "twin", effectiveFrom: "2026-01-01" })], "2026-02-01"),
    ).toThrow(/share/);
    expect(() => selectInForce([v1], "01/02/2026")).toThrow(RuleError);
    expect(() =>
      selectInForce([version({ id: "x", effectiveFrom: "soon" })], "2026-02-01"),
    ).toThrow(RuleError);
  });
});

describe("precedence (PL-025)", () => {
  const layers = [
    { scope: "account" as const, versionId: "a1", params: { rate: "0.10" } },
    {
      scope: "platform" as const,
      versionId: "p1",
      params: { rate: "0.12", grace: "5", cap: "0.10" },
    },
    { scope: "tenant" as const, versionId: "t1", params: { grace: "7" } },
    { scope: "product" as const, versionId: "pr1", params: { cap: "0.08" } },
  ];

  it("lets the most specific layer win, key by key", () => {
    expect(resolveParameters(layers).params).toEqual({ rate: "0.10", grace: "7", cap: "0.08" });
  });

  it("records which version supplied each key", () => {
    expect(resolveParameters(layers).provenance).toEqual({
      rate: { scope: "account", versionId: "a1" },
      grace: { scope: "tenant", versionId: "t1" },
      cap: { scope: "product", versionId: "pr1" },
    });
  });

  it("gives the same answer whatever the order of the layers", () => {
    const expected = resolveParameters(layers);
    const permutations = [
      [3, 2, 1, 0],
      [1, 3, 0, 2],
      [2, 0, 3, 1],
      [0, 1, 2, 3],
    ];
    for (const order of permutations) {
      expect(resolveParameters(order.map((i) => layers[i]!))).toEqual(expected);
    }
  });

  it("replaces nested values whole instead of merging them", () => {
    const resolved = resolveParameters([
      { scope: "platform", versionId: "p", params: { order: { first: "loan", second: "cbu" } } },
      { scope: "tenant", versionId: "t", params: { order: { first: "cbu" } } },
    ]);
    expect(resolved.params).toEqual({ order: { first: "cbu" } });
  });

  it("refuses two layers for one scope", () => {
    expect(() => resolveParameters([layers[1]!, { ...layers[1]!, versionId: "other" }])).toThrow(
      /more than one layer/,
    );
  });

  it("builds layers from the versions in force for a date and context", () => {
    const versions: RuleVersionLike[] = [
      version({
        id: "p-old",
        scope: "platform",
        effectiveFrom: "2026-01-01",
        params: { x: "1", y: "1" },
      }),
      version({
        id: "p-new",
        scope: "platform",
        effectiveFrom: "2026-06-01",
        params: { x: "2", y: "2" },
      }),
      version({
        id: "pack",
        scope: "pack",
        scopeRef: "private",
        effectiveFrom: "2026-01-01",
        params: { y: "3" },
      }),
      version({
        id: "other-pack",
        scope: "pack",
        scopeRef: "government",
        effectiveFrom: "2026-01-01",
        params: { y: "9" },
      }),
      version({
        id: "prod",
        scope: "product",
        scopeRef: "regular",
        effectiveFrom: "2026-09-01",
        params: { z: "1" },
      }),
    ];
    const picked = versionsInForceByScope(versions, "calculation_conventions", "2026-07-01", {
      pack: "private",
      product: "regular",
    });
    expect(picked.map((v) => v.id)).toEqual(["p-new", "pack"]); // product version starts later; other pack ignored
    expect(resolveParameters(layersFromVersions(picked)).params).toEqual({ x: "2", y: "3" });
    const early = versionsInForceByScope(versions, "calculation_conventions", "2026-02-01", {
      pack: "private",
    });
    expect(resolveParameters(layersFromVersions(early)).params).toEqual({ x: "1", y: "3" });
  });
});

describe("worked-example runner", () => {
  const example = (id: string, expected: Record<string, unknown>): Example => ({
    id,
    code: id,
    kind: "normal",
    inputs: { a: "2", b: "3" },
    expected,
  });
  const registry = new RuleRegistry().register({
    ruleType: "adder",
    schemaVersion: 1,
    schema: calculationConventionsSchema,
    handler: (inputs) => ({
      sum: "5.00",
      rows: [
        ["1", "2.50"],
        ["2", "2.50"],
      ],
      echo: String(inputs.a),
    }),
  });

  it("passes when every expected output matches by value", () => {
    const [result] = runExamples({
      registry,
      ruleType: "adder",
      params: {},
      examples: [
        example("ok", {
          sum: "5",
          rows: [
            ["1", "2.5"],
            ["2", "2.50"],
          ],
        }),
      ],
    });
    expect(result?.passed).toBe(true);
    expect(result?.diff).toBeNull();
  });

  it("reports the exact difference when an output is wrong", () => {
    const [result] = runExamples({
      registry,
      ruleType: "adder",
      params: {},
      examples: [example("bad", { sum: "5.01" })],
    });
    expect(result?.passed).toBe(false);
    expect(result?.diff).toEqual({ sum: { expected: "5.01", actual: "5.00" } });
  });

  it("fails an expected output the handler did not produce", () => {
    expect(compareExpected({ missing: "1" }, { other: "1" })).toEqual({
      missing: { expected: "1", actual: undefined },
    });
  });

  it("fails every example of a rule type that has no handler", () => {
    const empty = createDefaultRegistry();
    const results = runExamples({
      registry: empty,
      ruleType: "calculation_conventions",
      params: {},
      examples: [example("x", {}), example("y", { a: "1" })],
    });
    expect(results.every((r) => !r.passed)).toBe(true);
  });

  it("fails an example whose handler throws, without stopping the others", () => {
    const throwing = new RuleRegistry().register({
      ruleType: "boom",
      schemaVersion: 1,
      schema: calculationConventionsSchema,
      handler: (inputs) => {
        if (inputs.a === "2") {
          throw new Error("division by zero");
        }
        return { v: "1" };
      },
    });
    const ok: Example = {
      id: "ok",
      code: "ok",
      kind: "normal",
      inputs: { a: "9" },
      expected: { v: "1" },
    };
    const results = runExamples({
      registry: throwing,
      ruleType: "boom",
      params: {},
      examples: [example("boom", { v: "1" }), ok],
    });
    expect(results.map((r) => r.passed)).toEqual([false, true]);
    expect(results[0]?.diff?.error?.actual).toMatch(/division by zero/);
  });

  it("compares decimals by value but other strings exactly", () => {
    expect(valuesEqual("1000", "1000.00")).toBe(true);
    expect(valuesEqual("0.1", "0.10")).toBe(true);
    expect(valuesEqual("pass", "PASS")).toBe(false);
    expect(valuesEqual("1000", "1000.01")).toBe(false);
    expect(valuesEqual(["1", "2"], ["1", "2", "3"])).toBe(false);
  });
});

describe("segment default features (D14)", () => {
  it("turns payroll deduction on only where the segment collects through payroll", async () => {
    const { defaultFeatures } = await import("../src/index.js");
    expect(defaultFeatures("s1_private")).toEqual({ payroll_deduction: false });
    expect(defaultFeatures("s2_government")).toEqual({ payroll_deduction: true });
  });

  it("lets a tenant switch a flag without changing its segment (first tenant: S1 with payroll on)", async () => {
    const { defaultFeatures } = await import("../src/index.js");
    expect(defaultFeatures("s1_private", { payroll_deduction: true })).toEqual({
      payroll_deduction: true,
    });
  });

  it("refuses a non-boolean flag", async () => {
    const { defaultFeatures } = await import("../src/index.js");
    expect(() => defaultFeatures("s1_private", { payroll_deduction: "yes" })).toThrow(TypeError);
  });
});
