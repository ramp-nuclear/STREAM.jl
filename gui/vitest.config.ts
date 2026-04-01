import { defineConfig } from "vitest/config";
import path from "path";

export default defineConfig({
  test: {
    // Use node environment by default -- jsdom has ESM incompatibility with
    // html-encoding-sniffer on Node.js 18. React component tests (added in later
    // phases) should add @vitest-environment jsdom docblock comment per-file.
    environment: "node",
    globals: true,
    setupFiles: ["./src/test-setup.ts"],
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
});
