// CommandPalette.tsx — Phase 69 Plan 02 — Ctrl+P jump-only palette.
//
// Controlled component (open + onOpenChange props). App.tsx (Plan 03) owns
// the local open state and the Ctrl+P shortcut wiring. This file does NOT
// register any global keydown handler and does NOT add a `paletteOpen` slice
// to zustand — palette open/closed is transient UI per CONTEXT.md
// <code_context> ("No new top-level state slices for transient UI"), mirroring
// the UnsavedChangesDialog pattern.
//
// Layout / decisions (CONTEXT.md):
//   D-02  top-anchored radix Dialog (~80px from top, ~640px wide, internal
//         scroll capped at 480px max-height). The shim's canonical
//         max-h-[400px] baseline is overridden via the className prop on
//         <CommandList>; tailwind-merge (via cn()) resolves the higher
//         max-h-[480px] override.
//   D-03  Forgiving off-layer handling: selecting an item that lives on an
//         off layer auto-enables that layer BEFORE setCenter + selectNode.
//   D-04  setCenter + zoom floor: max(getZoom(), ZOOM_MIN_LEGIBLE = 0.75),
//         duration 250ms. getZoom() is called inline (not captured at
//         component top-level) so it reads current viewport zoom at click
//         time, not a stale closure value.
//   D-05  Project Options is a single sentinel row (D-05 deferral of per-field
//         anchoring to Phase 72). On select → setActiveLeftTab("Project") +
//         clearSelection.
//   D-06  Jump-to-resource: setActiveLeftTab("Resources") + selectResource;
//         ResourcesTreePanel's Plan-01 useEffect handles scrollIntoView.
//   D-07  No matched-character highlighting in v1 (deferred to Phase 72).
//         Row names are plain text — the search query is never threaded down
//         to a custom highlight renderer.
//   D-08  Off-layer hint chip uses the per-layer accent color from
//         LayersPanel.LAYER_COLORS (Hydraulic blue / Thermal amber /
//         Sources violet / ReactorPhysics rose). Per Plan 01's audit note,
//         these constants are duplicated here rather than re-exported from
//         LayersPanel — consolidation is a Phase 72 design-system concern.
//
// Pitfalls actively avoided (RESEARCH.md):
//   - Pitfall 2 (useReactFlow outside provider): App.tsx and the test wrapper
//     both mount this component inside a <ReactFlowProvider>.
//   - Pitfall 7 (stale zoom): getZoom() is called inline inside handleSelect.
//   - Pitfall 8 (search-pool churn during drag): conditional `if (!open)
//     return null` early-exits so buildSearchPool's useMemo dependency only
//     re-evaluates while the palette is mounted/visible.

import * as React from "react";
import { Box, Library, Settings2 } from "lucide-react";
import { useReactFlow } from "@xyflow/react";

import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
import { cn } from "@/lib/utils";
import {
  buildSearchPool,
  type SearchItem,
} from "@/lib/commandPalette/searchPool";
import { getComponentLayers, type LayerKey } from "@/lib/layers";
import useStore from "@/store/useStore";

// D-04 — zoom floor for setCenter. 0.75 is the research-recommended starting
// value based on StreamNode.tsx's text-sm (14px) label rendering at ~10.5px
// screen-pixels at zoom 0.75 (still legible). UAT-tunable.
const ZOOM_MIN_LEGIBLE = 0.75;

// D-08 — per-layer accent palette. Copied verbatim from LayersPanel.tsx
// (LAYER_COLORS / LAYER_LABELS). LayersPanel deliberately does NOT export
// these — the duplication is a documented Phase 72 design-system
// consolidation target. Keeping them local to each consumer for now per the
// note in LayersPanel.tsx.
const LAYER_COLORS: Record<LayerKey, string> = {
  Hydraulic: "#3b82f6",
  Thermal: "#f59e0b",
  Sources: "#8b5cf6",
  ReactorPhysics: "#f43f5e",
};
const LAYER_LABELS: Record<LayerKey, string> = {
  Hydraulic: "Hydraulic",
  Thermal: "Thermal",
  Sources: "Sources",
  ReactorPhysics: "Reactor Physics",
};

// Cap of how many rows the flat (typed-input) list renders. Browse mode
// (empty input) shows all items grouped by kind. Per CONTEXT.md
// Claude's Discretion: "Max results shown with typed input: ~50".
const FLAT_LIST_CAP = 50;

interface CommandPaletteProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export default function CommandPalette(
  props: CommandPaletteProps,
): React.JSX.Element | null {
  const { open, onOpenChange } = props;

  // Pitfall 8: don't even build the pool / subscribe to nodes when palette
  // is closed. App.tsx may render <CommandPalette open={false} /> permanently
  // for state ownership; the cheap early-exit keeps node-drag updates from
  // triggering buildSearchPool churn.
  if (!open) return null;

  return <CommandPaletteInner open={open} onOpenChange={onOpenChange} />;
}

function CommandPaletteInner({
  open,
  onOpenChange,
}: CommandPaletteProps): React.JSX.Element {
  const nodes = useStore((s) => s.nodes);
  const resources = useStore((s) => s.resources);
  const activeLayers = useStore((s) => s.activeLayers);
  const setLayerVisible = useStore((s) => s.setLayerVisible);
  const selectNode = useStore((s) => s.selectNode);
  const selectResource = useStore((s) => s.selectResource);
  const setActiveLeftTab = useStore((s) => s.setActiveLeftTab);
  const clearSelection = useStore((s) => s.clearSelection);

  // Pitfall 2: useReactFlow requires a parent ReactFlowProvider — App.tsx
  // (and the test wrapper) always provides one.
  const { setCenter, getZoom } = useReactFlow();

  const items = React.useMemo(
    () => buildSearchPool(nodes, resources),
    [nodes, resources],
  );

  const [search, setSearch] = React.useState("");

  function handleSelect(item: SearchItem): void {
    if (item.kind === "component") {
      // D-03: auto-enable any off layers the component lives on, BEFORE the
      // pan/select runs. Multiple off layers are enabled in turn.
      const layers = getComponentLayers(item.comp);
      for (const k of layers) {
        if (!activeLayers[k]) setLayerVisible(k, true);
      }
      // D-04: setCenter + zoom floor. getZoom() is called inline (not stored
      // beforehand) so the current viewport zoom drives the floor calc and
      // the verify grep gate `Math.max(getZoom()` matches literally.
      setCenter(item.node.position.x, item.node.position.y, {
        zoom: Math.max(getZoom(), ZOOM_MIN_LEGIBLE),
        duration: 250,
      });
      selectNode(item.id);
    } else if (
      item.kind === "geometry" ||
      item.kind === "powerShape" ||
      item.kind === "fluid"
    ) {
      // D-06: switch tab + select; ResourcesTreePanel's Plan-01 useEffect
      // does the scrollIntoView.
      setActiveLeftTab("Resources");
      selectResource(item.uuid, item.kind);
    } else {
      // D-05: Project Options is a single sentinel row.
      setActiveLeftTab("Project");
      clearSelection();
    }
    onOpenChange(false);
    // Reset search last so re-opening the palette starts in browse mode.
    setSearch("");
  }

  // Group items by kind for browse mode (empty input). Order matches the
  // CONTEXT.md "browse-mode" canonical order: Components, Geometries, Power
  // Shapes, Fluids, Project.
  const grouped = React.useMemo(() => {
    const components: SearchItem[] = [];
    const geometries: SearchItem[] = [];
    const powerShapes: SearchItem[] = [];
    const fluids: SearchItem[] = [];
    const project: SearchItem[] = [];
    for (const it of items) {
      switch (it.kind) {
        case "component":
          components.push(it);
          break;
        case "geometry":
          geometries.push(it);
          break;
        case "powerShape":
          powerShapes.push(it);
          break;
        case "fluid":
          fluids.push(it);
          break;
        case "modelOptions":
          project.push(it);
          break;
      }
    }
    return { components, geometries, powerShapes, fluids, project };
  }, [items]);

  const isBrowseMode = search.length === 0;
  const flatItems = isBrowseMode ? items : items.slice(0, FLAT_LIST_CAP);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        showCloseButton={false}
        className={cn(
          // D-02: top-anchored override. Cancels DialogContent's default
          // top-[50%] translate-y-[-50%] centering via two higher-priority
          // utilities (tailwind-merge keeps the later ones).
          "top-[80px] translate-y-0",
          // ~640px on >sm; full viewport (minus inset) below sm.
          "w-[640px] max-w-[calc(100%-2rem)] sm:max-w-[640px]",
          // Strip DialogContent's default padding/gap so the cmdk Command
          // owns the inner box.
          "p-0 gap-0 overflow-hidden",
          "rounded-lg shadow-xl",
        )}
        data-testid="command-palette-content"
      >
        {/* Screen-reader-only title/description — radix Dialog requires a
            title for a11y; we hide it visually because cmdk's input is the
            visible label. */}
        <DialogHeader className="sr-only">
          <DialogTitle>Command Palette</DialogTitle>
          <DialogDescription>
            Jump to component or resource
          </DialogDescription>
        </DialogHeader>
        <Command label="Jump to component or resource">
          <CommandInput
            value={search}
            onValueChange={setSearch}
            placeholder="Type to search components and resources..."
          />
          {/* D-02: max-h-[480px] override of the shim's canonical
              max-h-[400px] baseline. tailwind-merge resolves the override. */}
          <CommandList className="max-h-[480px]">
            <CommandEmpty>No matches.</CommandEmpty>
            {isBrowseMode ? (
              <BrowseGroups
                grouped={grouped}
                activeLayers={activeLayers}
                onSelect={handleSelect}
              />
            ) : (
              <FlatList
                items={flatItems}
                activeLayers={activeLayers}
                onSelect={handleSelect}
              />
            )}
          </CommandList>
        </Command>
      </DialogContent>
    </Dialog>
  );
}

// ---------------------------------------------------------------------------
// BrowseGroups — empty-input mode. One <CommandGroup> per non-empty kind.
// ---------------------------------------------------------------------------

interface BrowseGroupsProps {
  grouped: {
    components: SearchItem[];
    geometries: SearchItem[];
    powerShapes: SearchItem[];
    fluids: SearchItem[];
    project: SearchItem[];
  };
  activeLayers: Record<LayerKey, boolean>;
  onSelect: (item: SearchItem) => void;
}

function BrowseGroups({
  grouped,
  activeLayers,
  onSelect,
}: BrowseGroupsProps): React.JSX.Element {
  return (
    <>
      {grouped.components.length > 0 && (
        <CommandGroup heading="Components">
          {grouped.components.map((it) => (
            <RenderItem
              key={it.id}
              item={it}
              activeLayers={activeLayers}
              onSelect={onSelect}
            />
          ))}
        </CommandGroup>
      )}
      {grouped.geometries.length > 0 && (
        <CommandGroup heading="Geometries">
          {grouped.geometries.map((it) => (
            <RenderItem
              key={it.id}
              item={it}
              activeLayers={activeLayers}
              onSelect={onSelect}
            />
          ))}
        </CommandGroup>
      )}
      {grouped.powerShapes.length > 0 && (
        <CommandGroup heading="Power Shapes">
          {grouped.powerShapes.map((it) => (
            <RenderItem
              key={it.id}
              item={it}
              activeLayers={activeLayers}
              onSelect={onSelect}
            />
          ))}
        </CommandGroup>
      )}
      {grouped.fluids.length > 0 && (
        <CommandGroup heading="Fluids">
          {grouped.fluids.map((it) => (
            <RenderItem
              key={it.id}
              item={it}
              activeLayers={activeLayers}
              onSelect={onSelect}
            />
          ))}
        </CommandGroup>
      )}
      {grouped.project.length > 0 && (
        <CommandGroup heading="Project">
          {grouped.project.map((it) => (
            <RenderItem
              key={it.id}
              item={it}
              activeLayers={activeLayers}
              onSelect={onSelect}
            />
          ))}
        </CommandGroup>
      )}
    </>
  );
}

// ---------------------------------------------------------------------------
// FlatList — typed-input mode. No group headers; cmdk's command-score does
// the filtering. Cap at FLAT_LIST_CAP rows.
// ---------------------------------------------------------------------------

interface FlatListProps {
  items: SearchItem[];
  activeLayers: Record<LayerKey, boolean>;
  onSelect: (item: SearchItem) => void;
}

function FlatList({
  items,
  activeLayers,
  onSelect,
}: FlatListProps): React.JSX.Element {
  return (
    <CommandGroup>
      {items.map((it) => (
        <RenderItem
          key={it.id}
          item={it}
          activeLayers={activeLayers}
          onSelect={onSelect}
        />
      ))}
    </CommandGroup>
  );
}

// ---------------------------------------------------------------------------
// RenderItem — per-kind row. Kind icon + name + (component only) typeLabel
// + (component only, when any layer off) inline accent-tinted chip.
// ---------------------------------------------------------------------------

interface RenderItemProps {
  item: SearchItem;
  activeLayers: Record<LayerKey, boolean>;
  onSelect: (item: SearchItem) => void;
}

function RenderItem({
  item,
  activeLayers,
  onSelect,
}: RenderItemProps): React.JSX.Element {
  // cmdk's filter scores the `value` prop against the input. For components
  // we concatenate name + typeLabel so the user can type either. For Project
  // Options we add "Model Options" tokens so the historical name still
  // matches.
  switch (item.kind) {
    case "component": {
      const offLayers = getComponentLayers(item.comp).filter(
        (k) => !activeLayers[k],
      );
      return (
        <CommandItem
          value={`${item.name} ${item.typeLabel}`}
          onSelect={() => onSelect(item)}
          data-testid={`cmdk-row-component-${item.id}`}
        >
          <Box />
          <span className="font-medium">{item.name}</span>
          <span className="text-xs text-muted-foreground ml-1">
            {item.typeLabel}
          </span>
          {offLayers.length > 0 && (
            <span className="ml-auto flex items-center gap-1">
              {offLayers.map((k) => (
                <span
                  key={k}
                  data-testid={`off-layer-chip-${k}`}
                  className="rounded-sm border px-1.5 py-0.5 text-[10px] font-medium"
                  style={{
                    borderColor: LAYER_COLORS[k],
                    color: LAYER_COLORS[k],
                  }}
                >
                  {LAYER_LABELS[k]} off — will enable
                </span>
              ))}
            </span>
          )}
        </CommandItem>
      );
    }
    case "geometry":
    case "powerShape":
    case "fluid": {
      return (
        <CommandItem
          value={item.name}
          onSelect={() => onSelect(item)}
          data-testid={`cmdk-row-${item.kind}-${item.uuid}`}
        >
          <Library />
          <span>{item.name}</span>
        </CommandItem>
      );
    }
    case "modelOptions": {
      return (
        <CommandItem
          value="Project Options Model Options"
          onSelect={() => onSelect(item)}
          data-testid="cmdk-row-modelOptions"
        >
          <Settings2 />
          <span>Project Options</span>
        </CommandItem>
      );
    }
  }
}
