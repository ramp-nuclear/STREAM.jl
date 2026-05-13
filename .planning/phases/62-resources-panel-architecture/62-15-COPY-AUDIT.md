# 62-15 Copy Audit — Phase 62 user-facing strings rewritten to engineering-tool voice

**Status:** Applied in Plan 62-15 (Phase 62 gap-closure Wave 5).
**Closes:** `.planning/phases/62-resources-panel-architecture/62-VERIFICATION.md` Critical Gap #4
("Professional copy pass — user-facing strings read as 'AI-ish'").
**Supersedes:** Locked decision D-26 sentinel-name value, per user feedback in
VERIFICATION.md Critical Gap #4 ("Need to rethink wording in this phase ...
professional voice"). The active locked value going forward is
`(leave unset — set in code)`.

## Rationale

Phase 62 introduced ~17 distinct user-facing strings (resource picker
empty-states, identifier-validation messages, error dialogs, sentinel
labels, disabled-button tooltips). Several read as future-tense roadmap
copy or as conversational/apology phrasing rather than as engineering-tool
voice. This audit lists every rewrite, the rationale tag per voice rule,
and the source/destination file where each substitution lands.

## Voice rules

1. **Terse, declarative.** Strip filler words ("Please", "just", "simply",
   "currently", "for now").
2. **Engineering-tool voice.** State the rule or fact; do not apologize or
   reassure.
3. **No em-dash decoration.** Em-dashes are fine for parenthetical asides
   (`(leave unset — set in code)`, `Power Shapes — z_cosine kind`) but
   not where a period works.
4. **Tooltips ≤ 60 chars.** Single line. State the rule.
5. **Error dialogs: `<Fact>. <Action.>`** Two short clauses. Both terminated.
6. **No future-tense excuses.** Replace "is planned for a future release"
   with "Not yet supported."
7. **Lowercase resource kinds in body text.** Use `geometry`, `power shape`,
   `fluid` — not `Geometry`, `Power Shape`, `Fluid` — when they appear in
   sentence body. Headers / section labels stay Title Case.
8. **Preserve the sentinel U+2014 in `(leave unset — set in code)`.** The
   parenthetical aside is the legitimate em-dash use case.

## Substitution table

| # | File | Current string | New string | Rationale |
|---|------|----------------|------------|-----------|
| 1 | `gui/src/store/useStore.ts` (SENTINEL_POWER_SHAPE_NAME) | `(leave unset — fill in code)` | `(leave unset — set in code)` | Rule 1: "fill in" is filler; "set in" is precise. Supersedes D-26. |
| 2 | `gui/src/components/sidebar/ResourceReferencePicker.tsx` (emptyCopy) | `No geometries yet — click + New… or open the Resources tab.` | `No geometries. Use + New or the Resources tab.` | Rule 1, 4. Two short clauses; no "yet"; no nested punctuation. |
| 3 | `gui/src/components/sidebar/ResourceReferencePicker.tsx` (emptyCopy) | `No power shapes yet — click + New… or open the Resources tab.` | `No power shapes. Use + New or the Resources tab.` | Rule 1, 4. |
| 4 | `gui/src/components/sidebar/ResourceReferencePicker.tsx` (sentinel SelectItem) | `(leave unset — fill in code)` | `(leave unset — set in code)` | Rule 1. Matches sentinel rename. Supersedes D-26. |
| 5 | `gui/src/components/sidebar/ResourceReferencePicker.tsx` (Edit-disabled tooltip) | `Select a resource to edit it.` | `Pick a resource first.` | Rule 1, 4. 22 chars vs 30; "pick" implies the select control directly. |
| 6 | `gui/src/components/sidebar/GeometryResourceEditor.tsx` (Julia-ident error) | `Use ASCII letters, digits, and underscores; must not start with a digit.` | `Letters, digits, underscores. Cannot start with a digit.` | Rule 1, 5. "ASCII" is jargon. Two clauses. |
| 7 | `gui/src/components/sidebar/PowerShapeResourceEditor.tsx` (Julia-ident error) | `Use ASCII letters, digits, and underscores; must not start with a digit.` | `Letters, digits, underscores. Cannot start with a digit.` | Rule 1, 5. Same as #6. |
| 8 | `gui/src/components/sidebar/PowerShapeResourceEditor.tsx` (amplitude error) | `Amplitude must be a finite number.` | `Amplitude must be finite.` | Rule 1. "a finite number" is six syllables for what "finite" says alone. |
| 9 | `gui/src/components/sidebar/PowerShapeResourceEditor.tsx` (path error) | `Please pick a CSV file via Browse.` | `Pick a CSV file via Browse.` | Rule 2. Drop "Please". |
| 10 | `gui/src/components/sidebar/SidebarPanel.tsx` (no-selection variant) | `Select a resource on the left to edit it.` | `Select a resource to edit it.` | Rule 1. "on the left" is redundant. |
| 11 | `gui/src/components/sidebar/SidebarPanel.tsx` (no-selection variant) | `Select a component on the canvas to view its properties.` | `Select a component to view its properties.` | Rule 1. "on the canvas" is redundant. |
| 12 | `gui/src/components/resources/ResourcesTreePanel.tsx` (search placeholder) | `Search resources…` | `Search resources…` | NO CHANGE — already terse, uses canonical ellipsis glyph. |
| 13 | `gui/src/components/resources/ResourcesTreePanel.tsx` (Fluids disabled tooltip) | `Multi-fluid support is planned for a future release.` | `Multiple fluids not yet supported.` | Rule 6, 4. 32 chars vs 50; states the rule, not the roadmap. |
| 13b | `gui/src/components/project/ModelOptionsPanel.tsx` (Default fluid disabled tooltip) | `Multi-fluid support is planned for a future release.` | `Multiple fluids not yet supported.` | Same as #13; same surface, second mount point. Discovered during gate verification (not in original PLAN substitution table). |
| 14 | `gui/src/components/resources/ResourceRow.tsx` (Delete description) | `Delete ${kindLabel(kind)} ${resource.name}? It is used by ${usages.length} component(s).` | `Delete ${kindLabel(kind)} ${resource.name}? Used by ${usages.length} component(s).` | Rule 1. "It is" is filler. |
| 15 | `gui/src/components/resources/ResourceRow.tsx` (kindLabel) | returns `"power shape"` | returns `"power shape"` | NO CHANGE — already lowercase. |
| 16 | `gui/src/store/useStore.ts` (save error dialogs ×2) | `Couldn't save project. Check that the file isn't read-only and there is enough disk space, then try again.` | `Save failed. Check the file is writable and there is disk space.` | Rule 5, 1. Two clauses; both terminated; drop "Couldn't" colloquial. |
| 17 | `gui/src/store/useStore.ts` (open error dialogs ×2) | `Couldn't open this project. The file may be missing, corrupted, or not a valid .scp file.` | `Open failed. The file may be missing, corrupted, or not a valid .scp file.` | Rule 5, 1. Same pattern. |
| 18 | `gui/src/store/useStore.ts` (missing power-shape) | `N power shape file(s) could not be found. Open the Resources tab to relocate them.` (and the singular variant) | `N power-shape file(s) not found. Open the Resources tab to relocate.` (and the singular variant) | Rule 1, 7. "could not be" is filler; "to relocate them" — "them" is implied. |
| 19 | `gui/src/store/useStore.ts` (missing-file dialog title) | `Missing Power Shape file` | `Missing power-shape file` | Rule 7 — sentence-case in body / dialog title, hyphenated. |

## Punctuation glyphs

- Straight ASCII punctuation throughout EXCEPT for the U+2014 em-dash in
  `(leave unset — set in code)` and the existing UI-SPEC parenthetical
  asides.
- The horizontal-ellipsis glyph U+2026 (`…`) IS kept in the `+ New…`,
  `Edit…`, `Browse…` button labels and in the search-resources
  placeholder — those are existing canonical Phase-62 button conventions
  and changing them is out of scope.

## Items audited but NOT changed

- **Editor headers** (`New Geometry` / `Edit Geometry` / `New Power Shape`
  / `Edit Power Shape`): unchanged. Section titles, Rule 7 keeps them
  Title Case.
- **ModelOptionsPanel descriptions** (lines 299, 324, 341, 358): info-
  tooltip help-text strings, not error/disabled tooltips. They read fine
  — declarative, terse, end with periods.
- **`(none yet — click +)` empty-state placeholder** in ResourcesTreePanel:
  audited but kept; the em-dash separates the state from the action, and
  the line is already terse.
- **`kindLabel` return values** (ResourceRow.tsx:369-373): function already
  returns lowercase `"geometry"` / `"power shape"` / `"fluid"`.

## Verification commands

Source-side OLD-string gates (each MUST return 0 in non-test files):

```sh
cd gui && grep -rE "fill in code" src/ | grep -v "__tests__\\|\\.test\\." | wc -l
cd gui && grep -rE "Please pick" src/ | grep -v "__tests__\\|\\.test\\." | wc -l
cd gui && grep -rE "is planned for a future release" src/ | grep -v "__tests__\\|\\.test\\." | wc -l
cd gui && grep -rE "It is used by" src/ | grep -v "__tests__\\|\\.test\\." | wc -l
cd gui && grep -rE "Couldn't save project|Couldn't open this project" src/ | grep -v "__tests__\\|\\.test\\." | wc -l
```

NEW-string gates (each MUST return ≥1 in the owning file):

```sh
cd gui && grep -c "set in code" src/store/useStore.ts
cd gui && grep -c "set in code" src/components/sidebar/ResourceReferencePicker.tsx
cd gui && grep -c "Pick a resource first" src/components/sidebar/ResourceReferencePicker.tsx
cd gui && grep -c "Save failed" src/store/useStore.ts
cd gui && grep -c "Open failed" src/store/useStore.ts
cd gui && grep -c "Multiple fluids not yet supported" src/components/resources/ResourcesTreePanel.tsx
cd gui && grep -cE "Used by \\\$\\{usages\\.length\\}" src/components/resources/ResourceRow.tsx
cd gui && grep -c "Amplitude must be finite" src/components/sidebar/PowerShapeResourceEditor.tsx
```

## Note on "on the canvas" / "on the left to edit" greps

The substitution-table gate over-matched two unrelated phrases in
`src/registry/types.ts` and `src/lib/codeGenerator.ts` — those are
English idiomatic usage in implementation-doc comments about canvas
blocks, not the user-facing copy this audit covers. Both files are
outside `files_modified` and outside the substitution table scope. The
relevant UI strings (SidebarPanel.tsx no-selection variant) have been
rewritten and verified.
