// Platform path for creating a tenant (PL-002, decision D25): service key, run by an iThink
// administrator, never exposed through the app. Every row it writes is audited by the database
// with actor_kind = 'service'. It can also create the tenant's first administrator (a sign-in
// identity without a password: the person sets one through "forgot password").
import { defaultFeatures } from "@icoops/rules";
import { adminBootstrapUser, adminCreateTenant } from "../src/rpc.js";
import { createServiceClient } from "../src/client.js";
import { CREATE_TENANT_USAGE, parseCreateTenantArgs } from "../src/admin-args.js";

async function main(): Promise<void> {
  const url = process.env.SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceKey) {
    throw new Error("set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY");
  }
  const args = parseCreateTenantArgs(process.argv.slice(2));
  const db = createServiceClient({ url, serviceKey });

  const tenantId = await adminCreateTenant(db, {
    code: args.code,
    name: args.name,
    segment: args.segment,
    parentTenantId: args.parent,
    features: defaultFeatures(args.segment, args.features),
    isSandbox: args.sandbox,
  });
  console.log(`tenant ${args.code} created: ${tenantId}`);

  if (args.adminEmail && args.adminName) {
    const { data, error } = await db.auth.admin.createUser({
      email: args.adminEmail,
      email_confirm: true,
    });
    if (error || !data.user) {
      throw new Error(
        `could not create the sign-in identity: ${error?.message ?? "no user returned"}`,
      );
    }
    await adminBootstrapUser(db, {
      tenantId,
      authUserId: data.user.id,
      displayName: args.adminName,
      email: args.adminEmail,
      roleCodes: ["tenant_admin"],
    });
    console.log(`administrator ${args.adminEmail} created with the tenant_admin role`);
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  console.error(CREATE_TENANT_USAGE);
  process.exit(1);
});
