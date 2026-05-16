import {
  MenubarContent,
  MenubarItem,
  MenubarMenu,
  MenubarPortal,
  MenubarRadioGroup,
  MenubarRadioItem,
  MenubarShortcut,
  MenubarSub,
  MenubarSubContent,
  MenubarSubTrigger,
  MenubarTrigger,
} from "./ui/menubar";
import { THEMES, type Theme } from "../hooks/useTheme";
import useStore from "../store/useStore";

interface Props {
  theme: Theme;
  setTheme: (t: Theme) => void;
}

/**
 * View menu (Phase 67 D-11, D-21 — round 2 trim + Menubar migration;
 * Phase 68 D-07 / D-10 — Layer submenu confirmed removed, Toggle Code Preview
 * added back as the keyboard-shortcut hub entry for Ctrl+`).
 *
 * Round 2 — migrated from DropdownMenu to shadcn Menubar so the parent
 * <Menubar> in CustomTitlebar coordinates click-once switching between
 * sibling menus (UAT round 2 #5).
 *
 * Phase 68:
 *   - Toggle Code Preview lives here (D-10) — same toggleBottomPanel() action
 *     as the bottom-panel header collapse button and the App.tsx Ctrl+`
 *     handler.
 *   - Layer submenu stays removed (D-07) — the floating Layers chip on the
 *     canvas is the sole layer UI for Phase 68 onward.
 *
 * D-21 — Theme submenu maps over THEMES — adding a new entry to the
 * exported array widens the union and adds a radio item automatically.
 */
export default function ViewMenu({ theme, setTheme }: Props) {
  // Phase 68 D-10 / D-13 — Toggle Code Preview rehomed to the View menu after
  // the secondary toolbar strip was deleted. Same store action the App.tsx
  // Ctrl+` shortcut and the BottomPanel header collapse button call: one
  // toggleBottomPanel entry point, three UI surfaces.
  function handleToggleCodePreview() {
    useStore.getState().toggleBottomPanel();
  }

  return (
    <MenubarMenu>
      <MenubarTrigger className="h-full rounded-none px-3 py-0 text-xs font-normal hover:bg-accent hover:text-accent-foreground">
        View
      </MenubarTrigger>
      <MenubarContent align="start">
        <MenubarItem onClick={handleToggleCodePreview}>
          Toggle Code Preview
          <MenubarShortcut>Ctrl+`</MenubarShortcut>
        </MenubarItem>
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
