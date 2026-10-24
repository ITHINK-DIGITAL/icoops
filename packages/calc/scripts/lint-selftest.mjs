// Self-test of the business-literal guard: a fixture full of violations MUST be rejected by the
// calc ESLint config. If this ever passes silently, the guard has died and the build fails.
import { ESLint } from "eslint";

const FIXTURE = `
import fs from "node:fs";
export const vat = 0.12;
export const rate = 12;
export const label = "regular";
export const now = new Date();
export const env = process.env.TENANT;
export const root = Math.sqrt(2);
export const asNumber = Number("1.5");
export const msg = \`tenant \${label}\`;
export default fs;
`;

const EXPECTED = [
  "no-magic-numbers",
  "no-restricted-syntax",
  "no-restricted-globals",
  "no-restricted-properties",
  "no-restricted-imports",
];

const eslint = new ESLint({ cwd: new URL("..", import.meta.url).pathname });
const [result] = await eslint.lintText(FIXTURE, { filePath: "src/__selftest__.ts" });
const fired = new Set(result.messages.map((m) => m.ruleId));
const missing = EXPECTED.filter((rule) => !fired.has(rule));

if (missing.length > 0) {
  console.error(
    "calc literal guard self-test FAILED. Rules that did not fire:",
    missing.join(", "),
  );
  console.error(
    "Messages seen:",
    result.messages.map((m) => `${m.ruleId}: ${m.message}`).join("\n  "),
  );
  process.exit(1);
}
console.log(
  `calc literal guard self-test passed (${result.messages.length} violations caught, ${EXPECTED.length} rules fired)`,
);
