---
phase: 61-registry-audit-rewrite-for-v1-1
plan: 04
subsystem: gui/registry
tags: [gui, registry, audit, unchanged-components, drift-cleanup]
dependency-graph:
  requires:
    - .planning/phases/61-registry-audit-rewrite-for-v1-1/61-01-SUMMARY.md
    - .planning/phases/61-registry-audit-rewrite-for-v1-1/61-02-SUMMARY.md
    - .planning/phases/61-registry-audit-rewrite-for-v1-1/61-03-SUMMARY.md
    - src/components/pump.jl
    - src/components/flapper.jl
    - src/components/resistors.jl
    - src/components/misc.jl
  provides:
    - "Re-audited unchanged-component entries in gui/src/registry/components.json (Pump, Flapper, Friction, Gravity, Resistor, Inertia, HeatExchanger, ConstantTemperature)"
    - "Confirmation that the legacy `array: true` / `arrayParam: <name>` port-key shape has been globally eliminated from components.json"
  affects:
    - "Plan 61-05 (test updates can lock in the audited surface)"
tech-stack:
  added: []
  patterns:
    - "Per-component kwarg-by-kwarg diff against src/components/*.jl constructor signature"
    - "Silent drift cleanup: remove registry kwargs that do not exist in src"
key-files:
  created:
    - .planning/phases/61-registry-audit-rewrite-for-v1-1/61-04-SUMMARY.md
  modified:
    - gui/src/registry/components.json (Flapper entry only)
decisions:
  - "Pump callable mode (Pump(dP_pump::Any; name)) intentionally NOT exposed in registry. Plan explicitly preserves the two GUI-accessible modes (fixed-dP, fixed-mdot) per Phase 22; the callable mode is a Julia-side caller convenience for transient dP_pump(t) parameter wiring and is not selectable from the toolbox."
  - "Flapper threshold removed from parameters[] — it is a flapper_callback() kwarg, not a Flapper constructor kwarg. The misnamed registry entry would have generated `Flapper(; ..., threshold=0.01, ...)` which Julia rejects (LoadError: UndefKeywordError or MethodError: no method matching Flapper)."
  - "Flapper use_callback removed — does not exist anywhere in src/. Likely vestige of an earlier API draft."
  - "Inertia/HeatExchanger/ConstantTemperature audited with zero drift. Documented per plan's 'zero drift is a valid outcome' rule."
  - "Global legacy-port-key sweep found 0 offenders — Plans 02/03 already eliminated all `array: true` / `arrayParam` keys from JSON during their rewrites. The TypeScript Port interface still admits both keys as optional (future cleanup phase will tighten the type)."
metrics:
  duration: "~8m"
  completed: 2026-05-12
  tasks_completed: 2
  files_changed: 1
  files_created: 1
---

# Phase 61 Plan 04: Unchanged-component drift audit — Summary

**One-liner:** Audited 8 unchanged registry components against their current Julia constructors; only Flapper carried drift (two misplaced kwargs removed) — the other 7 are clean and the global legacy port-key sweep returns zero offenders.

## Audit Results

For each of the 8 audited components, the table below lists (a) the canonical src constructor signature, (b) the registry parameters[] surface before this plan, and (c) the action taken.

### 1. Pump (`src/components/pump.jl`)

**Src signatures (three methods):**
- `Pump(dP_pump::Real; name)` — scalar fixed-dP mode
- `Pump(dP_pump::Any; name)` — callable fixed-dP mode (transient `dP_pump(t)`)
- `Pump(; name, mdot0)` — fixed-mdot mode

**Registry parameters[]:** `dP_pump` (Real, Pa, positional, required), `mdot0` (Real, kg/s, kwarg, required)
**Registry constructorModes (2):** `fixed-dP` → `Pump(dP_pump::Real; name)`; `fixed-mdot` → `Pump(; name, mdot0)`

**Action:** **No drift.** The callable mode is intentionally not GUI-exposed per the plan's instruction ("Pump's two modes (`fixed-dP`, `fixed-mdot`) per Phase 22 are still present in src; preserve them"). The callable variant is a Julia-side convenience for transient pump profiles wired via `op` dict — not a toolbox-selectable mode.

### 2. Flapper (`src/components/flapper.jl`)

**Src signature:** `Flapper(; name, dt=5.0, R_closed=1e8, R_open=100.0)`

**Registry parameters[] before:** `dt`, `threshold`, `R_closed`, `R_open`, `use_callback` (5 entries)
**Registry parameters[] after:** `dt`, `R_closed`, `R_open` (3 entries)

**Drift found and fixed:**
- ❌ `threshold` — NOT a `Flapper` constructor kwarg; it is a `flapper_callback(ssys, sym; threshold=0.01)` kwarg. **Removed** from parameters[] and the constructorModes[0].parameters array.
- ❌ `use_callback` — does NOT exist anywhere in `src/components/flapper.jl`. Likely a vestige of an earlier API draft. **Removed**.
- `constructorModes[0].signature` updated from `Flapper(; name, dt=5.0, threshold=0.01, R_closed=1e8, R_open=100.0, use_callback=true)` to `Flapper(; name, dt=5.0, R_closed=1e8, R_open=100.0)`.

**Commit:** `aa03d75` — `fix(61-04): drop misplaced Flapper kwargs threshold and use_callback`

### 3. Friction (`src/components/resistors.jl`)

**Src signature:** `Friction(; name, L, D, A)`
**Registry parameters[]:** `L` (m), `D` (m), `A` (m^2) — all kwarg, required.
**Action:** **No drift.** Name match, unit strings match docstring units, default values absent on both sides.

### 4. Gravity (`src/components/resistors.jl`)

**Src signature:** `Gravity(H; name)` — positional `H` [m]
**Registry parameters[]:** `H` (Real, m, positional, required)
**Registry constructorModes:** single mode `Gravity(H; name)`
**Action:** **No drift.**

### 5. Resistor (`src/components/resistors.jl`)

**Src signature:** `Resistor(R; name)` — positional `R` [Pa/(kg/s)]
**Registry parameters[]:** `R` (Real, "Pa/(kg/s)", positional, required)
**Action:** **No drift.** Unit `Pa/(kg/s)` matches docstring.

### 6. Inertia (`src/components/misc.jl`)

**Src signature:** `Inertia(L_over_A; name)` — positional `L_over_A` [1/m]
**Registry parameters[]:** `L_over_A` (Real, "1/m", positional, required)
**Action:** **No drift.**

### 7. HeatExchanger (`src/components/misc.jl`)

**Src signature:** `HeatExchanger(T_bc; name)` — positional `T_bc` [K]
**Registry parameters[]:** `T_bc` (Real, K, positional, required)
**Action:** **No drift.**

### 8. ConstantTemperature (`src/components/misc.jl`)

**Src signature:** `ConstantTemperature(T; name)` — positional `T` [K]
**Registry parameters[]:** `T` (Real, K, positional, required)
**Registry category:** `"Thermal"` (legacy invariant preserved per registry.test.ts:150-152)
**Action:** **No drift.** Note: the in-component parameter is renamed `T_bc = T` for symbolic clarity (`@parameters T_bc = T`), but the exposed constructor kwarg is `T` — registry correctly mirrors the kwarg name, not the internal parameter name.

## Global Legacy Port-Key Sweep

**Procedure:** iterated every component's `ports[]` looking for ports with `array === true` or any key named `arrayParam`.

**Result:** **0 offenders.**

Plans 61-02 (channel-family rewrite) and 61-03 (4 new components added) already used the v1.1 `array_size` / `default_axis` shape exclusively. The legacy keys never re-entered the JSON. Recorded as the plan instructed: "no legacy port keys found outside Plan 02's rewrites."

The TypeScript `Port` interface in `gui/src/registry/types.ts` still declares `array?: boolean` and `arrayParam?: string` as optional — that interface tightening (removing the legacy fields entirely) is explicitly deferred per Plan 04's scope statement: "Do NOT remove the legacy `array`/`arrayParam` fields from the TypeScript Port interface in types.ts — that is a future cleanup phase's concern."

## Verification

| Check | Result |
|-------|--------|
| `node -e '...c.components.length'` returns `16` | 16 |
| `Pump.constructorModes.length === 2` | true (`fixed-dP`, `fixed-mdot` preserved) |
| `ConstantTemperature.category === "Thermal"` | true (invariant preserved) |
| Legacy port-key sweep offender count | 0 |
| All 8 audited entries still present | true |
| `npm run build` error count | 7 (baseline unchanged — same 7 pre-existing tsc errors documented in deferred-items.md; **no new errors introduced**) |
| `npm test -- src/registry/__tests__/registry.test.ts --run` | 14/14 passing |
| Full `npm test --run` | 232 passing, 17 todo (baseline preserved) |

## Deviations from Plan

None — plan executed exactly as written. The Flapper drift was the single concrete fix; the rest of the audit confirms cleanliness (a valid outcome per the plan).

### Auth gates

None.

## Threat Flags

None — this plan modifies only registry metadata for components whose Julia surface is unchanged. No new network endpoints, auth paths, file-access patterns, or trust-boundary surface introduced.

## Self-Check: PASSED

- gui/src/registry/components.json modified — diff confirmed via `git show aa03d75 --stat` (1 file, 2 insertions, 19 deletions).
- Commit `aa03d75` present in `git log --oneline`.
- Flapper entry confirmed via `node -e` — 3 parameters (dt, R_closed, R_open), single constructorModes signature `Flapper(; name, dt=5.0, R_closed=1e8, R_open=100.0)`.
- Inertia/HeatExchanger/ConstantTemperature entries cross-checked against `src/components/misc.jl` constructors — exact match.
- Legacy port-key sweep returns 0 — confirmed via node iteration over all 16 components' ports.
- `.components | length === 16` confirmed.
- `ConstantTemperature.category === "Thermal"` confirmed.

## Known Stubs

None.
