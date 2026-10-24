import { describe, expect, it, vi } from "vitest";
import {
  DbError,
  adminCreateTenant,
  decideApprovalRequest,
  recordWorkedExampleResult,
} from "../src/index.js";
import type { Db } from "../src/index.js";

function fakeDb(result: { data?: unknown; error?: { code: string; message: string } }) {
  const rpc = vi.fn().mockResolvedValue({ data: result.data ?? null, error: result.error ?? null });
  return { db: { rpc } as unknown as Db, rpc };
}

describe("rpc wrappers", () => {
  it("map arguments to the function's parameter names", async () => {
    const { db, rpc } = fakeDb({});
    await decideApprovalRequest(db, "req-1", "reject", "over limit");
    expect(rpc).toHaveBeenCalledWith("decide_approval_request", {
      p_request_id: "req-1",
      p_decision: "reject",
      p_reason: "over limit",
    });
  });

  it("send null, not undefined, for omitted optionals", async () => {
    const { db, rpc } = fakeDb({ data: "tenant-id" });
    await expect(
      adminCreateTenant(db, { code: "x-co", name: "X", segment: "s1_private" }),
    ).resolves.toBe("tenant-id");
    expect(rpc.mock.calls[0]?.[1]).toMatchObject({
      p_parent_tenant_id: null,
      p_features: {},
      p_is_sandbox: false,
    });
  });

  it("carry result columns for the run recorder", async () => {
    const { db, rpc } = fakeDb({});
    await recordWorkedExampleResult(db, {
      exampleId: "e1",
      passed: true,
      actual: undefined,
      diff: null,
      paramsHash: "h",
      library: "lib@1",
    });
    expect(rpc.mock.calls[0]?.[1]).toMatchObject({
      p_example_id: "e1",
      p_passed: true,
      p_actual: {},
      p_diff: {},
      p_params_hash: "h",
    });
  });

  it("turn a database error into a DbError with the SQLSTATE", async () => {
    const { db } = fakeDb({
      error: { code: "42501", message: "maker-checker: the maker cannot decide" },
    });
    await expect(decideApprovalRequest(db, "r", "approve")).rejects.toMatchObject({
      name: "DbError",
      code: "42501",
      fn: "decide_approval_request",
    });
    await expect(decideApprovalRequest(db, "r", "approve")).rejects.toBeInstanceOf(DbError);
  });
});
