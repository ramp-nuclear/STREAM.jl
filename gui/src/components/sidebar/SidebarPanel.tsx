// SidebarPanel.tsx — Phase 62 Plan 62-09: selection-kind router (D-05, D-06, CD-05).
//
// Routes the right Properties panel on the store-derived `selectionKind`
// discriminator (set by 62-02 in `selectNode` / `selectResource` /
// `clearSelection`):
//   • "component" → existing Component editor (today's behavior, preserved)
//   • "resource" → ResourceEditor for the selected resource kind:
//       - geometry   → <GeometryResourceEditor mode="edit" ... />
//       - powerShape → <PowerShapeResourceEditor mode="edit" ... />,
//         OR the read-only sentinel placeholder when the selection is the
//         SENTINEL_UNSET_POWER_SHAPE (D-26: sentinel is uneditable).
//       - fluid      → read-only light_water placeholder (D-03;
//         RESEARCH Open Question 3 recommendation copy).
//   • "none" / "project" → no-selection body:
//       - Resources tab active → variant copy "Select a resource to edit it."
//         (UI-SPEC §"Right Properties panel — no-selection body";
//         rewritten in 62-15 per VERIFICATION.md Gap #4)
//       - Otherwise → standard "Select a component to view its properties."
//
// Header text (D-06, UI-SPEC §"Right Properties panel — header text"):
//   • component → "Properties"
//   • geometry  → `Geometry: <name>`
//   • powerShape → `Power Shape: <name>`
//   • fluid     → `Fluid: <name>` (extends UI-SPEC §269-272 by consistency)
//   • no selection / project → "Properties"
//
// Esc cascade tail (UI-SPEC §"Esc precedence cascade" item 4):
//   • A document-level keydown listener calls `clearSelection()` when
//     `selectionKind !== "none"`. Higher-precedence items in the cascade
//     are owned by their layers and stop propagation before reaching here:
//       1. Popover Esc — owned by ResourceCreationPopover.tsx (62-08):
//          its `onEscapeKeyDown` calls `e.preventDefault() + e.stopPropagation()`.
//       2. Inline-rename Esc — owned by ResourceRow rename Input (62-07).
//       3. Context-menu Esc — owned by Radix ContextMenu internals.
//     The `e.defaultPrevented` guard here is belt-and-braces: if any
//     higher-precedence handler called preventDefault, we skip the tail.

import { useEffect } from "react";
import useStore, {
  SENTINEL_UNSET_POWER_SHAPE,
  type StreamNodeData,
} from "@/store/useStore";
import { getComponent } from "@/registry";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import InstanceNameField from "./InstanceNameField";
import ParameterForm from "./ParameterForm";
import ModeToggle from "./ModeToggle";
import GeometryResourceEditor from "./GeometryResourceEditor";
import PowerShapeResourceEditor from "./PowerShapeResourceEditor";

interface SidebarPanelProps {
  width: number;
  onResizeMouseDown?: (e: React.MouseEvent) => void;
}

export default function SidebarPanel({ width, onResizeMouseDown }: SidebarPanelProps) {
  const selectionKind = useStore((s) => s.selectionKind);
  const selectedNodeId = useStore((s) => s.selectedNodeId);
  const selectedResourceId = useStore((s) => s.selectedResourceId);
  const selectedResourceKind = useStore((s) => s.selectedResourceKind);
  const activeLeftTab = useStore((s) => s.activeLeftTab);
  const nodes = useStore((s) => s.nodes);
  const resources = useStore((s) => s.resources);
  const updateNodeParams = useStore((s) => s.updateNodeParams);
  const updateResource = useStore((s) => s.updateResource);
  const clearSelection = useStore((s) => s.clearSelection);

  // ---------------------------------------------------------------------
  // Esc cascade tail (UI-SPEC §"Esc precedence cascade" item 4 only).
  // Items 1-3 (popover-close, rename-cancel, context-menu-close) are owned
  // by their respective layers and stop propagation before reaching this
  // listener — see file header for details.
  // ---------------------------------------------------------------------
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      // Defensive: skip if a higher-precedence handler already consumed
      // the Esc. Radix Popover (via 62-08) and Radix ContextMenu both
      // call preventDefault on Esc; this is belt-and-braces.
      if (e.defaultPrevented) return;
      if (e.key !== "Escape") return;
      // Read fresh state inside the handler — the closure was created
      // once on mount and cannot stale-close over selectionKind.
      if (useStore.getState().selectionKind !== "none") {
        useStore.getState().clearSelection();
      }
    };
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, []);

  // ---------------------------------------------------------------------
  // Resolve the selected resource record (used for header text + body).
  // ---------------------------------------------------------------------
  const selectedGeometry =
    selectionKind === "resource" &&
    selectedResourceKind === "geometry" &&
    selectedResourceId != null
      ? resources.geometries[selectedResourceId]
      : undefined;
  const selectedPowerShape =
    selectionKind === "resource" &&
    selectedResourceKind === "powerShape" &&
    selectedResourceId != null
      ? resources.powerShapes[selectedResourceId]
      : undefined;
  const selectedFluid =
    selectionKind === "resource" &&
    selectedResourceKind === "fluid" &&
    selectedResourceId != null
      ? resources.fluids[selectedResourceId]
      : undefined;

  // ---------------------------------------------------------------------
  // Header text (D-06)
  // ---------------------------------------------------------------------
  let headerText: string = "Properties";
  if (selectionKind === "component") {
    headerText = "Properties";
  } else if (selectedGeometry) {
    headerText = `Geometry: ${selectedGeometry.name}`;
  } else if (selectedPowerShape) {
    headerText = `Power Shape: ${selectedPowerShape.name}`;
  } else if (selectedFluid) {
    headerText = `Fluid: ${selectedFluid.name}`;
  }

  // ---------------------------------------------------------------------
  // Body branch selector (returns the inner JSX; the outer chrome —
  // resize handle + padding — is rendered once below).
  // ---------------------------------------------------------------------
  function renderBody() {
    // ----- component branch ---------------------------------------------
    if (selectionKind === "component" && selectedNodeId != null) {
      const node = nodes.find((n) => n.id === selectedNodeId);
      if (!node) return null;
      const data = node.data as unknown as StreamNodeData;
      const component = getComponent(data.componentId);
      if (!component) {
        return (
          <p className="text-destructive text-sm mt-[16px]">
            Unknown component: {data.componentId}
          </p>
        );
      }
      const activeMode =
        data.constructorMode ?? component.constructorModes[0]?.mode ?? "default";
      return (
        <div key={selectedNodeId}>
          <div className="mt-[24px] flex flex-col gap-[8px]">
            <InstanceNameField
              value={data.instanceName}
              onChange={(name) =>
                updateNodeParams(selectedNodeId, { instanceName: name })
              }
            />
            <Badge variant="secondary">{component.label}</Badge>
          </div>

          <Separator className="my-[24px]" />

          {component.constructorModes.length > 1 && (
            <>
              <ModeToggle
                modes={component.constructorModes}
                activeMode={activeMode}
                onChange={(mode) =>
                  updateNodeParams(selectedNodeId, { constructorMode: mode })
                }
              />
              <Separator className="my-[24px]" />
            </>
          )}

          <ParameterForm
            component={component}
            activeMode={activeMode}
            values={data.parameters}
            onParamChange={(name, value) =>
              updateNodeParams(selectedNodeId, {
                parameters: { [name]: value },
              })
            }
          />
        </div>
      );
    }

    // ----- resource: geometry -------------------------------------------
    if (selectedGeometry) {
      return (
        <div className="mt-[24px]" key={selectedGeometry.uuid}>
          <GeometryResourceEditor
            mode="edit"
            initialName={selectedGeometry.name}
            initialKind={selectedGeometry.kind}
            initialParams={selectedGeometry.params}
            editingUuid={selectedGeometry.uuid}
            onSubmit={(g) =>
              updateResource("geometry", selectedGeometry.uuid, g)
            }
            onCancel={() => clearSelection()}
          />
        </div>
      );
    }

    // ----- resource: powerShape -----------------------------------------
    if (selectedPowerShape) {
      // Sentinel (D-26): show a read-only placeholder body instead of the
      // editor form. The sentinel is uneditable; surfacing the editor with
      // disabled controls would be misleading.
      if (selectedPowerShape.uuid === SENTINEL_UNSET_POWER_SHAPE) {
        return (
          <div className="mt-[24px] text-[14px] text-muted-foreground leading-[1.5]">
            <p>
              This Power Shape is the global "unset" placeholder. Selecting it
              means the generated script has a TODO marker for you to fill in.
              (Cannot be edited.)
            </p>
          </div>
        );
      }

      // Type-narrow to a user kind for the editor.
      if (
        selectedPowerShape.kind === "uniform" ||
        selectedPowerShape.kind === "z_cosine" ||
        selectedPowerShape.kind === "file_loaded"
      ) {
        return (
          <div className="mt-[24px]" key={selectedPowerShape.uuid}>
            <PowerShapeResourceEditor
              mode="edit"
              initialName={selectedPowerShape.name}
              initialKind={selectedPowerShape.kind}
              initialParams={selectedPowerShape.params}
              editingUuid={selectedPowerShape.uuid}
              onSubmit={(p) =>
                updateResource("powerShape", selectedPowerShape.uuid, p)
              }
              onCancel={() => clearSelection()}
            />
          </div>
        );
      }
      // Fallthrough — should be unreachable (kind === "unset" handled above)
      return null;
    }

    // ----- resource: fluid (read-only placeholder, RESEARCH Q3) ---------
    if (selectedFluid) {
      return (
        <div className="mt-[24px] text-[14px] text-muted-foreground leading-[1.5] flex flex-col gap-[8px]">
          <p>Fluid: {selectedFluid.name}</p>
          <p>rho, cp, mu, k are baked in for v1.</p>
          <p>Multi-fluid abstraction is v0.6+.</p>
        </div>
      );
    }

    // ----- no selection / project tab -----------------------------------
    // D-04: the Project tab body IS the form; the right panel is unused.
    // We surface the same no-selection body. When the Resources tab is
    // active with no resource selected, swap the body description for the
    // variant copy.
    const variantCopy =
      activeLeftTab === "Resources"
        ? "Select a resource to edit it."
        : "Select a component to view its properties.";
    return (
      <div className="mt-[32px]">
        <p className="text-[14px] font-semibold text-muted-foreground">
          No selection
        </p>
        <p className="text-[14px] text-muted-foreground mt-[8px]">
          {variantCopy}
        </p>
      </div>
    );
  }

  return (
    <div className="relative h-full border-l shrink-0 overflow-hidden" style={{ width }}>
      {onResizeMouseDown && (
        <div
          className="absolute left-0 top-0 w-1 h-full cursor-col-resize z-10 hover:bg-border/50"
          onMouseDown={onResizeMouseDown}
        />
      )}
      <ScrollArea className="h-full">
        <div className="p-[16px] pt-[32px] min-w-0">
          <h2 className="text-[16px] font-semibold leading-[1.3]">
            {headerText}
          </h2>
          {renderBody()}
        </div>
      </ScrollArea>
    </div>
  );
}
