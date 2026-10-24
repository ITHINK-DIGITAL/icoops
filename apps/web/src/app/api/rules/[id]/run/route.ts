import { NextResponse } from "next/server";
import { createServiceClient } from "@icoops/db";
import { createDefaultRegistry } from "@icoops/rules";
import { serviceEnv } from "@/lib/env";
import { runRuleVersion } from "@/lib/run-rule-version";
import { createSupabaseServer } from "@/lib/supabase/server";

// POST /api/rules/{id}/run: run a draft rule version's worked examples and record the results.
export async function POST(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const user = await createSupabaseServer();
  const { data } = await user.auth.getUser();
  if (!data.user) {
    return NextResponse.json({ message: "Sign in first." }, { status: 401 });
  }
  const { url, serviceKey } = serviceEnv();
  const outcome = await runRuleVersion(
    { user, service: createServiceClient({ url, serviceKey }), registry: createDefaultRegistry() },
    id,
  );
  if (!outcome.ok) {
    return NextResponse.json(
      { message: outcome.message, issues: outcome.issues },
      { status: outcome.status },
    );
  }
  return NextResponse.json({
    total: outcome.total,
    passed: outcome.passed,
    results: outcome.results,
  });
}
