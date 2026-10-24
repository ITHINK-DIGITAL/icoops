import { createServerClient } from "@supabase/ssr";
import type { CookieOptions } from "@supabase/ssr";
import { cookies } from "next/headers";
import { publicEnv } from "../env";

type CookieToSet = { name: string; value: string; options: CookieOptions };

/** Supabase client bound to the request's session cookies: every query runs under the user's RLS. */
export async function createSupabaseServer() {
  const store = await cookies();
  const { url, anonKey } = publicEnv();
  return createServerClient(url, anonKey, {
    cookies: {
      getAll: () => store.getAll(),
      setAll: (list: CookieToSet[]) => {
        try {
          for (const { name, value, options } of list) {
            store.set(name, value, options);
          }
        } catch {
          // Called from a Server Component, where cookies are read-only; the middleware refreshes them.
        }
      },
    },
  });
}
