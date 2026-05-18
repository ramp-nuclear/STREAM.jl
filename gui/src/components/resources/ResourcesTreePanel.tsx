import { useEffect, useRef, useState } from "react";
import useStore, { SENTINEL_UNSET_POWER_SHAPE } from "@/store/useStore";
import { Input } from "@/components/ui/input";
import { ScrollArea } from "@/components/ui/scroll-area";
import ResourceGroupHeader from "./ResourceGroupHeader";
import ResourceRow from "./ResourceRow";

// Phase 62 Plan 62-06 — Resources tab body.
//
// Hand-rolled `<ul>`-based tree per CD-01 (NOT react-arborist). Three group
// headers GEOMETRIES / POWER SHAPES / FLUIDS, each with a trailing `+`
// button (Fluids' is disabled per D-03 + UI-SPEC). A top search box does
// case-insensitive substring matching across all three groups. Empty
// groups post-filter collapse to the locked `(none yet — click +)`
// placeholder line.
//
// The sentinel PowerShape (uuid SENTINEL_UNSET_POWER_SHAPE) is filtered out
// of the visible tree per D-26 — it only lives as the fixed top entry in
// the field-level reference picker (62-08).
//
// The `+` button handler is a stub until 62-08 ships the shared `+ New…`
// popover. See the plan's `<integration_seam_for_popover_creation>` for
// the rationale (strategy 2 — local popover per consumer).
//
// Keyboard arrow-key navigation across rows (Up/Down/Home/End on
// role="treeitem") is intentionally deferred per UI-SPEC §"Inside Resources
// tab — keyboard nav after switch" (CD-01 leeway). Default to Tab-only nav
// for v1.

export default function ResourcesTreePanel() {
  const [searchQuery, setSearchQuery] = useState("");

  const resources = useStore((s) => s.resources);
  const selectedResourceId = useStore((s) => s.selectedResourceId);
  const selectedResourceKind = useStore((s) => s.selectedResourceKind);

  // Phase 69 D-06 — scroll the selected ResourceRow into view when
  // `selectedResourceId`/`selectedResourceKind` change (e.g., the user picked
  // a resource via Ctrl+P). The mechanism is purely DOM-side: no new store
  // slice, no expand-state slice — D-06 explicitly forbids that. We query the
  // matching ResourceRow by its existing `data-resource-uuid` /
  // `data-resource-kind` attributes (already emitted by ResourceRow.tsx) and
  // call scrollIntoView with `{ block: "center", behavior: "smooth" }`.
  //
  // Single retry via requestAnimationFrame handles the mount race when the
  // user is on a different left tab at selection time and the Resources panel
  // hasn't rendered yet. We deliberately don't loop — a missing row after one
  // RAF means the row genuinely isn't in the DOM (e.g., filtered out by the
  // search box).
  const panelRootRef = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    if (selectedResourceId == null || selectedResourceKind == null) return;

    function scrollTarget(): boolean {
      const root = panelRootRef.current;
      if (!root) return false;
      const el = root.querySelector<HTMLElement>(
        `[data-resource-uuid="${selectedResourceId}"][data-resource-kind="${selectedResourceKind}"]`,
      );
      if (!el) return false;
      el.scrollIntoView({ block: "center", behavior: "smooth" });
      return true;
    }

    if (!scrollTarget()) {
      const raf = requestAnimationFrame(() => {
        scrollTarget();
      });
      return () => cancelAnimationFrame(raf);
    }
  }, [selectedResourceId, selectedResourceKind]);

  const q = searchQuery.toLowerCase();

  const geometries = Object.values(resources.geometries).filter((g) =>
    g.name.toLowerCase().includes(q),
  );
  const powerShapes = Object.values(resources.powerShapes)
    // D-26: sentinel never appears in the visible tree.
    .filter((p) => p.uuid !== SENTINEL_UNSET_POWER_SHAPE)
    .filter((p) => p.name.toLowerCase().includes(q));
  const fluids = Object.values(resources.fluids).filter((f) =>
    f.name.toLowerCase().includes(q),
  );

  // TODO(62-08): replace the console.log stubs with the shared `+ New…`
  // popover handler. The plan's <integration_seam_for_popover_creation>
  // picks strategy 2 (local popover per consumer) — this component will
  // own its own Popover instance and render <GeometryResourceEditor> /
  // <PowerShapeResourceEditor> inside.
  function handleAddGeometry() {
    console.log("[ResourcesTreePanel] create resource kind=geometry — popover coming in 62-08");
  }
  function handleAddPowerShape() {
    console.log("[ResourcesTreePanel] create resource kind=powerShape — popover coming in 62-08");
  }
  function handleAddFluid() {
    // Disabled in Phase 62; never called (the button is disabled in
    // ResourceGroupHeader). This stub exists only to satisfy TypeScript's
    // prop typing.
  }

  return (
    <div ref={panelRootRef} className="h-full flex flex-col">
      <div className="px-[8px] py-[8px] border-b">
        <Input
          type="text"
          placeholder="Search resources…"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          aria-label="Search resources"
          className="h-[28px] text-[13px]"
        />
      </div>
      <ScrollArea className="flex-1 min-h-0">
        <ul role="tree" className="pb-[8px]">
          {/* GEOMETRIES group */}
          <li role="none">
            <ResourceGroupHeader
              label="Geometries"
              addAriaLabel="Add geometry"
              onAdd={handleAddGeometry}
              resourceKind="geometry"
            />
            <ul role="group" className="mt-[2px]">
              {geometries.length === 0 ? (
                <li className="text-[12px] italic text-muted-foreground pl-[8px]">
                  (none yet — click +)
                </li>
              ) : (
                geometries.map((g) => (
                  <ResourceRow
                    key={g.uuid}
                    resource={g}
                    kind="geometry"
                    isSelected={
                      selectedResourceKind === "geometry" &&
                      selectedResourceId === g.uuid
                    }
                  />
                ))
              )}
            </ul>
          </li>

          {/* POWER SHAPES group */}
          <li role="none">
            <ResourceGroupHeader
              label="Power Shapes"
              addAriaLabel="Add power shape"
              onAdd={handleAddPowerShape}
              resourceKind="powerShape"
            />
            <ul role="group" className="mt-[2px]">
              {powerShapes.length === 0 ? (
                <li className="text-[12px] italic text-muted-foreground pl-[8px]">
                  (none yet — click +)
                </li>
              ) : (
                powerShapes.map((p) => (
                  <ResourceRow
                    key={p.uuid}
                    resource={p}
                    kind="powerShape"
                    isSelected={
                      selectedResourceKind === "powerShape" &&
                      selectedResourceId === p.uuid
                    }
                  />
                ))
              )}
            </ul>
          </li>

          {/* FLUIDS group */}
          <li role="none">
            <ResourceGroupHeader
              label="Fluids"
              addAriaLabel="Add fluid"
              onAdd={handleAddFluid}
              disabled
              disabledTooltip="Multiple fluids not yet supported."
            />
            <ul role="group" className="mt-[2px]">
              {fluids.length === 0 ? (
                <li className="text-[12px] italic text-muted-foreground pl-[8px]">
                  (none yet — click +)
                </li>
              ) : (
                fluids.map((f) => (
                  <ResourceRow
                    key={f.uuid}
                    resource={f}
                    kind="fluid"
                    isSelected={
                      selectedResourceKind === "fluid" &&
                      selectedResourceId === f.uuid
                    }
                  />
                ))
              )}
            </ul>
          </li>
        </ul>
      </ScrollArea>
    </div>
  );
}
