import { createClient } from "@supabase/supabase-js";
import type { SupabaseClient } from "@supabase/supabase-js";
import * as OTPAuth from "otpauth";

/** Seeded synthetic users (supabase/seed.sql). The password is a published development placeholder. */
export const PASSWORD = "local-dev-only-password";

function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    // A skipped isolation test is a false green, so a missing stack is a failure, not a skip.
    throw new Error(
      `${name} is not set. Start the local stack (supabase start) and export its URL and keys; see CLAUDE.md.`,
    );
  }
  return value;
}

export const env = {
  get url() {
    return required("SUPABASE_URL");
  },
  get anonKey() {
    return required("SUPABASE_ANON_KEY");
  },
  get serviceKey() {
    return required("SUPABASE_SERVICE_ROLE_KEY");
  },
};

const options = { auth: { persistSession: false, autoRefreshToken: false } };

export const anon = (): SupabaseClient => createClient(env.url, env.anonKey, options);
export const service = (): SupabaseClient => createClient(env.url, env.serviceKey, options);

export async function signIn(name: string, tenantKey: "a" | "b"): Promise<SupabaseClient> {
  const client = anon();
  const { error } = await client.auth.signInWithPassword({
    email: `${name}.${tenantKey}@example.test`,
    password: PASSWORD,
  });
  if (error) {
    throw new Error(`sign-in failed for ${name}.${tenantKey}: ${error.message}`);
  }
  return client;
}

// An aal2 session is created once per user per run and reused: a TOTP code can be replayed only
// once per 30-second step, and enrolling a second factor while a verified one exists is refused at
// aal1. Start from a fresh database (supabase db reset).
const secondFactorSessions = new Map<string, SupabaseClient>();

function totpCode(secret: string): string {
  return new OTPAuth.TOTP({
    secret: OTPAuth.Secret.fromBase32(secret),
    digits: 6,
    period: 30,
  }).generate();
}

/** Sign in and upgrade the session to a second factor (aal2) with a TOTP code. */
export async function signInWithSecondFactor(
  name: string,
  tenantKey: "a" | "b",
): Promise<SupabaseClient> {
  const key = `${name}.${tenantKey}`;
  const cached = secondFactorSessions.get(key);
  if (cached) {
    return cached;
  }
  const client = await signIn(name, tenantKey);
  const { data, error } = await client.auth.mfa.enroll({ factorType: "totp" });
  if (error || !data) {
    throw new Error(
      `could not enrol a TOTP factor for ${key}: ${error?.message}. Reset the database and retry.`,
    );
  }
  const { data: challenge, error: challengeError } = await client.auth.mfa.challenge({
    factorId: data.id,
  });
  if (challengeError || !challenge) {
    throw new Error(`could not challenge the factor: ${challengeError?.message}`);
  }
  const { error: verifyError } = await client.auth.mfa.verify({
    factorId: data.id,
    challengeId: challenge.id,
    code: totpCode(data.totp.secret),
  });
  if (verifyError) {
    throw new Error(`second factor was not accepted: ${verifyError.message}`);
  }
  secondFactorSessions.set(key, client);
  return client;
}

export async function tenantIds(): Promise<{ a: string; b: string }> {
  const { data, error } = await service()
    .from("tenant")
    .select("id, code")
    .in("code", ["sandbox-a", "sandbox-b"]);
  if (error || !data || data.length !== 2) {
    throw new Error(`seeded tenants not found: ${error?.message ?? "run supabase db reset"}`);
  }
  const byCode = Object.fromEntries(data.map((t) => [t.code as string, t.id as string]));
  return { a: byCode["sandbox-a"]!, b: byCode["sandbox-b"]! };
}
