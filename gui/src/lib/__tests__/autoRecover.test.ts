// autoRecover.test.ts — Unit tests for the AutoRecover substrate.
//
// Environment: node (no Tauri IPC). Tauri-backed I/O is mocked via vi.mock.
// Pure helpers, lockfile parsing, crash detection logic, and debounce timing
// are all covered here.

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// ---------------------------------------------------------------------------
// Mock Tauri APIs — must come BEFORE any import of the module under test.
// ---------------------------------------------------------------------------

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const mockWriteTextFile = vi.fn<any>().mockResolvedValue(undefined);
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const mockReadTextFile = vi.fn<any>().mockResolvedValue("");
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const mockRemove = vi.fn<any>().mockResolvedValue(undefined);
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const mockMkdir = vi.fn<any>().mockResolvedValue(undefined);
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const mockReadDir = vi.fn<any>().mockResolvedValue([]);
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const mockAppDataDir = vi.fn<any>().mockResolvedValue("/mock/appdata");
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const mockJoin = vi.fn<any>().mockImplementation((...parts: unknown[]) => Promise.resolve((parts as string[]).join("/")));
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const mockInvoke = vi.fn<any>().mockResolvedValue(true);

vi.mock("@tauri-apps/plugin-fs", () => ({
  writeTextFile: mockWriteTextFile,
  readTextFile: mockReadTextFile,
  remove: mockRemove,
  mkdir: mockMkdir,
  readDir: mockReadDir,
}));

vi.mock("@tauri-apps/api/path", () => ({
  appDataDir: mockAppDataDir,
  join: mockJoin,
}));

vi.mock("@tauri-apps/api/core", () => ({
  invoke: mockInvoke,
}));

// Now import the module under test
import {
  getSidecarBasename,
  parseLockfileContent,
  detectCrashOnLaunch,
  createDebouncedSidecarWriter,
  // The following are imported to verify they exist as named exports (acceptance criterion)
  // but are not exercised directly in tests that run in node env without full Tauri IPC
  getSidecarPath as _getSidecarPath,
  getLockfilePath as _getLockfilePath,
  writeSidecar as _writeSidecar,
  readSidecar as _readSidecar,
  clearSidecar as _clearSidecar,
  enumerateSidecars as _enumerateSidecars,
  writeLockfile as _writeLockfile,
  readLockfile as _readLockfile,
  clearLockfile as _clearLockfile,
  isPidAlive as _isPidAlive,
} from "../autoRecover";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

beforeEach(() => {
  vi.clearAllMocks();
  // Default: appDataDir returns a sensible path; join concatenates with "/"
  mockAppDataDir.mockResolvedValue("/mock/appdata");
  mockJoin.mockImplementation((...parts: unknown[]) => Promise.resolve((parts as string[]).join("/")));
});

// ---------------------------------------------------------------------------
// Pure helpers: getSidecarBasename
// ---------------------------------------------------------------------------

describe("getSidecarBasename", () => {
  it("extracts basename from Unix path", () => {
    expect(getSidecarBasename("/home/me/projects/foo.scp", "uuid-A")).toBe("foo.scp.autosave");
  });

  it("returns untitled- format for null path", () => {
    expect(getSidecarBasename(null, "uuid-A")).toBe("untitled-uuid-A.scp.autosave");
  });

  it("extracts basename from Windows-style path", () => {
    expect(getSidecarBasename("C:\\Users\\me\\bar.scp", "uuid-X")).toBe("bar.scp.autosave");
  });

  it("strips path traversal components (../../etc/passwd)", () => {
    const result = getSidecarBasename("../../etc/passwd", "uuid-X");
    expect(result).toBe("passwd.scp.autosave");
  });

  it("replaces spaces and special chars with underscores", () => {
    expect(getSidecarBasename("weird name with spaces!.scp", "u")).toBe(
      "weird_name_with_spaces_.scp.autosave"
    );
  });

  it("result always matches safe charset /^[A-Za-z0-9._-]+$/", () => {
    const inputs = [
      "../../etc/passwd",
      "normal-file.scp",
      "with spaces.scp",
      "C:\\weird\\path.scp",
      "unix/nested/file.scp",
      "file with (parens) & more!.scp",
    ];
    for (const input of inputs) {
      const result = getSidecarBasename(input, "safe-uuid");
      expect(result).toMatch(/^[A-Za-z0-9._-]+$/);
      expect(result).not.toContain("..");
      expect(result).not.toContain("/");
      expect(result).not.toContain("\\");
    }
  });

  it("path-traversal result has no '..' segments", () => {
    const result = getSidecarBasename("../../etc/passwd", "uuid-X");
    expect(result).not.toContain("..");
    expect(result).not.toContain("/");
  });
});

// ---------------------------------------------------------------------------
// parseLockfileContent
// ---------------------------------------------------------------------------

describe("parseLockfileContent", () => {
  it("parses valid lockfile content", () => {
    const result = parseLockfileContent("1234\n2026-05-14T10:30:00Z");
    expect(result).toEqual({ pid: 1234, startedAt: "2026-05-14T10:30:00Z" });
  });

  it("returns null for garbage input", () => {
    expect(parseLockfileContent("garbage")).toBeNull();
  });

  it("returns null for empty string", () => {
    expect(parseLockfileContent("")).toBeNull();
  });

  it("returns null for PID only (missing timestamp)", () => {
    expect(parseLockfileContent("1234")).toBeNull();
  });

  it("returns null for non-numeric PID", () => {
    expect(parseLockfileContent("notapid\n2026-05-14T10:30:00Z")).toBeNull();
  });

  it("returns null for zero PID", () => {
    expect(parseLockfileContent("0\n2026-05-14T10:30:00Z")).toBeNull();
  });

  it("returns null for negative PID", () => {
    expect(parseLockfileContent("-1\n2026-05-14T10:30:00Z")).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Crash detection: detectCrashOnLaunch
// ---------------------------------------------------------------------------

describe("detectCrashOnLaunch", () => {
  it("returns crashed:false when no lockfile exists", async () => {
    // readTextFile throws (file not found) → readLockfile → null
    mockReadTextFile.mockRejectedValue(new Error("not found"));
    const result = await detectCrashOnLaunch(1000);
    expect(result).toEqual({ crashed: false, sidecars: [], staleLockfile: null });
  });

  it("returns crashed:false when lockfile PID is alive", async () => {
    mockReadTextFile.mockResolvedValue("999\n2026-05-14T10:00:00Z");
    // isPidAlive → invoke returns true
    mockInvoke.mockResolvedValue(true);
    const result = await detectCrashOnLaunch(1000);
    expect(result.crashed).toBe(false);
  });

  it("returns crashed:true with sidecar basenames when lockfile PID is dead", async () => {
    mockReadTextFile.mockResolvedValue("999\n2026-05-14T10:00:00Z");
    // isPidAlive → invoke returns false (process dead)
    mockInvoke.mockResolvedValue(false);
    // enumerateSidecars → readDir returns some .scp.autosave files
    mockReadDir.mockResolvedValue([
      { name: "foo.scp.autosave", isDirectory: false },
      { name: "running.lock", isDirectory: false },
      { name: "bar.scp.autosave", isDirectory: false },
    ]);
    const result = await detectCrashOnLaunch(1000);
    expect(result.crashed).toBe(true);
    expect(result.sidecars).toContain("foo.scp.autosave");
    expect(result.sidecars).toContain("bar.scp.autosave");
    expect(result.sidecars).not.toContain("running.lock");
    expect(result.staleLockfile).toEqual({ pid: 999, startedAt: "2026-05-14T10:00:00Z" });
  });
});

// ---------------------------------------------------------------------------
// Debounce timing
// ---------------------------------------------------------------------------

describe("createDebouncedSidecarWriter", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    mockWriteTextFile.mockResolvedValue(undefined);
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("does NOT call serialize before the debounce window elapses", async () => {
    const serialize = vi.fn(() => "project-content");
    const getBasename = vi.fn(() => "test.scp.autosave");
    const writer = createDebouncedSidecarWriter(2000, serialize, getBasename);

    writer.schedule();
    vi.advanceTimersByTime(1900);
    // Must flush the promise queue before checking
    await Promise.resolve();

    expect(serialize).not.toHaveBeenCalled();
    writer.cancel();
  });

  it("calls serialize exactly once after 2.1s debounce window", async () => {
    const serialize = vi.fn(() => "project-content");
    const getBasename = vi.fn(() => "test.scp.autosave");
    const writer = createDebouncedSidecarWriter(2000, serialize, getBasename);

    writer.schedule();
    vi.advanceTimersByTime(2100);
    // Flush microtasks so async writeSidecar completes
    await vi.runAllTimersAsync();

    expect(serialize).toHaveBeenCalledTimes(1);
  });

  it("resets debounce on second schedule within window", async () => {
    const serialize = vi.fn(() => "project-content");
    const getBasename = vi.fn(() => "test.scp.autosave");
    const writer = createDebouncedSidecarWriter(2000, serialize, getBasename);

    writer.schedule();
    vi.advanceTimersByTime(1000);
    writer.schedule(); // reset the timer
    vi.advanceTimersByTime(1000); // total 2s from first, but only 1s from second
    await Promise.resolve();

    expect(serialize).not.toHaveBeenCalled();
    writer.cancel();
  });

  it("cancel prevents serialize from being called", async () => {
    const serialize = vi.fn(() => "project-content");
    const getBasename = vi.fn(() => "test.scp.autosave");
    const writer = createDebouncedSidecarWriter(2000, serialize, getBasename);

    writer.schedule();
    vi.advanceTimersByTime(1000);
    writer.cancel();
    vi.advanceTimersByTime(5000); // advance well past the window
    await Promise.resolve();

    expect(serialize).not.toHaveBeenCalled();
  });

  it("flush() calls serialize immediately and writes sidecar", async () => {
    const serialize = vi.fn(() => "project-content");
    const getBasename = vi.fn(() => "test.scp.autosave");
    const writer = createDebouncedSidecarWriter(2000, serialize, getBasename);

    writer.schedule();
    await writer.flush();

    expect(serialize).toHaveBeenCalledTimes(1);
  });
});
