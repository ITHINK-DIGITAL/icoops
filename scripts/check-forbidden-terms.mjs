#!/usr/bin/env node
// Keeps this public repo free of secrets, real contact details and real partner names
// (CLAUDE.md: synthetic data only, no names, no .env files; decision D13).
//
//   node scripts/check-forbidden-terms.mjs            scan the repository
//   node scripts/check-forbidden-terms.mjs --self-test   prove the scanner still catches things
//
// Real partner and employer names cannot be listed in a public repo. They are supplied at run
// time in FORBIDDEN_TERMS (one per line or comma-separated, case-insensitive), a GitHub Actions
// secret. Matches are reported by file and line only, never by the term itself.
// FORBIDDEN_TERMS_REQUIRED=1 turns "no list configured" into a failure (used on main).
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, statSync } from "node:fs";
import { join, resolve } from "node:path";

const ROOT = resolve(new URL("..", import.meta.url).pathname);

const FORBIDDEN_FILE_NAMES = [
  /(^|\/)\.env(\.|$)(?!example$)/,
  /\.(pem|key|p12|pfx|jks)$/i,
  /(^|\/)id_(rsa|dsa|ecdsa|ed25519)/,
];

const SECRET_PATTERNS = [
  ["private key block", /-----BEGIN [A-Z ]*PRIVATE KEY-----/],
  ["JSON web token", /\beyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{10,}/],
  ["Supabase secret key", /\bsb_secret_[A-Za-z0-9_-]{10,}/],
  ["AWS access key id", /\bAKIA[0-9A-Z]{16}\b/],
  ["GitHub token", /\bgh[pousr]_[A-Za-z0-9]{30,}/],
  // Obvious placeholders (replace-with-..., your-..., changeme, <...>) are fine; anything else long is not.
  [
    "service key assignment",
    /SERVICE_ROLE_KEY\s*[=:]\s*["']?(?!replace-with|your-|changeme|<)[A-Za-z0-9._-]{20,}/,
  ],
];

// Only reserved example domains and the noreply attribution addresses may appear as emails.
const EMAIL = /[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,})/g;
const ALLOWED_EMAIL_DOMAINS = [
  /^example\.(test|com|org|net)$/i,
  /\.example\.test$/i,
  /^noreply\.github\.com$/i,
  /^users\.noreply\.github\.com$/i,
  /^anthropic\.com$/i,
];

const SKIP_PATH = /(^|\/)(docs\/media\/|pnpm-lock\.yaml$|scripts\/fixtures\/)/;
const BINARY_EXT = /\.(png|jpe?g|gif|ico|webp|pdf|woff2?|ttf|zip)$/i;

function listFiles(root) {
  const out = execFileSync("git", ["ls-files", "--cached", "--others", "--exclude-standard"], {
    cwd: root,
    encoding: "utf8",
  });
  return out
    .split("\n")
    .filter(Boolean)
    .filter((f) => existsSync(join(root, f)) && statSync(join(root, f)).isFile());
}

export function parseTerms(raw) {
  return (raw ?? "")
    .split(/[\n,]/)
    .map((t) => t.trim())
    .filter((t) => t.length >= 3);
}

export function scanText(path, text, terms) {
  const findings = [];
  const lines = text.split("\n");
  lines.forEach((line, index) => {
    const where = `${path}:${index + 1}`;
    for (const [label, pattern] of SECRET_PATTERNS) {
      if (pattern.test(line)) findings.push(`${where}: looks like a ${label}`);
    }
    for (const match of line.matchAll(EMAIL)) {
      if (!ALLOWED_EMAIL_DOMAINS.some((ok) => ok.test(match[1]))) {
        findings.push(`${where}: email address outside the reserved example domains`);
      }
    }
    terms.forEach((term, termIndex) => {
      if (line.toLowerCase().includes(term.toLowerCase()))
        findings.push(`${where}: forbidden term #${termIndex + 1}`);
    });
  });
  return findings;
}

export function scanFiles(root, files, terms) {
  const findings = [];
  for (const file of files) {
    if (FORBIDDEN_FILE_NAMES.some((p) => p.test(file)))
      findings.push(`${file}: file type must never be committed`);
    if (SKIP_PATH.test(file) || BINARY_EXT.test(file)) continue;
    findings.push(...scanText(file, readFileSync(join(root, file), "utf8"), terms));
  }
  return findings;
}

function selfTest() {
  const terms = ["Acme Hypothetical Coop"];
  // Fixtures are assembled from pieces so that this file does not trip its own patterns.
  const bad = [
    ["a.txt", "contact jun@" + "realcompany.ph for access"],
    [
      "b.txt",
      "key = eyJ" +
        "hbGciOiJIUzI1NiIsInR5cCI6.eyJ" +
        "yb2xlIjoic2VydmljZV9yb2xlIiwiaXNz.c2lnbmF0dXJlc2lnbmF0dXJl",
    ],
    ["c.txt", "-----BEGIN RSA " + "PRIVATE KEY-----"],
    ["d.txt", "Pilot with acme hypothetical coop in Cebu"],
    ["e.txt", "SUPABASE_SERVICE_" + "ROLE_KEY=abcdefghijklmnopqrstuvwxyz0123456789"],
  ];
  const good = [
    [
      "ok.txt",
      "synthetic: admin@example.test and noreply@anthropic.com, PARTNER-S1, sb_publishable_xyz",
    ],
  ];
  const missed = bad.filter(([p, t]) => scanText(p, t, terms).length === 0).map(([p]) => p);
  const falsePositives = good.filter(([p, t]) => scanText(p, t, terms).length > 0).map(([p]) => p);
  const nameCheck = ["server/.env", ".env.production", "keys/server.pem", "id_rsa"].filter(
    (f) => !FORBIDDEN_FILE_NAMES.some((p) => p.test(f)),
  );
  const allowedName = FORBIDDEN_FILE_NAMES.some((p) => p.test(".env.example"));
  if (missed.length || falsePositives.length || nameCheck.length || allowedName) {
    console.error("forbidden-terms self-test FAILED", {
      missed,
      falsePositives,
      nameCheck,
      allowedName,
    });
    process.exit(1);
  }
  console.log("forbidden-terms self-test passed");
}

if (process.argv.includes("--self-test")) {
  selfTest();
} else {
  const terms = parseTerms(process.env.FORBIDDEN_TERMS);
  const files = listFiles(ROOT);
  const findings = scanFiles(ROOT, files, terms);
  if (terms.length === 0) {
    const message =
      "FORBIDDEN_TERMS is not set: partner and employer names were NOT checked (set the Actions secret).";
    if (process.env.FORBIDDEN_TERMS_REQUIRED === "1") {
      findings.push(message);
    } else {
      console.log(`warning: ${message}`);
    }
  }
  if (findings.length > 0) {
    console.error(`forbidden-terms check FAILED (${findings.length}):\n  ${findings.join("\n  ")}`);
    process.exit(1);
  }
  console.log(
    `forbidden-terms check passed: ${files.length} files scanned, ${terms.length} private terms applied`,
  );
}
