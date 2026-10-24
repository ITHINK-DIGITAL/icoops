import { parseArgs } from "node:util";

export interface CreateTenantArgs {
  code: string;
  name: string;
  segment: "s1_private" | "s2_government" | "s3_federation";
  parent?: string;
  sandbox: boolean;
  features: Record<string, unknown>;
  adminEmail?: string;
  adminName?: string;
}

const SEGMENTS = ["s1_private", "s2_government", "s3_federation"] as const;

export const CREATE_TENANT_USAGE = `Usage: pnpm --filter @icoops/db admin:create-tenant -- \\
  --code <slug> --name <name> --segment <s1_private|s2_government|s3_federation> \\
  [--parent <federation tenant id>] [--sandbox] [--features '{"payroll_deduction":true}'] \\
  [--admin-email <email> --admin-name <name>]

Environment: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (the key is never printed).`;

export function parseCreateTenantArgs(argv: readonly string[]): CreateTenantArgs {
  const { values } = parseArgs({
    args: [...argv],
    options: {
      code: { type: "string" },
      name: { type: "string" },
      segment: { type: "string" },
      parent: { type: "string" },
      sandbox: { type: "boolean", default: false },
      features: { type: "string" },
      "admin-email": { type: "string" },
      "admin-name": { type: "string" },
    },
    strict: true,
  });
  if (!values.code || !values.name || !values.segment) {
    throw new Error("--code, --name and --segment are required");
  }
  const segment = SEGMENTS.find((s) => s === values.segment);
  if (!segment) {
    throw new Error(`--segment must be one of ${SEGMENTS.join(", ")}`);
  }
  if (Boolean(values["admin-email"]) !== Boolean(values["admin-name"])) {
    throw new Error("--admin-email and --admin-name go together");
  }
  let features: Record<string, unknown> = {};
  if (values.features) {
    const parsed: unknown = JSON.parse(values.features);
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
      throw new Error("--features must be a JSON object");
    }
    features = parsed as Record<string, unknown>;
  }
  return {
    code: values.code,
    name: values.name,
    segment,
    parent: values.parent,
    sandbox: values.sandbox ?? false,
    features,
    adminEmail: values["admin-email"],
    adminName: values["admin-name"],
  };
}
