import { useState } from "react";
import {
  MenubarContent,
  MenubarItem,
  MenubarMenu,
  MenubarShortcut,
  MenubarTrigger,
} from "./ui/menubar";
import AboutDialog from "./AboutDialog";

/**
 * Help menu (Phase 67 D-12, expanded Phase 72 help-system shape).
 *
 * Entries:
 *   - "Shortcuts" → opens the command palette in shortcut mode via the
 *     `stream:open-shortcuts` custom event. Mirrors the `?` keybind.
 *   - "Anatomy" → opens the AnatomyDialog visual legend via
 *     `stream:open-anatomy`. No keybind by design (low-frequency reference).
 *   - "About STREAM Composer" → AboutDialog (unchanged).
 *
 * Custom events are dispatched on `window` and listened to in App.tsx, where
 * the open state for each surface lives — keeps HelpMenu free of prop drilling
 * and matches the existing `stream:open-save-preset` pattern.
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
          <MenubarItem
            onClick={() =>
              window.dispatchEvent(new CustomEvent("stream:open-shortcuts"))
            }
          >
            <span>Shortcuts</span>
            <MenubarShortcut>?</MenubarShortcut>
          </MenubarItem>
          <MenubarItem
            onClick={() =>
              window.dispatchEvent(new CustomEvent("stream:open-anatomy"))
            }
          >
            <span>Anatomy</span>
          </MenubarItem>
          <MenubarItem onClick={() => setAboutOpen(true)}>
            <span>About STREAM Composer</span>
          </MenubarItem>
        </MenubarContent>
      </MenubarMenu>
      <AboutDialog open={aboutOpen} onOpenChange={setAboutOpen} />
    </>
  );
}
