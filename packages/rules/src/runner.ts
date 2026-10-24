import Decimal from "decimal.js";
import type { RuleRegistry } from "./registry.js";
import type { Params } from "./types.js";

export interface Example {
  readonly id: string;
  readonly code: string;
  readonly kind: "normal" | "boundary" | "exception";
  readonly inputs: Params;
  readonly expected: Params;
}

export interface ExampleResult {
  readonly id: string;
  readonly code: string;
  readonly passed: boolean;
  readonly actual: Params | null;
  readonly diff: Record<string, { expected: unknown; actual: unknown }> | null;
}

const DECIMAL_LIKE = /^-?\d+(\.\d+)?$/;

/** Decimal strings compare by value ("1000" equals "1000.00"); everything else compares exactly. */
export function valuesEqual(expected: unknown, actual: unknown): boolean {
  if (typeof expected === "string" && typeof actual === "string") {
    if (DECIMAL_LIKE.test(expected) && DECIMAL_LIKE.test(actual)) {
      return new Decimal(expected).eq(new Decimal(actual));
    }
    return expected === actual;
  }
  if (Array.isArray(expected) && Array.isArray(actual)) {
    return (
      expected.length === actual.length &&
      expected.every((value, index) => valuesEqual(value, actual[index]))
    );
  }
  if (isRecord(expected) && isRecord(actual)) {
    const keys = Object.keys(expected);
    return (
      keys.length === Object.keys(actual).length &&
      keys.every((key) => key in actual && valuesEqual(expected[key], actual[key]))
    );
  }
  return expected === actual;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Every expected output must be present and equal; extra actual outputs are not an error. */
export function compareExpected(expected: Params, actual: Params): ExampleResult["diff"] {
  const diff: Record<string, { expected: unknown; actual: unknown }> = {};
  for (const [key, value] of Object.entries(expected)) {
    if (!(key in actual) || !valuesEqual(value, actual[key])) {
      diff[key] = { expected: value, actual: actual[key] };
    }
  }
  return Object.keys(diff).length === 0 ? null : diff;
}

/**
 * Run worked examples through the handler registered for the rule type. A rule type with no
 * handler, or a handler that throws, fails every example: nothing can pass by being unrunnable.
 */
export function runExamples(args: {
  readonly registry: RuleRegistry;
  readonly ruleType: string;
  readonly params: Params;
  readonly examples: readonly Example[];
}): ExampleResult[] {
  const { registry, ruleType, params, examples } = args;
  const handler = registry.get(ruleType).handler;
  return examples.map((example): ExampleResult => {
    if (!handler) {
      return fail(example, null, {
        handler: { expected: "a registered calculation", actual: "none" },
      });
    }
    try {
      const actual = handler(example.inputs, params);
      const diff = compareExpected(example.expected, actual);
      return { id: example.id, code: example.code, passed: diff === null, actual, diff };
    } catch (error) {
      return fail(example, null, { error: { expected: "a result", actual: String(error) } });
    }
  });
}

function fail(
  example: Example,
  actual: Params | null,
  diff: NonNullable<ExampleResult["diff"]>,
): ExampleResult {
  return { id: example.id, code: example.code, passed: false, actual, diff };
}
