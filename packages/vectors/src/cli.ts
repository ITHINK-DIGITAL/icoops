// CI entry point: validate starter.json and run every vector that has a handler.
//   pnpm --filter @icoops/vectors run test:vectors            (slice 1: pending vectors reported)
//   VECTORS_STRICT=1 pnpm --filter @icoops/vectors run test:vectors   (slice 2+: pending fails)
import { HANDLERS } from "./handlers.js";
import { loadStarter } from "./load.js";
import { runVectors } from "./run.js";
import { checkStructure } from "./structure.js";

const strict = process.env.VECTORS_STRICT === "1";
const file = loadStarter();
const structure = checkStructure(file);
const report = runVectors(file, HANDLERS);

console.log(`starter.json: ${file.vectors.length} vectors (${file.status})`);
for (const warning of structure.warnings) {
  console.log(`  warning: ${warning}`);
}
for (const error of structure.errors) {
  console.error(`  ERROR: ${error}`);
}
for (const result of report.results.filter((r) => r.status === "fail")) {
  console.error(`  FAIL ${result.id} (${result.rule}): ${result.detail}`);
}
const { pass, fail, pending } = report.counts;
console.log(
  `result: ${pass} passed, ${fail} failed, ${pending} pending (strict mode ${strict ? "on" : "off"})`,
);

if (structure.errors.length > 0 || fail > 0 || (strict && pending > 0)) {
  process.exit(1);
}
if (pending > 0) {
  console.log(
    "pending vectors have no calculation yet; they must all pass from slice 2 (VECTORS_STRICT=1)",
  );
}
