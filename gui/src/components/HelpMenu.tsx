import { useState } from "react";
import {
  MenubarContent,
  MenubarItem,
  MenubarMenu,
  MenubarTrigger,
} from "./ui/menubar";
import AboutDialog from "./AboutDialog";

/**
 * Help menu (Phase 67 D-12).
 *
 * Round 2 — migrated from DropdownMenu to shadcn Menubar so the parent
 * <Menubar> in CustomTitlebar coordinates click-once switching between
 * sibling menus (UAT round 2 #5).
 *
 * - About STREAM Composer opens AboutDialog (controlled via local state).
 * - Keyboard Shortcuts is a disabled stub deferred to Phase 72.
 *
 * The AboutDialog is rendered as a sibling AFTER the closing </MenubarMenu>
 * to keep JSX flat — Radix Portal handles z-order either way.
 */
export default function HelpMenu() {
  const [aboutOpen, setAboutOpen] = useState(false);

  return (
    <>
      <MenubarMenu>
        <MenubarTrigger className="h-full rounded-none px-3 py-0 text-xs font-normal hover:bg-accent hover:text-accent-foreground">
          Help
        </MenubarTrigger>
        <MenubarContent align="start">
          <MenubarItem onClick={() => setAboutOpen(true)}>
            <span>About STREAM Composer</span>
          </MenubarItem>
          <MenubarItem disabled>
            <span>Keyboard Shortcuts</span>
          </MenubarItem>
        </MenubarContent>
      </MenubarMenu>
      <AboutDialog open={aboutOpen} onOpenChange={setAboutOpen} />
    </>
  );
}
