#!/usr/bin/env node
// Second line of defence for packages/calc (docs/08 "CI enforcement", L7): a plain text check
// that fails the build if calculation code names a tenant, a segment, a profile pack, a customer
// or an identifier. ESLint (packages/calc/eslint.config.js) catches numeric and string literals;
// this catches names, even inside comments, because a comment that names a customer is the first
// step toward code that does.
//
//   node scripts/check-calc-literals.mjs [dir]       default: packages/calc/src
//   node scripts/check-calc-literals.mjs --self-test
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const ROOT = resolve(new URL("..", import.meta.url).pathname);
const DEFAULT_DIR = join(ROOT, "packages/calc/src");

const RULES = [
  ["tenant", /tenant/i],
  [
    "segment code",
    /\bs[123]_(private|government|federation)\b|\bs[123]\b(?=[ _-]?(segment|private|gov|fed))/i,
  ],
  ["segment word", /\b(private|government|federation)\b(?=[ _-]?(segment|co-?op|pack|profile))/i],
  ["profile pack", /\b(pnp|psmb|deped|lgu|corporate)\b/i],
  ["partner", /partner/i],
  ["uuid", /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i],
  ["environment or clock access", /process\.env|Date\.now|new Date|Math\.random/],
  ["floating point parse", /parseFloat|Number\.parseFloat/],
];

// The invariants file may document why it exists in general words; it still may not name tenants.
function walk(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    return statSync(path).isDirectory()
      ? walk(path)
      : /\.(ts|tsx|js|mjs)$/.test(name)
        ? [path]
        : [];
  });
}

export function scan(dir) {
  const findings = [];
  for (const file of walk(dir)) {
    readFileSync(file, "utf8")
      .split("\n")
      .forEach((line, index) => {
        for (const [label, pattern] of RULES) {
          if (pattern.test(line))
            findings.push(`${file.replace(`${ROOT}/`, "")}:${index + 1}: ${label}`);
        }
      });
  }
  return findings;
}

function selfTest() {
  const fixtures = join(ROOT, "scripts/fixtures/calc-violations");
  const found = scan(fixtures);
  const labels = new Set(found.map((f) => f.split(": ").pop()));
  const expected = RULES.map(([label]) => label);
  const missing = expected.filter((label) => !labels.has(label));
  if (missing.length > 0) {
    console.error(
      "calc-literals self-test FAILED: the fixture was not caught for:",
      missing.join(", "),
    );
    process.exit(1);
  }
  // and the real directory must still be scannable through the CLI path
  const cli = spawnSync(process.execPath, [new URL(import.meta.url).pathname, fixtures], {
    encoding: "utf8",
  });
  if (cli.status === 0) {
    console.error(
      "calc-literals self-test FAILED: the command exits 0 on a directory full of violations",
    );
    process.exit(1);
  }
  console.log(
    `calc-literals self-test passed (${expected.length} rules, ${found.length} violations caught)`,
  );
}

if (process.argv.includes("--self-test")) {
  selfTest();
} else {
  const dir = resolve(process.argv[2] ?? DEFAULT_DIR);
  const findings = scan(dir);
  if (findings.length > 0) {
    console.error(`calc-literals check FAILED (${findings.length}):\n  ${findings.join("\n  ")}`);
    process.exit(1);
  }
  console.log(
    `calc-literals check passed: ${walk(dir).length} files in ${dir.replace(`${ROOT}/`, "")}`,
  );
}
