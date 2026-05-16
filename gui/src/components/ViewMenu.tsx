import { Check, ChevronDown } from "lucide-react";
import { Button } from "./ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuPortal,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
  DropdownMenuTrigger,
} from "./ui/dropdown-menu";
import useStore from "../store/useStore";
import { THEMES, type Theme } from "../hooks/useTheme";
import type { LayerView } from "../lib/layers";

interface Props {
  theme: Theme;
  setTheme: (t: Theme) => void;
}

/**
 * View menu (Phase 67 D-11, D-21).
 *
 * - Toggle Code Preview shows a leading check mark when bottomPanelOpen.
 * - Layer submenu binds bidirectionally to store activeLayer/setActiveLayer
 *   (same slice as SecondaryToolbar's ToggleGroup, so the two stay in sync).
 * - Theme submenu maps over THEMES (D-21) — adding a new entry to the
 *   exported array widens the union and adds a radio item automatically.
 */
export default function ViewMenu({ theme, setTheme }: Props) {
  const bottomPanelOpen = useStore((s) => s.bottomPanelOpen);
  const toggleBottomPanel = useStore((s) => s.toggleBottomPanel);
  const activeLayer = useStore((s) => s.activeLayer);
  const setActiveLayer = useStore((s) => s.setActiveLayer);

  const layers: LayerView[] = ["Hydraulic", "Both", "Thermal"];

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="sm">
          View
          <ChevronDown className="h-3.5 w-3.5 ml-1" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start">
        <DropdownMenuItem onClick={() => toggleBottomPanel()}>
          {bottomPanelOpen ? (
            <Check className="h-4 w-4 mr-2" />
          ) : (
            <span className="w-4 h-4 mr-2" />
          )}
          <span>Toggle Code Preview</span>
        </DropdownMenuItem>

        <DropdownMenuSub>
          <DropdownMenuSubTrigger>Layer</DropdownMenuSubTrigger>
          <DropdownMenuPortal>
            <DropdownMenuSubContent>
              <DropdownMenuRadioGroup
                value={activeLayer}
                onValueChange={(v) => setActiveLayer(v as LayerView)}
              >
                {layers.map((l) => (
                  <DropdownMenuRadioItem key={l} value={l}>
                    {l}
                  </DropdownMenuRadioItem>
                ))}
              </DropdownMenuRadioGroup>
            </DropdownMenuSubContent>
          </DropdownMenuPortal>
        </DropdownMenuSub>

        <DropdownMenuSub>
          <DropdownMenuSubTrigger>Theme</DropdownMenuSubTrigger>
          <DropdownMenuPortal>
            <DropdownMenuSubContent>
              <DropdownMenuRadioGroup
                value={theme}
                onValueChange={(v) => setTheme(v as Theme)}
              >
                {THEMES.map((t) => (
                  <DropdownMenuRadioItem key={t} value={t}>
                    {t.charAt(0).toUpperCase() + t.slice(1)}
                  </DropdownMenuRadioItem>
                ))}
              </DropdownMenuRadioGroup>
            </DropdownMenuSubContent>
          </DropdownMenuPortal>
        </DropdownMenuSub>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
