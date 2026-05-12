// @vitest-environment happy-dom
//
// Phase 62 Plan 62-08 Task 3 — ResourceReferencePicker integration tests.
// Covers D-14 (layout), D-15 (auto-select on Create + Pitfall 1 focus
// return), D-16 (popover non-dismiss-on-click-outside), D-18 (Edit… jump
// to Resources tab), D-20 (empty-state copy), D-26 (Power Shape sentinel
// top entry), INV-13..INV-17, and UI-SPEC §"Esc precedence cascade" item 1
// (popover Esc is a hard stop — `outerListener` receives zero Esc events).

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import ResourceReferencePicker from "../ResourceReferencePicker";
import useStore, {
  SENTINEL_UNSET_POWER_SHAPE,
  SENTINEL_LIGHT_WATER_FLUID,
} from "../../../store/useStore";
import { TooltipProvider } from "../../ui/tooltip";

function resetStore() {
  useStore.setState({
    nodes: [],
    edges: [],
    bcs: [],
    selectedNodeId: null,
    selectedResourceId: null,
    selectedResourceKind: null,
    selectionKind: "none",
    isDirty: false,
    _undoPast: [],
    _undoFuture: [],
    activeLeftTab: "Components",
    resources: {
      geometries: {},
      powerShapes: {
        [SENTINEL_UNSET_POWER_SHAPE]: {
          uuid: SENTINEL_UNSET_POWER_SHAPE,
          name: "(leave unset — fill in code)",
          kind: "unset",
          params: {},
        },
      },
      fluids: {
        [SENTINEL_LIGHT_WATER_FLUID]: {
          uuid: SENTINEL_LIGHT_WATER_FLUID,
          name: "light_water",
        },
      },
    },
  });
}

function renderPicker(
  props: Partial<React.ComponentProps<typeof ResourceReferencePicker>> = {},
) {
  return render(
    <TooltipProvider>
      <ResourceReferencePicker
        resourceKind={props.resourceKind ?? "geometry"}
        value={props.value ?? null}
        onChange={props.onChange ?? vi.fn()}
      />
    </TooltipProvider>,
  );
}

function flushTimers() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe("ResourceReferencePicker", () => {
  beforeEach(() => {
    resetStore();
  });

  describe("D-14: layout — dropdown + + New… + Edit… on a single row", () => {
    it("D-14: renders a Select trigger plus + New… and Edit… buttons", () => {
      renderPicker();
      // Radix Select trigger has role="combobox".
      expect(screen.getByRole("combobox")).toBeTruthy();
      expect(screen.getByText("+ New…")).toBeTruthy();
      expect(screen.getByText("Edit…")).toBeTruthy();
    });
  });

  describe("D-20 / INV-15: empty-state copy when zero resources of that kind exist", () => {
    it("D-20 / INV-15: geometry picker shows the verbatim empty-state copy", () => {
      renderPicker({ resourceKind: "geometry" });
      expect(
        screen.getByText(
          "No geometries yet — click + New… or open the Resources tab.",
        ),
      ).toBeTruthy();
    });
  });

  describe("D-26: Power Shape sentinel — `(leave unset — fill in code)` is the fixed top entry", () => {
    it("D-26: Power Shape picker dropdown includes the sentinel item", async () => {
      renderPicker({ resourceKind: "powerShape" });
      // Open the Select menu by clicking the trigger.
      fireEvent.click(screen.getByRole("combobox"));
      await flushTimers();

      // The sentinel option renders the verbatim copy "(leave unset — fill
      // in code)" — it must be present.
      expect(screen.getByText("(leave unset — fill in code)")).toBeTruthy();
    });
  });

  describe("INV-13: click-outside does NOT dismiss the popover (D-16)", () => {
    it("INV-13 / D-16: clicking outside the popover keeps it open", async () => {
      renderPicker();
      fireEvent.click(screen.getByText("+ New…"));
      await flushTimers();
      // Popover body contains the GeometryResourceEditor's header.
      expect(screen.queryByText("New Geometry")).not.toBeNull();

      // Dispatch a bubbling pointerdown on document.body — Radix uses
      // pointerdown to detect outside clicks. preventDefault on
      // onInteractOutside must suppress dismissal.
      const evt = new Event("pointerdown", { bubbles: true, cancelable: true });
      document.body.dispatchEvent(evt);
      fireEvent.click(document.body);

      // Popover content still in the document.
      expect(screen.queryByText("New Geometry")).not.toBeNull();
    });
  });

  describe("INV-13 + UI-SPEC §Esc precedence cascade item 1: Esc closes popover ONLY", () => {
    it("Esc closes the popover; document-level outerListener is NOT called", async () => {
      const outerListener = vi.fn();
      document.addEventListener("keydown", outerListener);

      try {
        renderPicker();
        fireEvent.click(screen.getByText("+ New…"));
        await flushTimers();
        expect(screen.queryByText("New Geometry")).not.toBeNull();

        // Press Esc on the popover content's body. Radix attaches its
        // onEscapeKeyDown handler to the content; the handler calls
        // stopPropagation() on the event before close — so the
        // document-level outerListener must NOT see an Escape event.
        const content = screen.getByText("New Geometry").parentElement!;
        fireEvent.keyDown(content, { key: "Escape", code: "Escape" });

        await waitFor(() => {
          expect(screen.queryByText("New Geometry")).toBeNull();
        });

        // UI-SPEC §"Esc precedence cascade" item 1: the popover Esc is a
        // hard stop. The cascade-stop is the only mechanism that keeps
        // SidebarPanel (62-09) from also clearing selection on the same
        // Esc press. The contract is verified by the absence of an Escape
        // delivery at the document level.
        const escapeCalls = outerListener.mock.calls.filter(
          (c) => (c[0] as KeyboardEvent).key === "Escape",
        );
        expect(escapeCalls.length).toBe(0);
      } finally {
        document.removeEventListener("keydown", outerListener);
      }
    });
  });

  describe("INV-14 / D-15: Create auto-selects the new resource and closes", () => {
    it("INV-14: clicking Create on a valid form auto-selects the new UUID via onChange", async () => {
      const onChange = vi.fn();
      renderPicker({ onChange });
      fireEvent.click(screen.getByText("+ New…"));
      await flushTimers();
      // Editor mounted.
      expect(screen.queryByText("New Geometry")).not.toBeNull();

      // Fill required dimension fields (Name is pre-filled via D-19 to
      // `geometry_1`). The dimension inputs are inputs after the name input.
      const inputs = screen.getAllByRole("textbox");
      // inputs[0] = name; inputs[1] = L; inputs[2] = D
      fireEvent.change(inputs[1], { target: { value: "0.6" } });
      fireEvent.change(inputs[2], { target: { value: "0.025" } });

      fireEvent.click(screen.getByText("Create"));
      await flushTimers();

      // Resource exists in the store.
      const geometries = useStore.getState().resources.geometries;
      const created = Object.values(geometries);
      expect(created.length).toBe(1);
      const newUuid = created[0].uuid;

      // onChange called with the new UUID — D-15 auto-select.
      expect(onChange).toHaveBeenCalledWith(newUuid);

      // Popover closed.
      await waitFor(() => {
        expect(screen.queryByText("New Geometry")).toBeNull();
      });
    });
  });

  describe("D-15 / Pitfall 1: focus returns to + New… button after Esc close", () => {
    it("Pitfall 1: triggerRef.current?.focus() is called on Esc close", async () => {
      renderPicker();
      const newButton = screen.getByText("+ New…");
      newButton.focus();
      fireEvent.click(newButton);
      await flushTimers();
      expect(screen.queryByText("New Geometry")).not.toBeNull();

      // Press Esc inside the popover.
      const content = screen.getByText("New Geometry").parentElement!;
      fireEvent.keyDown(content, { key: "Escape", code: "Escape" });

      // Wait for the close animation to finish + the setTimeout(0)
      // focus-return to fire.
      await waitFor(
        () => {
          expect(document.activeElement).toBe(newButton);
        },
        { timeout: 1000 },
      );
    });
  });

  describe("D-18 / INV-17: Edit… jumps to Resources tab and selects the row", () => {
    it("D-18 / INV-17: clicking Edit… sets activeLeftTab=Resources and selects the resource", async () => {
      // Seed a geometry and set the picker value to its UUID.
      const uuid = useStore.getState().addGeometry({
        name: "mtr_channel",
        kind: "rectangular",
        params: { L: 0.6, W: 0.07, H: 0.0025 },
      });
      const onChange = vi.fn();
      renderPicker({ value: uuid, onChange });

      // Click Edit…
      fireEvent.click(screen.getByText("Edit…"));

      // Per UI-SPEC + D-18:
      const s = useStore.getState();
      expect(s.activeLeftTab).toBe("Resources");
      expect(s.selectedResourceId).toBe(uuid);
      expect(s.selectedResourceKind).toBe("geometry");
      expect(s.selectedNodeId).toBeNull();
    });
  });

  describe("Edit… disabled rules (UI-SPEC §Reference picker)", () => {
    it("Edit… is disabled when the picker has no current selection", () => {
      renderPicker({ value: null });
      const editButton = screen
        .getByText("Edit…")
        .closest("button") as HTMLButtonElement;
      expect(editButton.disabled).toBe(true);
    });

    it("Edit… is disabled when the Power Shape picker is on the unset sentinel", () => {
      renderPicker({
        resourceKind: "powerShape",
        value: SENTINEL_UNSET_POWER_SHAPE,
      });
      const editButton = screen
        .getByText("Edit…")
        .closest("button") as HTMLButtonElement;
      expect(editButton.disabled).toBe(true);
    });

    it("Edit… disabled tooltip shows the verbatim copy 'Select a resource to edit it.'", async () => {
      renderPicker({ value: null });
      // Radix Tooltip portals its content lazily — it is NOT in the DOM
      // until the trigger is hovered/focused. Focus the wrapper span (the
      // Tooltip trigger) and wait for the portal to render the content.
      // The disabled <button> intercepts focus, so we focus the wrapping
      // <span tabIndex={0}> per the standard "disabled button + tooltip"
      // pattern.
      const triggerSpan = screen
        .getByText("Edit…")
        .closest("[data-slot='tooltip-trigger']") as HTMLElement;
      expect(triggerSpan).not.toBeNull();
      fireEvent.focus(triggerSpan);
      // Radix Tooltip renders BOTH the visual tooltip content AND a
      // visually-hidden `role="tooltip"` for assistive tech, so the
      // verbatim copy appears twice — we use getAllByText to assert at
      // least one occurrence.
      await waitFor(() => {
        const hits = screen.getAllByText("Select a resource to edit it.");
        expect(hits.length).toBeGreaterThan(0);
      });
    });
  });

  // Cleanup any stray document listeners between tests (defensive against
  // leakage from the Esc-cascade test).
  afterEach(() => {
    // No-op — test bodies attach + detach their own outerListener inside a
    // try/finally. Kept here as a structural reminder.
  });
});
