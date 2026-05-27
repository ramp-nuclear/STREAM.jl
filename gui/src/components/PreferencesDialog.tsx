// PreferencesDialog.tsx — User-global preferences (Phase 72)
//
// Reached from `Edit > Preferences…` and `Ctrl+,`. Two-pane Dialog: 180 px
// category rail (left) + dense setting rows (right). Locked Dialog vocab on
// the outside; the ValidationPanel selected-row idiom on the rail.
//
// Persistence: localStorage via `lib/preferences.ts`. Every control is
// autosave-on-change — no Apply button. Side-effect wiring for the
// straightforward settings lives in the consumer code (useStore.ts,
// useTheme.ts, validation/runner.ts, etc.); the dialog itself only writes
// to the prefs store.
//
// Settings without a downstream consumer yet are rendered as DISABLED
// controls with a `Not yet wired.` sub-line — same vocab as the explicit
// Density / Daemon-status / Performance-overlay placeholders. The
// preference value is still persisted; future phases that wire the
// consumer don't need to touch the dialog.

import { useState } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { Input } from "@/components/ui/input";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { ScrollArea } from "@/components/ui/scroll-area";
import { SectionHeader } from "@/components/ui/section-header";
import { cn } from "@/lib/utils";
import { usePreference, resetAllPreferences } from "@/lib/preferences";
import { THEMES, useTheme, type Theme } from "@/hooks/useTheme";
import { validators } from "@/lib/validation";

// ---------------------------------------------------------------------------
// Category rail
// ---------------------------------------------------------------------------

const CATEGORIES = [
  { id: "editor", label: "Editor" },
  { id: "appearance", label: "Appearance" },
  { id: "files", label: "Files" },
  { id: "validation", label: "Validation" },
  { id: "codeExport", label: "Code Export" },
  { id: "advanced", label: "Advanced" },
] as const;

type CategoryId = (typeof CATEGORIES)[number]["id"];

// ---------------------------------------------------------------------------
// Setting row — shared shape for every preference row
// ---------------------------------------------------------------------------

interface SettingRowProps {
  label: string;
  description: string;
  /** Render the right-side control. */
  control: React.ReactNode;
  /** True when the control isn't yet read by any consumer — appends the
   *  `Not yet wired.` placeholder line and lets the control style as
   *  disabled (the caller is responsible for the actual disabled prop). */
  notYetWired?: boolean;
}

function SettingRow({ label, description, control, notYetWired }: SettingRowProps) {
  return (
    <div className="grid grid-cols-[1fr_auto] gap-6 items-center py-3 border-b border-border/40 last:border-b-0">
      <div className="min-w-0">
        <div className={cn("text-body font-medium", notYetWired && "text-foreground/55")}>
          {label}
        </div>
        <div className="text-label text-foreground/65 mt-0.5">{description}</div>
        {notYetWired && (
          <div className="text-label text-foreground/45 mt-0.5 font-mono">
            Not yet wired.
          </div>
        )}
      </div>
      <div className="shrink-0">{control}</div>
    </div>
  );
}

/** Tight sub-header used inside categories that have sub-clusters (e.g. the
 *  per-rule Validation switches sit under a "Rules" sub-header). */
function SubHeader({ label }: { label: string }) {
  return <SectionHeader className="mt-4 mb-1">{label}</SectionHeader>;
}

// ---------------------------------------------------------------------------
// Category panes
// ---------------------------------------------------------------------------

function EditorPane() {
  const [offLayer, setOffLayer] = usePreference("editor", "offLayerBehavior");
  const [snap, setSnap] = usePreference("editor", "snapToGrid");
  const [lock, setLock] = usePreference("editor", "interactiveLock");
  const [autoFlip, setAutoFlip] = usePreference("editor", "autoFlipPortsOnConnect");
  const [showPortType, setShowPortType] = usePreference("editor", "showPortTypeOnHover");
  const [defaultZoom, setDefaultZoom] = usePreference("editor", "defaultZoomOnOpen");

  return (
    <>
      <SettingRow
        label="Off-layer behavior"
        description="How off-layer items render when filtered out."
        control={
          <Select value={offLayer} onValueChange={(v) => setOffLayer(v as "dim" | "hide")}>
            <SelectTrigger size="sm" className="w-[140px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="dim">Dim</SelectItem>
              <SelectItem value="hide">Hide</SelectItem>
            </SelectContent>
          </Select>
        }
      />
      <SettingRow
        label="Snap to grid"
        description="Drag-snap nodes to the canvas grid."
        control={<Switch checked={snap} onCheckedChange={setSnap} />}
      />
      <SettingRow
        label="Interactive lock"
        description="Lock canvas pan and zoom; nodes stay selectable."
        control={<Switch checked={lock} onCheckedChange={setLock} />}
      />
      <SettingRow
        label="Auto-flip ports on connect"
        description="Reorient ports to the connection's natural axis on drop."
        control={<Switch checked={autoFlip} onCheckedChange={setAutoFlip} />}
      />
      <SettingRow
        label="Show port type on hover"
        description="Reveal FlowPort or ThermalPort labels on hover."
        control={<Switch checked={showPortType} onCheckedChange={setShowPortType} />}
      />
      <SettingRow
        label="Default zoom on open"
        description="What File > Open and File > New zoom the canvas to."
        control={
          <Select
            value={defaultZoom}
            onValueChange={(v) => setDefaultZoom(v as "fit" | "100" | "last")}
          >
            <SelectTrigger size="sm" className="w-[140px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="fit">Fit</SelectItem>
              <SelectItem value="100">100%</SelectItem>
              <SelectItem value="last">Last used</SelectItem>
            </SelectContent>
          </Select>
        }
      />
    </>
  );
}

function AppearancePane() {
  // Theme is canonical in useTheme (localStorage key `stream-composer-theme`).
  // Preferences mirrors the View > Theme entry via the same hook — both
  // surfaces write to the same key so flipping in either place propagates.
  const { theme, setTheme } = useTheme();
  const [density, setDensity] = usePreference("appearance", "density");
  const [reduceMotion, setReduceMotion] = usePreference("appearance", "reduceMotion");

  return (
    <>
      <SettingRow
        label="Theme"
        description="Mirrors View > Theme."
        control={
          <ToggleGroup
            type="single"
            size="sm"
            value={theme}
            onValueChange={(v) => v && setTheme(v as Theme)}
          >
            {THEMES.map((t) => (
              <ToggleGroupItem key={t} value={t} aria-label={t}>
                {t.charAt(0).toUpperCase() + t.slice(1)}
              </ToggleGroupItem>
            ))}
          </ToggleGroup>
        }
      />
      <SettingRow
        notYetWired
        label="Density"
        description="Chrome spacing density."
        control={
          <Select
            value={density}
            disabled
            onValueChange={(v) => setDensity(v as "comfortable" | "compact")}
          >
            <SelectTrigger size="sm" className="w-[140px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="comfortable">Comfortable</SelectItem>
              <SelectItem value="compact">Compact</SelectItem>
            </SelectContent>
          </Select>
        }
      />
      <SettingRow
        label="Reduce motion"
        description="Animation respect override for prefers-reduced-motion."
        control={
          <Select
            value={reduceMotion}
            onValueChange={(v) =>
              setReduceMotion(v as "system" | "always" | "never")
            }
          >
            <SelectTrigger size="sm" className="w-[140px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="system">Follow system</SelectItem>
              <SelectItem value="always">Always on</SelectItem>
              <SelectItem value="never">Always off</SelectItem>
            </SelectContent>
          </Select>
        }
      />
    </>
  );
}

function FilesPane() {
  const [autoRecover, setAutoRecover] = usePreference("files", "autorecoverEnabled");
  const [interval, setInterval] = usePreference("files", "autorecoverIntervalMs");
  const [recentMax, setRecentMax] = usePreference("files", "recentFilesMax");
  const [undoDepth, setUndoDepth] = usePreference("files", "undoHistoryDepth");
  const [defaultOpen, setDefaultOpen] = usePreference("files", "defaultOpenLocation");

  return (
    <>
      <SettingRow
        label="Autorecover"
        description="Debounced sidecar write after each edit."
        control={<Switch checked={autoRecover} onCheckedChange={setAutoRecover} />}
      />
      <SettingRow
        label="Autorecover interval"
        description="How long after an edit the sidecar writes."
        control={
          <Select
            value={String(interval)}
            disabled={!autoRecover}
            onValueChange={(v) =>
              setInterval(Number(v) as 2000 | 5000 | 10000 | 30000)
            }
          >
            <SelectTrigger size="sm" className="w-[120px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="2000">2 seconds</SelectItem>
              <SelectItem value="5000">5 seconds</SelectItem>
              <SelectItem value="10000">10 seconds</SelectItem>
              <SelectItem value="30000">30 seconds</SelectItem>
            </SelectContent>
          </Select>
        }
      />
      <SettingRow
        label="Recent files"
        description="How many recent project paths to keep."
        control={
          <Input
            type="number"
            min={1}
            max={20}
            value={recentMax}
            onChange={(e) => {
              const n = Number(e.target.value);
              if (Number.isFinite(n) && n >= 1 && n <= 20) setRecentMax(n);
            }}
            className="w-[80px]"
          />
        }
      />
      <SettingRow
        label="Undo history depth"
        description="How many undo snapshots to retain."
        control={
          <Input
            type="number"
            min={50}
            max={2000}
            step={50}
            value={undoDepth}
            onChange={(e) => {
              const n = Number(e.target.value);
              if (Number.isFinite(n) && n >= 50 && n <= 2000) setUndoDepth(n);
            }}
            className="w-[80px]"
          />
        }
      />
      <SettingRow
        label="Default open location"
        description="Where File > Open starts. Empty means OS default."
        control={
          <Input
            value={defaultOpen}
            onChange={(e) => setDefaultOpen(e.target.value)}
            placeholder="OS default"
            className="w-[220px]"
          />
        }
      />
    </>
  );
}

function ValidationPane() {
  const [rulesEnabled, setRulesEnabled] = usePreference("validation", "rulesEnabled");
  const [groupBy, setGroupBy] = usePreference("validation", "defaultGroupBy");
  const [severityFilter, setSeverityFilter] = usePreference(
    "validation",
    "defaultSeverityFilter",
  );
  const [tracePersistence, setTracePersistence] = usePreference(
    "validation",
    "loopTracePersistence",
  );

  function toggleRule(id: string, next: boolean) {
    setRulesEnabled({ ...rulesEnabled, [id]: next });
  }

  return (
    <>
      <SubHeader label="Rules" />
      {validators.map((v) => {
        const enabled = rulesEnabled[v.id] ?? true;
        return (
          <div
            key={v.id}
            className="grid grid-cols-[1fr_auto] gap-6 items-center py-2 border-b border-border/40 last:border-b-0"
          >
            <div className="min-w-0">
              <div className="flex items-baseline gap-2">
                <span className="text-body font-mono text-foreground">{v.id}</span>
                <span
                  className="text-micro uppercase tracking-wide font-mono"
                  style={{
                    color:
                      v.severity === "error"
                        ? "var(--destructive)"
                        : v.severity === "warning"
                        ? "var(--color-warning)"
                        : "var(--color-info)",
                  }}
                >
                  {v.severity}
                </span>
              </div>
              <div className="text-label text-foreground/65 mt-0.5">
                {v.description}
              </div>
            </div>
            <Switch checked={enabled} onCheckedChange={(c) => toggleRule(v.id, c)} />
          </div>
        );
      })}

      <SubHeader label="Panel defaults" />
      <SettingRow
        label="Default group-by"
        description="Group-by mode the panel opens with."
        control={
          <Select
            value={groupBy}
            onValueChange={(v) => setGroupBy(v as "none" | "rule" | "component")}
          >
            <SelectTrigger size="sm" className="w-[140px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="none">None</SelectItem>
              <SelectItem value="rule">Rule</SelectItem>
              <SelectItem value="component">Component</SelectItem>
            </SelectContent>
          </Select>
        }
      />
      <SettingRow
        label="Default severity filter"
        description="Filter applied when the panel opens."
        control={
          <Select
            value={severityFilter}
            onValueChange={(v) =>
              setSeverityFilter(v as "all" | "errors" | "warnings+" | "info+")
            }
          >
            <SelectTrigger size="sm" className="w-[140px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All</SelectItem>
              <SelectItem value="errors">Errors only</SelectItem>
              <SelectItem value="warnings+">Warnings and up</SelectItem>
              <SelectItem value="info+">Info and up</SelectItem>
            </SelectContent>
          </Select>
        }
      />
      <SettingRow
        label="Loop-trace persistence"
        description="How long the marching-ants trace stays after focus."
        control={
          <Select
            value={tracePersistence}
            onValueChange={(v) =>
              setTracePersistence(v as "until-click" | "5s" | "10s")
            }
          >
            <SelectTrigger size="sm" className="w-[160px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="until-click">Until canvas click</SelectItem>
              <SelectItem value="5s">5 seconds</SelectItem>
              <SelectItem value="10s">10 seconds</SelectItem>
            </SelectContent>
          </Select>
        }
      />
    </>
  );
}

function CodeExportPane() {
  const [exportPath, setExportPath] = usePreference("codeExport", "defaultPath");
  const [indent, setIndent] = usePreference("codeExport", "indentWidth");
  const [includeComments, setIncludeComments] = usePreference(
    "codeExport",
    "includeSourceComments",
  );
  const [openAfter, setOpenAfter] = usePreference("codeExport", "openExportedFile");

  return (
    <>
      <SettingRow
        label="Default export path"
        description="Where File > Export to Julia writes. Empty means alongside .scp."
        control={
          <Input
            value={exportPath}
            onChange={(e) => setExportPath(e.target.value)}
            placeholder="alongside .scp"
            className="w-[220px]"
          />
        }
      />
      <SettingRow
        label="Indent width"
        description="Julia source indentation."
        control={
          <Select
            value={indent}
            onValueChange={(v) =>
              setIndent(v as "2-spaces" | "4-spaces" | "tab")
            }
          >
            <SelectTrigger size="sm" className="w-[140px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="2-spaces">2 spaces</SelectItem>
              <SelectItem value="4-spaces">4 spaces</SelectItem>
              <SelectItem value="tab">Tab</SelectItem>
            </SelectContent>
          </Select>
        }
      />
      <SettingRow
        notYetWired
        label="Include source comments"
        description="Emit # from canvas: <node> markers in generated Julia."
        control={
          <Switch checked={includeComments} disabled onCheckedChange={setIncludeComments} />
        }
      />
      <SettingRow
        label="Open exported file"
        description="Open the .jl file in the OS default handler after export."
        control={<Switch checked={openAfter} onCheckedChange={setOpenAfter} />}
      />
    </>
  );
}

function AdvancedPane() {
  const [daemonStatus, setDaemonStatus] = usePreference("advanced", "showDaemonStatus");
  const [perfOverlay, setPerfOverlay] = usePreference("advanced", "performanceOverlay");

  return (
    <>
      <SettingRow
        notYetWired
        label="Show daemon status"
        description="Surface bin/jl daemon liveness in the status bar."
        control={
          <Switch
            checked={daemonStatus}
            disabled
            onCheckedChange={setDaemonStatus}
          />
        }
      />
      <SettingRow
        notYetWired
        label="Performance overlay"
        description="Show FPS and paint budget over the canvas."
        control={
          <Switch
            checked={perfOverlay}
            disabled
            onCheckedChange={setPerfOverlay}
          />
        }
      />
    </>
  );
}

// ---------------------------------------------------------------------------
// Dialog root
// ---------------------------------------------------------------------------

interface PreferencesDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export default function PreferencesDialog({ open, onOpenChange }: PreferencesDialogProps) {
  const [activeCategory, setActiveCategory] = useState<CategoryId>("editor");
  const [confirmingReset, setConfirmingReset] = useState(false);

  function handleResetAll() {
    resetAllPreferences();
    setConfirmingReset(false);
  }

  // Map active category to its current label for the right-pane header.
  const activeLabel = CATEGORIES.find((c) => c.id === activeCategory)?.label ?? "";

  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        // Close → also drop any pending reset-confirmation.
        if (!o) setConfirmingReset(false);
        onOpenChange(o);
      }}
    >
      <DialogContent
        // Phase 72 post-Preferences-feedback — Preferences inherits the
        // CommandPalette visual lineage: transparent scrim, --dialog-surface
        // body, atmospheric --shadow-dialog (all now Dialog-primitive
        // defaults). Position is top-anchored (top-[80px]) to match the
        // CommandPalette and shortcuts-mode keymap, both of which the user
        // asked Preferences to look like.
        //
        // Fixed 720 × 560 — desktop-only per scope. Override the primitive's
        // grid + gap so the two-pane layout sits flush, and zero the inner
        // padding so the rail's border-r reaches the dialog edges.
        className="top-[80px] translate-y-0 !max-w-[720px] w-[720px] h-[560px] !p-0 !gap-0 flex flex-col overflow-hidden"
      >
        <DialogHeader className="px-6 py-4 border-b border-border">
          <DialogTitle className="text-title font-semibold">Preferences</DialogTitle>
        </DialogHeader>

        <div className="flex-1 min-h-0 flex">
          {/* Category rail */}
          <div className="w-[180px] shrink-0 border-r border-border bg-panel flex flex-col py-2">
            {CATEGORIES.map((cat) => {
              const selected = activeCategory === cat.id;
              return (
                <button
                  key={cat.id}
                  type="button"
                  onClick={() => setActiveCategory(cat.id)}
                  data-selected={selected || undefined}
                  className={cn(
                    "relative h-9 px-3 mx-1 my-px text-left text-body font-medium rounded-sm",
                    "outline-none transition-colors duration-[80ms] motion-reduce:transition-none",
                    "focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-0",
                    selected
                      ? "bg-card text-foreground"
                      : "text-foreground/65 hover:bg-card/60 hover:text-foreground",
                  )}
                >
                  {selected && (
                    <span
                      aria-hidden
                      className="absolute left-0 top-1.5 bottom-1.5 w-[2px]"
                      style={{ background: "var(--ring)" }}
                    />
                  )}
                  {cat.label}
                </button>
              );
            })}
          </div>

          {/* Right pane */}
          <ScrollArea className="flex-1 min-h-0">
            <div className="px-6 py-5">
              <SectionHeader className="mb-3">{activeLabel}</SectionHeader>
              {activeCategory === "editor" && <EditorPane />}
              {activeCategory === "appearance" && <AppearancePane />}
              {activeCategory === "files" && <FilesPane />}
              {activeCategory === "validation" && <ValidationPane />}
              {activeCategory === "codeExport" && <CodeExportPane />}
              {activeCategory === "advanced" && <AdvancedPane />}
            </div>
          </ScrollArea>
        </div>

        {/* Footer */}
        <div className="h-12 border-t border-border px-4 flex items-center justify-between shrink-0">
          {confirmingReset ? (
            <div className="flex items-center gap-2 flex-1">
              <span className="text-label text-foreground/85">
                Reset every preference to its default?
              </span>
              <div className="ml-auto flex items-center gap-2">
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setConfirmingReset(false)}
                >
                  Cancel
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  className="text-destructive hover:bg-destructive/10 hover:text-destructive"
                  onClick={handleResetAll}
                >
                  Reset all
                </Button>
              </div>
            </div>
          ) : (
            <>
              <Button
                variant="ghost"
                size="sm"
                className="text-foreground/65 hover:text-destructive hover:bg-destructive/10"
                onClick={() => setConfirmingReset(true)}
              >
                Reset all preferences
              </Button>
              <Button size="sm" onClick={() => onOpenChange(false)}>
                Done
              </Button>
            </>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
