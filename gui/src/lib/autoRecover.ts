// autoRecover.ts — AutoRecover I/O substrate for STREAM Composer.
//
// Pure-where-possible utilities + Tauri-backed I/O wrappers.
// All Tauri calls use dynamic imports (same pattern as useStore.ts loadRecentFiles)
// so this module can be imported in a vitest node environment without crashing.
//
// D-01: debounced-on-dirty (~2s) sidecar write
// D-02: clean-shutdown lockfile + PID-alive crash detection
// D-04: untitled-<uuid>.scp.autosave for never-saved projects
// D-05: appDataDir/STREAM-Composer/autorecover/ storage location
// D-06: full .scp payload via projectIO.serialize

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const AUTORECOVER_DIR = "STREAM-Composer/autorecover";
const LOCKFILE_NAME = "running.lock";
const AUTOSAVE_SUFFIX = ".scp.autosave";

// ---------------------------------------------------------------------------
// Pure path helpers
// ---------------------------------------------------------------------------

/**
 * Derive the sidecar basename from the current file path or untitled UUID.
 *
 * # Arguments
 * - `currentFilePath` — absolute path to the `.scp` project file, or null for untitled
 * - `untitledUuid`    — stable UUID for the current in-memory untitled project
 *
 * # Returns
 * A flat filename (no path separators) matching `/^[A-Za-z0-9._-]+$/`
 * with `.scp.autosave` suffix. Never contains `..`, `/`, or `\`.
 */
export function getSidecarBasename(
  currentFilePath: string | null,
  untitledUuid: string,
): string {
  if (currentFilePath === null) {
    return `untitled-${untitledUuid}${AUTOSAVE_SUFFIX}`;
  }

  // Extract the basename — split on both / and \ to handle Unix and Windows paths.
  const parts = currentFilePath.split(/[/\\]/);
  let base = parts[parts.length - 1] ?? "";

  // Strip the .scp extension (case-insensitive).
  base = base.replace(/\.scp$/i, "");

  // Replace any character outside the safe charset with underscore.
  base = base.replace(/[^A-Za-z0-9._-]/g, "_");

  // Collapse consecutive underscores to a single one.
  base = base.replace(/_+/g, "_");

  // Strip leading dots (prevent hidden files like .hidden).
  base = base.replace(/^\.+/, "");

  // If sanitization left us with an empty string (e.g. input was ".."), use a fallback.
  if (base.length === 0) {
    base = "untitled";
  }

  return `${base}${AUTOSAVE_SUFFIX}`;
}

/**
 * Resolve the absolute path to the sidecar file for the given basename.
 *
 * # Arguments
 * - `basename` — value from `getSidecarBasename`
 *
 * # Returns
 * Absolute path: `appDataDir/STREAM-Composer/autorecover/<basename>`
 */
export async function getSidecarPath(basename: string): Promise<string> {
  const { appDataDir, join } = await import("@tauri-apps/api/path");
  const dir = await appDataDir();
  return join(dir, AUTORECOVER_DIR, basename);
}

/**
 * Resolve the absolute path to the running.lock file.
 *
 * # Returns
 * Absolute path: `appDataDir/STREAM-Composer/autorecover/running.lock`
 */
export async function getLockfilePath(): Promise<string> {
  const { appDataDir, join } = await import("@tauri-apps/api/path");
  const dir = await appDataDir();
  return join(dir, AUTORECOVER_DIR, LOCKFILE_NAME);
}

// ---------------------------------------------------------------------------
// Internal: resolve the autorecover directory path
// ---------------------------------------------------------------------------

async function getAutorecoverDir(): Promise<string> {
  const { appDataDir, join } = await import("@tauri-apps/api/path");
  const dir = await appDataDir();
  return join(dir, AUTORECOVER_DIR);
}

// ---------------------------------------------------------------------------
// Tauri-backed I/O wrappers — sidecar read/write/clear
// ---------------------------------------------------------------------------

/**
 * Write the sidecar file for the given basename.
 * Creates the autorecover directory if it doesn't exist.
 * Silent failure — mirrors the saveRecentFiles pattern in useStore.ts.
 */
export async function writeSidecar(basename: string, content: string): Promise<void> {
  try {
    const { writeTextFile, mkdir } = await import("@tauri-apps/plugin-fs");
    const dir = await getAutorecoverDir();
    await mkdir(dir, { recursive: true });
    const path = await getSidecarPath(basename);
    await writeTextFile(path, content);
  } catch (err) {
    // Silent failure to caller; logged under DEV.
    if (import.meta.env.DEV) {
      console.warn("[autoRecover] writeSidecar failed:", err);
    }
  }
}

/**
 * Read the sidecar file for the given basename.
 *
 * # Returns
 * File content string, or null if the file doesn't exist or read fails.
 */
export async function readSidecar(basename: string): Promise<string | null> {
  try {
    const { readTextFile } = await import("@tauri-apps/plugin-fs");
    const path = await getSidecarPath(basename);
    return await readTextFile(path);
  } catch (err) {
    // Silent failure to caller; logged under DEV.
    if (import.meta.env.DEV) {
      console.warn("[autoRecover] readSidecar failed:", err);
    }
    return null;
  }
}

/**
 * Delete the sidecar file for the given basename. Silent failure.
 */
export async function clearSidecar(basename: string): Promise<void> {
  try {
    const { remove } = await import("@tauri-apps/plugin-fs");
    const path = await getSidecarPath(basename);
    await remove(path);
  } catch (err) {
    // Silent failure to caller; logged under DEV.
    if (import.meta.env.DEV) {
      console.warn("[autoRecover] clearSidecar failed:", err);
    }
  }
}

/**
 * List all sidecar basenames (files matching `*.scp.autosave`) in the
 * autorecover directory.
 *
 * # Returns
 * Array of basenames. Empty array on error or if directory doesn't exist.
 */
export async function enumerateSidecars(): Promise<string[]> {
  try {
    const { readDir } = await import("@tauri-apps/plugin-fs");
    const dir = await getAutorecoverDir();
    const entries = await readDir(dir);
    return entries
      .filter((e) => !e.isDirectory && e.name != null && e.name.endsWith(AUTOSAVE_SUFFIX))
      .map((e) => e.name as string);
  } catch (err) {
    // Silent failure to caller; logged under DEV.
    if (import.meta.env.DEV) {
      console.warn("[autoRecover] enumerateSidecars failed:", err);
    }
    return [];
  }
}

// ---------------------------------------------------------------------------
// Lockfile types and API
// ---------------------------------------------------------------------------

/** Parsed content of the running.lock file. */
export interface LockfileContent {
  pid: number;
  startedAt: string;
}

/**
 * Write the running.lock file with the current PID and ISO timestamp.
 * Creates the autorecover directory if it doesn't exist.
 * Silent failure.
 */
export async function writeLockfile(pid: number): Promise<void> {
  try {
    const { writeTextFile, mkdir } = await import("@tauri-apps/plugin-fs");
    const dir = await getAutorecoverDir();
    await mkdir(dir, { recursive: true });
    const path = await getLockfilePath();
    await writeTextFile(path, `${pid}\n${new Date().toISOString()}`);
  } catch (err) {
    // Silent failure to caller; logged under DEV.
    if (import.meta.env.DEV) {
      console.warn("[autoRecover] writeLockfile failed:", err);
    }
  }
}

/**
 * Read and parse the running.lock file.
 *
 * # Returns
 * Parsed `LockfileContent`, or null if the file doesn't exist or is malformed.
 */
export async function readLockfile(): Promise<LockfileContent | null> {
  try {
    const { readTextFile } = await import("@tauri-apps/plugin-fs");
    const path = await getLockfilePath();
    const content = await readTextFile(path);
    return parseLockfileContent(content);
  } catch (err) {
    // Silent failure to caller; logged under DEV.
    if (import.meta.env.DEV) {
      console.warn("[autoRecover] readLockfile failed:", err);
    }
    return null;
  }
}

/**
 * Delete the running.lock file. Call on graceful app shutdown.
 * Silent failure.
 */
export async function clearLockfile(): Promise<void> {
  try {
    const { remove } = await import("@tauri-apps/plugin-fs");
    const path = await getLockfilePath();
    await remove(path);
  } catch (err) {
    // Silent failure to caller; logged under DEV.
    if (import.meta.env.DEV) {
      console.warn("[autoRecover] clearLockfile failed:", err);
    }
  }
}

/**
 * Parse the raw text content of a running.lock file.
 *
 * Expected format (two lines):
 * ```
 * <pid>
 * <ISO timestamp>
 * ```
 *
 * # Arguments
 * - `text` — raw file content
 *
 * # Returns
 * `LockfileContent` if the format is valid, `null` otherwise.
 */
export function parseLockfileContent(text: string): LockfileContent | null {
  if (!text) return null;

  const lines = text.split("\n");
  if (lines.length < 2) return null;

  const pidStr = lines[0].trim();
  const timestamp = lines[1].trim();

  if (!pidStr || !timestamp) return null;

  const pidNum = parseInt(pidStr, 10);
  if (!Number.isInteger(pidNum) || pidNum <= 0) return null;

  return { pid: pidNum, startedAt: timestamp };
}

// ---------------------------------------------------------------------------
// Crash detection
// ---------------------------------------------------------------------------

/** Result of `detectCrashOnLaunch`. */
export interface CrashDetectionResult {
  crashed: boolean;
  sidecars: string[];             // basenames; [] if no crash
  staleLockfile: LockfileContent | null;
}

/**
 * Check whether a PID is currently alive via a Tauri IPC command.
 *
 * Uses the `is_pid_alive` Tauri command backed by sysinfo (lib.rs).
 * Falls back to `false` on any IPC error — treats as dead so crash modal fires;
 * user can dismiss if it's a false positive.
 *
 * # Arguments
 * - `pid` — process ID to check
 *
 * # Returns
 * `true` if the process is alive, `false` otherwise (including on IPC error).
 */
export async function isPidAlive(pid: number): Promise<boolean> {
  /*
   * Tauri v2 IPC invocation note (read this before debugging IPC failures):
   *
   * Use `(await import('@tauri-apps/api/core')).invoke(...)` — NOT
   * `window.__TAURI__.core.invoke(...)`. The latter is a Tauri v1 idiom; in v2,
   * `window.__TAURI__` is intentionally undefined by default because
   * `app.withGlobalTauri` is unset in `gui/src-tauri/tauri.conf.json` (the v2
   * default). ES-module imports of `@tauri-apps/api/*` and `@tauri-apps/plugin-*`
   * go through the v2 IPC bridge (postMessage / IPC handlers) which is ALWAYS on
   * regardless of `withGlobalTauri`.
   *
   * If you see `Cannot read properties of undefined (reading 'invoke')` in devtools
   * from `window.__TAURI__.core.invoke(...)`, that is expected — switch your
   * smoke-test snippet to the dynamic import form. See
   * .planning/debug/autorecover-bridge.md "Resolution" for the full diagnosis.
   */
  try {
    const { invoke } = await import("@tauri-apps/api/core");
    return await invoke<boolean>("is_pid_alive", { pid });
  } catch (err) {
    // Silent failure to caller; logged under DEV.
    if (import.meta.env.DEV) {
      console.warn("[autoRecover] isPidAlive failed:", err);
    }
    return false;
  }
}

/**
 * Detect whether the previous app run crashed.
 *
 * Algorithm (D-02):
 * 1. If no lockfile → not a crash (normal first launch or clean shutdown).
 * 2. If lockfile PID === currentPid → same process somehow (defensive; skip).
 * 3. If lockfile PID is alive → another instance is running (not a crash).
 * 4. If lockfile PID is dead → previous run crashed → enumerate sidecars.
 *
 * # Arguments
 * - `currentPid` — PID of the current process (used to avoid self-detection)
 *
 * # Returns
 * `CrashDetectionResult`
 */
export async function detectCrashOnLaunch(
  currentPid: number,
): Promise<CrashDetectionResult> {
  const lockfile = await readLockfile();

  if (lockfile === null) {
    return { crashed: false, sidecars: [], staleLockfile: null };
  }

  // Defensive: same PID (shouldn't happen but be safe)
  if (lockfile.pid === currentPid) {
    return { crashed: false, sidecars: [], staleLockfile: null };
  }

  const alive = await isPidAlive(lockfile.pid);

  if (alive) {
    // Another instance is running — not a crash
    return { crashed: false, sidecars: [], staleLockfile: null };
  }

  // PID is dead → previous run crashed
  const sidecars = await enumerateSidecars();
  return { crashed: true, sidecars, staleLockfile: lockfile };
}

// ---------------------------------------------------------------------------
// Debounced sidecar writer factory
// ---------------------------------------------------------------------------

/**
 * Create a debounced sidecar writer that captures the current project state
 * and writes it to disk after `delayMs` of inactivity.
 *
 * Designed to be called from the store's isDirty subscription.
 *
 * # Arguments
 * - `delayMs`    — debounce window in milliseconds (typically 2000)
 * - `serialize`  — closure that captures the current store state and returns
 *                  a `.scp` JSON string (called at write-time, not schedule-time)
 * - `getBasename` — closure that returns the current sidecar basename
 *                   (handles untitled project UUID transitions transparently)
 *
 * # Returns
 * An object with three methods:
 * - `schedule()` — call on every isDirty=true mutation; resets the debounce timer
 * - `cancel()`   — call when isDirty becomes false (Save completed); clears timer
 * - `flush()`    — force-immediate write; used at graceful shutdown
 */
export function createDebouncedSidecarWriter(
  delayMs: number,
  serialize: () => string,
  getBasename: () => string,
): {
  schedule: () => void;
  cancel: () => void;
  flush: () => Promise<void>;
} {
  let timer: ReturnType<typeof setTimeout> | null = null;

  function schedule(): void {
    if (timer !== null) {
      clearTimeout(timer);
    }
    timer = setTimeout(() => {
      timer = null;
      void writeSidecar(getBasename(), serialize());
    }, delayMs);
  }

  function cancel(): void {
    if (timer !== null) {
      clearTimeout(timer);
      timer = null;
    }
  }

  async function flush(): Promise<void> {
    if (timer !== null) {
      clearTimeout(timer);
      timer = null;
    }
    await writeSidecar(getBasename(), serialize());
  }

  return { schedule, cancel, flush };
}
