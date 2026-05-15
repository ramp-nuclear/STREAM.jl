// AddComponentSubmenu.tsx — Phase 65 Plan 11: uses Radix DropdownMenu.Sub for viewport-collision-aware placement (was PopoverMenuSub* with hardcoded left-full positioning).
//
// Groups registry components by category (alphabetical) and drops a new instance at
// the flow-coordinate position passed from CanvasPanel.

import { useMemo } from "react";
import {
  DropdownMenuItem,
  DropdownMenuPortal,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
} from "@/components/ui/dropdown-menu";
import { getAllComponents } from "@/registry";
import useStore from "@/store/useStore";

interface AddComponentSubmenuProps {
  flowPosition: { x: number; y: number };
  onClose: () => void;
}

export default function AddComponentSubmenu({
  flowPosition,
  onClose,
}: AddComponentSubmenuProps) {
  // Group components by category, sorted alphabetically (category and component name).
  const grouped = useMemo(() => {
    const components = getAllComponents();
    const map = new Map<string, { id: string; label: string }[]>();
    for (const comp of components) {
      const list = map.get(comp.category) ?? [];
      list.push({ id: comp.id, label: comp.label });
      map.set(comp.category, list);
    }
    // Sort entries alphabetically by category name, components alphabetically within.
    const sorted = Array.from(map.entries()).sort(([a], [b]) => a.localeCompare(b));
    return sorted.map(([category, comps]) => ({
      category,
      components: [...comps].sort((a, b) => a.label.localeCompare(b.label)),
    }));
  }, []);

  return (
    <>
      {grouped.map(({ category, components }) => (
        <DropdownMenuSub key={category}>
          <DropdownMenuSubTrigger>{category}</DropdownMenuSubTrigger>
          <DropdownMenuPortal>
            <DropdownMenuSubContent>
              {components.map((comp) => (
                <DropdownMenuItem
                  key={comp.id}
                  onSelect={(e) => {
                    e.preventDefault?.();
                    useStore.getState().addNode(comp.id, flowPosition);
                    onClose();
                  }}
                >
                  {comp.label}
                </DropdownMenuItem>
              ))}
            </DropdownMenuSubContent>
          </DropdownMenuPortal>
        </DropdownMenuSub>
      ))}
    </>
  );
}
