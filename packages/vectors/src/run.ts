import { compareExpected } from "@icoops/rules";
import type { ExampleHandler, Params } from "@icoops/rules";
import type { StarterFile, Vector } from "./schema.js";

export type VectorStatus = "pass" | "fail" | "pending";

export interface VectorResult {
  readonly id: string;
  readonly rule: string;
  readonly status: VectorStatus;
  readonly detail: string;
}

export interface VectorReport {
  readonly results: VectorResult[];
  readonly counts: Record<VectorStatus, number>;
}

/** A vector's "expected.note" is commentary, not an output (see docs/05). */
function expectedOutputs(vector: Vector): Params {
  const { note: _note, ...outputs } = vector.expected;
  return outputs;
}

/**
 * Run every vector through the handler registered for its rule, with the file's default
 * parameters. A vector with no handler is "pending": from slice 2 on, pending fails the build.
 */
export function runVectors(
  file: StarterFile,
  handlers: Readonly<Record<string, ExampleHandler>>,
): VectorReport {
  const results = file.vectors.map((vector): VectorResult => {
    const handler = handlers[vector.rule];
    if (!handler) {
      return {
        id: vector.id,
        rule: vector.rule,
        status: "pending",
        detail: "no calculation registered yet",
      };
    }
    try {
      const diff = compareExpected(
        expectedOutputs(vector),
        handler(vector.inputs, file.parameter_defaults),
      );
      return diff === null
        ? { id: vector.id, rule: vector.rule, status: "pass", detail: "" }
        : { id: vector.id, rule: vector.rule, status: "fail", detail: JSON.stringify(diff) };
    } catch (error) {
      return {
        id: vector.id,
        rule: vector.rule,
        status: "fail",
        detail: `threw: ${String(error)}`,
      };
    }
  });
  const counts: Record<VectorStatus, number> = { pass: 0, fail: 0, pending: 0 };
  for (const result of results) {
    counts[result.status] += 1;
  }
  return { results, counts };
}
