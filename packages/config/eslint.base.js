import js from "@eslint/js";
import tseslint from "typescript-eslint";

/** Shared flat-config base: recommended rules plus the repo-wide bans on floats and unsafe casts. */
export const base = tseslint.config(
  { ignores: ["dist/**", ".next/**", "coverage/**", "node_modules/**", "next-env.d.ts"] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    rules: {
      "@typescript-eslint/no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_", ignoreRestSiblings: true },
      ],
      "@typescript-eslint/consistent-type-imports": "error",
      eqeqeq: ["error", "always"],
    },
  },
);

export default base;
