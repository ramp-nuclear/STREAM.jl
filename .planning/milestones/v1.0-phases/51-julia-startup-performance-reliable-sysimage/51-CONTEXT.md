# Phase 51: Julia Startup Performance & Reliable Sysimage - Context

**Gathered:** 2026-04-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix the sysimage build process so it works reliably on WSL2 without crashing, and reduce
Julia startup/TTFX time for `using STREAM`, `mtkcompile`, and loop construction.

Scope: `build_sysimage.sh`, `build_sysimage.jl`, `test/precompile_exec.jl`, and CLAUDE.md
documentation. Does NOT change any STREAM physics or test logic (except removing a dead import).
</domain>

<decisions>
## Implementation Decisions

### Precompile Warmup
- **D-01:** Add real STREAM code to `test/precompile_exec.jl` — at minimum call `mtkcompile`
  on a small minimal system (e.g. Pump + Channel, 2 nodes). This bakes the expensive symbolic
  IR compilation path into the sysimage so the first `mtkcompile` in a real session is fast.
  This is the standard, documented PackageCompiler pattern (the `precompile_execution_file`
  parameter exists precisely for this purpose).
- **D-02:** Keep warmup inputs small/cheap (minimal topology, not `build_loop` + solve) to
  avoid adding memory pressure during the build. The goal is to bake method dispatch, not run
  a full simulation.

### Build Reliability
- **D-03:** Add a pre-flight memory check to `build_sysimage.sh` before the `exec julia` call.
  If free RAM is below a safe threshold (6 GB), print a clear error with instructions (increase
  WSL2 memory via `.wslconfig`) and exit 1. This prevents silent 15-minute builds that die at
  the end.
- **D-04:** Document the WSL2 `.wslconfig` memory fix in CLAUDE.md:
  - How to check total Windows RAM (PowerShell one-liner)
  - The `.wslconfig` `memory=` setting
  - The `wsl --shutdown` restart step
  - Recommended: set to ~65% of physical RAM (e.g. `memory=10GB` on a 16GB machine)

### Package Scope
- **D-05:** Sysimage package list is correct as-is: `STREAM, ModelingToolkit, OrdinaryDiffEq,
  Symbolics, QuadGK, Sundials`. No additions needed.
- **D-06:** `NonlinearSolve` is a dead import in `test/test_resistors.jl` — imported but never
  used. Remove it. It is a test-only dep (`[extras]`, not `[deps]`) and was never in the
  runtime dependency tree. This is a cleanup task, not a sysimage concern.

### Verification (Hard Gates)
- **D-07:** The phase is NOT complete until `./build_sysimage.sh` actually produces `stream.so`
  on the user's machine. This is a hard gate. If the build crashes (WSL2 OOM), the plan must
  fix the root cause before closing.
- **D-08:** Timing script: a small `time_startup.jl` (or shell snippet) that measures wall time
  for `using STREAM`, first `mtkcompile`, first `solve_steady` — with and without `stream.so`.
  Run and record numbers. Phase not done until improvement is confirmed.
- **D-09:** Full test suite must pass with sysimage: `julia --sysimage stream.so --project=.
  test/runtests.jl`. Proves sysimage doesn't break correctness.

### Claude's Discretion
- Exact memory threshold for pre-flight check (reasonable default: 6 GB free)
- Specific Julia code in precompile_exec.jl (small Pump+Channel system is sufficient)
- Whether to use `free -m` or `/proc/meminfo` for the RAM check in bash

### WSL2 Build Crash Warning
When the executor runs `./build_sysimage.sh`, **WSL2 may crash and terminate the chat session**.
The execution plan must warn the user before running the build and suggest they run it manually
in a separate terminal. If the session crashes, the user reboots, checks for `stream.so`, and
reports back.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

No external specs — requirements are fully captured in decisions above.

### Existing implementation files
- `build_sysimage.sh` — current WSL2-hardened wrapper (4GB heap, 1 thread)
- `build_sysimage.jl` — PackageCompiler invocation + package list
- `test/precompile_exec.jl` — warmup script (currently empty — only `using` imports)
- `test/test_resistors.jl:5` — dead `using NonlinearSolve` import to remove
- `CLAUDE.md` §Performance — Sysimage section to update with WSL2 memory docs

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `build_sysimage.sh` — already has the correct WSL2 flags; only needs a pre-flight check prepended
- `build_sysimage.jl` — correct package list; no changes needed
- `test/precompile_exec.jl` — exists but needs warmup code added
- `src/examples.jl` — `build_loop()` and other helpers available for use in warmup if needed

### Established Patterns
- `@register_symbolic`, `mtkcompile`, `compose_systems` are the expensive paths to bake
- PackageCompiler's `precompile_execution_file` is the correct hook — already wired up in `build_sysimage.jl`
- CLAUDE.md performance section already mentions the 60-120s → 5s improvement claim; update with concrete numbers after verification

### Integration Points
- `test/precompile_exec.jl` is referenced in `build_sysimage.jl` as `precompile_execution_file`
- `build_sysimage.sh` wraps `build_sysimage.jl` — bash pre-flight check goes in the .sh file
- CLAUDE.md §Performance is the user-facing doc for sysimage instructions
- `test/Project.toml` has NonlinearSolve — removing from both test/Project.toml and test/test_resistors.jl
</code_context>

<specifics>
## Specific Ideas

- "I want to be 100% sure the .so file actually builds and works — not done until I've seen it succeed."
- WSL2 has crashed during previous build attempts, sometimes terminating the chat session itself. This is a known risk; handle it with a manual build step and clear recovery instructions.
- User is willing to increase WSL2 memory via `.wslconfig` if we tell them the exact steps.
</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.
</deferred>

---

*Phase: 51-julia-startup-performance-reliable-sysimage*
*Context gathered: 2026-04-10*
