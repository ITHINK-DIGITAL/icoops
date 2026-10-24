import { signIn } from "./actions";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;
  return (
    <main>
      <h1>Sign in to iCOOPs</h1>
      <form action={signIn} className="card">
        <label htmlFor="email">Email</label>
        <input id="email" name="email" type="email" autoComplete="username" required />
        <label htmlFor="password">Password</label>
        <input
          id="password"
          name="password"
          type="password"
          autoComplete="current-password"
          required
        />
        {error ? (
          <p role="alert" className="error">
            Sign-in failed. Check your email and password.
          </p>
        ) : null}
        <p>
          <button className="primary" type="submit">
            Sign in
          </button>
        </p>
        <p className="muted">
          Staff accounts are created by your cooperative&apos;s administrator.
        </p>
      </form>
    </main>
  );
}
