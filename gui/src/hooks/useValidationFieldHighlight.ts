/**
 * useValidationFieldHighlight — Phase 71 Plan 11
 *
 * Subscribes to `validationResults` from the store. When the selected node
 * changes or results update, clears all prior highlight classes from
 * data-field-path elements in the sidebar container, then re-applies
 * .validation-field-error or .validation-field-warning to the matching
 * elements for kind === 'field' targets referencing the currently-selected node.
 *
 * D-12 convention: fieldPath is a dot/bracket-notation string (e.g. 'n',
 * 'geom.L', 'T_wall_left'). CSS.escape() is used before injecting into
 * querySelector so paths with dots or brackets are matched correctly.
 *
 * The hook is layout-transparent: it only adds/removes CSS classes; it does
 * not change any DOM structure.
 */

import { useEffect, type RefObject } from "react";
import useStore from "../store/useStore";

export function useValidationFieldHighlight(
  selectedNodeId: string | null,
  containerRef: RefObject<HTMLElement | null>,
): void {
  const validationResults = useStore((s) => s.validationResults);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    // Remove all prior highlight classes from every data-field-path element.
    container.querySelectorAll("[data-field-path]").forEach((el) => {
      el.classList.remove("validation-field-error", "validation-field-warning");
    });

    // If no node is selected, nothing further to paint.
    if (!selectedNodeId) return;

    // For each result, iterate field targets referencing the selected node
    // and apply the matching highlight class.
    for (const result of validationResults) {
      for (const target of result.targets) {
        if (target.kind !== "field" || target.nodeId !== selectedNodeId) {
          continue;
        }
        // CSS.escape ensures dots/brackets in fieldPath are not misinterpreted
        // as CSS class/descendant selectors.
        const el = container.querySelector(
          `[data-field-path="${CSS.escape(target.fieldPath)}"]`,
        );
        if (!el) continue;
        const cls =
          result.severity === "error"
            ? "validation-field-error"
            : result.severity === "warning"
              ? "validation-field-warning"
              : null;
        if (cls) el.classList.add(cls);
      }
    }
    // Cleanup is implicit: the next effect run (triggered by dep change)
    // starts by removing all prior highlights before re-applying new ones.
  }, [selectedNodeId, validationResults, containerRef]);
}
