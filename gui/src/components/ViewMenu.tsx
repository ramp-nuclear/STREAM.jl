import { Button } from "./ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuPortal,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
  DropdownMenuTrigger,
} from "./ui/dropdown-menu";
import { THEMES, type Theme } from "../hooks/useTheme";

interface Props {
  theme: Theme;
  setTheme: (t: Theme) => void;
}

/**
 * View menu (Phase 67 D-11, D-21 — round 2 trim).
 *
 * Round 2 UAT items #6 and #7 removed two entries:
 *   - "Toggle Code Preview" — duplicate of the always-visible Code button in
 *     SecondaryToolbar; users found the menu copy redundant.
 *   - "Layer" radio submenu — duplicate of SecondaryToolbar's ToggleGroup;
 *     same reason.
 *
 * Remaining: Theme submenu only. Per the plan, View is kept (single submenu
 * is still meaningful) — Phase 72 may add more.
 *
 * D-21 — Theme submenu maps over THEMES (D-21) — adding a new entry to the
 * exported array widens the union and adds a radio item automatically.
 */
export default function ViewMenu({ theme, setTheme }: Props) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="ghost"
          size="sm"
          className="h-full rounded-none px-3 py-0 text-xs font-normal"
        >
          View
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start">
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
