import { describe, expect, it } from "vitest";
import { HANDLERS, checkStructure, loadStarter, runVectors } from "../src/index.js";
import type { StarterFile } from "../src/index.js";

const real = loadStarter();

function file(overrides: Partial<StarterFile> = {}): StarterFile {
  return {
    status: "test",
    conventions: {},
    parameter_defaults: real.parameter_defaults,
    vectors: [
      {
        id: "T-1",
        rule: "r",
        kind: "normal",
        inputs: { a: "2" },
        expected: { out: "4" },
        note: "",
        segment: "ALL",
      },
      {
        id: "T-2",
        rule: "r",
        kind: "boundary",
        inputs: { a: "0" },
        expected: { out: "0" },
        note: "",
        segment: "ALL",
      },
      {
        id: "T-3",
        rule: "r",
        kind: "exception",
        inputs: { a: "-1" },
        expected: { out: "-2", note: "negative" },
        note: "",
        segment: "ALL",
      },
    ],
    ...overrides,
  };
}

describe("starter.json as committed", () => {
  it("matches the vector schema and has no structural errors", () => {
    expect(real.vectors.length).toBeGreaterThan(0);
    expect(checkStructure(real).errors).toEqual([]);
  });

  it("has unique ids and its default parameters satisfy the published schema", () => {
    expect(new Set(real.vectors.map((v) => v.id)).size).toBe(real.vectors.length);
  });

  it("reports vectors as pending until slice 2 registers the calculations", () => {
    const report = runVectors(real, HANDLERS);
    expect(report.counts.pending).toBe(real.vectors.length);
    expect(report.counts.fail).toBe(0);
  });
});

describe("structural checks", () => {
  it("accepts a well-formed file", () => {
    expect(checkStructure(file())).toEqual({ errors: [], warnings: [] });
  });

  it("rejects duplicate ids", () => {
    const base = file();
    const dup = file({ vectors: [...base.vectors, base.vectors[0]!] });
    expect(checkStructure(dup).errors).toEqual(["duplicate vector id T-1"]);
  });

  it("rejects JSON floats anywhere in inputs or expected, but allows integers", () => {
    const base = file();
    const bad = file({
      vectors: [
        { ...base.vectors[0]!, inputs: { a: 0.1, nested: [{ b: 2 }] } },
        { ...base.vectors[1]!, expected: { out: { deep: 1.5 } } },
      ],
    });
    const errors = checkStructure(bad).errors;
    expect(errors).toHaveLength(2);
    expect(errors[0]).toMatch(/T-1\.inputs\.a is a JSON float/);
    expect(errors[1]).toMatch(/T-2\.expected\.out\.deep is a JSON float/);
  });

  it("rejects default parameters that break the published schema", () => {
    const bad = file({
      parameter_defaults: { ...real.parameter_defaults, rounding_mode: "banker" },
    });
    expect(checkStructure(bad).errors[0]).toMatch(/parameter_defaults do not satisfy/);
  });

  it("warns about rules that lack one of the three example kinds the gate needs", () => {
    const base = file();
    const thin = file({ vectors: [base.vectors[0]!] });
    expect(checkStructure(thin).warnings).toEqual([
      "r: no boundary or exception example (the activation gate needs all three)",
    ]);
  });
});

describe("vector runner", () => {
  const doubler = {
    r: (inputs: Record<string, unknown>) => ({ out: String(Number(inputs.a) * 2) }),
  };

  it("passes matching vectors, ignoring commentary keys in expected", () => {
    const report = runVectors(file(), doubler);
    expect(report.counts).toEqual({ pass: 3, fail: 0, pending: 0 });
  });

  it("fails a vector whose output differs and says how", () => {
    const report = runVectors(file(), { r: () => ({ out: "5" }) });
    expect(report.counts.fail).toBe(3);
    expect(report.results[0]?.detail).toContain('"expected":"4"');
  });

  it("counts a thrown error as a failure and a missing handler as pending", () => {
    const report = runVectors(file(), {
      r: () => {
        throw new Error("boom");
      },
    });
    expect(report.results.every((r) => r.status === "fail" && r.detail.includes("boom"))).toBe(
      true,
    );
    expect(runVectors(file(), {}).counts.pending).toBe(3);
  });
});
