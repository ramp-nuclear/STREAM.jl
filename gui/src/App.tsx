import { useEffect, useRef, useState, useCallback } from "react";
import { ReactFlowProvider } from "@xyflow/react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import ToolboxPanel from "./components/ToolboxPanel";
import LayersPanel from "./components/LayersPanel";
import ResourcesTreePanel from "./components/resources/ResourcesTreePanel";
import ModelOptionsPanel from "./components/project/ModelOptionsPanel";
import PresetsPanel from "./components/PresetsPanel";
import SavePresetModal from "./components/SavePresetModal";
import CanvasPanel from "./components/CanvasPanel";
import SidebarPanel from "./components/SidebarPanel";
import CustomTitlebar from "./components/CustomTitlebar";
import BottomPanel from "./components/BottomPanel";
import ValidationStatusBar from "./components/ValidationStatusBar";
import UnsavedChangesDialog from "./components/UnsavedChangesDialog";
import CommandPalette from "./components/CommandPalette";
import AnatomyDialog from "./components/AnatomyDialog";
import PreferencesDialog from "./components/PreferencesDialog";
import AutoRecoverRestoreModal, {
  type RestoreCandidate,
} from "./components/AutoRecoverRestoreModal";
import { TooltipProvider } from "./components/ui/tooltip";
import { Toaster } from "./components/ui/sonner";
import ExportConfirmDialog from "./components/ExportConfirmDialog";
import { Tabs, TabsContent } from "@/components/ui/tabs";
import { ResponsiveTabsList } from "./components/ResponsiveTabsList";
import { Boxes, Library, Settings2, BookMarked } from "lucide-react";
import useStore from "./store/useStore";
import { initializeRecentFiles, initAutoRecover, initValidation } from "./store/useStore";
import { detectCrashOnLaunch } from "./lib/autoRecover";
import type { LockfileContent } from "./lib/autoRecover";
import {
  initPreferencesBridge,
  getPreference,
  onPreferenceChange,
} from "./lib/preferences";
import { useResizable } from "./hooks/useResizable";
import { useTheme } from "./hooks/useTheme";
import { useShowCodeFor } from "./hooks/useShowCodeFor";

type DialogCallback = (action: "save" | "discard" | "cancel") => void;

// Phase 72 (help-system) — declare the help-surface custom events so the
// keydown/dispatch wiring below is fully typed. `gsd:open-command-palette`
// is the legacy ViewMenu hook (Phase 69 D-02); kept for parity.
declare global {
  interface WindowEventMap {
    "stream:open-shortcuts": CustomEvent<void>;
    "stream:open-anatomy": CustomEvent<void>;
    "stream:open-preferences": CustomEvent<void>;
  }
}

function App() {
  // Phase 66 Plan 03: install the window-level `stream:show-code-for` listener
  // at app root so it survives BottomPanel mount/unmount cycles (CodePreview
  // is short-circuited when the bottom panel is closed — Pitfall 2). Writes
  // detail.nodeIds → useStore.pendingShowCodeFor; CodePreview consumes on
  // next render (Plan 04 wires the consumer).
  useShowCodeFor();

  const [dialogOpen, setDialogOpen] = useState(false);
  const dialogCallbackRef = useRef<DialogCallback | null>(null);

  // Phase 69 Plan 03 — Ctrl+P command palette open/closed state.
  // Local component state, not zustand (CONTEXT.md: "No new top-level state
  // slices for transient UI"). Toggled by the Ctrl+P branch in handleKeyDown
  // below and by the palette's onOpenChange (Esc / click-outside / select).
  const [paletteOpen, setPaletteOpen] = useState(false);
  // Phase 72 (help-system) — which view the palette opens in. Set by the
  // opener (`?` → "shortcuts"; `Ctrl+P` → "commands"; menu entries pass the
  // same). The palette then owns mode internally and lets the user swap.
  const [paletteMode, setPaletteMode] = useState<"commands" | "shortcuts">(
    "commands",
  );
  // Phase 72 (help-system) — AnatomyDialog open/closed. Same local-state
  // pattern as paletteOpen.
  const [anatomyOpen, setAnatomyOpen] = useState(false);
  // Phase 72 (Preferences) — PreferencesDialog open/closed.
  const [preferencesOpen, setPreferencesOpen] = useState(false);

  // Panel collapse state
  const toolboxCollapsed = useStore((s) => s.toolboxCollapsed);
  const sidebarCollapsed = useStore((s) => s.sidebarCollapsed);
  const setToolboxCollapsed = useStore((s) => s.setToolboxCollapsed);
  const setSidebarCollapsed = useStore((s) => s.setSidebarCollapsed);

  // Phase 62 D-01 / D-07 — left-panel tabs + Ctrl+1/2/3 accelerators
  const activeLeftTab = useStore((s) => s.activeLeftTab);
  const setActiveLeftTab = useStore((s) => s.setActiveLeftTab);

  // Panel resize hooks
  const toolboxResize = useResizable({ direction: "left", minWidth: 120, maxWidth: 360, defaultWidth: 240 });
  const sidebarResize = useResizable({ direction: "right", minWidth: 200, maxWidth: 400, defaultWidth: 320 });

  // Theme
  const { theme, resolvedTheme, setTheme } = useTheme();

  // Returns a promise that resolves when the user picks an action.
  const showUnsavedDialog = useCallback(
    (): Promise<"save" | "discard" | "cancel"> =>
      new Promise((resolve) => {
        dialogCallbackRef.current = resolve;
        setDialogOpen(true);
      }),
    [],
  );

  function handleDialogSave() {
    setDialogOpen(false);
    dialogCallbackRef.current?.("save");
  }
  function handleDialogDiscard() {
    setDialogOpen(false);
    dialogCallbackRef.current?.("discard");
  }
  function handleDialogCancel() {
    setDialogOpen(false);
    dialogCallbackRef.current?.("cancel");
  }

  // ---------------------------------------------------------------------------
  // Phase 65 Plan 08: AutoRecover crash-detection + restore modal (D-03/D-04)
  // ---------------------------------------------------------------------------

  // null  = crash check not yet run (show boot splash)
  // []    = crash check done, no crash → normal workspace
  // [...] = crash detected → show blocking restore modal
  const [restoreCandidates, setRestoreCandidates] = useState<
    RestoreCandidate[] | null
  >(null);
  const teardownRef = useRef<(() => Promise<void>) | null>(null);

  // Helper: derive a RestoreCandidate from a basename + stale lockfile
  function buildRestoreCandidate(
    basename: string,
    staleLockfile: LockfileContent | null,
  ): RestoreCandidate {
    const isUntitled = basename.startsWith("untitled-");
    const displayName = isUntitled
      ? "Unsaved project"
      : basename.replace(/\.scp\.autosave$/, "");
    const modifiedAt = staleLockfile?.startedAt ?? new Date().toISOString();
    return { basename, displayName, modifiedAt };
  }

  useEffect(() => {
    let canceled = false;
    (async () => {
      // Get current PID via Tauri IPC
      let pid = 0;
      try {
        // v2 IPC: use ES-module import, not window.__TAURI__ (which is intentionally undefined). See autoRecover.ts header for the long-form rationale.
        const { invoke } = await import("@tauri-apps/api/core");
        pid = await invoke<number>("get_pid");
      } catch {
        // Non-Tauri env (e.g. browser preview) — treat as no crash
      }

      const result = await detectCrashOnLaunch(pid);
      if (canceled) return;

      if (result.crashed) {
        // Crash detected — show modal before workspace loads.
        // DEFER initAutoRecover until user resolves the modal (D-02: don't
        // clobber the stale lockfile while we're still inspecting it).
        const candidates = result.sidecars.map((basename) =>
          buildRestoreCandidate(basename, result.staleLockfile),
        );
        setRestoreCandidates(candidates);
      } else {
        // Clean launch — start the autoRecover writer + lockfile immediately.
        setRestoreCandidates([]);
        try {
          const { teardown } = await initAutoRecover();
          if (!canceled) {
            teardownRef.current = teardown;
          } else {
            // Effect cleaned up before init returned — tear down immediately
            await teardown();
          }
        } catch (err) {
          console.error("[AutoRecover] initAutoRecover on clean launch failed:", err);
        }
      }
    })();

    return () => {
      canceled = true;
      if (teardownRef.current) {
        void teardownRef.current();
        teardownRef.current = null;
      }
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Modal resolution handlers (try/finally: initAutoRecover always runs even on
  // error, and modal always closes — user has committed to a choice)
  async function handleRecover(basename: string) {
    try {
      await useStore.getState().recoverFromSidecar(basename);
    } catch (err) {
      console.error("[AutoRecover] Recover failed:", err);
    } finally {
      try {
        const { teardown } = await initAutoRecover();
        teardownRef.current = teardown;
      } catch (err) {
        console.error("[AutoRecover] initAutoRecover after Recover failed:", err);
      }
      setRestoreCandidates([]);
    }
  }

  async function handleDiscard() {
    try {
      await useStore.getState().discardAllSidecars();
    } catch (err) {
      console.error("[AutoRecover] Discard failed:", err);
    } finally {
      try {
        const { teardown } = await initAutoRecover();
        teardownRef.current = teardown;
      } catch (err) {
        console.error("[AutoRecover] initAutoRecover after Discard failed:", err);
      }
      setRestoreCandidates([]);
    }
  }

  // Initialize recent files on mount
  useEffect(() => {
    initializeRecentFiles();
  }, []);

  // Phase 71 Plan 10: bootstrap validation subscription on App lifetime.
  // initValidation() wires a zustand subscribe listener that runs all validators
  // on every store mutation affecting nodes/edges/anchors/bcMode/resources, and
  // writes validationResults + errorNodeIds back to the store (D-09).
  // The returned teardown cleans up the listener + any pending debounce timer.
  // Separate useEffect from autoRecover — these are independent subscriptions.
  useEffect(() => {
    const teardown = initValidation();
    return teardown;
  }, []);

  // Keyboard shortcuts (global)
  // kbLock prevents re-entrant execution: on Linux, GTK native dialogs leak
  // keystrokes (e.g. Ctrl+N = new folder) into the WebView while open, which
  // would trigger newProject() mid-save and clear the canvas.
  const kbLock = useRef(false);
  useEffect(() => {
    const handleKeyDown = async (e: KeyboardEvent) => {
      if (kbLock.current) return;
      try {
        // Ctrl+Shift+S — Save As
        if ((e.ctrlKey || e.metaKey) && e.key === "s" && e.shiftKey) {
          e.preventDefault();
          kbLock.current = true;
          await useStore.getState().saveProjectAs();
          return;
        }
        // Ctrl+S — Save
        if ((e.ctrlKey || e.metaKey) && e.key === "s" && !e.shiftKey) {
          e.preventDefault();
          kbLock.current = true;
          await useStore.getState().saveProject();
          return;
        }
        // Ctrl+O — Open
        if ((e.ctrlKey || e.metaKey) && e.key === "o") {
          e.preventDefault();
          kbLock.current = true;
          const { isDirty: dirty } = useStore.getState();
          if (dirty) {
            const action = await showUnsavedDialog();
            if (action === "cancel") return;
            if (action === "save") await useStore.getState().saveProject();
          }
          await useStore.getState().loadProject();
          return;
        }
        // Ctrl+N — New
        if ((e.ctrlKey || e.metaKey) && e.key === "n") {
          e.preventDefault();
          kbLock.current = true;
          const { isDirty: dirty } = useStore.getState();
          if (dirty) {
            const action = await showUnsavedDialog();
            if (action === "cancel") return;
            if (action === "save") await useStore.getState().saveProject();
          }
          await useStore.getState().newProject();
          return;
        }
        // Ctrl+` (backtick) — Toggle bottom code panel (Phase 68 D-13).
        // Skip when the user is editing text so a literal backtick still types
        // into inputs / textareas / contentEditable surfaces (same guard
        // pattern as the Esc clear-pins handler below).
        if ((e.ctrlKey || e.metaKey) && e.key === "`") {
          const target = e.target as HTMLElement | null;
          if (
            target instanceof HTMLInputElement ||
            target instanceof HTMLTextAreaElement ||
            target instanceof HTMLSelectElement ||
            (target && target.isContentEditable)
          ) {
            return;
          }
          e.preventDefault();
          useStore.getState().toggleBottomPanel();
          return;
        }
      } catch (err) {
        console.error("[handleKeyDown] unhandled error:", err);
      } finally {
        kbLock.current = false;
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [showUnsavedDialog]);

  // Phase 62 D-07 / INV-12 — Ctrl+1..Ctrl+4 left-tab accelerators.
  // Bound globally on window per UI-SPEC §"Tab strip — preventDefault on
  // accelerator". Only bare Ctrl is honored — Ctrl+Shift+N / Alt+N / Meta+N
  // are passed through so Ctrl+Shift+S (Save As) still wins. Ctrl+Tab is
  // intentionally NOT intercepted (D-07: browser-collision avoidance).
  // Order (Phase 70 UAT reshuffle): 1=Components, 2=Presets, 3=Resources, 4=Project.
  // Components and Presets are both drag-source palettes (grouped left); Resources
  // configures already-dropped nodes; Project is metadata/file-ops (rightmost).
  useEffect(() => {
    const handleLeftTabKey = (e: KeyboardEvent) => {
      if (!e.ctrlKey || e.shiftKey || e.altKey || e.metaKey) return;
      if (e.key === "1") {
        e.preventDefault();
        setActiveLeftTab("Components");
      } else if (e.key === "2") {
        e.preventDefault();
        setActiveLeftTab("Presets");
      } else if (e.key === "3") {
        e.preventDefault();
        setActiveLeftTab("Resources");
      } else if (e.key === "4") {
        e.preventDefault();
        setActiveLeftTab("Project");
      }
    };
    window.addEventListener("keydown", handleLeftTabKey);
    return () => window.removeEventListener("keydown", handleLeftTabKey);
  }, [setActiveLeftTab]);

  // Phase 70 D-01 — SavePresetModal open state. Lifted to App.tsx so both
  // FileMenu (sibling) and NodeContextMenu (deep descendant) can open it via
  // a custom DOM event, keeping coupling low (mirrors the Ctrl+P / palette pattern).
  const [savePresetOpen, setSavePresetOpen] = useState(false);
  useEffect(() => {
    const handler = () => setSavePresetOpen(true);
    window.addEventListener("stream:open-save-preset", handler);
    return () => window.removeEventListener("stream:open-save-preset", handler);
  }, []);

  // Phase 69 D-02 — Ctrl+P toggles the command palette.
  // Pitfall 1 (RESEARCH.md): preventDefault() MUST run synchronously before
  // any state mutation or early-return so the OS/browser Print dialog never
  // leaks. The earlier consolidated handleKeyDown gates ALL its branches
  // behind `if (kbLock.current) return;` — if a Ctrl+S save dialog is
  // awaiting IPC, kbLock is true and the Ctrl+P branch would be skipped
  // BEFORE preventDefault ran, letting the Print dialog through. Hoisting
  // Ctrl+P into its own listener (mirroring the Ctrl+1/2/3 pattern above)
  // bypasses kbLock entirely.
  // Ctrl+Shift+P is intentionally NOT intercepted (CONTEXT.md: Ctrl+P-only).
  useEffect(() => {
    const handlePaletteKey = (e: KeyboardEvent) => {
      // e.key is uppercase when caps lock is on ("P" instead of "p"), so
      // compare case-insensitively. UAT round 2 caught the original `=== "p"`
      // missing the caps-lock case (Linux/GTK confirmed; Windows/macOS too).
      if (
        !(e.ctrlKey || e.metaKey) ||
        e.key.toLowerCase() !== "p" ||
        e.shiftKey
      )
        return;
      // Always-swallow: preventDefault first to suppress the OS Print dialog
      // (Pitfall 1). Then toggle the palette regardless of focus — Ctrl+P is
      // a navigation shortcut with no in-input semantics, and every
      // comparable tool (VSCode, Linear, Notion, Figma) opens the palette
      // even while a text field is focused. UAT round 1 flagged the prior
      // input-focus skip as overly cautious.
      e.preventDefault();
      setPaletteOpen((v) => !v);
    };
    // Discoverability hook: View → Jump to… (ViewMenu.tsx) dispatches this
    // custom event so the menu entry shares one open path with Ctrl+P.
    // Keeps paletteOpen as local App state (no store churn) while still
    // letting any chrome surface open the palette by name.
    const handleOpenEvent = () => {
      setPaletteMode("commands");
      setPaletteOpen(true);
    };
    // Phase 72 (help-system) — `?` opens the palette in shortcut mode. Sits
    // beside Ctrl+P in its own handler. Same input-focus guard as Ctrl+`
    // and Esc — typing `?` into a text input must still produce a literal
    // `?` rather than open the palette.
    const handleShortcutsKey = (e: KeyboardEvent) => {
      if (e.key !== "?") return;
      const target = e.target as HTMLElement | null;
      if (
        target instanceof HTMLInputElement ||
        target instanceof HTMLTextAreaElement ||
        target instanceof HTMLSelectElement ||
        (target && target.isContentEditable)
      ) {
        return;
      }
      e.preventDefault();
      setPaletteMode("shortcuts");
      setPaletteOpen(true);
    };
    // Phase 72 (help-system) — menu entry "Show Shortcuts… ?" dispatches
    // a custom event so the menu and `?` share one open path.
    const handleOpenShortcuts = () => {
      setPaletteMode("shortcuts");
      setPaletteOpen(true);
    };
    // Phase 72 (help-system) — menu entry "Show Anatomy…" dispatches a
    // custom event from HelpMenu. AnatomyDialog has no global keybind by
    // design (low-frequency reference doesn't earn one).
    const handleOpenAnatomy = () => setAnatomyOpen(true);
    // Phase 72 (Preferences) — Ctrl+, opens / toggles the PreferencesDialog.
    // Same input-focus guard as Ctrl+` and `?` — typing a literal comma
    // inside a text input must still produce a comma. Edit menu entry +
    // `stream:open-preferences` custom event share this open path.
    const handlePreferencesKey = (e: KeyboardEvent) => {
      if (!(e.ctrlKey || e.metaKey) || e.key !== "," || e.shiftKey) return;
      const target = e.target as HTMLElement | null;
      if (
        target instanceof HTMLInputElement ||
        target instanceof HTMLTextAreaElement ||
        target instanceof HTMLSelectElement ||
        (target && target.isContentEditable)
      ) {
        return;
      }
      e.preventDefault();
      setPreferencesOpen((v) => !v);
    };
    const handleOpenPreferences = () => setPreferencesOpen(true);
    window.addEventListener("keydown", handlePaletteKey);
    window.addEventListener("keydown", handleShortcutsKey);
    window.addEventListener("keydown", handlePreferencesKey);
    window.addEventListener("gsd:open-command-palette", handleOpenEvent);
    window.addEventListener("stream:open-shortcuts", handleOpenShortcuts);
    window.addEventListener("stream:open-anatomy", handleOpenAnatomy);
    window.addEventListener("stream:open-preferences", handleOpenPreferences);
    return () => {
      window.removeEventListener("keydown", handlePaletteKey);
      window.removeEventListener("keydown", handleShortcutsKey);
      window.removeEventListener("keydown", handlePreferencesKey);
      window.removeEventListener("gsd:open-command-palette", handleOpenEvent);
      window.removeEventListener("stream:open-shortcuts", handleOpenShortcuts);
      window.removeEventListener("stream:open-anatomy", handleOpenAnatomy);
      window.removeEventListener("stream:open-preferences", handleOpenPreferences);
    };
  }, []);

  // Phase 72 Preferences — bridge user-global prefs to the per-runtime
  // mirrors in useStore. The store's slice already seeds initial values from
  // localStorage at module-eval time; this bridge keeps them in sync when
  // the dialog (or a canvas overlay button writing through setPreference)
  // flips a setting at runtime.
  useEffect(() => {
    return initPreferencesBridge({
      setHideOffLayer: useStore.getState().setHideOffLayer,
      setSnapToGrid: useStore.getState().setSnapToGrid,
      setInteractiveLocked: useStore.getState().setInteractiveLocked,
    });
  }, []);

  // Phase 72 (post-Preferences) — apply the `appearance.reduceMotion`
  // override by writing a `data-motion` attribute on <html>. CSS rules in
  // index.css consume it (see the data-motion blocks). Three states:
  //   - "system" (default) → no attribute; OS pref drives motion
  //   - "always" → data-motion="full"; OS reduced-motion is overridden OFF
  //   - "never"  → data-motion="reduced"; OS pref is overridden ON
  useEffect(() => {
    function apply() {
      const v = getPreference("appearance", "reduceMotion");
      const html = document.documentElement;
      if (v === "always") html.setAttribute("data-motion", "full");
      else if (v === "never") html.setAttribute("data-motion", "reduced");
      else html.removeAttribute("data-motion");
    }
    apply();
    return onPreferenceChange((detail) => {
      if (detail.category === "*" || detail.category === "appearance") apply();
    });
  }, []);

  // Phase 66 Plan 03: Esc clears pinned code-panel sub-blocks.
  // Coexists with the CanvasPanel.tsx Esc handler and the SidebarPanel.tsx
  // Esc handler (Phase 65 Plan 10): all three are global on window keydown,
  // none call stopPropagation, and each clears its own slice idempotently.
  // Input-focus guard is the SAME predicate as CanvasPanel.tsx:276-289 — when
  // the user is editing text, Esc should not clear pins.
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return;
      const target = e.target as HTMLElement;
      if (
        target instanceof HTMLInputElement ||
        target instanceof HTMLTextAreaElement ||
        target instanceof HTMLSelectElement ||
        target.isContentEditable
      ) {
        return;
      }
      useStore.getState().clearPinnedSourceIds();
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, []);

  // Window title sync — subscribe outside React to bypass render batching.
  // On Linux/WebKitGTK, setTitle() IPC doesn't update the GTK title bar reliably;
  // we invoke the underlying command directly as a fallback.
  useEffect(() => {
    function syncTitle(filePath: string | null, dirty: boolean) {
      const filename = filePath ? filePath.split(/[/\\]/).pop() : null;
      const marker = dirty ? "*" : "";
      const title = filename
        ? `${filename}${marker} - STREAM Composer`
        : "STREAM Composer";
      document.title = title;
      getCurrentWindow().setTitle(title).catch(console.error);
    }

    // Run immediately with current state
    const s = useStore.getState();
    syncTitle(s.currentFilePath, s.isDirty);

    // Phase 65 Plan 14: selector-gated — setTitle IPC fires only on filePath/dirty change.
    const unsub = useStore.subscribe(
      (state) => ({ filePath: state.currentFilePath, dirty: state.isDirty }),
      ({ filePath, dirty }) => syncTitle(filePath, dirty),
      {
        equalityFn: (a, b) =>
          a.filePath === b.filePath && a.dirty === b.dirty,
      },
    );
    return unsub;
  }, []);

  // Window close guard — fixed: track unlisten via ref to avoid async race in Strict Mode
  const unlistenRef = useRef<(() => void) | null>(null);
  useEffect(() => {
    let active = true;

    getCurrentWindow()
      .onCloseRequested(async (event) => {
        const { isDirty: dirty } = useStore.getState();
        if (!dirty) return; // allow close

        event.preventDefault(); // must be synchronous before any await
        const action = await showUnsavedDialog();
        if (action === "save") {
          await useStore.getState().saveProject();
        }
        if (action !== "cancel") {
          // destroy() bypasses CloseRequested — avoids re-triggering this guard
          await getCurrentWindow().destroy();
        }
      })
      .then((fn) => {
        if (!active) {
          fn(); // effect already cleaned up — unlisten immediately
        } else {
          unlistenRef.current = fn;
        }
      });

    return () => {
      active = false;
      unlistenRef.current?.();
      unlistenRef.current = null;
    };
  }, [showUnsavedDialog]);

  // ---------------------------------------------------------------------------
  // Phase 65 Plan 08: Render gate — AutoRecover modal or boot splash (D-03)
  // ---------------------------------------------------------------------------

  // While crash check hasn't completed: show a minimal boot splash.
  if (restoreCandidates === null) {
    return <div className="h-screen w-screen bg-background" />;
  }

  // Crash detected: show blocking modal BEFORE the canvas mounts (D-03).
  if (restoreCandidates.length > 0) {
    return (
      <AutoRecoverRestoreModal
        candidates={restoreCandidates}
        onRecover={handleRecover}
        onDiscard={handleDiscard}
      />
    );
  }

  return (
    <ReactFlowProvider>
      <TooltipProvider delayDuration={500} skipDelayDuration={300}>
        <div className="flex flex-col h-screen w-screen overflow-hidden">
          <CustomTitlebar
            onUnsavedCheck={showUnsavedDialog}
            theme={theme}
            setTheme={setTheme}
          />
          <div className="flex flex-1 min-h-0">
            {!toolboxCollapsed && (
              <div
                className="relative h-full border-r shrink-0 flex flex-col overflow-hidden bg-panel"
                style={{ width: toolboxResize.width }}
              >
                {/* VS Code-style sash on inner edge: 4px hit area, transparent at
                    rest, subtle hover tint, double-click to collapse. The panel's
                    `border-r` is the 1px visible line; this overlay is the hit/drag
                    surface. */}
                <div
                  role="separator"
                  aria-orientation="vertical"
                  aria-label="Resize left panel"
                  className="absolute right-0 top-0 w-1 h-full cursor-col-resize z-10 hover:bg-primary/40 active:bg-primary/60 transition-colors"
                  onMouseDown={toolboxResize.onMouseDown}
                  onDoubleClick={() => setToolboxCollapsed(true)}
                />
                {/* Phase 62 D-01 — left-panel tab strip. Phase 70 reshuffle:
                    order is [Components][Presets][Resources][Project] — drag-source
                    palettes (Components, Presets) grouped left; Resources configures
                    dropped nodes; Project (mostly handled via File menu) rightmost.
                    ResponsiveTabsList collapses overflowing tabs into a "..." menu
                    when the panel is too narrow. UI-SPEC §Tab strip: text-only,
                    bottom-border active indicator, no bg pill. */}
                <Tabs
                  value={activeLeftTab}
                  onValueChange={(v) =>
                    setActiveLeftTab(v as "Components" | "Presets" | "Resources" | "Project")
                  }
                  className="flex-1 min-h-0 gap-0"
                >
                  <ResponsiveTabsList
                    tabs={[
                      { value: "Components", label: "Components", icon: Boxes },
                      { value: "Presets", label: "Presets", icon: BookMarked },
                      { value: "Resources", label: "Resources", icon: Library },
                      { value: "Project", label: "Project", icon: Settings2 },
                    ]}
                    value={activeLeftTab}
                    onValueChange={(v) =>
                      setActiveLeftTab(v as "Components" | "Presets" | "Resources" | "Project")
                    }
                  />
                  <TabsContent value="Components" className="flex-1 min-h-0 overflow-hidden mt-0">
                    <ToolboxPanel />
                  </TabsContent>
                  <TabsContent value="Presets" className="flex-1 min-h-0 overflow-hidden mt-0">
                    <PresetsPanel />
                  </TabsContent>
                  <TabsContent value="Resources" className="flex-1 min-h-0 overflow-hidden mt-0">
                    <ResourcesTreePanel />
                  </TabsContent>
                  <TabsContent value="Project" className="flex-1 min-h-0 overflow-hidden mt-0">
                    <ModelOptionsPanel />
                  </TabsContent>
                </Tabs>
                {/* Phase 68 — LayersPanel docked at the bottom of the left
                    sidebar. Always visible while sidebar is open, regardless
                    of active tab. Replaces the canvas-overlay LayersChip
                    deleted after UAT 2026-05-17. */}
                <LayersPanel />
              </div>
            )}
            {/* Collapsed-edge re-expand affordance for the left panel. Renders only
                when the panel is hidden: a 4px clickable strip flush with the canvas
                edge. Cursor + tooltip do the discovery work. */}
            {toolboxCollapsed && (
              <button
                type="button"
                aria-label="Expand left panel"
                title="Expand left panel"
                className="h-full w-1 shrink-0 border-r cursor-pointer hover:bg-primary/40 transition-colors"
                onClick={() => setToolboxCollapsed(false)}
              />
            )}
            <div className="flex flex-col flex-1 min-w-0">
              <CanvasPanel resolvedTheme={resolvedTheme} />
            </div>
            {sidebarCollapsed && (
              <button
                type="button"
                aria-label="Expand right panel"
                title="Expand right panel"
                className="h-full w-1 shrink-0 border-l cursor-pointer hover:bg-primary/40 transition-colors"
                onClick={() => setSidebarCollapsed(false)}
              />
            )}
            {!sidebarCollapsed && (
              <SidebarPanel
                width={sidebarResize.width}
                onResizeMouseDown={sidebarResize.onMouseDown}
                onCollapse={() => setSidebarCollapsed(true)}
              />
            )}
          </div>
          <BottomPanel />
          <ValidationStatusBar />
        </div>
        <UnsavedChangesDialog
          open={dialogOpen}
          onSave={handleDialogSave}
          onDiscard={handleDialogDiscard}
          onCancel={handleDialogCancel}
        />
        {/* Phase 69 Plan 03 — CommandPalette mounted as a sibling to the
            other dialogs INSIDE <ReactFlowProvider> + <TooltipProvider>
            (Pitfall 2: useReactFlow() inside the palette requires a parent
            ReactFlowProvider; mounting at the root above the render gate
            would crash on open). */}
        <CommandPalette
          open={paletteOpen}
          onOpenChange={setPaletteOpen}
          initialMode={paletteMode}
        />
        {/* Phase 72 (help-system) — AnatomyDialog. Visual legend for the
            canvas vocabulary (StreamNode + edges + their states). Opens from
            HelpMenu only; no keybind by design. */}
        <AnatomyDialog open={anatomyOpen} onOpenChange={setAnatomyOpen} />
        {/* Phase 72 (Preferences) — user-global Preferences dialog. Opens
            from Edit > Preferences… or Ctrl+, (Linear / Cursor / VSCode
            convention). Strictly user-global; per-project state stays in
            Project Options. */}
        <PreferencesDialog
          open={preferencesOpen}
          onOpenChange={setPreferencesOpen}
        />
        {/* Phase 70 Plan 06 — SavePresetModal mounted at the top level so both
            FileMenu and NodeContextMenu can open it via the
            "stream:open-save-preset" custom event without prop drilling. */}
        <SavePresetModal open={savePresetOpen} onOpenChange={setSavePresetOpen} />
        {/* Phase 71 Plan 10 — sonner Toaster mounted once at app lifetime.
            Position bottom-right, 2s duration, theme-aware via useTheme()
            inside the Toaster wrapper. Plan 12 fires the export-gate toast
            here. Mounted inside <TooltipProvider> per plan instructions. */}
        <Toaster />
        <ExportConfirmDialog />
      </TooltipProvider>
    </ReactFlowProvider>
  );
}

export default App;
