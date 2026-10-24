import type { ExampleHandler } from "@icoops/rules";

/**
 * Calculation handlers by vector rule name. Empty in slice 1: the libraries arrive in slice 2,
 * which registers one handler per rule here. Until then every vector is reported as pending.
 */
export const HANDLERS: Readonly<Record<string, ExampleHandler>> = {};
