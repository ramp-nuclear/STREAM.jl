// sourceValueEntry.ts — Plan 63.1-14 GAP-RC-4 BC-mode parity follow-up.
//
// Discriminated union for the value parameter on Sources-category components
// (currently WallTemperature.T_wall and HeatFluxSource.q). Narrower than
// BCModeEntry: no `mark` arm (a source cannot mark; mark is a consumer-side
// surrogate for hand-wired bindings), no `source` arm (a source cannot bind
// to another source).
//
// Profile and Function arms are intentionally structurally identical to the
// corresponding BCModeEntry arms so the extracted ProfileModeEditor /
// FunctionModeEditor in modeEditors.tsx work for both surfaces without a
// type adapter.

export type SourceValueEntry =
  | { mode: "value"; value: number }
  | { mode: "profile"; preset: "cosine"; amplitude: number; peakingFactor: number }
  | { mode: "profile"; preset: "file"; path: string }
  | { mode: "function"; signature: "fn(t)" | "fn(t, i)"; functionName: string };

export function isSourceValueEntry(v: unknown): v is SourceValueEntry {
  if (typeof v !== "object" || v === null) return false;
  const m = (v as { mode?: unknown }).mode;
  if (m === "value") return typeof (v as { value?: unknown }).value === "number";
  if (m === "profile") {
    const p = (v as { preset?: unknown }).preset;
    if (p === "cosine") {
      return (
        typeof (v as { amplitude?: unknown }).amplitude === "number" &&
        typeof (v as { peakingFactor?: unknown }).peakingFactor === "number"
      );
    }
    if (p === "file") {
      return typeof (v as { path?: unknown }).path === "string";
    }
    return false;
  }
  if (m === "function") {
    const s = (v as { signature?: unknown }).signature;
    return (
      (s === "fn(t)" || s === "fn(t, i)") &&
      typeof (v as { functionName?: unknown }).functionName === "string"
    );
  }
  return false;
}

export function defaultSourceValueEntry(value: number): SourceValueEntry {
  return { mode: "value", value };
}
