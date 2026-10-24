import { Nav } from "@/components/Nav";
import { createSupabaseServer } from "@/lib/supabase/server";

export default async function HomePage() {
  const supabase = await createSupabaseServer();
  const { data: auth } = await supabase.auth.getUser();
  // Row-level security returns only the signed-in user's own tenant.
  const { data: tenant } = await supabase
    .from("tenant")
    .select("name, code, segment, features, is_sandbox")
    .maybeSingle();
  const { data: me } = await supabase
    .from("app_user")
    .select("id, display_name, email")
    .eq("email", auth.user?.email ?? "")
    .maybeSingle();
  const { data: grants } = me
    ? await supabase.from("user_role").select("role_id, valid_to").eq("user_id", me.id)
    : { data: [] };
  const roleIds = (grants ?? []).map((g) => g.role_id as string);
  const { data: roles } = roleIds.length
    ? await supabase.from("role").select("id, name").in("id", roleIds)
    : { data: [] };
  const features = Object.entries((tenant?.features ?? {}) as Record<string, boolean>);

  return (
    <>
      <Nav name={me?.display_name ?? auth.user?.email ?? ""} />
      <main>
        <h1>{tenant?.name ?? "No tenant"}</h1>
        {tenant?.is_sandbox ? <p className="pill">Sandbox: synthetic data only</p> : null}
        <section className="card" aria-labelledby="who">
          <h2 id="who">You</h2>
          <p>
            {me?.display_name} <span className="muted">({me?.email})</span>
          </p>
          <p>Roles: {(roles ?? []).map((r) => r.name).join(", ") || "none"}</p>
        </section>
        <section className="card" aria-labelledby="tenant">
          <h2 id="tenant">Cooperative</h2>
          <p>
            Segment: <code>{tenant?.segment}</code>
          </p>
          <p>
            Features:{" "}
            {features.length === 0
              ? "none"
              : features.map(([key, on]) => `${key} ${on ? "on" : "off"}`).join(", ")}
          </p>
        </section>
      </main>
    </>
  );
}
