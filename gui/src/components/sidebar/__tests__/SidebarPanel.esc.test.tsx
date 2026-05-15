// @vitest-environment happy-dom
//
// Phase 65 Plan 10 — Esc input-focus guard on SidebarPanel's document-level
// keydown handler.
//
// Closes UAT Test 7 desync (major): pressing Esc while a sidebar text input
// is focused must NOT clear the zustand selection slice. The desync happens
// because SidebarPanel's Esc handler unconditionally calls clearSelection()
// while CanvasPanel's handler (the canonical one) early-returns when an
// input/textarea/select/contentEditable element is the event target. After
// the fix both handlers agree.
//
// Reference implementation guard: CanvasPanel.tsx:266-275.

import { describe, it, expect, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import SidebarPanel from "../SidebarPanel";
import useStore, {
  SENTINEL_UNSET_POWER_SHAPE,
  SENTINEL_LIGHT_WATER_FLUID,
} from "../../../store/useStore";
import { TooltipProvider } from "../../ui/tooltip";

function resetStore() {
  useStore.setState({
    nodes: [],
    edges: [],
    anchors: {},
    selectedNodeId: null,
    selectedResourceId: null,
    selectedResourceKind: null,
    selectionKind: "none",
    isDirty: false,
    _undoPast: [],
    _undoFuture: [],
    activeLeftTab: "Components",
    bcMode: {},
    bcSymmetric: {},
    resources: {
      geometries: {},
      powerShapes: {
        [SENTINEL_UNSET_POWER_SHAPE]: {
          uuid: SENTINEL_UNSET_POWER_SHAPE,
          name: "(leave unset — set in code)",
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

function renderPanel() {
  return render(
    <TooltipProvider>
      <SidebarPanel width={320} />
    </TooltipProvider>,
  );
}

/**
 * Seed a node and select it so SidebarPanel renders the InstanceNameField
 * input (an HTMLInputElement).
 */
function seedSelectedNode() {
  useStore.getState().addNode("Pump", { x: 0, y: 0 });
  const nodeId = useStore.getState().nodes[0].id;
  useStore.getState().selectNode(nodeId);
  return nodeId;
}

/**
 * Dispatch a real Escape KeyboardEvent on document. When `focusTarget` is
 * provided, focus it first so `e.target` resolves to that element.
 */
function dispatchEscOn(focusTarget: HTMLElement | null) {
  if (focusTarget) {
    focusTarget.focus();
  } else {
    (document.activeElement as HTMLElement | null)?.blur();
  }
  const event = new KeyboardEvent("keydown", {
    key: "Escape",
    bubbles: true,
    cancelable: true,
  });
  // happy-dom dispatches the event from document; the focused element is
  // the natural target for keydown — that mirrors real-browser behavior.
  document.dispatchEvent(event);
}

beforeEach(() => {
  resetStore();
});

describe("SidebarPanel — Esc input-focus guard (Phase 65 Plan 10)", () => {
  it("Esc inside a focused <input> does NOT clear selection (UAT Test 7 fix)", () => {
    const nodeId = seedSelectedNode();
    renderPanel();
    // InstanceNameField + ParameterForm both render <input role="textbox">.
    // Any one of them is a valid HTMLInputElement focus target for the guard.
    const input = screen.getAllByRole("textbox")[0] as HTMLInputElement;
    dispatchEscOn(input);
    expect(useStore.getState().selectionKind).toBe("component");
    expect(useStore.getState().selectedNodeId).toBe(nodeId);
  });

  it("Esc with NO input focused still clears selection (regression guard)", () => {
    seedSelectedNode();
    renderPanel();
    dispatchEscOn(null);
    expect(useStore.getState().selectionKind).toBe("none");
    expect(useStore.getState().selectedNodeId).toBeNull();
  });

  it("Esc inside a focused <textarea> does NOT clear selection (edge — same guard arm)", () => {
    const nodeId = seedSelectedNode();
    renderPanel();
    // Mount an extra textarea outside the sidebar. The handler is
    // document-level, so the source of the textarea is irrelevant — only
    // the event target type matters.
    const ta = document.createElement("textarea");
    document.body.appendChild(ta);
    try {
      dispatchEscOn(ta);
      expect(useStore.getState().selectionKind).toBe("component");
      expect(useStore.getState().selectedNodeId).toBe(nodeId);
    } finally {
      ta.remove();
    }
  });

  it("Esc inside a contentEditable element does NOT clear selection (edge — same guard arm)", () => {
    const nodeId = seedSelectedNode();
    renderPanel();
    const div = document.createElement("div");
    div.contentEditable = "true";
    // happy-dom needs tabindex/contenteditable to make .focus() effective.
    div.tabIndex = 0;
    document.body.appendChild(div);
    try {
      dispatchEscOn(div);
      expect(useStore.getState().selectionKind).toBe("component");
      expect(useStore.getState().selectedNodeId).toBe(nodeId);
    } finally {
      div.remove();
    }
  });
});
