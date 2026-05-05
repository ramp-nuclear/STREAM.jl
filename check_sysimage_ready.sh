#!/usr/bin/env bash
# check_sysimage_ready.sh — Pre-flight check before running ./build_sysimage.sh
#
# Runs two quick tests with the same Julia flags the real build uses:
#   1. Load all sysimage packages (catches OOM during the `using` phase)
#   2. Build a tiny sysimage with QuadGK only (proves PackageCompiler works here)
#
# If both pass, ./build_sysimage.sh should complete without crashing WSL.
# Takes ~2-4 minutes total (vs 5-15 min for the real build).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

JULIA_FLAGS="--heap-size-hint=4G --threads=1 --project=."
PASS=0
FAIL=0

run_check() {
    local label="$1"
    local code="$2"
    printf "  %-55s" "$label..."
    if env JULIA_NUM_THREADS=1 julia $JULIA_FLAGS -e "$code" 2>/dev/null; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL"
        FAIL=$((FAIL + 1))
    fi
}

echo ""
echo "=== STREAM.jl sysimage pre-flight check ==="
echo "Julia:     $(julia --version)"
echo "RAM total: $(free -h | awk '/^Mem:/{print $2}')"
echo "RAM free:  $(free -h | awk '/^Mem:/{print $7}')"
echo "Flags:     $JULIA_FLAGS JULIA_NUM_THREADS=1"
echo ""

# ── Check 1: available memory ─────────────────────────────────────────────────
echo "[ Memory ]"
FREE_MB=$(free -m | awk '/^Mem:/{print $7}')
if [ "$FREE_MB" -ge 4500 ]; then
    echo "  Free RAM: ${FREE_MB} MB — OK (>=4500 MB needed)        PASS"
    PASS=$((PASS + 1))
else
    echo "  Free RAM: ${FREE_MB} MB — LOW (<4500 MB). Close other apps and retry. FAIL"
    FAIL=$((FAIL + 1))
fi
echo ""

# ── Check 2: Julia starts with the flags ─────────────────────────────────────
echo "[ Julia startup ]"
run_check "Julia starts with --heap-size-hint=4G --threads=1" \
    'println("ok: threads=", Threads.nthreads(), " heap_hint_respected=true")'
echo ""

# ── Check 3: load all sysimage packages ──────────────────────────────────────
echo "[ Package loading — the slow part, ~1-3 min ]"
run_check "using ModelingToolkit" \
    'using ModelingToolkit'
run_check "using OrdinaryDiffEq" \
    'using OrdinaryDiffEq'
run_check "using Sundials" \
    'using Sundials'
run_check "using STREAM (all packages together)" \
    'using STREAM, ModelingToolkit, OrdinaryDiffEq, Sundials, Symbolics, QuadGK'
echo ""

# ── Check 4: PackageCompiler can build a tiny sysimage ───────────────────────
# Uses incremental=true (default) — same mode as the real build.
# incremental=false recompiles all of Julia Base from scratch (~15-30 min, much heavier).
echo "[ PackageCompiler smoke test — tiny sysimage with QuadGK only, ~1-2 min ]"
TINY_SO="/tmp/stream_preflight_tiny.so"
rm -f "$TINY_SO"
run_check "create_sysimage([\"QuadGK\"]) succeeds" \
    "using PackageCompiler; create_sysimage([\"QuadGK\"]; sysimage_path=\"$TINY_SO\", project=\".\")"
rm -f "$TINY_SO"
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -eq 0 ]; then
    echo ""
    echo "All checks passed. Run ./build_sysimage.sh when ready."
    echo ""
    exit 0
else
    echo ""
    echo "Fix the failures above before running ./build_sysimage.sh."
    echo "  - If package loading failed:   run  julia --project=. -e 'using Pkg; Pkg.instantiate()'"
    echo "  - If memory is too low:        close browser/other WSL apps and retry"
    echo ""
    exit 1
fi
