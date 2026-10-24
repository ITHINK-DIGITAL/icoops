"use client";

import { useCallback, useEffect, useState } from "react";
import { createSupabaseBrowser } from "@/lib/supabase/browser";
import { Nav } from "@/components/Nav";

type Stage = "loading" | "none" | "enrolling" | "verify" | "done";

// Approvals need an aal2 session (second factor). This page enrols a TOTP authenticator app and
// upgrades the current session.
export default function MfaPage() {
  const supabase = createSupabaseBrowser();
  const [stage, setStage] = useState<Stage>("loading");
  const [factorId, setFactorId] = useState("");
  const [qr, setQr] = useState("");
  const [secret, setSecret] = useState("");
  const [code, setCode] = useState("");
  const [message, setMessage] = useState("");

  const refresh = useCallback(async () => {
    const { data: level } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
    if (level?.currentLevel === "aal2") {
      setStage("done");
      return;
    }
    const { data: factors } = await supabase.auth.mfa.listFactors();
    const verified = factors?.totp?.[0];
    if (verified) {
      setFactorId(verified.id);
      setStage("verify");
    } else {
      setStage("none");
    }
  }, [supabase]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  async function startEnrol() {
    setMessage("");
    const { data, error } = await supabase.auth.mfa.enroll({ factorType: "totp" });
    if (error || !data) {
      setMessage(error?.message ?? "Could not start set-up.");
      return;
    }
    setFactorId(data.id);
    setQr(data.totp.qr_code);
    setSecret(data.totp.secret);
    setStage("enrolling");
  }

  async function submitCode(event: React.FormEvent) {
    event.preventDefault();
    setMessage("");
    const { data: challenge, error: challengeError } = await supabase.auth.mfa.challenge({
      factorId,
    });
    if (challengeError || !challenge) {
      setMessage(challengeError?.message ?? "Could not start the check.");
      return;
    }
    const { error } = await supabase.auth.mfa.verify({
      factorId,
      challengeId: challenge.id,
      code: code.trim(),
    });
    if (error) {
      setMessage("That code was not accepted. Check the time on your phone and try again.");
      return;
    }
    setCode("");
    setStage("done");
  }

  return (
    <>
      <Nav name="" />
      <main>
        <h1>Two-factor sign-in</h1>
        {stage === "loading" ? <p>Checking…</p> : null}
        {stage === "none" ? (
          <section className="card">
            <p>
              Approvals need a second factor. Set up an authenticator app (for example Google
              Authenticator).
            </p>
            <button className="primary" type="button" onClick={startEnrol}>
              Set up
            </button>
          </section>
        ) : null}
        {stage === "enrolling" ? (
          <section className="card">
            <img src={qr} alt="QR code for your authenticator app" width={200} height={200} />
            <p className="muted">
              Cannot scan? Enter this key: <code>{secret}</code>
            </p>
          </section>
        ) : null}
        {stage === "enrolling" || stage === "verify" ? (
          <form className="card" onSubmit={submitCode}>
            <label htmlFor="code">6-digit code</label>
            <input
              id="code"
              type="text"
              inputMode="numeric"
              autoComplete="one-time-code"
              pattern="[0-9]{6}"
              value={code}
              onChange={(e) => setCode(e.target.value)}
              required
            />
            <p>
              <button className="primary" type="submit">
                Confirm
              </button>
            </p>
          </form>
        ) : null}
        {stage === "done" ? (
          <p role="status" className="notice card">
            Two-factor is active for this session. You can approve requests now.
          </p>
        ) : null}
        {message ? (
          <p role="alert" className="error">
            {message}
          </p>
        ) : null}
      </main>
    </>
  );
}
