// AT-14 through the API: the creator of a withdrawal above limit cannot approve it, and an
// approval needs a real second-factor session (aal2), not just a password.
import { describe, expect, it } from "vitest";
import { signIn, signInWithSecondFactor } from "./support.js";

async function newWithdrawal(): Promise<string> {
  const teller = await signIn("teller", "a");
  const { data, error } = await teller.rpc("create_approval_request", {
    p_type: "withdrawal_above_limit",
    p_subject_table: "txn",
    p_subject_id: crypto.randomUUID(),
    p_amount: "60000",
    p_payload: { source: "api-test" },
  });
  expect(error).toBeNull();
  return data as string;
}

describe("maker-checker (AT-14)", () => {
  it("refuses the maker, refuses a password-only checker, accepts a checker with a second factor", async () => {
    const requestId = await newWithdrawal();

    const teller = await signIn("teller", "a");
    const byMaker = await teller.rpc("decide_approval_request", {
      p_request_id: requestId,
      p_decision: "approve",
    });
    expect(byMaker.error?.message).toMatch(/maker-checker|permission/);

    const gmPasswordOnly = await signIn("gm", "a");
    const withoutFactor = await gmPasswordOnly.rpc("decide_approval_request", {
      p_request_id: requestId,
      p_decision: "approve",
    });
    expect(withoutFactor.error?.message).toMatch(/second-factor/);

    const gm = await signInWithSecondFactor("gm", "a");
    const approved = await gm.rpc("decide_approval_request", {
      p_request_id: requestId,
      p_decision: "approve",
    });
    expect(approved.error).toBeNull();

    const { data } = await gm
      .from("approval_request")
      .select("status")
      .eq("id", requestId)
      .single();
    expect(data?.status).toBe("approved");
  });

  it("does not let a client choose who decided", async () => {
    const requestId = await newWithdrawal();
    const gm = await signInWithSecondFactor("gm", "a");
    const forged = await gm.from("approval_decision").insert({
      request_id: requestId,
      step_no: 1,
      decided_by: crypto.randomUUID(),
      decision: "approve",
    });
    expect(forged.error).not.toBeNull();
  });
});
