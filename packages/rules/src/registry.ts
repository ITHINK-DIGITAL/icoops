import type { ZodType } from "zod";
import {
  calculationConventionsSchema,
  CALCULATION_CONVENTIONS_TYPE,
} from "./schemas/calculation_conventions.js";
import { RuleError } from "./types.js";
import type { Params } from "./types.js";

/** A rule type's calculation, used to run worked examples. Returns the outputs by name. */
export type ExampleHandler = (inputs: Params, params: Params) => Params;

export interface RuleTypeDefinition {
  readonly ruleType: string;
  readonly schemaVersion: number;
  readonly schema: ZodType<unknown>;
  /** Absent until the library exists (slice 2). A type without a handler cannot pass its examples. */
  readonly handler?: ExampleHandler;
}

export class RuleRegistry {
  private readonly types = new Map<string, RuleTypeDefinition>();

  register(definition: RuleTypeDefinition): this {
    if (this.types.has(definition.ruleType)) {
      throw new Error(`rule type already registered: ${definition.ruleType}`);
    }
    this.types.set(definition.ruleType, definition);
    return this;
  }

  get(ruleType: string): RuleTypeDefinition {
    const found = this.types.get(ruleType);
    if (!found) {
      throw new RuleError("unknown_rule_type", `unknown rule type: ${ruleType}`);
    }
    return found;
  }

  has(ruleType: string): boolean {
    return this.types.has(ruleType);
  }

  list(): readonly RuleTypeDefinition[] {
    return [...this.types.values()];
  }

  /** Validate a parameter set against the published schema. Throws; never defaults (L3). */
  validate(ruleType: string, schemaVersion: number, params: Params): Params {
    const definition = this.get(ruleType);
    if (definition.schemaVersion !== schemaVersion) {
      throw new RuleError(
        "schema_version_mismatch",
        `rule type ${ruleType} is at schema version ${definition.schemaVersion}, got ${schemaVersion}`,
      );
    }
    const parsed = definition.schema.safeParse(params);
    if (!parsed.success) {
      throw new RuleError(
        "invalid_params",
        `invalid parameters for ${ruleType}`,
        parsed.error.issues.map((issue) => `${issue.path.join(".") || "(root)"}: ${issue.message}`),
      );
    }
    return parsed.data as Params;
  }
}

/** The rule types published in slice 1. Calculation rule types are added with their libraries. */
export function createDefaultRegistry(): RuleRegistry {
  return new RuleRegistry().register({
    ruleType: CALCULATION_CONVENTIONS_TYPE,
    schemaVersion: 1,
    schema: calculationConventionsSchema,
  });
}
