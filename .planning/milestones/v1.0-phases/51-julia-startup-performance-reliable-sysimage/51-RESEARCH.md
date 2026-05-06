# Phase 51: Julia Startup Performance & Reliable Sysimage - Research

**Researched:** 2026-04-10
**Domain:** Julia PackageCompiler.jl / TTFX reduction / WSL2 memory management
**Confidence:** HIGH

## Summary

This phase has exactly four file-level changes: (1) add warmup code to `test/precompile_exec.jl`,
(2) prepend a memory pre-flight check to `build_sysimage.sh`, (3) remove a dead import from
`test/test_resistors.jl`, and (4) update the sysimage section of `CLAUDE.md`. The infrastructure
is already correct — `build_sysimage.sh`, `build_sysimage.jl`, `check_sysimage_ready.sh`, and
`test/precompile_exec.jl` all exist with the right structure. The gap is that
`test/precompile_exec.jl` contains only `using` imports and no actual compilation-triggering code,
so no expensive MTK methods are baked into the sysimage.

The WSL2 crash mode is OOM during the PackageCompiler link step, not during package loading. The
existing `--heap-size-hint=4G --threads=1` flags reduce the risk, and `check_sysimage_ready.sh`
already validates memory and runs a QuadGK smoke test. The missing piece is a hard pre-flight gate
in `build_sysimage.sh` itself that aborts before starting a 15-minute build when RAM is too low.

The current machine has 15.9 GB total / 14.7 GB available RAM [VERIFIED: /proc/meminfo]. This is
sufficient. The hard gate threshold of 6 GB free is a reasonable conservative default.

**Primary recommendation:** Three small code changes + one doc update, all in files that already
exist. No new infrastructure needed. Run `check_sysimage_ready.sh` before `build_sysimage.sh` to
confirm the environment, then run the build in a separate terminal per D-07.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Add real STREAM code to `test/precompile_exec.jl` — at minimum call `mtkcompile` on a
  small minimal system (e.g. Pump + Channel, 2 nodes). This bakes the expensive symbolic IR
  compilation path into the sysimage so the first `mtkcompile` in a real session is fast.
- **D-02:** Keep warmup inputs small/cheap (minimal topology, not `build_loop` + solve) to avoid
  adding memory pressure during the build. Goal: bake method dispatch, not run a full simulation.
- **D-03:** Add a pre-flight memory check to `build_sysimage.sh` before the `exec julia` call. If
  free RAM is below a safe threshold (6 GB), print a clear error with `.wslconfig` instructions
  and exit 1.
- **D-04:** Document the WSL2 `.wslconfig` memory fix in CLAUDE.md: PowerShell RAM check,
  `memory=` setting, `wsl --shutdown` restart, recommended 65% of physical RAM.
- **D-05:** Sysimage package list is correct as-is: `STREAM, ModelingToolkit, OrdinaryDiffEq,
  Symbolics, QuadGK, Sundials`. No additions needed.
- **D-06:** `NonlinearSolve` is a dead import in `test/test_resistors.jl` — remove it. It is a
  test-only dep (`[extras]`, not `[deps]`) and was never in the runtime dependency tree.
- **D-07:** Phase NOT complete until `./build_sysimage.sh` actually produces `stream.so`. Hard gate.
- **D-08:** Timing script: `time_startup.jl` (or shell snippet) measuring wall time for
  `using STREAM`, first `mtkcompile`, first `solve_steady` — with and without `stream.so`. Run
  and record numbers. Phase not done until improvement is confirmed.
- **D-09:** Full test suite must pass with sysimage:
  `julia --sysimage stream.so --project=. test/runtests.jl`.

### Claude's Discretion

- Exact memory threshold for pre-flight check (reasonable default: 6 GB free)
- Specific Julia code in `precompile_exec.jl` (small Pump+Channel system is sufficient)
- Whether to use `free -m` or `/proc/meminfo` for the RAM check in bash

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TTFX-01 | Reduce `using STREAM` + first `mtkcompile` from ~90s to ~5s with sysimage | Warmup code in precompile_exec.jl bakes MTK dispatch into stream.so |
| TTFX-02 | Sysimage build must complete without OOM crash on WSL2 | Pre-flight memory gate + existing heap-size-hint flags |
| TTFX-03 | Measure and record baseline vs. sysimage TTFX numbers | time_startup.jl timing script |
| TTFX-04 | Full test suite passes with sysimage | julia --sysimage stream.so test/runtests.jl |
| TTFX-05 | Dead NonlinearSolve import removed from test_resistors.jl | Verified: grep finds no usage in test/ |
| TTFX-06 | CLAUDE.md updated with WSL2 .wslconfig memory docs | Doc update to Performance section |
</phase_requirements>

---

## Standard Stack

### Core Tools

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| PackageCompiler.jl | ~2.1 (in Manifest [ASSUMED]) | Build `stream.so` sysimage | Only Julia tool for native sysimage creation |
| PrecompileTools.jl | bundled with Julia 1.10+ | Annotate precompile workloads inside packages | Standard complement to PackageCompiler |

**Note:** PackageCompiler is listed as `[extras]` in `Project.toml`, not `[deps]`. It is only
needed for the build step, not at runtime. [VERIFIED: Project.toml line 27]

**Julia version on this machine:** 1.12.5 [VERIFIED: julia --version]

### Existing Infrastructure (all present, no installation needed)

| File | Status | Purpose |
|------|--------|---------|
| `build_sysimage.sh` | Complete, needs pre-flight check prepended | WSL2-safe wrapper |
| `build_sysimage.jl` | Complete, no changes needed | PackageCompiler invocation |
| `test/precompile_exec.jl` | Needs warmup code added | PackageCompiler precompile_execution_file hook |
| `check_sysimage_ready.sh` | Complete, no changes needed | Pre-flight validator (already validates RAM at 4500 MB) |

**Installation:** No new packages needed. [VERIFIED: all files exist in repo root and test/]

---

## Architecture Patterns

### PackageCompiler Precompile Execution File Pattern

The `precompile_execution_file` parameter in `create_sysimage` runs a Julia script during the
sysimage build. Julia records every method that gets compiled during that execution and bakes
those native code objects into the `.so`. On next startup with `--sysimage stream.so`, those
methods are already compiled — no JIT overhead on first call. [CITED: PackageCompiler.jl docs]

**What to bake:**
- `mtkcompile(sys)` — the dominant TTFX contributor. MTK's structural analysis + tearing +
  Jacobian sparsity detection triggers hundreds of method compilations in Symbolics/MTK internals.
- `@named` macro expansion — triggers component constructor dispatch
- `solve_steady` or a minimal `ODEProblem` + `solve` — bakes OrdinaryDiffEq/Sundials dispatch

**What NOT to bake (D-02):**
- Large systems (n=10+ cells) — memory spike during build
- `build_loop` full solve — unnecessary, method signatures are identical across system sizes

### Minimal Warmup System Pattern

```julia
# Source: PackageCompiler.jl precompile_execution_file contract [ASSUMED pattern]
# Trigger: bake mtkcompile + @named dispatch for Pump and Channel
using STREAM
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq
using Sundials
using Symbolics
using QuadGK

# ── Warmup: minimal Pump + Channel system ─────────────────────────
# n=2 is the smallest valid Channel (1 would be degenerate).
# This topology matches the real build_loop minus the HeatExchanger.
# Goal: trigger mtkcompile method dispatch, not produce a valid solution.
@named pump = Pump(3.0e4)
geo = PipeGeometry_circular(0.01)
@named ch = Channel(; n=2, geometry=geo)

eqs = [
    connect(pump.outlet, ch.inlet),
    connect(ch.outlet, pump.inlet),
    ch.thermal.T ~ 373.15,
    pump.inlet.P ~ 1.0e5,
]
@named sys = System(eqs, t, [], []; systems=[pump, ch])
ssys = mtkcompile(sys)
```

**Why this is sufficient:** `mtkcompile` on any topology triggers the same MTK internal methods
(tearing, index reduction, code generation). The exact number of unknowns affects compile time
linearly but the method signatures are the same at n=2 as at n=10. [ASSUMED]

### Pre-flight Memory Check Pattern for bash

```bash
# Use /proc/meminfo for portability (works on all Linux including WSL2)
# free -m is also fine — both are available on WSL2 [VERIFIED: free -m present on this machine]

FREE_MB=$(awk '/^MemAvailable:/{print int($2/1024)}' /proc/meminfo)
THRESHOLD_MB=6144  # 6 GB — conservative for PackageCompiler + MTK + Sundials

if [ "$FREE_MB" -lt "$THRESHOLD_MB" ]; then
    echo "ERROR: Only ${FREE_MB} MB free (need >= ${THRESHOLD_MB} MB)"
    echo ""
    echo "To increase WSL2 memory:"
    echo "  1. Check Windows RAM (PowerShell): (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB"
    echo "  2. Edit %USERPROFILE%\\.wslconfig:"
    echo "       [wsl2]"
    echo "       memory=10GB   # ~65% of 16 GB physical RAM"
    echo "  3. Restart WSL: wsl --shutdown (then reopen terminal)"
    exit 1
fi
```

**Why /proc/meminfo over free -m:** `/proc/meminfo` is always available; `MemAvailable` is more
accurate than `free -m`'s "available" column on some WSL2 kernel versions. [ASSUMED — both work]

### WSL2 .wslconfig Memory Setting (D-04 documentation content)

```ini
# %USERPROFILE%\.wslconfig
[wsl2]
memory=10GB      # ~65% of 16 GB physical RAM
                 # WSL2 default: 50% of physical RAM (may be too low for sysimage build)
swap=4GB         # optional — extra safety net
```

PowerShell one-liner to check Windows RAM:
```powershell
(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
```

After editing `.wslconfig`, restart: `wsl --shutdown` then reopen WSL terminal.

Recommended: set to 65% of physical RAM (leaves headroom for Windows).
[ASSUMED — 65% is a commonly cited safe ratio, not from official Microsoft docs]

### Timing Script Pattern (D-08)

```bash
# time_startup.jl — measure TTFX for using STREAM + mtkcompile
# Usage: julia --project=. time_startup.jl
#    OR: julia --sysimage stream.so --project=. time_startup.jl
```

```julia
t0 = time()
using STREAM, ModelingToolkit, OrdinaryDiffEq, Sundials
using ModelingToolkit: t_nounits as t
t_load = time() - t0
println("using STREAM (load): $(round(t_load, digits=1)) s")

t1 = time()
@named pump = Pump(3.0e4)
geo = PipeGeometry_circular(0.01)
@named ch = Channel(; n=2, geometry=geo)
eqs = [connect(pump.outlet, ch.inlet),
       connect(ch.outlet, pump.inlet),
       ch.thermal.T ~ 373.15,
       pump.inlet.P ~ 1.0e5]
@named sys = System(eqs, t, [], []; systems=[pump, ch])
ssys = mtkcompile(sys)
t_compile = time() - t1
println("mtkcompile (minimal): $(round(t_compile, digits=1)) s")

println("Total: $(round(time() - t0, digits=1)) s")
```

**Shell wrapper to run both without and with sysimage:**

```bash
echo "=== Without sysimage ===" && time julia --project=. time_startup.jl
echo ""
echo "=== With sysimage ===" && time julia --sysimage stream.so --project=. time_startup.jl
```

### Anti-Patterns to Avoid

- **Running `julia build_sysimage.jl` directly:** Uses all available RAM; WSL2 will OOM. Always
  use `./build_sysimage.sh`. [VERIFIED: documented in both CLAUDE.md and build_sysimage.jl header]
- **Using `incremental=false` in PackageCompiler:** Recompiles all of Julia Base from scratch;
  takes 15-30 minutes and uses much more memory. The existing `build_sysimage.jl` does NOT pass
  `incremental=false` — this is correct. [VERIFIED: build_sysimage.jl line 21]
- **Large warmup system:** n=10+ cell systems during precompile_exec.jl execution add significant
  memory pressure during the already memory-intensive PackageCompiler link step.
- **Baking examples.jl build_loop:** build_loop calls solve_steady which calls solve with
  KINSOL — unnecessary for TTFX improvement and adds memory pressure during build.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Sysimage creation | Custom AOT compilation script | `PackageCompiler.create_sysimage` | Handles Julia IR, native code layout, stdlib integration |
| Memory detection | Parse `/proc/meminfo` manually | `awk '/^MemAvailable:/{print int($2/1024)}' /proc/meminfo` | One-liner, always correct |
| Precompile recording | Manual `precompile()` calls | `precompile_execution_file` parameter | PackageCompiler records ALL methods called, not just manually listed ones |

---

## Common Pitfalls

### Pitfall 1: precompile_exec.jl with only `using` imports does nothing useful

**What goes wrong:** Sysimage is built, startup time for `using` is fast, but first `mtkcompile`
still takes 30-60s because no MTK dispatch was triggered during the build.
**Why it happens:** `using` loads Julia source and runs `__init__` but does NOT compile methods.
Method compilation only happens on first call. PackageCompiler only bakes compiled methods.
**How to avoid:** Actually call `mtkcompile(sys)` on a real (minimal) system in
`test/precompile_exec.jl`. [VERIFIED: current file has only `using` statements — this is the gap]
**Warning signs:** Startup with sysimage is fast but first MTK use in a REPL session still hangs.

### Pitfall 2: WSL2 OOM during PackageCompiler link step

**What goes wrong:** Build runs for 10-14 minutes, then WSL2 process is killed (or entire WSL
instance reboots). No `stream.so` is produced.
**Why it happens:** PackageCompiler's native linking step for large packages (MTK + Sundials C
library + ODE solvers) requires 5-7 GB of RAM at peak. WSL2's default 50% memory allocation
on a 16 GB machine = 8 GB, which is marginal. Other processes consuming RAM push it over the limit.
**How to avoid:** Pre-flight check gates on 6 GB free (not just total). `check_sysimage_ready.sh`
already validates this at 4500 MB — the build script gate at 6144 MB is more conservative.
**Warning signs:** WSL2 terminal closes unexpectedly during build; no `stream.so` in repo root.

### Pitfall 3: NonlinearSolve import confusion

**What goes wrong:** Removing `using NonlinearSolve` from `test/test_resistors.jl` appears to
remove a dependency, but NonlinearSolve is still in the transitive dependency tree via
OrdinaryDiffEq and ModelingToolkit. Tests continue to work.
**Why it happens:** NonlinearSolve is a transitive dep of DifferentialEquations, OrdinaryDiffEq,
and MTK. [VERIFIED: Manifest.toml shows OrdinaryDiffEq depends on OrdinaryDiffEqNonlinearSolve
which depends on NonlinearSolve]
**How to avoid:** Remove only the `using NonlinearSolve` line from test_resistors.jl. Do NOT
attempt to remove it from Manifest.toml — it is a transitive dep that will be reinstalled.

### Pitfall 4: System constructor change between MTK versions

**What goes wrong:** `precompile_exec.jl` uses `System(eqs, t, [], []; systems=[...])` but the
installed MTK version uses a different constructor signature.
**Why it happens:** MTK 9+ changed `ODESystem` to `System`. Current Project.toml specifies
`ModelingToolkit = "11"`. [VERIFIED: Project.toml compat entry]
**How to avoid:** Look at existing test files for the exact constructor call pattern — they are
the ground truth. Use `System(eqs, t, [], []; systems=[...])` matching existing test patterns.
[VERIFIED: test/test_resistors.jl uses `mtkcompile(r; fully_determined=false)` confirming MTK 11]

---

## Runtime State Inventory

Not applicable — this is a build tooling / warmup script phase, not a rename/refactor/migration.
No stored data, live service config, OS registrations, secrets, or build artifacts reference
strings that change. The sysimage `stream.so` does not exist yet (will be created by this phase).

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| julia | Build + test | Yes | 1.12.5 | — |
| bash `free -m` | Pre-flight check | Yes | (system) | Use `/proc/meminfo` directly |
| `/proc/meminfo` | Pre-flight check | Yes | (kernel) | — |
| PackageCompiler | `build_sysimage.jl` | In `[extras]` — available | ~2.x | — |
| `stream.so` | TTFX reduction | Does not exist yet | — | Build is the deliverable |

[VERIFIED: julia --version, free -m, /proc/meminfo on this machine]

**RAM available:** 15.9 GB total / ~14.7 GB available [VERIFIED: /proc/meminfo]. Build should
succeed on this machine without `.wslconfig` changes. The pre-flight check and doc update are
for users with less RAM or tighter allocations.

**Missing dependencies with no fallback:** None — all required tools are present.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Julia built-in Test stdlib |
| Config file | none (run directly with julia) |
| Quick run command | `julia --project=. -e 'using Test; include("test/test_resistors.jl")'` |
| Full suite command | `julia --project=. test/runtests.jl` (or with --sysimage) |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TTFX-01 | mtkcompile TTFX reduced with sysimage | benchmark | `julia --sysimage stream.so --project=. time_startup.jl` | No — Wave 0 gap |
| TTFX-02 | Build completes without OOM | smoke | `./build_sysimage.sh` exits 0 + stream.so exists | Build script exists |
| TTFX-03 | Baseline vs sysimage numbers recorded | manual/benchmark | `julia --project=. time_startup.jl` (without sysimage) | No — Wave 0 gap |
| TTFX-04 | Full test suite passes with sysimage | regression | `julia --sysimage stream.so --project=. test/runtests.jl` | Yes (runtests.jl) |
| TTFX-05 | No NonlinearSolve import in test_resistors.jl | lint/grep | `grep -n NonlinearSolve test/test_resistors.jl` (expect: no output) | Implicit |
| TTFX-06 | CLAUDE.md documents .wslconfig steps | doc review | manual review | Yes (CLAUDE.md) |

### Sampling Rate

- **Per task commit:** Verify changed files are syntactically valid (Julia parse check)
- **Per wave merge:** `julia --project=. test/runtests.jl` (without sysimage, confirms no regressions from warmup or dead-import removal)
- **Phase gate (D-07, D-08, D-09):**
  1. `./build_sysimage.sh` completes → `stream.so` exists
  2. `julia --project=. time_startup.jl` → record baseline numbers
  3. `julia --sysimage stream.so --project=. time_startup.jl` → confirm improvement
  4. `julia --sysimage stream.so --project=. test/runtests.jl` → all tests pass

### Wave 0 Gaps

- `time_startup.jl` — covers TTFX-01, TTFX-03 (timing benchmark script)

*(All other test infrastructure exists. `runtests.jl` and full test suite are present and cover
the regression check for TTFX-04.)*

---

## File-Level Change Summary

This phase touches exactly 4 files (plus 1 new file):

| File | Change | Size |
|------|--------|------|
| `test/precompile_exec.jl` | Add ~20 lines: minimal Pump+Channel system + mtkcompile call | Small |
| `build_sysimage.sh` | Prepend ~15 lines: free RAM check before `exec julia` | Small |
| `test/test_resistors.jl` | Remove 1 line: `using NonlinearSolve` (but file currently has no such line — needs verification) | Tiny |
| `CLAUDE.md` | Expand Performance section with .wslconfig docs (~20 lines) | Small |
| `time_startup.jl` (new) | Timing benchmark script (~25 lines) | Small |

**Note on NonlinearSolve:** Current search finds no `NonlinearSolve` import in any `.jl` file
under `test/`. [VERIFIED: grep found no matches in test/]. The CONTEXT.md references
`test/test_resistors.jl:5` but that line currently reads `using DifferentialEquations`. This may
have already been removed in a previous phase, or the file was restructured. The planner should
verify the current file state before scheduling a task to remove it.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | PackageCompiler ~2.x is in Manifest (as extras dep) | Standard Stack | Low — extras are separate from runtime; PackageCompiler presence verified by build_sysimage.jl using it |
| A2 | mtkcompile on a Pump+Channel n=2 system bakes the same method signatures as larger systems | Architecture Patterns | Low — if wrong, warmup needs more topology variety; easily fixed |
| A3 | `System(eqs, t, [], []; systems=[...])` is the correct MTK 11 constructor syntax | Architecture Patterns | Medium — if wrong, precompile_exec.jl will error during build; planner should cross-check with existing test files |
| A4 | 65% of physical RAM is safe for .wslconfig memory= setting | Architecture Patterns | Low — if too high, Windows becomes unstable; user can tune |
| A5 | NonlinearSolve dead import was in test_resistors.jl but may already be removed | File-Level Changes | Low — the task is to verify and remove if present |

---

## Sources

### Primary (HIGH confidence)
- `/home/itay/projects/Julia-STREAM/build_sysimage.sh` — complete script, all flags verified
- `/home/itay/projects/Julia-STREAM/build_sysimage.jl` — PackageCompiler invocation, package list
- `/home/itay/projects/Julia-STREAM/test/precompile_exec.jl` — current state (using-only, no warmup)
- `/home/itay/projects/Julia-STREAM/check_sysimage_ready.sh` — existing pre-flight validator
- `/home/itay/projects/Julia-STREAM/Project.toml` — package deps and compat constraints
- `/proc/meminfo` on current machine — RAM availability
- `/home/itay/projects/Julia-STREAM/CLAUDE.md` — current documentation state

### Secondary (MEDIUM confidence)
- PackageCompiler.jl `precompile_execution_file` behavior — well-documented, standard pattern

### Tertiary (LOW confidence)
- Specific memory threshold recommendations (6 GB, 65% of physical) — community convention, not from official PackageCompiler docs

---

## Metadata

**Confidence breakdown:**
- File inventory: HIGH — verified by reading every file
- PackageCompiler pattern: HIGH — precompile_execution_file is the documented hook; exists in build_sysimage.jl
- Warmup code correctness: MEDIUM — constructor syntax assumed from test file patterns; executor must verify
- Memory thresholds: MEDIUM — reasonable values, not authoritative

**Research date:** 2026-04-10
**Valid until:** 2026-05-10 (stable domain; Julia 1.12 + MTK 11 API is stable)
