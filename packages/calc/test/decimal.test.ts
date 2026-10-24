import { describe, expect, it } from "vitest";
import { D, LIBRARY_NAME, LIBRARY_VERSION, parseDecimal, withProvenance } from "../src/index.js";

describe("decimal arithmetic", () => {
  it("is exact where floats are not", () => {
    expect(0.1 + 0.2).not.toBe(0.3); // the problem being avoided
    expect(parseDecimal("0.1").plus(parseDecimal("0.2")).toString()).toBe("0.3");
  });

  it("keeps its own precision, independent of the global Decimal class", () => {
    const sum = parseDecimal("99999999999999999999999999999999").plus(parseDecimal("0.01"));
    expect(sum.toString()).toBe("99999999999999999999999999999999.01");
  });

  it("rounds only when asked, with the rounding mode supplied by the caller", () => {
    const x = parseDecimal("2.345");
    expect(x.toDecimalPlaces(2, D.ROUND_HALF_UP).toString()).toBe("2.35");
    expect(x.toDecimalPlaces(2, D.ROUND_HALF_EVEN).toString()).toBe("2.34");
    expect(x.toDecimalPlaces(2, D.ROUND_DOWN).toString()).toBe("2.34");
  });

  it("prints plain notation for very large and very small values", () => {
    expect(parseDecimal("1000000000000000000000000").toString()).toBe("1000000000000000000000000");
    expect(parseDecimal("0.0000001").toString()).toBe("0.0000001");
  });

  it("refuses numbers so that no float can enter a calculation", () => {
    expect(() => parseDecimal(0.1 as unknown as string)).toThrow(TypeError);
  });

  it("refuses malformed strings", () => {
    for (const bad of ["", "1,000.00", "1e5", " 1", "1.", ".5", "0x10", "NaN", "Infinity", "--1"]) {
      expect(() => parseDecimal(bad)).toThrow(RangeError);
    }
  });

  it("accepts plain signed decimals", () => {
    for (const ok of ["0", "-0.01", "100000.00", "0.000001"]) {
      expect(parseDecimal(ok).toString()).toBe(new D(ok).toString());
    }
  });
});

describe("provenance envelope (L5)", () => {
  it("records library, version and rule version", () => {
    const result = withProvenance("x", "rv-1");
    expect(result.provenance).toEqual({
      library: LIBRARY_NAME,
      libraryVersion: LIBRARY_VERSION,
      ruleVersionId: "rv-1",
    });
    expect(withProvenance("x", null).provenance.ruleVersionId).toBeNull();
  });
});
