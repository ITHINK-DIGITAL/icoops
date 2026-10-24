"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import {
  DbError,
  cancelApprovalRequest,
  decideApprovalRequest,
  executeApprovalRequest,
} from "@icoops/db";
import { createSupabaseServer } from "@/lib/supabase/server";

type Op = "approve" | "reject" | "cancel" | "execute";

const DONE: Record<Op, string> = {
  approve: "approved",
  reject: "rejected",
  cancel: "cancelled",
  execute: "executed",
};

/** Every rule (maker-checker, role, amount limit, second factor) is enforced by the database; the
 *  app only carries the request and shows the database's own message when it refuses. */
export async function act(formData: FormData): Promise<void> {
  const id = String(formData.get("id") ?? "");
  const op = String(formData.get("op") ?? "") as Op;
  const reason = String(formData.get("reason") ?? "").trim() || undefined;
  const supabase = await createSupabaseServer();
  let outcome: string;
  try {
    if (op === "approve" || op === "reject") {
      await decideApprovalRequest(supabase, id, op, reason);
    } else if (op === "cancel") {
      await cancelApprovalRequest(supabase, id, reason);
    } else if (op === "execute") {
      await executeApprovalRequest(supabase, id);
    } else {
      throw new Error("unknown action");
    }
    outcome = `notice=${encodeURIComponent(`Request ${DONE[op]}.`)}`;
  } catch (error) {
    outcome = `error=${encodeURIComponent(error instanceof DbError ? error.message.replace(/^[a-z_]+: /, "") : "Something went wrong.")}`;
  }
  revalidatePath("/approvals");
  redirect(`/approvals?${outcome}`);
}
