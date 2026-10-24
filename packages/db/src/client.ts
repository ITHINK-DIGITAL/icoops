import { createClient } from "@supabase/supabase-js";
import type { SupabaseClient } from "@supabase/supabase-js";

export type Db = SupabaseClient;

/** A client that acts as a signed-in user: every query runs under that user's row-level security. */
export function createUserClient(options: {
  url: string;
  anonKey: string;
  accessToken?: string;
}): Db {
  return createClient(options.url, options.anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: options.accessToken
      ? { headers: { Authorization: `Bearer ${options.accessToken}` } }
      : {},
  });
}

/**
 * A client with the service key: it bypasses row-level security and may call the platform
 * functions. Server-side only (scripts and route handlers); never import this in browser code.
 */
export function createServiceClient(options: { url: string; serviceKey: string }): Db {
  if (typeof window !== "undefined") {
    throw new Error("the service client must never be created in the browser");
  }
  return createClient(options.url, options.serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
