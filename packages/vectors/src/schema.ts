import { z } from "zod";

export const vectorSchema = z
  .object({
    id: z.string().min(1),
    rule: z.string().min(1),
    kind: z.enum(["normal", "boundary", "exception"]),
    inputs: z.record(z.string(), z.unknown()),
    expected: z.record(z.string(), z.unknown()),
    note: z.string(),
    segment: z.enum(["ALL", "S1", "S2", "S3"]),
    requires_flag: z.string().min(1).optional(),
  })
  .strict();

export const starterFileSchema = z
  .object({
    status: z.string(),
    conventions: z.record(z.string(), z.string()),
    vectors: z.array(vectorSchema).min(1),
    parameter_defaults: z.record(z.string(), z.unknown()),
  })
  .strict();

export type Vector = z.infer<typeof vectorSchema>;
export type StarterFile = z.infer<typeof starterFileSchema>;
