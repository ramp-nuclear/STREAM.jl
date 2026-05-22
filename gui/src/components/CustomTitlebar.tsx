import { useState, useRef, useEffect } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import useStore from "../store/useStore";
import FileMenu from "./FileMenu";
import EditMenu from "./EditMenu";
import ViewMenu from "./ViewMenu";
import HelpMenu from "./HelpMenu";
import WindowControls from "./WindowControls";
import { Menubar } from "./ui/menubar";
import type { Theme } from "../hooks/useTheme";

interface Props {
  onUnsavedCheck: () => Promise<"save" | "discard" | "cancel">;
  theme: Theme;
  setTheme: (t: Theme) => void;
}

/**
 * Custom titlebar shell (Phase 67 D-01/D-05/D-06/D-07/D-13/D-26, round 2 #8).
 *
 * 36px full-width strip with three layers:
 *   - Left cluster (anchored left): [icon] [File][Edit][View][Help]
 *   - Center overlay (absolute, pointer-events-none): [filename] [● dirty]
 *   - Right cluster (anchored right): [WindowControls]
 *   - Drag region: sibling div between left cluster and right cluster
 *
 * Round 2 #8 — the filename + dirty dot now render as an `absolute` overlay
 * centered horizontally in the titlebar. Previously the name was inline
 * between the icon and the menu cluster, which pushed the menus and drag
 * region right as the filename grew. `pointer-events-none` on the center
 * overlay ensures clicks pass through to the sibling drag region so window
 * dragging is unaffected.
 *
 * D-26 — `data-tauri-drag-region` is a SIBLING div between the menu cluster
 * and WindowControls, never a wrapper. Wrapping menus inside it breaks click
 * handlers (Tauri issue #9901; see 67-RESEARCH.md Pitfall 2).
 *
 * D-06 — Project name derives from currentFilePath basename without extension;
 * falls back to "Untitled" when isDirty && !currentFilePath; empty when clean
 * and unsaved. The dirty marker is a literal Unicode bullet `●` (NOT a Lucide
 * icon — UI-SPEC §Copywriting).
 *
 * D-25 — App icon path is `/32x32.png` (Vite serves gui/public/32x32.png at root).
 *
 * Theme/setTheme are passed in from App.tsx (single useTheme() owner) and
 * forwarded to ViewMenu.
 */
export default function CustomTitlebar({
  onUnsavedCheck,
  theme,
  setTheme,
}: Props) {
  const isDirty = useStore((s) => s.isDirty);
  const currentFilePath = useStore((s) => s.currentFilePath);

  // Controlled Menubar state — used to auto-close the active menu when the
  // cursor leaves both the menubar triggers AND the open submenu content
  // (Phase 68 UAT 2026-05-17). Default Radix behavior keeps the menu open
  // until clicked-outside or Escape; the user expects mouse-leave to close.
  //
  // Grace-period close: while a menu is open we watch global mousemove. If
  // the cursor is inside the menubar root OR inside any portaled element
  // with role="menu" (Radix renders submenu content with that role), any
  // pending close timer is cancelled. If the cursor leaves both safe zones,
  // a 200ms close timer is scheduled. The delay covers the unavoidable
  // 1-2px transition between the trigger and the menu content as the user
  // moves between them — without it the cursor briefly registers as
  // "outside" mid-transit and the menu closes prematurely.
  //
  // The trigger's lingering highlight after close is fixed in `ui/menubar.tsx`
  // by removing `focus:bg-accent` from MenubarTrigger's base classes —
  // data-[state=open] is now the only highlight trigger. No blur juggling
  // needed here.
  const [openMenu, setOpenMenu] = useState<string>("");
  const menubarRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!openMenu) return;

    let closeTimer: number | null = null;

    const handler = (e: MouseEvent) => {
      const target = e.target as Element | null;
      if (!target) return;
      const insideMenubar = menubarRef.current?.contains(target);
      const insideMenu = !!target.closest('[role="menu"]');
      if (insideMenubar || insideMenu) {
        if (closeTimer != null) {
          window.clearTimeout(closeTimer);
          closeTimer = null;
        }
      } else if (closeTimer == null) {
        closeTimer = window.setTimeout(() => {
          closeTimer = null;
          setOpenMenu("");
        }, 200);
      }
    };

    // Small initial delay so the synthetic mousemove from the click that
    // opened the menu doesn't get evaluated before the content has mounted.
    const initTimer = window.setTimeout(() => {
      document.addEventListener("mousemove", handler);
    }, 50);

    return () => {
      window.clearTimeout(initTimer);
      if (closeTimer != null) window.clearTimeout(closeTimer);
      document.removeEventListener("mousemove", handler);
    };
  }, [openMenu]);

  // D-06 — project name display
  let projectName = "";
  if (currentFilePath) {
    const basename = currentFilePath.split(/[/\\]/).pop() ?? "";
    projectName = basename.replace(/\.[^.]+$/, "");
  } else if (isDirty) {
    projectName = "Untitled";
  }

  return (
    <div className="relative flex items-center h-9 bg-chrome border-b w-full">
      <img
        src="/32x32.png"
        alt=""
        className="w-5 h-5 mx-3 shrink-0 [filter:brightness(0)_invert(1)]"
      />
      {/* Single <Menubar> parent coordinates click-once switching between
          sibling menus (Office / VSCode / IntelliJ pattern — UAT round 2 #5).
          Override shadcn's default border / bg / padding so the menubar
          is transparent and inherits the chrome bg from the titlebar.
          Phase 68 UAT 2026-05-17 — controlled via openMenu state so the
          mousemove effect above can clear the active menu when the cursor
          leaves both the triggers and any portaled submenu content. */}
      <div ref={menubarRef} className="h-full">
        <Menubar
          value={openMenu}
          onValueChange={setOpenMenu}
          className="border-0 bg-transparent shadow-none p-0 h-full rounded-none gap-0"
        >
          <FileMenu onUnsavedCheck={onUnsavedCheck} />
          <EditMenu />
          <ViewMenu theme={theme} setTheme={setTheme} />
          <HelpMenu />
        </Menubar>
      </div>
      {/* D-26: drag region MUST be a sibling (not a wrapper) — wrapping the
          menu cluster inside data-tauri-drag-region breaks Radix click
          handlers (Tauri #9901). */}
      <div
        data-tauri-drag-region
        className="flex-1 h-full"
        onDoubleClick={() => void getCurrentWindow().toggleMaximize()}
      />
      <WindowControls />
      {/* Absolute-centered filename + dirty dot (round 2 #8). pointer-events-none
          ensures clicks fall through to the sibling drag region underneath, so
          the absolute overlay never intercepts window-drag events. */}
      <div className="pointer-events-none absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 flex items-center max-w-[40%]">
        <span className="text-xs text-muted-foreground select-none truncate">
          {projectName}
        </span>
        {isDirty && (
          <span className="text-xs text-muted-foreground ml-0.5 select-none">
            ●
          </span>
        )}
      </div>
    </div>
  );
}
