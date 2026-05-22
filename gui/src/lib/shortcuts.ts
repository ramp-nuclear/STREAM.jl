// shortcuts.ts — single source of truth for the keyboard-shortcut catalog.
//
// Phase 72 (help-system shape, 2026-05-22). Consumed by:
//   - CommandPalette in "shortcuts" mode (? keybind opens it on this view).
//   - AnatomyDialog (no — the Anatomy is a visual legend, not a keymap).
//
// New shortcuts MUST be added here in addition to the actual keydown handler
// that owns the binding. The catalog is descriptive, not authoritative — the
// real binding lives in App.tsx / CanvasPanel.tsx — but every binding the
// user can press should appear here so `?` discovers it.

export type ShortcutGroup =
  | "File"
  | "Edit"
  | "View"
  | "Canvas"
  | "Help";

export interface ShortcutEntry {
  /** Group bucket — controls rendering order + section header. */
  group: ShortcutGroup;
  /** Short, lowercase, action-only label (matches first-run keymap idiom). */
  label: string;
  /** Display string (e.g. "Ctrl+O"). Plain text matching the menubar idiom —
   *  no ⌘ glyph branching. */
  keys: string;
  /** Optional tokens that broaden cmdk fuzzy-search hits (e.g. "save as"
   *  should also match "export"). Joined with spaces into the cmdk `value`. */
  aliases?: readonly string[];
}

// Groups render in this order in shortcut-mode cmdk. Mirrors the menubar.
export const SHORTCUT_GROUP_ORDER: readonly ShortcutGroup[] = [
  "File",
  "Edit",
  "View",
  "Canvas",
  "Help",
];

// Ordered within each group by frequency-of-use, not alphabetical. The user
// scanning for "save" should see save before save-as, etc.
export const SHORTCUTS_CATALOG: readonly ShortcutEntry[] = [
  // File
  { group: "File", label: "new project", keys: "Ctrl+N" },
  { group: "File", label: "open project", keys: "Ctrl+O" },
  { group: "File", label: "save", keys: "Ctrl+S" },
  { group: "File", label: "save as", keys: "Ctrl+Shift+S", aliases: ["export"] },

  // Edit
  { group: "Edit", label: "undo", keys: "Ctrl+Z" },
  { group: "Edit", label: "redo", keys: "Ctrl+Y", aliases: ["Ctrl+Shift+Z"] },
  { group: "Edit", label: "cut", keys: "Ctrl+X" },
  { group: "Edit", label: "copy", keys: "Ctrl+C" },
  { group: "Edit", label: "paste", keys: "Ctrl+V" },
  { group: "Edit", label: "duplicate", keys: "Ctrl+D" },

  // View
  { group: "View", label: "command palette", keys: "Ctrl+P" },
  { group: "View", label: "toggle bottom panel", keys: "Ctrl+`", aliases: ["code", "validation"] },
  { group: "View", label: "components tab", keys: "Ctrl+1" },
  { group: "View", label: "presets tab", keys: "Ctrl+2" },
  { group: "View", label: "resources tab", keys: "Ctrl+3" },
  { group: "View", label: "project tab", keys: "Ctrl+4" },

  // Canvas
  { group: "Canvas", label: "deselect", keys: "Esc" },
  { group: "Canvas", label: "delete selection", keys: "Del", aliases: ["Backspace"] },

  // Help
  { group: "Help", label: "shortcuts", keys: "?", aliases: ["help", "cheatsheet"] },
];
