// AT-13 through the API: a user of tenant A, holding a real token, cannot read or write any row
// of tenant B. The database-level matrix (supabase/tests/database/002_isolation.test.sql) is
// generated from the catalog; this proves the same through PostgREST with signed JWTs.
import { beforeAll, describe, expect, it } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { anon, service, signIn, tenantIds } from "./support.js";

// Every table in public. A table added later is covered by the database matrix; add it here too.
const TABLES = [
  "tenant",
  "app_user",
  "audit_log",
  "role",
  "role_permission",
  "user_role",
  "approval_matrix",
  "approval_matrix_step",
  "approval_request",
  "approval_request_step",
  "approval_decision",
  "rule_version",
  "worked_example",
] as const;

let ids: { a: string; b: string };
let rvB: string;
let exB: string;
let mxB: string;
let reqB: string;
let userA: SupabaseClient;
let adminA: SupabaseClient;
let auditorB: SupabaseClient;

beforeAll(async () => {
  ids = await tenantIds();
  const svc = service();
  // One row of each kind for tenant B, written with the service key.
  const rv = await svc
    .from("rule_version")
    .insert({
      tenant_id: ids.b,
      rule_type: "api_iso",
      scope: "tenant",
      params: { k: "b" },
      effective_from: "2030-01-01",
    })
    .select("id")
    .single();
  rvB = rv.data!.id as string;
  const ex = await svc
    .from("worked_example")
    .insert({
      tenant_id: ids.b,
      rule_version_id: rvB,
      code: "API-ISO",
      kind: "normal",
      inputs: {},
      expected: {},
    })
    .select("id")
    .single();
  exB = ex.data!.id as string;
  const mx = await svc
    .from("approval_matrix")
    .insert({
      tenant_id: ids.b,
      txn_type: "withdrawal_above_limit",
      min_amount: 0,
      max_amount: 1000,
      effective_from: "2030-01-01",
    })
    .select("id")
    .single();
  mxB = mx.data!.id as string;
  const tellerB = await signIn("teller", "b");
  const req = await tellerB.rpc("create_approval_request", {
    p_type: "withdrawal_above_limit",
    p_subject_table: "txn",
    p_subject_id: crypto.randomUUID(),
    p_amount: "60000",
    p_payload: { n: "b" },
  });
  reqB = req.data as string;
  userA = await signIn("teller", "a");
  adminA = await signIn("admin", "a");
  auditorB = await signIn("auditor", "b");
});

describe("reads", () => {
  it.each(TABLES)("tenant A never sees tenant B rows in %s", async (table) => {
    for (const client of [userA, adminA]) {
      const { data, error } = await client.from(table).select("*");
      if (error) {
        expect(error.code).toBe("42501"); // refused outright is fine
        continue;
      }
      const foreign = (data ?? []).filter(
        (row) =>
          row.tenant_id !== ids.a && row.tenant_id !== "00000000-0000-0000-0000-000000000001",
      );
      expect(foreign).toEqual([]);
      expect((data ?? []).filter((row) => row.tenant_id === ids.b)).toEqual([]);
    }
  });

  it("tenant B's auditor sees B's audit rows but none of A's", async () => {
    const { data, error } = await auditorB.from("audit_log").select("tenant_id").limit(1000);
    expect(error).toBeNull();
    expect(data!.length).toBeGreaterThan(0);
    expect(data!.every((row) => row.tenant_id === ids.b)).toBe(true);
  });

  it("a teller sees no audit rows (needs audit_log:view)", async () => {
    const { data } = await userA.from("audit_log").select("id").limit(1);
    expect(data ?? []).toEqual([]);
  });

  it("anonymous requests see nothing in any table", async () => {
    for (const table of TABLES) {
      const { data, error } = await anon().from(table).select("*");
      expect(error !== null || (data ?? []).length === 0, `anon read of ${table}`).toBe(true);
    }
  });
});

describe("writes", () => {
  it.each(TABLES)("cannot insert into %s on behalf of tenant B", async (table) => {
    const { error } = await adminA.from(table).insert({ tenant_id: ids.b });
    expect(error, `insert into ${table}`).not.toBeNull();
  });

  it("cannot update or delete tenant B's rows", async () => {
    const accountantA = await signIn("accountant", "a");
    const updates = [
      accountantA
        .from("rule_version")
        .update({ effective_from: "2031-01-01" })
        .eq("id", rvB)
        .select("id"),
      accountantA.from("worked_example").update({ note: "x" }).eq("id", exB).select("id"),
      accountantA.from("approval_matrix").update({ max_amount: 5000 }).eq("id", mxB).select("id"),
    ];
    for (const result of await Promise.all(updates)) {
      expect(result.error !== null || (result.data ?? []).length === 0).toBe(true);
    }
    for (const table of TABLES) {
      const { error } = await accountantA.from(table).delete().eq("tenant_id", ids.b);
      expect(error, `delete from ${table}`).not.toBeNull();
    }
    const { data } = await service()
      .from("rule_version")
      .select("effective_from")
      .eq("id", rvB)
      .single();
    expect(data!.effective_from).toBe("2030-01-01");
  });
});

describe("guarded functions with tenant B's ids", () => {
  it("refuse every call", async () => {
    const accountantA = await signIn("accountant", "a");
    const calls: [string, Record<string, unknown>][] = [
      ["submit_rule_version", { p_rule_version_id: rvB }],
      ["submit_approval_matrix", { p_matrix_id: mxB }],
      ["cancel_approval_request", { p_request_id: reqB }],
      ["execute_approval_request", { p_request_id: reqB }],
      ["decide_approval_request", { p_request_id: reqB, p_decision: "approve" }],
      ["log_sensitive_view", { p_entity: "rule_version", p_entity_id: rvB }],
    ];
    for (const [fn, args] of calls) {
      const { error } = await accountantA.rpc(fn, args);
      expect(error, fn).not.toBeNull();
    }
  });

  it("keep the platform functions closed to signed-in users and to anonymous callers", async () => {
    for (const client of [adminA, anon()]) {
      const tenant = await client.rpc("admin_create_tenant", {
        p_code: "intruder",
        p_name: "x",
        p_segment: "s1_private",
      });
      expect(tenant.error).not.toBeNull();
      const run = await client.rpc("record_worked_example_result", {
        p_example_id: exB,
        p_passed: true,
        p_actual: {},
        p_diff: {},
        p_params_hash: "h",
        p_library: "l",
      });
      expect(run.error).not.toBeNull();
    }
  });
});
