// anchors.ts — Phase 63.1: shared pressure-anchor types (D-02).
//
// Zero React dependencies, zero zustand dependencies, zero ReactFlow imports.
// This module is consumed by:
//   - gui/src/store/useStore.ts        (the anchors slice + setAnchor/clearAnchor; Plan 03)
//   - gui/src/lib/codeGenerator.ts     (anchors emission loop; Plan 04)
//   - gui/src/lib/projectIO.ts         (StreamProject schema; Plan 03)
//   - gui/src/components/sidebar/AnchorsSection.tsx (sidebar UI; Plan 06)
//   - gui/src/components/StreamNode.tsx (canvas anchor indicator; Plan 08)
//
// Sentinel-via-absence (D-02): `anchors[nodeId] === undefined` is the canonical
// "no anchor on that component" sentinel. There is NO `{kind: "unset"}` entry.
// At-most-one-per-node — re-assigning to the same nodeId overwrites. Mirrors
// the bcMode.ts D-09 idiom: presence-or-absence is the discriminator, no
// dedicated unset record.
//
// D-01 restriction: AnchorEntry models a *pressure anchor only* — `portField`
// is locked to `"port_in.P" | "port_out.P"`. No other anchor type (gravity
// reference, transient initial condition) can be represented or persisted in
// this phase. Gravity stays a per-component property via Gravity(H) (unchanged);
// transient ICs continue to source from steady_state_guess (unchanged).

// ---------------------------------------------------------------------------
// AnchorEntry — per-node pressure-anchor record (D-02)
// ---------------------------------------------------------------------------

/** A single pressure anchor on one node. The store slice is
 *  `anchors: Record<nodeId, AnchorEntry>`; at most one entry per nodeId
 *  (D-02 at-most-one semantics). */
export interface AnchorEntry {
  portField: "port_in.P" | "port_out.P";
  value: number;
}

/** Codegen-input shape: the anchors slice passed by value into generateCode
 *  (Plan 04). Mirrors the CodegenBCsState idiom in codeGenerator.ts:83-86 —
 *  types-only state shape, no store import. */
export interface CodegenAnchorsState {
  anchors: Record<string, AnchorEntry>;
}
