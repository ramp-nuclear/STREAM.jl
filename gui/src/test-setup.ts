// Polyfill crypto.randomUUID for vitest node environment
// (Node.js has crypto module but vitest doesn't always expose it as a global)
import { randomUUID } from "node:crypto";

if (!globalThis.crypto) {
  // @ts-expect-error -- partial polyfill is sufficient for tests
  globalThis.crypto = { randomUUID };
} else if (!globalThis.crypto.randomUUID) {
  globalThis.crypto.randomUUID = randomUUID;
}
