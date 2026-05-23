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
import { Box, EyeOff, Library, Settings2 } from "lucide-react";
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
import {
  SHORTCUT_GROUP_ORDER,
  SHORTCUTS_CATALOG,
  type ShortcutEntry,
  type ShortcutGroup,
} from "@/lib/shortcuts";
import useStore from "@/store/useStore";

export type CommandPaletteMode = "commands" | "shortcuts";

// D-04 — zoom floor for setCenter. Started at the research-recommended 0.75
// (StreamNode.tsx text-sm labels render at ~10.5px screen-px at z=0.75) but
// UAT round 1 found it still too small to read comfortably, so bumped to 1.0
// — labels at full size, no scaling tax on the eye.
const ZOOM_MIN_LEGIBLE = 1.0;

// D-08 originally specified per-layer accent colors here too, but the
// post-UAT redesign replaced the colored chip/dot with the same muted-gray
// EyeOff icon used by LayersPanel so the palette shares one visual
// vocabulary with the rest of the app. Per-layer color is no longer
// surfaced in the palette — the tooltip names the layer in plain text.
const LAYER_LABELS: Record<LayerKey, string> = {
  Hydraulic: "Hydraulic",
  Thermal: "Thermal",
  Sources: "Sources",
  ReactorPhysics: "Reactor Physics",
};

// Category taxonomy for both browse-mode order and typed-mode reorder-by-
// best-match. Mid-UAT change from plan-02's "typed mode = flat list":
// keeping headers in typed mode preserves the meaningful category context
// of this app (component vs resource is a real distinction users care
// about), and reordering by best-score-per-group avoids the only real cost
// of grouping (top hit not always first).
type CategoryKey =
  | "components"
  | "geometries"
  | "powerShapes"
  | "fluids"
  | "project";
const CATEGORY_HEADINGS: Record<CategoryKey, string> = {
  components: "Components",
  geometries: "Geometries",
  powerShapes: "Power Shapes",
  fluids: "Fluids",
  project: "Project",
};
const BROWSE_ORDER: readonly CategoryKey[] = [
  "components",
  "geometries",
  "powerShapes",
  "fluids",
  "project",
];

// Lightweight score used ONLY for cross-category ordering. cmdk still owns
// per-group filtering + ranking with its full command-score; this just lets
// us pick which category surfaces first. Ranges roughly 0 (no match) to ~1.
function scoreMatch(value: string, query: string): number {
  if (!query) return 0;
  const v = value.toLowerCase();
  const q = query.toLowerCase();
  if (v.startsWith(q)) {
    return 1 - ((v.length - q.length) / Math.max(v.length, 1)) * 0.1;
  }
  const idx = v.indexOf(q);
  if (idx >= 0) {
    return 0.7 - Math.min(idx, 30) / 100;
  }
  // Subsequence fuzzy match.
  let i = 0;
  for (let j = 0; j < v.length && i < q.length; j++) {
    if (v[j] === q[i]) i++;
  }
  if (i === q.length) return 0.3;
  return 0;
}

function itemValueForScoring(item: SearchItem): string {
  if (item.kind === "component") return `${item.name} ${item.typeLabel}`;
  if (item.kind === "modelOptions") return "Project Options Model Options";
  return item.name;
}

function bestScoreInGroup(group: SearchItem[], query: string): number {
  let best = 0;
  for (const it of group) {
    const s = scoreMatch(itemValueForScoring(it), query);
    if (s > best) best = s;
  }
  return best;
}

interface CommandPaletteProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /**
   * Phase 72 (help-system) — which view the palette opens in. `Ctrl+P` passes
   * "commands" (default); `?` passes "shortcuts". The user can swap modes via
   * the mode chip in the palette header after open.
   */
  initialMode?: CommandPaletteMode;
}

export default function CommandPalette(
  props: CommandPaletteProps,
): React.JSX.Element | null {
  const { open, onOpenChange, initialMode } = props;

  // Pitfall 8: don't even build the pool / subscribe to nodes when palette
  // is closed. App.tsx may render <CommandPalette open={false} /> permanently
  // for state ownership; the cheap early-exit keeps node-drag updates from
  // triggering buildSearchPool churn.
  if (!open) return null;

  return (
    <CommandPaletteInner
      open={open}
      onOpenChange={onOpenChange}
      initialMode={initialMode}
    />
  );
}

function CommandPaletteInner({
  open,
  onOpenChange,
  initialMode,
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
  // Phase 72 (help-system) — mode is a per-open-cycle local state seeded from
  // initialMode. The mode chip in the header lets the user swap without
  // closing and re-opening. Clearing search on swap keeps cmdk filtering
  // honest (a query that matched commands probably won't match shortcuts).
  const [mode, setMode] = React.useState<CommandPaletteMode>(
    initialMode ?? "commands",
  );

  function swapMode(next: CommandPaletteMode): void {
    setMode(next);
    setSearch("");
  }

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
      //
      // ReactFlow node.position is the TOP-LEFT corner; setCenter centers the
      // viewport on the world coordinate passed in, so we add half the node's
      // measured size to land on the node's actual center. measured is the
      // current xyflow v12 surface; fall back to top-level width/height (set
      // when a node has explicit dimensions) and finally to 0 for nodes that
      // haven't been measured yet (pre-render edge case).
      const w =
        item.node.measured?.width ?? item.node.width ?? 0;
      const h =
        item.node.measured?.height ?? item.node.height ?? 0;
      setCenter(
        item.node.position.x + w / 2,
        item.node.position.y + h / 2,
        {
          zoom: Math.max(getZoom(), ZOOM_MIN_LEGIBLE),
          duration: 250,
        },
      );
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

  // Group rendering order. Browse mode (empty query) uses the canonical
  // taxonomy order. Typed mode reorders categories by their best-scoring
  // item — the group with the strongest match surfaces first — so users
  // still see headers but the most-likely-matched category leads. Mid-UAT
  // change from plan-02's flat-list-in-typed-mode design after the user
  // flagged that category context is meaningful in this app.
  const groupOrder = React.useMemo<readonly CategoryKey[]>(() => {
    if (search.length === 0) return BROWSE_ORDER;
    return BROWSE_ORDER.slice().sort((a, b) => {
      const aMax = bestScoreInGroup(grouped[a], search);
      const bMax = bestScoreInGroup(grouped[b], search);
      return bMax - aMax;
    });
  }, [grouped, search]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        showCloseButton={false}
        // VSCode-style: ZERO scrim. The editor/canvas/sidebars stay fully
        // visible behind the palette. The palette stands out via tonal
        // distinction (its own darker tinted bg, below) + shadow + border
        // + top-anchored position — not via dimming the rest of the GUI.
        // Empty class still goes through DialogOverlay so click-outside-to-
        // close still works; it just paints nothing.
        overlayClassName="bg-transparent"
        // Pitfall 6 / CONTEXT.md D-08: Radix calls onEscapeKeyDown BEFORE its
        // own default close, so stopping propagation here both (a) lets the
        // dialog still close (we do NOT preventDefault) and (b) blocks the
        // bubble up to the window-level Esc handler in App.tsx that clears
        // pinned code-preview blocks. Without this, every palette dismissal
        // would silently nuke the user's pinned sub-blocks.
        onEscapeKeyDown={(e) => e.stopPropagation()}
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
          // Tonal distinction: the palette is its OWN surface tone,
          // distinctly darker than the bg-popover the default DialogContent
          // would carry. Slight hue-254 tint shared with the project's
          // neutral hue family, but at lower lightness so the palette
          // visibly recedes from the surrounding chrome/canvas — the
          // VSCode/Cursor "tool overlay" idiom.
          "rounded-md",
          // Theme-aware palette surface — both modes pick a tone that's
          // distinctly off the chrome/panel/canvas trio. Dark mode goes
          // below chrome (0.16 → 0.13); light mode goes below chrome
          // (0.95 → 0.93) without flipping to a dark palette on light
          // theme (which would be jarring).
          "bg-[oklch(0.93_0.012_254)] dark:bg-[oklch(0.13_0.012_254)]",
          "border-[oklch(0.86_0.012_254)] dark:border-[oklch(0.24_0.012_254)]",
          // Real shadow for elevation — VSCode-style "this is the active
          // tool, it floats above your work" cue. Tighter dark shadow in
          // dark mode, softer in light.
          "shadow-[0_16px_40px_-12px_oklch(0.05_0_0/0.18),0_4px_12px_-4px_oklch(0.05_0_0/0.12)]",
          "dark:shadow-[0_16px_40px_-12px_oklch(0.05_0_0/0.55),0_4px_12px_-4px_oklch(0.05_0_0/0.40)]",
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
        <Command
          label="Jump to component or resource"
          // Strip the cmdk primitive's default bg-popover so the
          // DialogContent's darker palette tone shows through. Without
          // this the outer dark surface gets re-painted with the
          // grey-on-grey popover bg and the VSCode tonal distinction
          // gets erased.
          className="bg-transparent"
        >
          {/* Phase 72 — mode chip strip. Lives between the input and the
              list when the palette is in any non-default mode, OR persistently
              so users discover the swap. Click swaps modes. */}
          <ModeChipRow mode={mode} onSwap={swapMode} />
          <CommandInput
            value={search}
            onValueChange={setSearch}
            placeholder={
              mode === "shortcuts"
                ? "Type to search shortcuts..."
                : "Type to search components and resources..."
            }
          />
          {/* D-02: max-h-[480px] override of the shim's canonical
              max-h-[400px] baseline. tailwind-merge resolves the override. */}
          <CommandList className="max-h-[480px]">
            <CommandEmpty>
              {mode === "shortcuts" ? "No bindings." : "No matches."}
            </CommandEmpty>
            {mode === "commands" ? (
              <OrderedGroups
                grouped={grouped}
                order={groupOrder}
                activeLayers={activeLayers}
                onSelect={handleSelect}
              />
            ) : (
              <ShortcutGroups
                onSelect={() => {
                  onOpenChange(false);
                  setSearch("");
                }}
              />
            )}
          </CommandList>
        </Command>
      </DialogContent>
    </Dialog>
  );
}

// ---------------------------------------------------------------------------
// OrderedGroups — single renderer for both browse-mode (BROWSE_ORDER) and
// typed-mode (best-score-first). cmdk owns intra-group filtering + ranking;
// we own the cross-group order. Empty groups are hidden via key (omitted)
// at the call site.
// ---------------------------------------------------------------------------

interface OrderedGroupsProps {
  grouped: Record<CategoryKey, SearchItem[]>;
  order: readonly CategoryKey[];
  activeLayers: Record<LayerKey, boolean>;
  onSelect: (item: SearchItem) => void;
}

function OrderedGroups({
  grouped,
  order,
  activeLayers,
  onSelect,
}: OrderedGroupsProps): React.JSX.Element {
  return (
    <>
      {order.map((key) => {
        const items = grouped[key];
        if (items.length === 0) return null;
        return (
          <CommandGroup key={key} heading={CATEGORY_HEADINGS[key]}>
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
      })}
    </>
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
                  title={`${LAYER_LABELS[k]} layer off; will enable on select`}
                  aria-label={`${LAYER_LABELS[k]} layer off; will enable on select`}
                  className="inline-flex items-center"
                >
                  <EyeOff
                    className="h-3.5 w-3.5 text-muted-foreground shrink-0 opacity-50"
                    aria-hidden="true"
                  />
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

// ---------------------------------------------------------------------------
// ModeChipRow — Phase 72 help-system. The mode chip lives directly under the
// dialog's top edge and above the input. Both modes are always available; the
// chip swaps. The currently-active mode shows in mono uppercase
// foreground/85; the inactive mode is foreground/45 and clickable.
//
// Aria-pressed encodes which mode is current. Click swaps and clears the
// search query (`swapMode` upstream).
// ---------------------------------------------------------------------------

interface ModeChipRowProps {
  mode: CommandPaletteMode;
  onSwap: (next: CommandPaletteMode) => void;
}

function ModeChipRow({ mode, onSwap }: ModeChipRowProps): React.JSX.Element {
  return (
    <div
      role="tablist"
      aria-label="Palette mode"
      className="flex items-center gap-3 px-3 py-1.5 border-b border-border/60 font-mono text-[10px] uppercase tracking-wide select-none"
    >
      <ModeChip
        active={mode === "commands"}
        label="Commands"
        keyHint="Ctrl+P"
        onClick={() => onSwap("commands")}
      />
      <ModeChip
        active={mode === "shortcuts"}
        label="Shortcuts"
        keyHint="?"
        onClick={() => onSwap("shortcuts")}
      />
    </div>
  );
}

interface ModeChipProps {
  active: boolean;
  label: string;
  keyHint: string;
  onClick: () => void;
}

function ModeChip({ active, label, keyHint, onClick }: ModeChipProps): React.JSX.Element {
  return (
    <button
      type="button"
      role="tab"
      aria-pressed={active}
      onClick={onClick}
      className={cn(
        "inline-flex items-center gap-1.5 rounded-sm px-1.5 py-0.5 cursor-pointer",
        "transition-colors duration-[80ms] focus-visible:outline-none",
        active
          ? "text-foreground/85"
          : "text-foreground/45 hover:text-foreground/75 hover:bg-popover/60 focus-visible:bg-popover/60",
      )}
    >
      <span>{label}</span>
      <span className="text-foreground/45 font-mono normal-case">{keyHint}</span>
    </button>
  );
}

// ---------------------------------------------------------------------------
// ShortcutGroups — renders the SHORTCUTS_CATALOG into the cmdk list, grouped
// by area. Each row is a non-action `CommandItem` (the row closes the palette
// on select; it does NOT fire the underlying action). The shortcut row is a
// REFERENCE: the user reads the binding, dismisses, and presses it.
//
// Matches the first-run keymap doctrine "Shortcut-Is-Static-Text Rule" —
// duplicating action paths would create two cmdk-mount / file-dialog-mount
// surfaces for the same intent. cmdk owns the filter + the keyboard nav; the
// row's onSelect is the "dismiss-after-read" hook.
// ---------------------------------------------------------------------------

interface ShortcutGroupsProps {
  onSelect: () => void;
}

function ShortcutGroups({ onSelect }: ShortcutGroupsProps): React.JSX.Element {
  const byGroup = React.useMemo(() => {
    const m = new Map<ShortcutGroup, ShortcutEntry[]>();
    for (const g of SHORTCUT_GROUP_ORDER) m.set(g, []);
    for (const entry of SHORTCUTS_CATALOG) {
      const bucket = m.get(entry.group);
      if (bucket) bucket.push(entry);
    }
    return m;
  }, []);

  return (
    <>
      {SHORTCUT_GROUP_ORDER.map((group) => {
        const entries = byGroup.get(group);
        if (!entries || entries.length === 0) return null;
        return (
          <CommandGroup key={group} heading={group}>
            {entries.map((entry) => (
              <ShortcutRow key={entry.label} entry={entry} onSelect={onSelect} />
            ))}
          </CommandGroup>
        );
      })}
    </>
  );
}

interface ShortcutRowProps {
  entry: ShortcutEntry;
  onSelect: () => void;
}

function ShortcutRow({ entry, onSelect }: ShortcutRowProps): React.JSX.Element {
  const value = [entry.label, entry.keys, ...(entry.aliases ?? [])].join(" ");
  return (
    <CommandItem
      value={value}
      onSelect={onSelect}
      data-testid={`cmdk-shortcut-${entry.label.replace(/\s+/g, "-")}`}
    >
      <span className="flex-1">{entry.label}</span>
      <span className="ml-auto font-mono text-foreground/65 text-[11px]">
        {entry.keys}
      </span>
    </CommandItem>
  );
}
