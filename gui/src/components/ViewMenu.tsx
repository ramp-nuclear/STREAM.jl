import {
  MenubarContent,
  MenubarMenu,
  MenubarPortal,
  MenubarRadioGroup,
  MenubarRadioItem,
  MenubarSub,
  MenubarSubContent,
  MenubarSubTrigger,
  MenubarTrigger,
} from "./ui/menubar";
import { THEMES, type Theme } from "../hooks/useTheme";

interface Props {
  theme: Theme;
  setTheme: (t: Theme) => void;
}

/**
 * View menu (Phase 67 D-11, D-21 — round 2 trim + Menubar migration).
 *
 * Round 2 — migrated from DropdownMenu to shadcn Menubar so the parent
 * <Menubar> in CustomTitlebar coordinates click-once switching between
 * sibling menus (UAT round 2 #5).
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
 * D-21 — Theme submenu maps over THEMES — adding a new entry to the
 * exported array widens the union and adds a radio item automatically.
 */
export default function ViewMenu({ theme, setTheme }: Props) {
  return (
    <MenubarMenu>
      <MenubarTrigger className="h-full rounded-none px-3 py-0 text-xs font-normal hover:bg-accent hover:text-accent-foreground">
        View
      </MenubarTrigger>
      <MenubarContent align="start">
        <MenubarSub>
          <MenubarSubTrigger>Theme</MenubarSubTrigger>
          <MenubarPortal>
            <MenubarSubContent>
              <MenubarRadioGroup
                value={theme}
                onValueChange={(v) => setTheme(v as Theme)}
              >
                {THEMES.map((t) => (
                  <MenubarRadioItem key={t} value={t}>
                    {t.charAt(0).toUpperCase() + t.slice(1)}
                  </MenubarRadioItem>
                ))}
              </MenubarRadioGroup>
            </MenubarSubContent>
          </MenubarPortal>
        </MenubarSub>
      </MenubarContent>
    </MenubarMenu>
  );
}
