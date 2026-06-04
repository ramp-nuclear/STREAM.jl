---
phase: 65-interaction-model-overhaul
plan: 09
type: execute
wave: 1
depends_on: []
files_modified:
  - gui/src-tauri/capabilities/default.json
  - gui/src/lib/autoRecover.ts
autonomous: false
requirements: []
gap_closure: true
tags: [autorecover, tauri-capabilities, blocker, gap-closure, phase-65]

must_haves:
  truths:
    - "After unsaved edits (e.g. drop a node), within ~2s a *.scp.autosave file appears in ~/.local/share/com.stream.composer/STREAM-Composer/autorecover/."
    - "A running.lock file appears in the same directory while the app is running."
    - "After force-killing the Tauri shell with unsaved edits and relaunching, the AutoRecoverRestoreModal blocks the workspace (Test 17)."
    - "All Tauri fs operations from autoRecover.ts (mkdir, writeTextFile, readTextFile, readDir, remove) are permitted by the v2 capability ACL."
    - "Capability ACL grants $APPDATA scope broadly (so all fs ops succeed) AND additionally narrows a structured `fs:scope` entry to the `STREAM-Composer/autorecover/**` subtree (defense-in-depth — narrower grant takes precedence inside that subtree)."
    - "When fs operations DO fail (transient I/O error, etc.) in dev builds, the failure is logged via console.warn — not silently swallowed."
    - "The rationale for using `(await import('@tauri-apps/api/core')).invoke(...)` (vs the v1 `window.__TAURI__.core.invoke(...)` idiom) is preserved in source as an inline code comment so future debuggers don't re-derive it from scratch."
  artifacts:
    - path: "gui/src-tauri/capabilities/default.json"
      provides: "Tauri v2 fs ACL grants: appdata scope (read+write recursive), allow-remove, allow-read-dir. Plus a structured `fs:scope` entry binding `$APPDATA/STREAM-Composer/autorecover/**` for defense-in-depth narrowing. Existing home-recursive scope and dialog scope retained."
      contains: "fs:scope-appdata-recursive"
    - path: "gui/src/lib/autoRecover.ts"
      provides: "Seven previously-silent catch blocks now emit `console.warn('[autoRecover] <op> failed:', err)` under `import.meta.env.DEV`. Plus a header comment block explaining why ES-module imports (`await import('@tauri-apps/api/core')`) are the v2-correct invocation path and `window.__TAURI__` is intentionally undefined by default."
  key_links:
    - from: "autoRecover.ts writeSidecar"
      to: "$APPDATA/STREAM-Composer/autorecover/*.scp.autosave"
      via: "tauri-plugin-fs writeTextFile, permitted by fs:scope-appdata-recursive + fs:allow-appdata-write-recursive AND additionally by the structured fs:scope binding $APPDATA/STREAM-Composer/autorecover/**"
      pattern: "fs:scope-appdata-recursive"
    - from: "autoRecover.ts catch blocks"
      to: "devtools console"
      via: "console.warn under import.meta.env.DEV"
      pattern: "import.meta.env.DEV"
---

<objective>
Unblock AutoRecover (UAT Tests 16 + 17, both blockers). The substrate shipped in Plan 07 and the modal shipped in Plan 08 are correct — every Tauri fs call from `autoRecover.ts` is rejected by the v2 capability ACL because `gui/src-tauri/capabilities/default.json` grants only `fs:scope-home-recursive` (a READ scope on $HOME, not a write scope; and a different base directory from $APPDATA where AutoRecover writes). The seven `try { ... } catch { }` silent-fail blocks in `autoRecover.ts` swallow the rejections — zero files on disk, no errors surfaced.

Fix is two-file:
1. Add the missing fs permissions/scope to `gui/src-tauri/capabilities/default.json` — both the broad appdata grants (functional fix) AND a structured `fs:scope` object narrowed to `$APPDATA/STREAM-Composer/autorecover/**` (defense-in-depth).
2. Replace the seven silent `catch { }` blocks with `catch (err) { if (import.meta.env.DEV) console.warn('[autoRecover] <op> failed:', err); }` so future failures surface in devtools, AND add an inline header comment explaining the v2 ES-module invocation pattern so future debuggers don't re-derive the `window.__TAURI__` red herring from scratch.

After fix: rerun UAT 16 (edit → sidecar appears) and UAT 17 (kill -9 → relaunch → modal). This plan ends with a `checkpoint:human-verify` blocking on those two tests because they require running the Tauri dev shell (no vitest substitute exists).

Purpose: AutoRecover is a milestone-critical safety net (D-01..D-06 of Phase 65). Without it, every unsaved edit is at risk on a crash. This plan restores the loop.

Output: capability JSON + autoRecover.ts updated; UAT 16/17 pass.

Source: `.planning/debug/autorecover-bridge.md` (diagnosis complete; root cause confirmed via 7-step evidence chain).
</objective>

<execution_context>
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/workflows/execute-plan.md
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.planning/phases/65-interaction-model-overhaul/65-07-SUMMARY.md
@.planning/phases/65-interaction-model-overhaul/65-08-SUMMARY.md
@.planning/phases/65-interaction-model-overhaul/65-UAT.md
@.planning/debug/autorecover-bridge.md
@gui/src/lib/autoRecover.ts
@gui/src-tauri/capabilities/default.json

<interfaces>
<!-- Current capability permissions (line 6-19 of default.json) -->
The capability already grants: core:default, opener:default, dialog:default,
fs:default, fs:allow-write-text-file, fs:allow-read-text-file, fs:allow-exists,
fs:allow-mkdir, fs:scope-home-recursive, core:window:allow-set-title/close/destroy.

MISSING (must be added):
- fs:scope-appdata-recursive       (read scope for $APPDATA — flat string permission)
- fs:allow-appdata-write-recursive (write scope for $APPDATA — flat string permission)
- fs:allow-remove                  (clearSidecar / clearLockfile — flat string permission)
- fs:allow-read-dir                (enumerateSidecars — flat string permission)
- Structured `fs:scope` object narrowing to `$APPDATA/STREAM-Composer/autorecover/**`
  (defense-in-depth — UAT gap item, see Tauri v2 capability schema: identifier + allow
  array of { path } objects).

<!-- Tauri v2 capabilities permissions array supports mixing flat strings and structured
     objects in the same array. The schema (../gen/schemas/desktop-schema.json) validates
     both forms. Structured object shape per tauri-plugin-fs v2.4.5:
       { "identifier": "fs:scope", "allow": [ { "path": "<glob>" } ] }
     The narrower glob is additive — it does NOT revoke the broader recursive grants
     above. Both must be present for the functional fix AND the defense-in-depth
     narrowing to coexist (Tauri v2 ACL is union-of-grants, not intersection). -->

<!-- The seven silent-catch blocks in autoRecover.ts that need DEV-mode logging -->
The bare `} catch {` blocks (no parameter capture) are at:
- Line 121-123  writeSidecar       — mkdir + writeTextFile to sidecar path
- Line 137-139  readSidecar        — readTextFile for sidecar
- Line 150-152  clearSidecar       — remove sidecar
- Line 170-172  enumerateSidecars  — readDir of autorecover/
- Line 197-199  writeLockfile      — mkdir + writeTextFile for lockfile
- Line 213-216  readLockfile       — readTextFile + parseLockfileContent for lockfile
- Line 228-230  clearLockfile      — remove lockfile

Plus isPidAlive at 293-295 — also currently `} catch {` (this one wraps an
invoke() not an fs op, but the same logging pattern applies; the diagnosis
doesn't list it as load-bearing, but log it for consistency).

<!-- Tauri v2 fs plugin permission identifiers (from tauri-plugin-fs 2.4.5,
     which is already installed per Cargo.toml — no version bump needed) -->
The literal string identifiers (used directly as JSON array entries) are:
  "fs:scope-appdata-recursive"
  "fs:allow-appdata-write-recursive"
  "fs:allow-remove"
  "fs:allow-read-dir"

The JSON schema reference at line 2 of default.json (../gen/schemas/desktop-schema.json)
is autogenerated by Tauri and validates these identifiers as well as the structured
{identifier, allow} object form.
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Grant AutoRecover fs ACL permissions + defense-in-depth narrowing</name>
  <files>gui/src-tauri/capabilities/default.json</files>
  <action>
    Edit `gui/src-tauri/capabilities/default.json`. The `permissions` array currently contains
    only flat string entries. After this edit it will contain BOTH flat string entries (the
    broad functional grants) AND ONE structured object entry (the defense-in-depth narrowing).

    Step 1 — Add the four flat permission strings. In the `permissions` array, after the
    existing `"fs:scope-home-recursive"` line and before the `core:window:*` block, insert:

    - "fs:scope-appdata-recursive"
    - "fs:allow-appdata-write-recursive"
    - "fs:allow-remove"
    - "fs:allow-read-dir"

    Step 2 — Add the structured `fs:scope` entry for defense-in-depth narrowing.
    Immediately after the four flat strings above and BEFORE the `core:window:*` block,
    insert one additional array entry as a JSON object (not a string):

    ```json
    {
      "identifier": "fs:scope",
      "allow": [
        { "path": "$APPDATA/STREAM-Composer/autorecover/**" }
      ]
    }
    ```

    This narrower scope is ADDITIVE under Tauri v2 ACL (union-of-grants). The broad
    `fs:scope-appdata-recursive` keeps the functional fix intact for any future autoRecover
    paths that move outside `autorecover/`; the structured entry documents (in the ACL itself)
    that the only path AutoRecover legitimately writes is `$APPDATA/STREAM-Composer/autorecover/**`.
    It closes the explicit UAT gap item "Add a structured fs:scope entry binding
    $APPDATA/STREAM-Composer/autorecover/* (defense-in-depth)" from .planning/phases/65-…/65-UAT.md.

    Keep all existing entries (`core:default`, `opener:default`, `dialog:default`, `fs:default`,
    `fs:allow-write-text-file`, `fs:allow-read-text-file`, `fs:allow-exists`, `fs:allow-mkdir`,
    `fs:scope-home-recursive`, three `core:window:*`). Maintain the trailing comma rules of
    valid JSON — note that the structured object entry must be comma-separated from the
    surrounding entries.

    Diagnosis source: `.planning/debug/autorecover-bridge.md` "Resolution.root_cause".
    The fs plugin enforces a scoped ACL: every fs command requires BOTH an operation permission
    AND a scope permission for the target path. `fs:scope-home-recursive` is the READ scope for
    $HOME; AutoRecover writes to $APPDATA (Linux: ~/.local/share/&lt;bundle-id&gt;/), which is
    a separate base. The four flat new entries grant:
      - `fs:scope-appdata-recursive` — read scope for $APPDATA
      - `fs:allow-appdata-write-recursive` — write scope for $APPDATA (mkdir, writeTextFile)
      - `fs:allow-remove` — clearSidecar / clearLockfile use `remove`
      - `fs:allow-read-dir` — enumerateSidecars uses `readDir`
    The structured `fs:scope` entry then narrows to the actual subtree AutoRecover writes —
    documenting intent in-band and providing belt-and-suspenders ACL hygiene if a future
    Tauri version inverts grant semantics.

    No tauri-plugin-fs version bump required — 2.4.5 (already in Cargo.toml) supports all four
    flat identifiers AND the structured `fs:scope` object form per plugins-workspace v2
    autogenerated reference.

    No changes to `tauri.conf.json`. `withGlobalTauri=false` is the correct Tauri v2 default —
    `window.__TAURI__.core` being undefined in devtools is a red herring; ES module imports
    of `@tauri-apps/*` use the IPC bridge regardless. (The durable record of this red-herring
    rationale lives in `autoRecover.ts` per Task 2, not here.)

    After editing, validate JSON with `python3 -m json.tool gui/src-tauri/capabilities/default.json &gt; /dev/null`
    (or `jq . gui/src-tauri/capabilities/default.json &gt; /dev/null` if jq is available).

    Commit:
    ```
    git add gui/src-tauri/capabilities/default.json
    git commit -m "fix(65-09): grant appdata fs ACL for AutoRecover + defense-in-depth scope

    Tauri v2 fs plugin rejects every autoRecover.ts call because the
    capability grants only fs:scope-home-recursive (a READ scope on the
    wrong base). $APPDATA is a separate base and requires its own scope
    plus write/remove/read-dir grants.

    Adds four flat permissions (broad functional fix) PLUS a structured
    fs:scope entry narrowed to \$APPDATA/STREAM-Composer/autorecover/**
    (defense-in-depth, documents intent in-band).

    Closes UAT 16/17 root cause and the explicit defense-in-depth
    gap item (.planning/debug/autorecover-bridge.md).

    Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
    ```
  </action>
  <verify>
    <automated>
      # JSON validates
      python3 -m json.tool gui/src-tauri/capabilities/default.json &gt; /dev/null
      # All four new flat permission identifiers are present (each exactly once)
      test "$(grep -c 'fs:scope-appdata-recursive' gui/src-tauri/capabilities/default.json)" = 1
      test "$(grep -c 'fs:allow-appdata-write-recursive' gui/src-tauri/capabilities/default.json)" = 1
      test "$(grep -c 'fs:allow-remove' gui/src-tauri/capabilities/default.json)" = 1
      test "$(grep -c 'fs:allow-read-dir' gui/src-tauri/capabilities/default.json)" = 1
      # Structured fs:scope entry with autorecover/** glob is present (defense-in-depth gap closure)
      python3 -c "import json; d = json.load(open('gui/src-tauri/capabilities/default.json')); structured = [p for p in d['permissions'] if isinstance(p, dict) and p.get('identifier') == 'fs:scope']; assert len(structured) == 1, f'expected 1 structured fs:scope entry, got {len(structured)}'; allow = structured[0].get('allow', []); paths = [a.get('path') for a in allow]; assert '\$APPDATA/STREAM-Composer/autorecover/**' in paths, f'expected autorecover/** path in allow, got {paths}'; print('structured fs:scope OK')"
      # Existing permissions still present (regression guard)
      grep -q 'fs:scope-home-recursive' gui/src-tauri/capabilities/default.json
      grep -q 'core:window:allow-set-title' gui/src-tauri/capabilities/default.json
    </automated>
  </verify>
  <done>
    capabilities/default.json contains the four new flat fs permissions AND the structured
    fs:scope entry narrowed to $APPDATA/STREAM-Composer/autorecover/**; JSON parses;
    no existing permissions removed; commit recorded.
  </done>
</task>

<task type="auto">
  <name>Task 2: DEV-mode logging + v2 IPC rationale comment on autoRecover</name>
  <files>gui/src/lib/autoRecover.ts</files>
  <action>
    Two changes to `gui/src/lib/autoRecover.ts`:

    (A) Replace the seven bare `} catch {` blocks with a parameterized catch that logs under
        DEV mode (existing requirement, unchanged from previous revision).
    (B) Add a NEW inline code comment near the first `await import('@tauri-apps/api/core')`
        site explaining why the ES-module import is the v2-correct invocation path and why
        `window.__TAURI__` is intentionally undefined. This closes the UAT gap item:
        "Fix smoke-test guidance — replace window.__TAURI__.core.invoke(...) with
        `(await import('@tauri-apps/api/core')).invoke(...)`" durably in source rather than
        only in prose.

    === Change (A): DEV-mode logging on silent-catch blocks ===

    Lines to edit (each currently contains a comment line + closing brace):

    - L121-L123 (writeSidecar)
    - L137-L139 (readSidecar — keep `return null` after warn)
    - L150-L152 (clearSidecar)
    - L170-L172 (enumerateSidecars — keep `return []` after warn)
    - L197-L199 (writeLockfile)
    - L213-L216 (readLockfile — keep `return null` after warn)
    - L228-L230 (clearLockfile)

    Also update L293-L295 (`isPidAlive`) for consistency — but keep its `return false` behavior.

    New shape for each block (writeSidecar example):

      } catch (err) {
        if (import.meta.env.DEV) {
          console.warn("[autoRecover] writeSidecar failed:", err);
        }
      }

    Use the function name (`writeSidecar`, `readSidecar`, `clearSidecar`,
    `enumerateSidecars`, `writeLockfile`, `readLockfile`, `clearLockfile`,
    `isPidAlive`) in the warn message so multiple failures can be distinguished
    in the console.

    For blocks that have a fallthrough return value (readSidecar, enumerateSidecars,
    readLockfile, isPidAlive) — keep the existing return after the warn block.

    Replace the existing `// Silent failure ...` comment in each block with a
    one-line comment: `// Silent failure to caller; logged under DEV.` (keeps the
    semantic that callers never see the error).

    Reference: `.planning/debug/autorecover-bridge.md` Resolution — the silent-failure pattern
    was the load-bearing reason the ACL rejections never surfaced. With logging in place,
    future fs ACL gaps will be visible in devtools without changing user-facing behavior
    (`vite-plugin-react` / `vite` builds strip `import.meta.env.DEV` branches in production).

    No new imports needed — `import.meta.env.DEV` is a Vite-injected global, and `console.warn`
    is universal. Do NOT replace `try/catch` with `try/catch/finally` — the catch-only pattern
    is correct here.

    === Change (B): Inline v2 IPC rationale comment ===

    Locate the FIRST occurrence of `await import('@tauri-apps/api/core')` in autoRecover.ts
    (use `grep -n "@tauri-apps/api/core" gui/src/lib/autoRecover.ts | head -1` — expected to
    be inside the `isPidAlive` helper around L289). Immediately ABOVE that line, insert this
    JSDoc-style comment block:

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

    This comment lives next to the surprising code (rather than only in a UAT file that may be
    archived) so future debuggers reading the IPC site immediately understand the v2 contract.

    Also locate `gui/src/App.tsx` line where `get_pid` is invoked (if any — `grep -n "get_pid"
    gui/src/App.tsx`). If `App.tsx` ALSO calls `invoke('get_pid')` or uses
    `await import('@tauri-apps/api/core')`, add a SHORT one-line comment immediately above
    that call:

      // v2 IPC: use ES-module import, not window.__TAURI__ (which is intentionally undefined). See autoRecover.ts header for the long-form rationale.

    If `App.tsx` does NOT call `get_pid` or the core API directly (currently only autoRecover.ts
    does), skip the App.tsx edit — the autoRecover.ts header comment is sufficient.

    === Verification before commit ===

    Verify locally before commit:
      cd gui &amp;&amp; npx tsc --noEmit 2&gt;&amp;1 | grep -E "autoRecover\.ts|App\.tsx" | grep -v "^$"
        # should produce zero lines (no new tsc errors)

    Commit:
    ```
    git add gui/src/lib/autoRecover.ts gui/src/App.tsx
    git commit -m "feat(65-09): DEV-mode logging + v2 IPC rationale comment on autoRecover

    Replace bare \`catch {}\` with \`catch (err) { if (import.meta.env.DEV)
    console.warn(...); }\` on writeSidecar, readSidecar, clearSidecar,
    enumerateSidecars, writeLockfile, readLockfile, clearLockfile,
    isPidAlive. User-facing behavior unchanged; failures now surface in
    devtools.

    Plus inline header comment near the first \`@tauri-apps/api/core\` import
    site documenting why ES-module imports (not window.__TAURI__) are the
    v2-correct invocation path — closes the UAT gap item that prior plan
    revisions only addressed in prose. Future debuggers reading the IPC
    call site no longer re-derive the window.__TAURI__ red herring from
    scratch.

    Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
    ```

    (Adjust `git add` to omit `gui/src/App.tsx` if no edit was made there per the conditional above.)
  </action>
  <verify>
    <automated>
      # Eight `catch (err)` blocks exist with DEV-mode logging
      test "$(grep -c "catch (err)" gui/src/lib/autoRecover.ts)" = 8
      test "$(grep -c "import.meta.env.DEV" gui/src/lib/autoRecover.ts)" = 8
      test "$(grep -c '\[autoRecover\]' gui/src/lib/autoRecover.ts)" = 8
      # No remaining bare `} catch {` blocks
      test "$(grep -c '} catch {' gui/src/lib/autoRecover.ts)" = 0
      # v2 IPC rationale comment present (durable closure of the smoke-test-guidance UAT gap)
      grep -q 'Tauri v2 IPC invocation note' gui/src/lib/autoRecover.ts
      grep -q 'withGlobalTauri' gui/src/lib/autoRecover.ts
      grep -q 'window.__TAURI__' gui/src/lib/autoRecover.ts
      # Existing 22 vitest cases still pass (mocks Tauri IPC; DEV logging + comment are innocuous)
      cd gui &amp;&amp; npx vitest run src/lib/__tests__/autoRecover.test.ts
    </automated>
  </verify>
  <done>
    autoRecover.ts has eight DEV-logging catch blocks, zero bare catch-blocks, the v2 IPC
    rationale comment block present near the first core-API import site, and vitest passes.
  </done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 3: Manual UAT — Tests 16 + 17 re-run</name>
  <files>(no code change — manual UAT against the live Tauri dev shell)</files>
  <action>
    Capability ACL grants AutoRecover the appdata fs scope it needs. With the static ACL fixed,
    the substrate from Plan 07 and the modal from Plan 08 should produce the observable
    behavior promised by Tests 16 and 17. This step verifies end-to-end on a real Tauri
    dev process (vitest mocks IPC and cannot prove this).

    **How to verify:**

    1. In one terminal, run `cd gui &amp;&amp; npm run tauri dev`. Wait for the workspace to load
       (welcome overlay visible or a project is auto-loaded).

    2. **Test 16 — sidecar writer**. Drop any node from the toolbox onto the canvas (e.g., a Pump).
       Wait ~3 seconds (the debounce window is 2s + filesystem flush). Then in a separate
       terminal:
       ```
       ls -la ~/.local/share/com.stream.composer/STREAM-Composer/autorecover/
       ```
       Expected: at minimum one `*.scp.autosave` file AND one `running.lock` file, both with
       current timestamps. For an untitled project the autosave filename will be
       `untitled-&lt;uuid&gt;.scp.autosave`.

       Sanity-print the sidecar JSON:
       ```
       cat ~/.local/share/com.stream.composer/STREAM-Composer/autorecover/untitled-*.scp.autosave | head -40
       ```
       Expected: a JSON `.scp` envelope (`format_version`, `stream_version`, `nodes`, ...) — the
       same shape Save would write.

    3. Open devtools in the Tauri webview (right-click → Inspect Element, or
       `tauri::WebviewWindow::open_devtools` if configured). Confirm there are NO
       `[autoRecover] ... failed:` console.warn messages. If there are, paste them in your
       resume signal and **mark the checkpoint as needing rework**.

       **IMPORTANT — devtools IPC sanity check:** if you want to exercise the IPC bridge from
       the devtools console (e.g. to confirm `get_pid` works), use the v2-correct invocation:
       ```js
       (await import('@tauri-apps/api/core')).invoke('get_pid')
       ```
       NOT `window.__TAURI__.core.invoke('get_pid')` — that throws "Cannot read properties of
       undefined" by Tauri v2 design (see the header comment in `autoRecover.ts`).

    4. **Test 17 — crash modal**. Identify the Tauri shell PID:
       ```
       pgrep -fa "target/debug/gui" | head -3
       ```
       (Pick the actual `gui` binary line — not `npm`, not `cargo`, not `node`.)

       Force-kill it: `kill -9 &lt;pid&gt;`.

       Relaunch with `npm run tauri dev` (it should still be in the `gui/` cwd from step 1).
       Wait for the boot.

       Expected: a blocking modal appears BEFORE the workspace, body reads
       "Recover unsaved work from &lt;timestamp&gt; in &lt;Untitled or filename&gt;?", with
       [Recover] and [Discard] buttons. The canvas does NOT appear behind the modal.

    5. Click **Recover**. The unsaved node added in step 2 should appear on the canvas;
       the window title should show a `*` dirty marker. (Save As is required because
       `currentFilePath` stays null per D-04.)

    6. Repeat steps 2–4 with one variation: in step 5, click **Discard** instead. Confirm:
       ```
       ls ~/.local/share/com.stream.composer/STREAM-Composer/autorecover/
       ```
       returns empty (Discard clears all sidecars + lockfile). Relaunch — no modal appears.

    7. **Smoke for the DEV logging**: in devtools console, temporarily revoke fs by renaming
       the autorecover directory while the app runs:
       ```
       mv ~/.local/share/com.stream.composer/STREAM-Composer/autorecover \
          ~/.local/share/com.stream.composer/STREAM-Composer/autorecover.disabled
       ```
       Edit something in the app. Within ~3s, devtools console should show a
       `[autoRecover] writeSidecar failed:` or `[autoRecover] mkdir failed:` warning. Restore:
       ```
       mv ~/.local/share/com.stream.composer/STREAM-Composer/autorecover.disabled \
          ~/.local/share/com.stream.composer/STREAM-Composer/autorecover
       ```

    If all 7 steps behave as described — checkpoint approved.

    If step 2 still shows no sidecar files: capture the full devtools console output and
    the `tauri dev` terminal output, then mark the checkpoint as needing rework — the
    diagnosis missed something and Plan 09 must be revised.
  </action>
  <verify>
    <human-check>Human runs the 7-step sequence above on a live Tauri dev shell.</human-check>
  </verify>
  <done>User types "approved" indicating all 7 steps passed.</done>
  <resume-signal>
    Type "approved" if Tests 16 + 17 + DEV logging smoke all pass.
    If anything fails: paste devtools console output + `ls` output + which step failed.
  </resume-signal>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| webview → Tauri fs plugin | autoRecover.ts calls cross the IPC bridge into native fs; subject to capability ACL. |
| webview → Tauri core (invoke) | isPidAlive calls `is_pid_alive` on the Rust side. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-65-09a | Elevation of Privilege | gui/src-tauri/capabilities/default.json | accept | New flat permissions grant ONLY $APPDATA scope (not $HOME write, not arbitrary path). $APPDATA is the per-app data dir Tauri reserves for the bundle. Additionally, a structured `fs:scope` entry narrows declared intent to `$APPDATA/STREAM-Composer/autorecover/**` — documenting in-band that this is the only path AutoRecover legitimately needs. No widened blast radius beyond what AutoRecover already needs by design (T-65-09 was already accepted in Plan 07). |
| T-65-09b | Information Disclosure | autoRecover.ts catch blocks | accept | DEV-mode console.warn only logs error objects to the dev devtools console; production builds strip the branch via Vite. No PII; error strings are Tauri ACL diagnostic text. |
| T-65-09c | Tampering | capabilities/default.json | mitigate | JSON schema validation via $schema reference at line 2 (Tauri-autogenerated desktop-schema.json) catches malformed permission identifiers AND malformed structured `fs:scope` objects at build time. |
</threat_model>

<verification>
- JSON parses: `python3 -m json.tool gui/src-tauri/capabilities/default.json &gt; /dev/null`
- All 4 new flat permissions present: `for p in fs:scope-appdata-recursive fs:allow-appdata-write-recursive fs:allow-remove fs:allow-read-dir; do grep -q "$p" gui/src-tauri/capabilities/default.json || echo "MISSING: $p"; done` produces no output.
- Structured fs:scope entry present and narrowed to autorecover/**: `python3 -c "import json; d = json.load(open('gui/src-tauri/capabilities/default.json')); s = [p for p in d['permissions'] if isinstance(p, dict) and p.get('identifier') == 'fs:scope']; assert len(s) == 1 and '\$APPDATA/STREAM-Composer/autorecover/**' in [a['path'] for a in s[0]['allow']]"` exits 0.
- autoRecover.ts has 8 DEV-logging catch blocks: `test "$(grep -c "catch (err)" gui/src/lib/autoRecover.ts)" = 8`.
- No bare catch remains: `test "$(grep -c '} catch {' gui/src/lib/autoRecover.ts)" = 0`.
- v2 IPC rationale comment present: `grep -q 'Tauri v2 IPC invocation note' gui/src/lib/autoRecover.ts`.
- Existing 22 autoRecover vitest cases pass: `cd gui &amp;&amp; npx vitest run src/lib/__tests__/autoRecover.test.ts`.
- Manual UAT (Task 3) confirms sidecar appears on edit; modal appears after kill -9 + relaunch.
</verification>

<success_criteria>
- `gui/src-tauri/capabilities/default.json` contains the four new flat fs permission identifiers AND one structured `fs:scope` entry narrowed to `$APPDATA/STREAM-Composer/autorecover/**`; JSON is valid; no existing permissions removed.
- `gui/src/lib/autoRecover.ts` contains exactly 8 `catch (err)` blocks each gated by `import.meta.env.DEV`, each tagged with `[autoRecover] &lt;op&gt; failed:` and the operation name; no bare `} catch {` blocks remain; the "Tauri v2 IPC invocation note" comment block is present near the first `@tauri-apps/api/core` import site.
- All existing autoRecover vitest cases (22 in `autoRecover.test.ts`, 5 in `autoRecover.actions.test.ts`, 8 in `AutoRecoverRestoreModal.test.tsx`) still pass.
- Task 3 checkpoint approved: UAT Tests 16 + 17 + the DEV logging smoke all pass on the running Tauri dev shell.
</success_criteria>

<output>
Create `.planning/phases/65-interaction-model-overhaul/65-09-SUMMARY.md` when done.
</output>
