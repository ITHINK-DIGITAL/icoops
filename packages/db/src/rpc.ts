import type { Db } from "./client.js";
import type { Decision } from "./types.js";

export class DbError extends Error {
  constructor(
    readonly fn: string,
    readonly code: string | undefined,
    message: string,
  ) {
    super(`${fn}: ${message}`);
    this.name = "DbError";
  }
}

async function call<T>(db: Db, fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await db.rpc(fn, args);
  if (error) {
    throw new DbError(fn, error.code, error.message);
  }
  return data as T;
}

// Signed-in user functions. The database enforces every rule; these only carry arguments.
export const decideApprovalRequest = (
  db: Db,
  requestId: string,
  decision: Decision,
  reason?: string,
) =>
  call<null>(db, "decide_approval_request", {
    p_request_id: requestId,
    p_decision: decision,
    p_reason: reason ?? null,
  });

export const executeApprovalRequest = (db: Db, requestId: string) =>
  call<null>(db, "execute_approval_request", { p_request_id: requestId });

export const cancelApprovalRequest = (db: Db, requestId: string, reason?: string) =>
  call<null>(db, "cancel_approval_request", { p_request_id: requestId, p_reason: reason ?? null });

export const submitRuleVersion = (db: Db, ruleVersionId: string) =>
  call<string>(db, "submit_rule_version", { p_rule_version_id: ruleVersionId });

export const submitApprovalMatrix = (db: Db, matrixId: string) =>
  call<string>(db, "submit_approval_matrix", { p_matrix_id: matrixId });

export const requestUserRoleGrant = (db: Db, userId: string, roleId: string, validTo?: string) =>
  call<string>(db, "request_user_role_grant", {
    p_user_id: userId,
    p_role_id: roleId,
    p_valid_to: validTo ?? null,
  });

export const createApprovalRequest = (
  db: Db,
  args: {
    type: string;
    subjectTable: string;
    subjectId: string;
    amount: string | null;
    payload: Record<string, unknown>;
  },
) =>
  call<string>(db, "create_approval_request", {
    p_type: args.type,
    p_subject_table: args.subjectTable,
    p_subject_id: args.subjectId,
    p_amount: args.amount,
    p_payload: args.payload,
  });

export type FunctionCode =
  | "member_record"
  | "membership_approval"
  | "payment_posting"
  | "withdrawal_above_limit"
  | "loan_application"
  | "loan_approval"
  | "loan_release_voucher"
  | "teller_eod"
  | "deduction_batch"
  | "journal_voucher"
  | "period_close"
  | "product_rule_config"
  | "users_roles"
  | "audit_log"
  | "reports";
export type ActionCode = "create" | "approve" | "view";

export const currentUserCan = (db: Db, fn: FunctionCode, action: ActionCode) =>
  call<boolean>(db, "current_user_can", { p_function: fn, p_action: action });

export const logSensitiveView = (db: Db, entity: string, entityId: string, reason?: string) =>
  call<null>(db, "log_sensitive_view", {
    p_entity: entity,
    p_entity_id: entityId,
    p_reason: reason ?? null,
  });

// Platform functions: service key only.
export const recordWorkedExampleResult = (
  db: Db,
  args: {
    exampleId: string;
    passed: boolean;
    actual: unknown;
    diff: unknown;
    paramsHash: string;
    library: string;
  },
) =>
  call<null>(db, "record_worked_example_result", {
    p_example_id: args.exampleId,
    p_passed: args.passed,
    p_actual: args.actual ?? {},
    p_diff: args.diff ?? {},
    p_params_hash: args.paramsHash,
    p_library: args.library,
  });

export const adminCreateTenant = (
  db: Db,
  args: {
    code: string;
    name: string;
    segment: string;
    parentTenantId?: string;
    features?: Record<string, boolean>;
    isSandbox?: boolean;
  },
) =>
  call<string>(db, "admin_create_tenant", {
    p_code: args.code,
    p_name: args.name,
    p_segment: args.segment,
    p_parent_tenant_id: args.parentTenantId ?? null,
    p_features: args.features ?? {},
    p_is_sandbox: args.isSandbox ?? false,
  });

export const adminBootstrapUser = (
  db: Db,
  args: {
    tenantId: string;
    authUserId: string;
    displayName: string;
    email: string;
    roleCodes: string[];
  },
) =>
  call<string>(db, "admin_bootstrap_user", {
    p_tenant_id: args.tenantId,
    p_auth_user_id: args.authUserId,
    p_display_name: args.displayName,
    p_email: args.email,
    p_role_codes: args.roleCodes,
  });
