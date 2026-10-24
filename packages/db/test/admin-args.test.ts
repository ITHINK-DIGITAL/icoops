import { describe, expect, it } from "vitest";
import { parseCreateTenantArgs } from "../src/admin-args.js";

const base = ["--code", "first-coop", "--name", "First Co-op", "--segment", "s1_private"];

describe("create-tenant arguments", () => {
  it("parses the required arguments", () => {
    expect(parseCreateTenantArgs(base)).toMatchObject({
      code: "first-coop",
      segment: "s1_private",
      sandbox: false,
      features: {},
    });
  });

  it("parses flags, features and the first administrator", () => {
    const parsed = parseCreateTenantArgs([
      ...base,
      "--sandbox",
      "--features",
      '{"payroll_deduction":true}',
      "--admin-email",
      "admin@example.test",
      "--admin-name",
      "Admin",
    ]);
    expect(parsed.sandbox).toBe(true);
    expect(parsed.features).toEqual({ payroll_deduction: true });
    expect(parsed.adminEmail).toBe("admin@example.test");
  });

  it("refuses missing, unknown and inconsistent arguments", () => {
    expect(() => parseCreateTenantArgs(["--code", "x"])).toThrow(/required/);
    expect(() =>
      parseCreateTenantArgs(["--code", "x", "--name", "n", "--segment", "platform"]),
    ).toThrow(/must be one of/);
    expect(() => parseCreateTenantArgs([...base, "--admin-email", "a@example.test"])).toThrow(
      /go together/,
    );
    expect(() => parseCreateTenantArgs([...base, "--features", "[1]"])).toThrow(/JSON object/);
    expect(() => parseCreateTenantArgs([...base, "--unknown"])).toThrow();
  });
});
