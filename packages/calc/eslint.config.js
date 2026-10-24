import { base } from "@icoops/config/eslint-base";
import tseslint from "typescript-eslint";

// Business-literal guard for calculation code (docs/08 "CI enforcement", NF-019).
// Allowed in src: 0, 1, and named constants from src/invariants.ts (reviewed by the owner).
// Everything a business could change is a parameter, never a literal.
const STRING_LITERAL =
  "Literal[raw=/^[\"'`]/]:not(ImportDeclaration > Literal):not(ExportNamedDeclaration > Literal):not(ExportAllDeclaration > Literal):not(TSLiteralType > Literal):not(BinaryExpression:has(> UnaryExpression[operator='typeof']) > Literal)";

export const calcRules = {
  "no-magic-numbers": [
    "error",
    { ignore: [0, 1], ignoreArrayIndexes: false, enforceConst: true, detectObjects: true },
  ],
  "no-restricted-syntax": [
    "error",
    {
      selector: STRING_LITERAL,
      message: "String literal in calculation code: use a parameter or a named invariant.",
    },
    {
      selector: "TemplateLiteral[quasis.length>1], TemplateLiteral[quasis.0.value.raw!='']",
      message: "Template literal in calculation code: build messages from named invariants.",
    },
  ],
  // Purity (L1) and decimal-only arithmetic (L4): no clock, environment, network or floats.
  "no-restricted-globals": [
    "error",
    ...[
      "Date",
      "process",
      "fetch",
      "Math",
      "Number",
      "parseFloat",
      "parseInt",
      "window",
      "document",
      "globalThis",
      "setTimeout",
      "setInterval",
      "crypto",
    ].map((name) => ({ name, message: "Not allowed in calculation code (purity or float risk)." })),
  ],
  "no-restricted-properties": [
    "error",
    { object: "Math", message: "Math.* uses floats; use the decimal library." },
    { object: "Number", message: "Number.* uses floats; use the decimal library." },
    { object: "Date", message: "The caller passes dates in; calculation code reads no clock." },
  ],
  "no-restricted-imports": [
    "error",
    {
      patterns: [
        {
          regex: "^(?!decimal\\.js$|@icoops/rules$|\\.{1,2}/).+",
          message:
            "Calculation code may import only decimal.js, type-only @icoops/rules, and local files.",
        },
      ],
    },
  ],
};

export default tseslint.config(
  ...base,
  { files: ["src/**/*.ts"], ignores: ["src/invariants.ts"], rules: calcRules },
  {
    // Invariants are the one place for named constants; the owner reviews every change.
    files: ["src/invariants.ts"],
    rules: { "no-magic-numbers": "off", "no-restricted-syntax": "off" },
  },
  {
    // The guard is for library code; tests and scripts may use literals freely.
    files: ["test/**/*.ts", "scripts/**/*.mjs"],
    languageOptions: { globals: { process: "readonly", console: "readonly", URL: "readonly" } },
  },
);
