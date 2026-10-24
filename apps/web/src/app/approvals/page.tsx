import { Nav } from "@/components/Nav";
import { createSupabaseServer } from "@/lib/supabase/server";
import { act } from "./actions";

interface Row {
  id: string;
  request_type: string;
  amount: string | number | null;
  status: string;
  current_step: number;
  maker_user_id: string;
  created_at: string;
  payload: Record<string, unknown>;
}

export default async function ApprovalsPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; notice?: string }>;
}) {
  const { error, notice } = await searchParams;
  const supabase = await createSupabaseServer();
  const { data: auth } = await supabase.auth.getUser();
  const { data: me } = await supabase
    .from("app_user")
    .select("id, display_name")
    .eq("email", auth.user?.email ?? "")
    .maybeSingle();
  const { data } = await supabase
    .from("approval_request")
    .select("id, request_type, amount, status, current_step, maker_user_id, created_at, payload")
    .in("status", ["pending", "approved"])
    .order("created_at", { ascending: false })
    .limit(50);
  const rows = (data ?? []) as Row[];
  const { data: people } = await supabase.from("app_user").select("id, display_name");
  const names = new Map((people ?? []).map((p) => [p.id as string, p.display_name as string]));

  return (
    <>
      <Nav name={me?.display_name ?? ""} />
      <main>
        <h1>Approvals</h1>
        {error ? (
          <p role="alert" className="error">
            {error}
          </p>
        ) : null}
        {notice ? (
          <p role="status" className="notice">
            {notice}
          </p>
        ) : null}
        <p className="muted">
          You can never approve a request you made or edited. Approving needs a second-factor
          sign-in: set it up under Two-factor.
        </p>
        {rows.length === 0 ? (
          <p className="card">Nothing is waiting.</p>
        ) : (
          rows.map((row) => (
            <article className="card" key={row.id} aria-label={`${row.request_type} ${row.id}`}>
              <h2>{row.request_type.replaceAll("_", " ")}</h2>
              <p>
                <span className="pill">{row.status}</span>{" "}
                {row.status === "pending" ? (
                  <span className="pill">step {row.current_step}</span>
                ) : null}
              </p>
              <p>
                Made by {names.get(row.maker_user_id) ?? "someone"} on{" "}
                {new Date(row.created_at).toLocaleString("en-PH", { timeZone: "Asia/Manila" })}
                {row.amount !== null ? (
                  <>
                    , amount <strong>{String(row.amount)}</strong>
                  </>
                ) : null}
              </p>
              <form action={act} className="actions">
                <input type="hidden" name="id" value={row.id} />
                <label htmlFor={`reason-${row.id}`} className="muted">
                  Reason (needed to reject)
                </label>
                <input id={`reason-${row.id}`} name="reason" type="text" />
                {row.status === "pending" ? (
                  <>
                    <button className="primary" type="submit" name="op" value="approve">
                      Approve
                    </button>
                    <button type="submit" name="op" value="reject">
                      Reject
                    </button>
                    {row.maker_user_id === me?.id ? (
                      <button type="submit" name="op" value="cancel">
                        Cancel my request
                      </button>
                    ) : null}
                  </>
                ) : (
                  <button className="primary" type="submit" name="op" value="execute">
                    Execute
                  </button>
                )}
              </form>
            </article>
          ))
        )}
      </main>
    </>
  );
}
