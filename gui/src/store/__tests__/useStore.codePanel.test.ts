/**
 * Phase 66 Plan 03 Task 1 — useStore code-panel ephemeral slices.
 *
 * Tests the three new ephemeral slices and six actions that back the
 * Code panel hover-ring / pinning / canvas-jump-to-code flow:
 *
 *   hoveredSourceIds: Set<string>     (canvas hover ring driven by code-panel hover)
 *   pinnedSourceIds:  Set<string>     (canvas pin ring driven by sub-block click)
 *   pendingShowCodeFor: string[] | null
 *                                     (one-shot signal from stream:show-code-for
 *                                      consumed by CodePreview to scroll + flash)
 *
 *   setHoveredSourceIds(ids)         → fresh Set, replaces hover state
 *   clearHoveredSourceIds()          → empty Set, fresh ref
 *   togglePinnedForSubBlock(ids)     → D-10 overlap-toggle semantics
 *   clearPinnedSourceIds()           → empty Set, fresh ref
 *   setPendingShowCodeFor(ids)       → fresh array
 *   consumePendingShowCodeFor()      → returns + clears atomically
 *
 * Discipline (load-bearing — Pitfall 1):
 *   Every mutation produces a NEW Set / array reference. In-place mutation
 *   would cause Zustand shallow equality to miss the change and skip the
 *   re-render → hover/pin rings would never appear on canvas.
 *
 * .scp exclusion:
 *   The slices are session-only. They are NOT part of `serializeProject`'s
 *   args, so they cannot leak into `.scp` output. This test asserts the
 *   serialize output does not contain the new keys regardless of seed state.
 */

import { describe, it, expect, beforeEach } from "vitest";
import type { Node, Edge } from "@xyflow/react";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import useStore from "../useStore";
import { serializeProject } from "../../lib/projectIO";

beforeEach(() => {
  // Reset the three slices and isDirty to known clean state. Any other
  // store fields keep their defaults from the create() factory.
  useStore.setState({
    hoveredSourceIds: new Set<string>(),
    pinnedSourceIds: new Set<string>(),
    pendingShowCodeFor: null,
    isDirty: false,
  });
});

describe("useStore code-panel ephemeral slices — initial state", () => {
  it("hoveredSourceIds defaults to an empty Set", () => {
    expect(useStore.getState().hoveredSourceIds).toBeInstanceOf(Set);
    expect(useStore.getState().hoveredSourceIds.size).toBe(0);
  });

  it("pinnedSourceIds defaults to an empty Set", () => {
    expect(useStore.getState().pinnedSourceIds).toBeInstanceOf(Set);
    expect(useStore.getState().pinnedSourceIds.size).toBe(0);
  });

  it("pendingShowCodeFor defaults to null", () => {
    expect(useStore.getState().pendingShowCodeFor).toBeNull();
  });
});

describe("setHoveredSourceIds / clearHoveredSourceIds", () => {
  it("setHoveredSourceIds writes the given ids and produces a NEW Set reference (Pitfall 1)", () => {
    const before = useStore.getState().hoveredSourceIds;
    useStore.getState().setHoveredSourceIds(["a", "b", "c"]);
    const after = useStore.getState().hoveredSourceIds;

    expect(after).not.toBe(before);
    expect(after.has("a")).toBe(true);
    expect(after.has("b")).toBe(true);
    expect(after.has("c")).toBe(true);
    expect(after.size).toBe(3);
  });

  it("setHoveredSourceIds replaces (not merges) previous hover state", () => {
    useStore.getState().setHoveredSourceIds(["a", "b"]);
    useStore.getState().setHoveredSourceIds(["c"]);
    expect(useStore.getState().hoveredSourceIds.has("a")).toBe(false);
    expect(useStore.getState().hoveredSourceIds.has("c")).toBe(true);
    expect(useStore.getState().hoveredSourceIds.size).toBe(1);
  });

  it("clearHoveredSourceIds empties the Set and produces a fresh reference", () => {
    useStore.getState().setHoveredSourceIds(["a", "b"]);
    const before = useStore.getState().hoveredSourceIds;
    useStore.getState().clearHoveredSourceIds();
    const after = useStore.getState().hoveredSourceIds;

    expect(after).not.toBe(before);
    expect(after.size).toBe(0);
  });

  it("setHoveredSourceIds does not set isDirty (session-only state)", () => {
    expect(useStore.getState().isDirty).toBe(false);
    useStore.getState().setHoveredSourceIds(["a"]);
    expect(useStore.getState().isDirty).toBe(false);
  });
});

describe("togglePinnedForSubBlock — D-10 overlap-toggle semantics", () => {
  it("first call adds all ids to an empty pin set", () => {
    const before = useStore.getState().pinnedSourceIds;
    useStore.getState().togglePinnedForSubBlock(["a", "b"]);
    const after = useStore.getState().pinnedSourceIds;

    expect(after).not.toBe(before);
    expect(after.has("a")).toBe(true);
    expect(after.has("b")).toBe(true);
    expect(after.size).toBe(2);
  });

  it("calling twice on the same sub-block ids removes them (toggle off)", () => {
    useStore.getState().togglePinnedForSubBlock(["a", "b"]);
    useStore.getState().togglePinnedForSubBlock(["a", "b"]);
    expect(useStore.getState().pinnedSourceIds.size).toBe(0);
  });

  it("disjoint sub-blocks add additively (D-10 — pin set grows)", () => {
    useStore.getState().togglePinnedForSubBlock(["a", "b"]);
    useStore.getState().togglePinnedForSubBlock(["c", "d"]);
    const pins = useStore.getState().pinnedSourceIds;
    expect(pins.has("a")).toBe(true);
    expect(pins.has("b")).toBe(true);
    expect(pins.has("c")).toBe(true);
    expect(pins.has("d")).toBe(true);
    expect(pins.size).toBe(4);
  });

  it("partial overlap removes ALL ids of the second sub-block (D-10 overlap-removes-all)", () => {
    // {a, b} pinned. Click second sub-block {b, c}: 'b' overlaps → remove ALL of {b, c}.
    useStore.getState().togglePinnedForSubBlock(["a", "b"]);
    useStore.getState().togglePinnedForSubBlock(["b", "c"]);
    const pins = useStore.getState().pinnedSourceIds;
    expect(pins.has("a")).toBe(true);
    expect(pins.has("b")).toBe(false);
    expect(pins.has("c")).toBe(false);
    expect(pins.size).toBe(1);
  });

  it("every togglePinnedForSubBlock call produces a NEW Set reference (Pitfall 1)", () => {
    const before = useStore.getState().pinnedSourceIds;
    useStore.getState().togglePinnedForSubBlock(["a"]);
    const after1 = useStore.getState().pinnedSourceIds;
    expect(after1).not.toBe(before);

    useStore.getState().togglePinnedForSubBlock(["b"]);
    const after2 = useStore.getState().pinnedSourceIds;
    expect(after2).not.toBe(after1);
  });

  it("togglePinnedForSubBlock does not set isDirty (session-only state)", () => {
    expect(useStore.getState().isDirty).toBe(false);
    useStore.getState().togglePinnedForSubBlock(["a"]);
    expect(useStore.getState().isDirty).toBe(false);
  });
});

describe("clearPinnedSourceIds", () => {
  it("empties the pin Set and produces a fresh reference", () => {
    useStore.getState().togglePinnedForSubBlock(["a", "b", "c"]);
    const before = useStore.getState().pinnedSourceIds;
    useStore.getState().clearPinnedSourceIds();
    const after = useStore.getState().pinnedSourceIds;

    expect(after).not.toBe(before);
    expect(after.size).toBe(0);
  });

  it("clearing an already-empty pin set is idempotent (still fresh Set)", () => {
    const before = useStore.getState().pinnedSourceIds;
    useStore.getState().clearPinnedSourceIds();
    const after = useStore.getState().pinnedSourceIds;
    expect(after).not.toBe(before); // fresh ref
    expect(after.size).toBe(0);
  });
});

describe("setPendingShowCodeFor / consumePendingShowCodeFor — atomic one-shot", () => {
  it("setPendingShowCodeFor writes a fresh array (not the caller's reference)", () => {
    const input = ["a", "b"];
    useStore.getState().setPendingShowCodeFor(input);
    const stored = useStore.getState().pendingShowCodeFor;
    expect(stored).toEqual(["a", "b"]);
    expect(stored).not.toBe(input);
  });

  it("consumePendingShowCodeFor returns the ids and clears the slice (atomic)", () => {
    useStore.getState().setPendingShowCodeFor(["x", "y"]);
    const first = useStore.getState().consumePendingShowCodeFor();
    expect(first).toEqual(["x", "y"]);
    expect(useStore.getState().pendingShowCodeFor).toBeNull();
  });

  it("second consumePendingShowCodeFor returns null (already consumed)", () => {
    useStore.getState().setPendingShowCodeFor(["a"]);
    useStore.getState().consumePendingShowCodeFor();
    const second = useStore.getState().consumePendingShowCodeFor();
    expect(second).toBeNull();
  });

  it("consumePendingShowCodeFor on an unset slice returns null without throwing", () => {
    expect(useStore.getState().pendingShowCodeFor).toBeNull();
    expect(useStore.getState().consumePendingShowCodeFor()).toBeNull();
  });
});

describe(".scp exclusion — new slices never appear in serializeProject output", () => {
  it("serializeProject output JSON contains none of hoveredSourceIds, pinnedSourceIds, pendingShowCodeFor", () => {
    // Seed all three slices with non-empty values to make sure any accidental
    // bleed-through would be caught.
    useStore.getState().setHoveredSourceIds(["leak-h-1", "leak-h-2"]);
    useStore.getState().togglePinnedForSubBlock(["leak-p-1", "leak-p-2"]);
    useStore.getState().setPendingShowCodeFor(["leak-pending"]);

    const s = useStore.getState();
    const json = serializeProject({
      nodes: s.nodes as Node[],
      edges: s.edges as Edge[],
      anchors: s.anchors,
      resources: s.resources,
      modelOptions: s.modelOptions,
      activeLeftTab: s.activeLeftTab,
      activeLayer: s.activeLayer,
      snapToGrid: s.snapToGrid,
    });

    expect(json).not.toContain("hoveredSourceIds");
    expect(json).not.toContain("pinnedSourceIds");
    expect(json).not.toContain("pendingShowCodeFor");
    expect(json).not.toContain("leak-h-1");
    expect(json).not.toContain("leak-p-1");
    expect(json).not.toContain("leak-pending");
  });

  it("projectIO.ts source does not mention any of the new slice keys (defense in depth)", () => {
    const projectIOPath = resolve(__dirname, "..", "..", "lib", "projectIO.ts");
    const contents = readFileSync(projectIOPath, "utf-8");
    expect(contents).not.toMatch(/hoveredSourceIds/);
    expect(contents).not.toMatch(/pinnedSourceIds/);
    expect(contents).not.toMatch(/pendingShowCodeFor/);
  });
});
