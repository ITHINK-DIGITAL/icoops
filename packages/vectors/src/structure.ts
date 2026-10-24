import { CALCULATION_CONVENTIONS_TYPE, createDefaultRegistry } from "@icoops/rules";
import type { StarterFile } from "./schema.js";

export interface StructureReport {
  /** Problems that make the file unusable: the build fails. */
  readonly errors: string[];
  /** Gaps that will block activation of a rule version later: reported, not yet failing. */
  readonly warnings: string[];
}

const KINDS = ["normal", "boundary", "exception"] as const;

/** Paths of JSON numbers that are not integers: decimals must be strings (NF-012). */
function fractionalNumbers(value: unknown, path: string, found: string[]): void {
  if (typeof value === "number" && !Number.isInteger(value)) {
    found.push(path);
  } else if (Array.isArray(value)) {
    value.forEach((item, index) => fractionalNumbers(item, `${path}[${index}]`, found));
  } else if (typeof value === "object" && value !== null) {
    for (const [key, item] of Object.entries(value)) {
      fractionalNumbers(item, `${path}.${key}`, found);
    }
  }
}

export function checkStructure(file: StarterFile): StructureReport {
  const errors: string[] = [];
  const warnings: string[] = [];

  const seen = new Set<string>();
  for (const vector of file.vectors) {
    if (seen.has(vector.id)) {
      errors.push(`duplicate vector id ${vector.id}`);
    }
    seen.add(vector.id);
    const floats: string[] = [];
    fractionalNumbers(vector.inputs, `${vector.id}.inputs`, floats);
    fractionalNumbers(vector.expected, `${vector.id}.expected`, floats);
    for (const path of floats) {
      errors.push(`${path} is a JSON float; write decimals as strings`);
    }
  }

  const registry = createDefaultRegistry();
  try {
    registry.validate(CALCULATION_CONVENTIONS_TYPE, 1, file.parameter_defaults);
  } catch (error) {
    errors.push(
      `parameter_defaults do not satisfy the calculation_conventions schema: ${String(error)}`,
    );
  }

  // The activation gate needs one normal, one boundary and one exception example per rule version.
  const kindsByRule = new Map<string, Set<string>>();
  for (const vector of file.vectors) {
    const kinds = kindsByRule.get(vector.rule) ?? new Set<string>();
    kinds.add(vector.kind);
    kindsByRule.set(vector.rule, kinds);
  }
  for (const [rule, kinds] of kindsByRule) {
    const missing = KINDS.filter((kind) => !kinds.has(kind));
    if (missing.length > 0) {
      warnings.push(
        `${rule}: no ${missing.join(" or ")} example (the activation gate needs all three)`,
      );
    }
  }
  return { errors, warnings };
}
