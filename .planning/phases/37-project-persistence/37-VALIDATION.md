---
phase: 37
slug: project-persistence
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-02
---

# Phase 37 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | vitest (gui/package.json) + Tauri manual smoke tests |
| **Config file** | `gui/vite.config.ts` |
| **Quick run command** | `cd gui && npm run test -- --run` |
| **Full suite command** | `cd gui && npm run test -- --run --reporter=verbose` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd gui && npm run test -- --run`
- **After every plan wave:** Run `cd gui && npm run test -- --run --reporter=verbose`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 20 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 37-01-01 | 01 | 1 | PERS-01 | unit | `cd gui && npm run test -- --run src/store/useStore.test.ts` | ❌ W0 | ⬜ pending |
| 37-01-02 | 01 | 1 | PERS-01 | unit | `cd gui && npm run test -- --run src/store/useStore.test.ts` | ❌ W0 | ⬜ pending |
| 37-02-01 | 02 | 2 | PERS-01 | unit | `cd gui && npm run test -- --run src/store/useStore.test.ts` | ❌ W0 | ⬜ pending |
| 37-02-02 | 02 | 2 | PERS-02 | manual | see Manual-Only | — | ⬜ pending |
| 37-03-01 | 03 | 2 | PERS-03 | unit | `cd gui && npm run test -- --run src/store/useStore.test.ts` | ❌ W0 | ⬜ pending |
| 37-03-02 | 03 | 2 | PERS-04 | manual | see Manual-Only | — | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `gui/src/store/useStore.test.ts` — unit stubs for isDirty, currentFilePath, recentFiles state fields and newProject/loadProject actions (PERS-01, PERS-03)
- [ ] Vitest already installed — no framework install needed

*Existing vitest infrastructure covers automated parts; Wave 0 adds store test file only.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Native file open/save dialog appears | PERS-01 | Requires real Tauri runtime — cannot mock OS file picker in vitest | Run `cargo tauri dev`, click File > Open, verify native dialog appears; click Save As, verify dialog appears |
| Unsaved-changes dialog on window close | PERS-02 | Requires real Tauri window close event (`onCloseRequested`) | Run `cargo tauri dev`, add a node, click window X — verify "Save changes?" dialog with Save/Don't Save/Cancel |
| Recent Projects list updates and persists | PERS-04 | Requires Tauri `appDataDir()` and real FS writes | Save a project, close and reopen app — verify recent file appears in welcome overlay |
| Window title reflects dirty state | PERS-02 | Requires Tauri `getCurrentWindow().setTitle()` | Run `cargo tauri dev`, add a node — verify title shows asterisk; save — verify asterisk disappears |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 20s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
