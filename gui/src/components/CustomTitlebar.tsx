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
 * Custom titlebar shell (Phase 67 D-01/D-05/D-06/D-07/D-13/D-26).
 *
 * 36px full-width strip composing:
 *   [icon] [project name] [● dirty] [File][Edit][View][Help] [drag region (sibling)] [WindowControls]
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

  // D-06 — project name display
  let projectName = "";
  if (currentFilePath) {
    const basename = currentFilePath.split(/[/\\]/).pop() ?? "";
    projectName = basename.replace(/\.[^.]+$/, "");
  } else if (isDirty) {
    projectName = "Untitled";
  }

  return (
    <div className="flex items-center h-9 bg-chrome border-b w-full">
      <img
        src="/32x32.png"
        alt=""
        className="w-5 h-5 ml-2 shrink-0"
      />
      <span className="text-xs text-muted-foreground ml-1 select-none truncate max-w-[120px]">
        {projectName}
      </span>
      {isDirty && (
        <span className="text-xs text-muted-foreground ml-0.5 select-none">
          ●
        </span>
      )}
      {/* Single <Menubar> parent coordinates click-once switching between
          sibling menus (Office / VSCode / IntelliJ pattern — UAT round 2 #5).
          Override shadcn's default border / bg / padding so the menubar
          is transparent and inherits the chrome bg from the titlebar. */}
      <Menubar className="border-0 bg-transparent shadow-none p-0 h-full rounded-none gap-0">
        <FileMenu onUnsavedCheck={onUnsavedCheck} />
        <EditMenu />
        <ViewMenu theme={theme} setTheme={setTheme} />
        <HelpMenu />
      </Menubar>
      {/* D-26: drag region MUST be a sibling (not a wrapper) — wrapping the
          menu cluster inside data-tauri-drag-region breaks Radix click
          handlers (Tauri #9901). */}
      <div
        data-tauri-drag-region
        className="flex-1 h-full"
        onDoubleClick={() => void getCurrentWindow().toggleMaximize()}
      />
      <WindowControls />
    </div>
  );
}
