import Link from "next/link";

export function Nav({ name }: { name: string }) {
  return (
    <nav aria-label="Main">
      <strong>iCOOPs</strong>
      <Link href="/">Home</Link>
      <Link href="/approvals">Approvals</Link>
      <Link href="/account/mfa">Two-factor</Link>
      <span className="muted">{name}</span>
      <form action="/auth/signout" method="post">
        <button type="submit">Sign out</button>
      </form>
    </nav>
  );
}
