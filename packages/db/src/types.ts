// Row shapes for the tables the staff app reads. Hand-maintained for slice 1; replaced by types
// generated with `supabase gen types typescript` once the dev project exists (D24).
// Money and rates are strings: PostgREST returns numeric as JSON numbers for small values, so the
// app never does arithmetic on them (calculations live in @icoops/calc).

export type ApprovalStatus = "pending" | "approved" | "rejected" | "cancelled" | "executed";
export type ConfigStatus = "draft" | "submitted" | "active" | "rejected" | "withdrawn" | "retired";

export interface ApprovalRequestRow {
  id: string;
  tenant_id: string;
  request_type: string;
  subject_table: string;
  subject_id: string;
  amount: string | number | null;
  payload: Record<string, unknown>;
  maker_user_id: string;
  current_step: number;
  status: ApprovalStatus;
  created_at: string;
  decided_at: string | null;
  executed_at: string | null;
}

export interface AppUserRow {
  id: string;
  tenant_id: string;
  display_name: string;
  email: string;
  status: "active" | "locked" | "disabled";
}

export interface TenantRow {
  id: string;
  code: string;
  name: string;
  segment: "platform" | "s1_private" | "s2_government" | "s3_federation";
  features: Record<string, boolean>;
  status: "active" | "suspended" | "closed";
  is_sandbox: boolean;
}

export type Segment = TenantRow["segment"];
export type Decision = "approve" | "reject";
