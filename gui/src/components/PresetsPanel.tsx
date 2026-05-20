import { useEffect, useState } from "react";
import { ChevronDown } from "lucide-react";
import { cn } from "@/lib/utils";
import useStore from "@/store/useStore";
import PresetRow from "./PresetRow";
import type { UnwatchFn } from "@tauri-apps/plugin-fs";

// Phase 70 Plan 70-04 — Presets tab body (4th left-panel tab, D-01).
//
// Structure: full-height scrollable column with two collapsible sections —
// "Project" (entries from <project>/presets/) and "Library" (entries from
// appConfigDir/presets/). Each section renders either:
//   1. A skeleton while the watcher initializes.
//   2. An empty state when no presets exist.
//   3. The list of PresetRow entries.
//
// The watcher useEffect is keyed on currentProjectDir (D-06): project switch
// triggers cleanup of old watchers and rebinding to the new project directory.
//
// Wired into the left-panel Tabs in plan 70-06 (App.tsx <TabsContent>).
// Drop handling lives in plan 70-06 (CanvasPanel.tsx).

export default function PresetsPanel() {
  const projectPresets = useStore((s) => s.projectPresets);
  const libraryPresets = useStore((s) => s.libraryPresets);
  const currentFilePath = useStore((s) => s.currentFilePath);
  const refreshPresetsDir = useStore((s) => s.refreshPresetsDir);

  const [projectExpanded, setProjectExpanded] = useState(true);
  const [libraryExpanded, setLibraryExpanded] = useState(true);
  const [loading, setLoading] = useState(true);

  // Derive the project directory from the current file path.
  // Strip the trailing filename segment (works for both / and \ separators).
  const currentProjectDir = currentFilePath
    ? currentFilePath.replace(/[/\\][^/\\]+$/, "")
    : null;

  // ── File-system watcher lifecycle (D-05, D-06) ────────────────────────────
  useEffect(() => {
    let cancelled = false;
    const unwatchers: UnwatchFn[] = [];
    setLoading(true); // CR-02: reset skeleton on every project rebind (D-06)

    async function setup() {
      const { appConfigDir, join } = await import("@tauri-apps/api/path");
      const { watch, mkdir } = await import("@tauri-apps/plugin-fs");

      // ── Library store ────────────────────────────────────────────────────
      const libDir = await join(await appConfigDir(), "presets");
      // Pitfall 8: ensure the directory exists before watching.
      // WR-02: log unexpected errors; only swallow EEXIST-equivalent.
      await mkdir(libDir, { recursive: true }).catch((err) => {
        const msg = err instanceof Error ? err.message : String(err);
        if (!/already exists|EEXIST/i.test(msg)) {
          console.error("[PresetsPanel] mkdir library presets failed:", err);
        }
      });

      if (cancelled) return;

      await refreshPresetsDir("library", libDir);
      const unwatchLib = await watch(
        libDir,
        () => {
          refreshPresetsDir("library", libDir).catch(console.error);
        },
        { delayMs: 200 },
      );

      if (cancelled) {
        unwatchLib();
        return;
      }
      unwatchers.push(unwatchLib);

      // ── Project store (only if a project is open) ────────────────────────
      if (currentProjectDir) {
        // CR-01: wrap the project-store setup so scope-denied / out-of-HOME
        // errors surface clearly instead of silently emptying the section.
        try {
          const projDir = await join(currentProjectDir, "presets");
          await mkdir(projDir, { recursive: true }).catch((err) => {
            const msg = err instanceof Error ? err.message : String(err);
            if (!/already exists|EEXIST/i.test(msg)) {
              console.error("[PresetsPanel] mkdir project presets failed:", err);
            }
          });

          if (cancelled) return;

          await refreshPresetsDir("project", projDir);
          const unwatchProj = await watch(
            projDir,
            () => {
              refreshPresetsDir("project", projDir).catch(console.error);
            },
            { delayMs: 200 },
          );

          if (cancelled) {
            unwatchProj();
            return;
          }
          unwatchers.push(unwatchProj);
        } catch (err) {
          // Project directory is outside the granted FS scope (CR-01) or
          // another IO error. Log clearly; leave project section empty.
          console.error(
            "[PresetsPanel] Project preset directory unavailable " +
            "(path may be outside FS scope — see Tauri capability CR-01):",
            err,
          );
          if (!cancelled) useStore.getState().setProjectPresets([]);
        }
      } else {
        // No project open — clear any stale project presets.
        if (cancelled) return; // CR-02: guard the clear against cleanup races
        useStore.getState().setProjectPresets([]);
      }

      if (cancelled) return; // CR-02: don't setLoading(false) after cleanup
      setLoading(false);
    }

    setup().catch((err) => {
      console.error("PresetsPanel watcher setup failed", err);
      setLoading(false);
    });

    return () => {
      cancelled = true;
      unwatchers.forEach((fn) => fn());
    };
  }, [currentProjectDir]); // Re-runs on project switch (D-06).

  // ── Reveal handler (passed to PresetRow) ──────────────────────────────────
  // Three-tier strategy, ordered by reliability per platform:
  //
  //   1. Custom Rust command `reveal_in_wsl_explorer` (src-tauri/src/lib.rs):
  //      on WSL2 it converts the Linux path via `wslpath -w` and hands it to
  //      `explorer.exe /select,…`. Returns Err on non-WSL hosts so we move on.
  //   2. plugin-opener `revealItemInDir`: native Finder / Explorer / Linux
  //      DBus FileManager1 path. Works on macOS, Windows, and Linux desktops
  //      with a freedesktop file manager.
  //   3. plugin-opener `openPath(parentDir)`: last-resort — open the
  //      containing folder via xdg-open / Finder / Explorer. Won't select
  //      the file, but the user lands in the right place.
  async function reveal(filePath: string) {
    const opener = await import("@tauri-apps/plugin-opener");
    const { invoke } = await import("@tauri-apps/api/core");

    // Tier 1 — WSL fast-path (no-ops with Err on non-WSL hosts).
    try {
      await invoke("reveal_in_wsl_explorer", { path: filePath });
      return;
    } catch (wslErr) {
      // Quiet on non-WSL hosts; the Rust command returns a "not WSL" message.
      console.debug("reveal_in_wsl_explorer:", wslErr);
    }

    // Tier 2 — native reveal-and-select.
    try {
      await opener.revealItemInDir(filePath);
      return;
    } catch (revealErr) {
      console.warn("revealItemInDir failed, falling back to openPath:", revealErr);
    }

    // Tier 3 — open the parent directory.
    const parent = filePath.replace(/[/\\][^/\\]+$/, "");
    try {
      await opener.openPath(parent);
    } catch (openErr) {
      console.error("openPath fallback also failed:", openErr);
    }
  }

  // ── Render ─────────────────────────────────────────────────────────────────
  return (
    <div className="h-full p-2 overflow-y-auto min-w-0 bg-panel">

      {/* ── Project section ─────────────────────────────────────────────── */}
      <div
        className="flex items-center justify-between gap-1 pl-[8px] pr-[4px] mt-[8px] min-w-0"
        role="heading"
        aria-level={2}
      >
        <span className="text-xs font-semibold uppercase tracking-wide text-muted-foreground truncate min-w-0">
          Project
        </span>
        <button
          onClick={() => setProjectExpanded((v) => !v)}
          className="rounded-sm hover:bg-accent p-0.5 text-muted-foreground"
          aria-label={projectExpanded ? "Collapse Project section" : "Expand Project section"}
        >
          <ChevronDown
            className={cn(
              "h-4 w-4 transition-transform duration-150",
              !projectExpanded && "-rotate-90",
            )}
          />
        </button>
      </div>

      {projectExpanded && (
        <>
          {loading ? (
            <ul className="space-y-px mt-1">
              <li className="h-[22px] bg-muted animate-pulse rounded-sm mx-[8px]" />
              <li className="h-[22px] bg-muted animate-pulse rounded-sm mx-[8px]" />
            </ul>
          ) : !currentProjectDir ? (
            <div className="px-[8px] py-[4px]">
              <p className="text-xs text-muted-foreground">
                Open a project to use the Project store.
              </p>
            </div>
          ) : projectPresets.length === 0 ? (
            <div className="px-[8px] py-[4px]">
              <p className="text-xs font-medium text-muted-foreground">
                No project presets yet.
              </p>
              <p className="text-xs text-muted-foreground">
                Multi-select components and right-click to save.
              </p>
            </div>
          ) : (
            <ul role="list" className="space-y-px mt-1">
              {projectPresets.map((e) => (
                <PresetRow
                  key={e.filePath}
                  entry={e}
                  onRequestReveal={() => void reveal(e.filePath)}
                />
              ))}
            </ul>
          )}
        </>
      )}

      {/* ── Library section ─────────────────────────────────────────────── */}
      <div
        className="flex items-center justify-between gap-1 pl-[8px] pr-[4px] mt-[8px] min-w-0"
        role="heading"
        aria-level={2}
      >
        <span className="text-xs font-semibold uppercase tracking-wide text-muted-foreground truncate min-w-0">
          Library
        </span>
        <button
          onClick={() => setLibraryExpanded((v) => !v)}
          className="rounded-sm hover:bg-accent p-0.5 text-muted-foreground"
          aria-label={libraryExpanded ? "Collapse Library section" : "Expand Library section"}
        >
          <ChevronDown
            className={cn(
              "h-4 w-4 transition-transform duration-150",
              !libraryExpanded && "-rotate-90",
            )}
          />
        </button>
      </div>

      {libraryExpanded && (
        <>
          {loading ? (
            <ul className="space-y-px mt-1">
              <li className="h-[22px] bg-muted animate-pulse rounded-sm mx-[8px]" />
              <li className="h-[22px] bg-muted animate-pulse rounded-sm mx-[8px]" />
            </ul>
          ) : libraryPresets.length === 0 ? (
            <div className="px-[8px] py-[4px]">
              <p className="text-xs font-medium text-muted-foreground">
                No library presets yet.
              </p>
              <p className="text-xs text-muted-foreground">
                Save a selection to add your first template.
              </p>
            </div>
          ) : (
            <ul role="list" className="space-y-px mt-1">
              {libraryPresets.map((e) => (
                <PresetRow
                  key={e.filePath}
                  entry={e}
                  onRequestReveal={() => void reveal(e.filePath)}
                />
              ))}
            </ul>
          )}
        </>
      )}
    </div>
  );
}
