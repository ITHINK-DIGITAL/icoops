// Environment is read lazily so that building the app never needs secrets.
function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(
      `${name} is not set (see .env.example; secrets live in Vercel and Supabase settings only)`,
    );
  }
  return value;
}

export const publicEnv = () => ({
  url: required("NEXT_PUBLIC_SUPABASE_URL"),
  anonKey: required("NEXT_PUBLIC_SUPABASE_ANON_KEY"),
});

/** Server-only. Never import from a client component. */
export const serviceEnv = () => ({
  url: required("SUPABASE_URL"),
  serviceKey: required("SUPABASE_SERVICE_ROLE_KEY"),
});
