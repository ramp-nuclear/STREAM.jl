import { useEffect } from "react";
import useStore from "../store/useStore";

/**
 * Phase 72 — empty-canvas start panel (/impeccable shape first-run rev 5,
 * letterhead build, 2026-05-22).
 *
 * Rev 4 (single bg-popover panel with START / RECENT columns) read flat and
 * monotone — no brand identity, no real depth, no visual hierarchy beyond
 * the muted layer-accent labels. This rev introduces:
 *
 *   1. A saturated deep-navy LETTERHEAD header strip — the brand color zone
 *      at the top of the panel. Reads as a real bound surface, not a
 *      settings dialog.
 *   2. The STREAM brand mark (waveform-in-square) recolored to white via
 *      CSS filter so it shows on the navy header. Custom-rendered
 *      `STREAM.jl` wordmark + `composer` subtitle next to it.
 *   3. A clear two-tone composition: navy header (~104 px) over bg-popover
 *      body. The tonal step creates visible depth without a shadow.
 *
 * Header navy `oklch(0.32 0.14 254)`: deeper and more saturated than the
 * locked Hydraulic layer accent (`oklch(0.62 0.16 240)`), to read as a
 * real brand surface rather than a washed-out accent fill. Hue 254 keeps
 * it in the project's neutral-tinting family.
 *
 * Body keeps the START + RECENT two-column layout (rev 4 was correct
 * structurally); section labels demoted from hydraulic-blue to
 * foreground/55 since the navy header now carries the color story alone.
 *
 * Brand assets:
 *   - `gui/public/stream-icon.svg` = `gui/icons/SVG/blue_square.svg`
 *     (waveform-in-square, no text). Used in both the titlebar and here.
 *     Filter `brightness(0) invert(1)` recolors navy → white.
 *
 * Resolves Audit P0-1 (consumer-SaaS empty state) + P2-1 (div-onClick
 * a11y) + Critique P1-1 (first-run cognitive overload). Also delivers the
 * brand presence that prior revs lacked.
 *
 * PERF — gated on a single boolean primitive selector so the component
 * doesn't repaint during ReactFlow drags (BottomPanel commit 6c08bcd /
 * gui/PERFORMANCE.md §3).
 */
export default function WelcomeOverlay() {
  const isEmpty = useStore(
    (s) => s.nodes.length === 0 && s.edges.length === 0,
  );
  const welcomeDismissed = useStore((s) => s.welcomeDismissed);
  const recentFiles = useStore((s) => s.recentFiles);
  const loadProject = useStore((s) => s.loadProject);
  const loadProjectFromPath = useStore((s) => s.loadProjectFromPath);
  const newProject = useStore((s) => s.newProject);
  const pruneStaleRecentFiles = useStore((s) => s.pruneStaleRecentFiles);
  // (dismissWelcome is unused here — newProject() already sets
  // welcomeDismissed=true internally, and open/recent paths flip
  // isEmpty=false on success.)

  const visible = isEmpty && !welcomeDismissed;

  useEffect(() => {
    if (!visible) return;
    void pruneStaleRecentFiles();
  }, [visible, pruneStaleRecentFiles]);

  if (!visible) return null;

  const recents = recentFiles.slice(0, 5);
  const hasRecents = recents.length > 0;

  function openPalette() {
    window.dispatchEvent(new CustomEvent("gsd:open-command-palette"));
  }

  return (
    <div className="absolute inset-0 flex items-start justify-center pt-[16vh] pointer-events-none">
      <div className="pointer-events-auto w-[620px] bg-panel border border-border rounded-md overflow-hidden">
        {/* Letterhead — muted navy with brand mark + wordmark */}
        <div className="flex items-center gap-5 px-8 py-6 bg-[oklch(0.42_0.10_250)]">
          <img
            src="/stream-icon.svg"
            alt=""
            className="h-14 w-14 shrink-0 [filter:brightness(0)_invert(1)]"
          />
          <div className="flex flex-col leading-none">
            <div className="text-[28px] font-bold tracking-tight text-white">
              STREAM.jl
            </div>
            <div className="text-label font-mono uppercase tracking-wide text-white/65 mt-2">
              composer
            </div>
          </div>
        </div>

        {/* Body — START + RECENT two-column */}
        <div className="grid grid-cols-2 gap-12 p-8">
          <div className="flex flex-col">
            <div className="text-title font-mono uppercase text-foreground/55 mb-4">
              start
            </div>
            <div className="flex flex-col gap-1">
              <ActionRow
                label="new project"
                keys="Ctrl+N"
                onClick={() => void newProject()}
              />
              <ActionRow
                label="open project"
                keys="Ctrl+O"
                onClick={() => void loadProject()}
              />
              <ActionRow
                label="command palette"
                keys="Ctrl+P"
                onClick={openPalette}
              />
            </div>
          </div>

          <div className="flex flex-col">
            <div className="text-title font-mono uppercase text-foreground/55 mb-4">
              recent
            </div>
            {hasRecents ? (
              <div className="flex flex-col gap-1">
                {recents.map((fullPath) => {
                  const basename =
                    fullPath.split(/[/\\]/).pop() ?? fullPath;
                  const stem = basename.replace(/\.[^.]+$/, "");
                  return (
                    <button
                      key={fullPath}
                      type="button"
                      onClick={() => void loadProjectFromPath(fullPath)}
                      title={fullPath}
                      className="text-left text-body font-mono text-foreground truncate rounded-sm px-2 py-1.5 outline-none transition-colors duration-[80ms] hover:bg-card focus-visible:ring-2 focus-visible:ring-ring motion-reduce:!duration-0"
                    >
                      {stem}
                    </button>
                  );
                })}
              </div>
            ) : (
              <div className="text-body font-mono text-foreground/45 px-2 py-1.5">
                no recents
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function ActionRow({
  label,
  keys,
  onClick,
}: {
  label: string;
  keys: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex items-center justify-between gap-3 rounded-sm px-2 py-1.5 outline-none transition-colors duration-[80ms] hover:bg-card focus-visible:ring-2 focus-visible:ring-ring motion-reduce:!duration-0"
    >
      <span className="text-body text-foreground">{label}</span>
      <kbd className="inline-flex items-center justify-center font-mono text-label text-[color:var(--color-layer-hydraulic)] bg-card border border-border rounded-sm px-1.5 h-5 min-w-[3.5rem] shrink-0">
        {keys}
      </kbd>
    </button>
  );
}
