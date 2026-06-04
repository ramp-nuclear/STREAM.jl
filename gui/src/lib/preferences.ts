// preferences.ts — User-global preferences store (Phase 72)
//
// Strictly user-global. Per the DESIGN.md §5 Preferences lock:
//   - Project-scoped values (modelOptions: name, description, default_fluid,
//     g_default, solver) stay on the per-project Project Options surface.
//   - App-scoped values (theme, off-layer behavior, snap, autorecover interval,
//     undo depth, validation rule enable/disable, etc.) live here.
//
// Persistence model: localStorage, one key per setting, namespaced
// `stream-composer-pref.<category>.<setting>`. Why per-key vs one big blob:
// (a) future Tauri config write-side can map one-key-per-line cleanly to TOML,
// (b) a single corrupt value doesn't poison the whole prefs object,
// (c) reads can short-circuit defaults without parsing JSON.
//
// Cross-component sync: a `stream:prefs-changed` CustomEvent fires on every
// setPreference call. The `usePreference` hook subscribes via window event
// listener. Avoids polling, avoids a zustand slice for non-canvas state, keeps
// the undoable canvas snapshot clean.
//
// Why not zustand for prefs: prefs are user-global, not project-scoped. Putting
// them in `useStore` would pollute the undo stack (one undo would revert prefs)
// AND the .scp serialization would have to filter them out. A separate hook
// with localStorage backing is the cleaner boundary.

import { useEffect, useState } from "react";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface Preferences {
  editor: {
    /** Dim (default) or Hide off-layer items. Replaces the LayersPanel toggle. */
    offLayerBehavior: "dim" | "hide";
    /** Snap nodes to the canvas grid on drag. */
    snapToGrid: boolean;
    /** Lock canvas pan + zoom. Nodes still selectable. */
    interactiveLock: boolean;
    /** Auto-flip ports to natural side on connection drop (Phase 64 logic). */
    autoFlipPortsOnConnect: boolean;
    /** Reveal port type label on hover. */
    showPortTypeOnHover: boolean;
    /** Initial zoom on `Open` / `New`. */
    defaultZoomOnOpen: "fit" | "100" | "last";
  };
  appearance: {
    // Theme is canonical in useTheme (localStorage key `stream-composer-theme`).
    // Intentionally NOT mirrored here — preferences would diverge from the
    // hook's storage on every read. Preferences > Appearance > Theme renders
    // the useTheme hook directly.
    /** Chrome spacing density. Placeholder until density tokens land. */
    density: "comfortable" | "compact";
    /** Animation respect override for prefers-reduced-motion. */
    reduceMotion: "system" | "always" | "never";
  };
  files: {
    /** Debounced sidecar write after each edit (Phase 65 D-01). */
    autorecoverEnabled: boolean;
    /** Debounce window. 2 s matches the prior literal. */
    autorecoverIntervalMs: 2000 | 5000 | 10000 | 30000;
    /** Cap for `addToRecent` in the store (was hardcoded 5). */
    recentFilesMax: number;
    /** Cap for `_undoPast` (was unbounded). */
    undoHistoryDepth: number;
    /** Initial directory for File > Open. Empty = OS default. */
    defaultOpenLocation: string;
  };
  validation: {
    /** Per-rule enable/disable. Keyed by Validator.id (e.g. "length_match"). */
    rulesEnabled: Record<string, boolean>;
    /** Initial group-by mode on panel open. */
    defaultGroupBy: "none" | "rule" | "component";
    /** Initial severity filter on panel open. */
    defaultSeverityFilter: "all" | "errors" | "warnings+" | "info+";
    /** How long the canvas marching-ants loop trace stays visible after focus. */
    loopTracePersistence: "until-click" | "5s" | "10s";
  };
  codeExport: {
    /** Empty = "alongside .scp" (current default). */
    defaultPath: string;
    indentWidth: "2-spaces" | "4-spaces" | "tab";
    /** Emit `# from canvas: <node>` markers in generated Julia. */
    includeSourceComments: boolean;
    /** Open the .jl file in the OS default handler after export. */
    openExportedFile: boolean;
  };
  advanced: {
    /** Surface `bin/jl` daemon liveness in the status bar. Placeholder. */
    showDaemonStatus: boolean;
    /** Show FPS + paint budget over the canvas. Placeholder. */
    performanceOverlay: boolean;
  };
}

export type PreferenceCategory = keyof Preferences;
export type PreferenceKey<C extends PreferenceCategory> = keyof Preferences[C];

// ---------------------------------------------------------------------------
// Defaults
// ---------------------------------------------------------------------------

export const DEFAULT_PREFERENCES: Preferences = {
  editor: {
    offLayerBehavior: "dim",
    snapToGrid: false,
    interactiveLock: false,
    autoFlipPortsOnConnect: true,
    showPortTypeOnHover: false,
    defaultZoomOnOpen: "fit",
  },
  appearance: {
    density: "comfortable",
    reduceMotion: "system",
  },
  files: {
    autorecoverEnabled: true,
    autorecoverIntervalMs: 2000,
    recentFilesMax: 5,
    undoHistoryDepth: 200,
    defaultOpenLocation: "",
  },
  validation: {
    rulesEnabled: {
      port_type: true,
      required_connections: true,
      z_n_match: true,
      length_match: true,
      geometry_consistency: true,
      n_match: true,
      loop_closure: true,
      gravity_sum_per_loop: true,
      pressure_boundary_required: true,
      driving_element_required: true,
    },
    defaultGroupBy: "none",
    defaultSeverityFilter: "all",
    loopTracePersistence: "until-click",
  },
  codeExport: {
    defaultPath: "",
    indentWidth: "2-spaces",
    includeSourceComments: true,
    openExportedFile: false,
  },
  advanced: {
    showDaemonStatus: false,
    performanceOverlay: false,
  },
};

// ---------------------------------------------------------------------------
// Storage layer
// ---------------------------------------------------------------------------

const STORAGE_PREFIX = "stream-composer-pref";
const CHANGE_EVENT = "stream:prefs-changed";

function storageKey<C extends PreferenceCategory>(
  category: C,
  setting: PreferenceKey<C>,
): string {
  return `${STORAGE_PREFIX}.${String(category)}.${String(setting)}`;
}

function readRaw<C extends PreferenceCategory>(
  category: C,
  setting: PreferenceKey<C>,
): unknown {
  try {
    const raw = localStorage.getItem(storageKey(category, setting));
    if (raw === null) return undefined;
    return JSON.parse(raw);
  } catch {
    // Corrupt value or localStorage unavailable (SSR / Tauri pre-init); fall
    // back to default. Don't throw — preferences must never block app load.
    return undefined;
  }
}

function writeRaw<C extends PreferenceCategory>(
  category: C,
  setting: PreferenceKey<C>,
  value: Preferences[C][PreferenceKey<C>],
): void {
  try {
    localStorage.setItem(storageKey(category, setting), JSON.stringify(value));
  } catch {
    // Quota exceeded / private mode / etc. — preferences are best-effort.
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Read a single preference. Falls back to DEFAULT_PREFERENCES on missing /
 * corrupt values. Safe to call at any time (no React requirement).
 */
export function getPreference<C extends PreferenceCategory, K extends PreferenceKey<C>>(
  category: C,
  setting: K,
): Preferences[C][K] {
  const raw = readRaw(category, setting);
  if (raw === undefined) return DEFAULT_PREFERENCES[category][setting];
  return raw as Preferences[C][K];
}

/** Read every preference at once. Used by the dialog mount + by serialization. */
export function getAllPreferences(): Preferences {
  const out = structuredClone(DEFAULT_PREFERENCES);
  for (const cat of Object.keys(DEFAULT_PREFERENCES) as PreferenceCategory[]) {
    const catDefaults = DEFAULT_PREFERENCES[cat] as Record<string, unknown>;
    const target = out[cat] as Record<string, unknown>;
    for (const key of Object.keys(catDefaults)) {
      const raw = readRaw(cat, key as never);
      if (raw !== undefined) target[key] = raw;
    }
  }
  return out;
}

/**
 * Write a single preference. Persists to localStorage and broadcasts a
 * `stream:prefs-changed` CustomEvent so subscribed components re-render.
 */
export function setPreference<C extends PreferenceCategory, K extends PreferenceKey<C>>(
  category: C,
  setting: K,
  value: Preferences[C][K],
): void {
  writeRaw(category, setting, value);
  window.dispatchEvent(
    new CustomEvent(CHANGE_EVENT, {
      detail: { category, setting, value },
    }),
  );
}

/** Reset every preference to its default. Broadcasts a single change event. */
export function resetAllPreferences(): void {
  for (const cat of Object.keys(DEFAULT_PREFERENCES) as PreferenceCategory[]) {
    const catDefaults = DEFAULT_PREFERENCES[cat] as Record<string, unknown>;
    for (const key of Object.keys(catDefaults)) {
      try {
        localStorage.removeItem(storageKey(cat, key as never));
      } catch {
        // Best-effort
      }
    }
  }
  // One broadcast — consumers re-read whatever they care about.
  window.dispatchEvent(
    new CustomEvent(CHANGE_EVENT, {
      detail: { category: "*", setting: "*", value: null },
    }),
  );
}

// ---------------------------------------------------------------------------
// React hook
// ---------------------------------------------------------------------------

/**
 * Subscribe to a single preference value. Re-renders the calling component
 * whenever the value changes (via the broadcast custom event).
 *
 * Returns a tuple `[value, setValue]` so the dialog can render controls with
 * minimal ceremony.
 */
export function usePreference<C extends PreferenceCategory, K extends PreferenceKey<C>>(
  category: C,
  setting: K,
): [Preferences[C][K], (next: Preferences[C][K]) => void] {
  const [value, setValue] = useState<Preferences[C][K]>(() =>
    getPreference(category, setting),
  );

  useEffect(() => {
    const handler = (e: Event) => {
      const ce = e as CustomEvent<{
        category: PreferenceCategory | "*";
        setting: string | "*";
      }>;
      // Re-read on either a targeted change to this key or a global reset.
      if (
        ce.detail.category === "*" ||
        (ce.detail.category === category && ce.detail.setting === setting)
      ) {
        setValue(getPreference(category, setting));
      }
    };
    window.addEventListener(CHANGE_EVENT, handler);
    return () => window.removeEventListener(CHANGE_EVENT, handler);
  }, [category, setting]);

  const set = (next: Preferences[C][K]) => setPreference(category, setting, next);
  return [value, set];
}

/** Listen to all preference changes without subscribing to a specific key.
 *  Used by side-effect wiring (autorecover interval, validation rule filter,
 *  etc.) that needs to react to any change in its slice. */
export function onPreferenceChange(
  handler: (detail: {
    category: PreferenceCategory | "*";
    setting: string | "*";
  }) => void,
): () => void {
  const wrapped = (e: Event) => {
    const ce = e as CustomEvent<{
      category: PreferenceCategory | "*";
      setting: string | "*";
    }>;
    handler(ce.detail);
  };
  window.addEventListener(CHANGE_EVENT, wrapped);
  return () => window.removeEventListener(CHANGE_EVENT, wrapped);
}

// ---------------------------------------------------------------------------
// Side-effect bridge
// ---------------------------------------------------------------------------

/**
 * Wire user-global preferences into the per-runtime mirrors that consumers
 * already read from. Call once from App.tsx on mount; returns a teardown.
 *
 * The runtime mirrors live in useStore (`hideOffLayer`, `snapToGrid`,
 * `interactiveLocked`). The store already initializes them from prefs at
 * module-eval time; this bridge keeps them in sync when the user flips a
 * setting in the dialog (or via a canvas overlay button that writes to
 * prefs). No bridging is needed for prefs whose consumers read from
 * `getPreference()` directly at call-time (autorecover gate, undo depth
 * trim, recent files cap, validation rule filter).
 *
 * Returns a teardown that removes the listeners.
 */
export function initPreferencesBridge(handlers: {
  setHideOffLayer: (v: boolean) => void;
  setSnapToGrid: (v: boolean) => void;
  setInteractiveLocked: (v: boolean) => void;
}): () => void {
  return onPreferenceChange((detail) => {
    if (detail.category === "*") {
      // Global reset — push every mirror to its default-derived value.
      handlers.setHideOffLayer(getPreference("editor", "offLayerBehavior") === "hide");
      handlers.setSnapToGrid(getPreference("editor", "snapToGrid"));
      handlers.setInteractiveLocked(getPreference("editor", "interactiveLock"));
      return;
    }
    if (detail.category === "editor") {
      if (detail.setting === "offLayerBehavior") {
        handlers.setHideOffLayer(getPreference("editor", "offLayerBehavior") === "hide");
      } else if (detail.setting === "snapToGrid") {
        handlers.setSnapToGrid(getPreference("editor", "snapToGrid"));
      } else if (detail.setting === "interactiveLock") {
        handlers.setInteractiveLocked(getPreference("editor", "interactiveLock"));
      }
    }
  });
}
