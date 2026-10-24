import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { starterFileSchema } from "./schema.js";
import type { StarterFile } from "./schema.js";

/** docs/worked_examples/starter.json, relative to this package. */
export const STARTER_PATH = fileURLToPath(
  new URL("../../../docs/worked_examples/starter.json", import.meta.url),
);

export function loadStarter(path: string = STARTER_PATH): StarterFile {
  const parsed = starterFileSchema.safeParse(JSON.parse(readFileSync(path, "utf8")));
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("\n  ");
    throw new Error(`${path} does not match the vector schema:\n  ${issues}`);
  }
  return parsed.data;
}
