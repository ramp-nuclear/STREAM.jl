// NoProjectHome.tsx — Phase 72 first-run rebuild (2026-05-27 shape session).
//
// REPLACES the canvas region when no project is open. Supersedes the
// previous WelcomeOverlay (letterhead-card splash that violated PRODUCT.md
// anti-references) AND the locked-but-rejected chromeless-anchor doctrine
// in DESIGN.md §771-828. New doctrine landed in this commit.
//
// Topology: this component does NOT overlay the canvas; it replaces the
// canvas mount entirely when `nodes.length === 0 && edges.length === 0
// && !welcomeDismissed`. Chrome (titlebar, menubar, toolbox, layers,
// sidebar, status bar) stays interactive. Opening a project re-mounts
// the ReactFlow canvas in place of this surface.
//
// VSCode "Welcome" tab lineage: two-column structure, sparse, lowercase
// section labels, mono recents. Brand identity lives in the always-on
// titlebar; this surface carries only a subtle wordmark + version stamp
// in the bottom-right corner.
//
// Drop affordance: dragging a component from the Toolbox onto this
// surface fires the marching-ants `flow-trace-march` keyframe around the
// inner edge of the canvas region (same motion vocabulary as loop traces
// and code-link active edges — no new visual language). On drop, the
// dragged component triggers a fresh project + auto-places at canvas
// center coordinates.

import { useEffect, useState } from "react";
import { getVersion } from "@tauri-apps/api/app";
import { Plus, FolderOpen } from "lucide-react";
import useStore from "../store/useStore";
import { SectionHeader } from "./ui/section-header";
import { cn } from "../lib/utils";

/**
 * Template entry shape — bundled example projects shown in the `templates`
 * sub-list. Currently the list is empty; future phases will load `.scp`
 * fixtures from a `gui/examples/` directory and surface them here. When
 * the list is empty the templates section does not render (no empty-state
 * line; the section earns its space only when it has content).
 */
interface Template {
  name: string;
  path: string;
  description: string;
}

const TEMPLATES: Template[] = [];

export default function NoProjectHome(): React.ReactElement | null {
  const isEmpty = useStore(
    (s) => s.nodes.length === 0 && s.edges.length === 0,
  );
  const welcomeDismissed = useStore((s) => s.welcomeDismissed);
  const recentFiles = useStore((s) => s.recentFiles);
  const loadProject = useStore((s) => s.loadProject);
  const loadProjectFromPath = useStore((s) => s.loadProjectFromPath);
  const newProject = useStore((s) => s.newProject);
  const addNode = useStore((s) => s.addNode);
  const pruneStaleRecentFiles = useStore((s) => s.pruneStaleRecentFiles);

  const [isDragOver, setIsDragOver] = useState(false);
  const [version, setVersion] = useState<string>("");

  const visible = isEmpty && !welcomeDismissed;

  useEffect(() => {
    if (!visible) return;
    void pruneStaleRecentFiles();
  }, [visible, pruneStaleRecentFiles]);

  useEffect(() => {
    getVersion()
      .then((v) => setVersion(v))
      .catch(() => setVersion(""));
  }, []);

  if (!visible) return null;

  // Slice at 10. Smaller viewports rarely have that many recents in
  // practice; large viewports get a denser column for free. No need to
  // gate via matchMedia since the rows are cheap text and the visual
  // result looks correct at every size we ship.
  const recents = recentFiles.slice(0, 10);
  const hasRecents = recents.length > 0;

  function handleDragOver(e: React.DragEvent) {
    // Accept toolbox-component drags. Other drag types fall through.
    if (e.dataTransfer.types.includes("application/streamcomponent")) {
      e.preventDefault();
      e.dataTransfer.dropEffect = "move";
      if (!isDragOver) setIsDragOver(true);
    }
  }

  function handleDragLeave(e: React.DragEvent) {
    // Only clear when leaving the wrapper entirely, not when crossing
    // child elements. The relatedTarget check filters child crossings.
    if (e.currentTarget.contains(e.relatedTarget as Node | null)) return;
    setIsDragOver(false);
  }

  async function handleDrop(e: React.DragEvent) {
    e.preventDefault();
    setIsDragOver(false);
    const componentId = e.dataTransfer.getData("application/streamcomponent");
    if (!componentId) return;
    await newProject();
    // Drop the component near canvas origin so it lands in the
    // default fitView. Coordinates are flow-space, not screen-space.
    addNode(componentId, { x: 160, y: 120 });
  }

  return (
    <div
      data-testid="no-project-home"
      className="absolute inset-0 bg-canvas overflow-hidden"
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
    >
      {/* Drop-affordance border. CSS `border` on a div (not SVG) so
          Tailwind's `box-sizing: border-box` keeps the stroke strictly
          inside the inset bounds. inset-1 (4 px) keeps the dashed line
          very close to the canvas edge — visually hugging the work
          area. Static dashed border matches the "drop file here"
          reference idiom. */}
      <div
        aria-hidden
        className={cn(
          "pointer-events-none absolute inset-1 rounded-md transition-opacity duration-150 motion-reduce:transition-none",
          isDragOver ? "opacity-100" : "opacity-0",
        )}
        style={{ border: "2px dashed var(--ring)" }}
      />

      {/* Main content — two-column home surface. Container max-width and
          top padding both scale with viewport: at default windowed
          (~1280 px) the content cluster reads as a contained centerpiece;
          at fullscreen (1920 px+) the cluster grows to fill more
          horizontal real estate and lifts closer to the top so the eye
          doesn't traverse empty space below. The previous fullscreen
          empty-space complaint came from a fixed 720 px cluster floating
          in a 1900 px wide canvas region. */}
      <div className="absolute inset-x-0 top-0 bottom-0 flex justify-center pt-[15vh] 2xl:pt-[10vh] px-8 pointer-events-none">
        <div className="pointer-events-auto w-full max-w-[720px] xl:max-w-[920px] 2xl:max-w-[1120px] flex gap-12">
          {/* Left column — recent projects */}
          <div className="flex-1 min-w-0">
            <SectionHeader className="mb-4">recent</SectionHeader>
            {hasRecents ? (
              <ul className="flex flex-col gap-px">
                {recents.map((path) => {
                  const stem = stemFor(path);
                  return (
                    <li key={path}>
                      <button
                        type="button"
                        onClick={() => void loadProjectFromPath(path)}
                        title={path}
                        className="w-full text-left text-body font-mono text-foreground truncate rounded-sm px-2 py-1.5 outline-none transition-colors duration-[80ms] hover:bg-card focus-visible:ring-2 focus-visible:ring-ring motion-reduce:!duration-0"
                      >
                        {stem}
                      </button>
                    </li>
                  );
                })}
              </ul>
            ) : (
              <div className="px-2 py-1.5 text-label text-foreground/45 font-mono">
                no recent projects yet
              </div>
            )}
          </div>

          {/* 1 px vertical hairline separator */}
          <div
            aria-hidden
            className="w-px self-stretch bg-border"
          />

          {/* Right column — start actions + templates */}
          <div className="flex-1 min-w-0">
            <SectionHeader className="mb-4">start</SectionHeader>
            <ul className="flex flex-col gap-px">
              <ActionRow
                icon={<Plus className="h-3.5 w-3.5" strokeWidth={1.5} />}
                label="New project"
                onActivate={() => void newProject()}
              />
              <ActionRow
                icon={<FolderOpen className="h-3.5 w-3.5" strokeWidth={1.5} />}
                label="Open project…"
                onActivate={() => void loadProject()}
              />
            </ul>

            {TEMPLATES.length > 0 && (
              <>
                <div
                  aria-hidden
                  className="my-4 h-px bg-border"
                />
                <SectionHeader className="mb-3">templates</SectionHeader>
                <ul className="flex flex-col gap-px">
                  {TEMPLATES.map((t) => (
                    <li key={t.path}>
                      <button
                        type="button"
                        onClick={() => void loadProjectFromPath(t.path)}
                        title={t.description}
                        className="w-full text-left text-body font-mono text-foreground truncate rounded-sm px-2 py-1.5 outline-none transition-colors duration-[80ms] hover:bg-card focus-visible:ring-2 focus-visible:ring-ring motion-reduce:!duration-0"
                      >
                        {t.name}
                      </button>
                    </li>
                  ))}
                </ul>
              </>
            )}

            {/* Shortcuts — informational, NOT click affordances (locked
                Shortcut-Is-Static-Text Rule, DESIGN.md §"No-project home
                surface"). Renders as <ul>/<li> with no role=button and no
                tabIndex; the keybind IS the affordance, pressed not
                clicked. Provides density on first launch when recents +
                templates are both empty. */}
            <div aria-hidden className="my-4 h-px bg-border" />
            <SectionHeader className="mb-3">shortcuts</SectionHeader>
            <ul className="flex flex-col gap-px">
              <ShortcutRow label="Command palette" keys="Ctrl+P" />
              <ShortcutRow label="All shortcuts" keys="?" />
              <ShortcutRow label="Preferences" keys="Ctrl+," />
              <ShortcutRow label="Toggle bottom panel" keys="Ctrl+`" />
            </ul>
          </div>
        </div>
      </div>

      {/* Corner identity stamp — wordmark SVG + version. The public
          `/stream-wordmark.svg` is the CROPPED version (viewBox tight on
          content) so `h-N` produces a true-sized wordmark; the original
          1080x1080-viewBox asset rendered as a thin smudge regardless of
          height because content occupied only 14 % of the vertical
          viewBox. h-9 default (36 px) grows to h-11 (44 px) at 2xl
          viewports. Brand presence is exactly this stamp; titlebar
          carries the always-on mark. Native blue retained per shape
          decision (small + cornered = identity stamp, not splash). */}
      <div className="absolute bottom-6 right-8 flex items-end gap-3 pointer-events-none select-none">
        <img
          src="/stream-wordmark.svg"
          alt="STREAM Composer"
          className="h-9 2xl:h-11 w-auto"
        />
        {version && (
          <span className="text-label font-mono text-foreground/65 pb-0.5">
            v{version}
          </span>
        )}
      </div>
    </div>
  );
}

interface ActionRowProps {
  icon: React.ReactNode;
  label: string;
  onActivate: () => void;
}

function ActionRow({ icon, label, onActivate }: ActionRowProps) {
  return (
    <li>
      <button
        type="button"
        onClick={onActivate}
        className="w-full text-left text-body font-mono text-foreground flex items-center gap-2 rounded-sm px-2 py-1.5 outline-none transition-colors duration-[80ms] hover:bg-card focus-visible:ring-2 focus-visible:ring-ring motion-reduce:!duration-0"
      >
        <span className="text-foreground/55">{icon}</span>
        <span>{label}</span>
      </button>
    </li>
  );
}

interface ShortcutRowProps {
  label: string;
  keys: string;
}

/** Informational row showing a label + its keyboard shortcut. NOT a button:
 *  the keybind is the affordance (Shortcut-Is-Static-Text Rule). Plain <li>
 *  with no role / no tabIndex / no click handler. */
function ShortcutRow({ label, keys }: ShortcutRowProps) {
  return (
    <li className="flex items-center justify-between gap-3 text-body font-mono px-2 py-1.5">
      <span className="text-foreground/85">{label}</span>
      <span className="text-foreground/45 text-label">{keys}</span>
    </li>
  );
}

/**
 * Display stem for a recent-file path: basename minus the .scp extension.
 * On Windows paths the regex still matches the trailing segment since
 * forward-slash and back-slash are both treated as separators.
 */
function stemFor(p: string): string {
  const base = p.split(/[\\/]/).pop() ?? p;
  return base.replace(/\.scp$/i, "");
}
