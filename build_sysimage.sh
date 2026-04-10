#!/usr/bin/env bash
# build_sysimage.sh — WSL-safe sysimage builder for STREAM.jl
#
# Usage:
#   chmod +x build_sysimage.sh
#   ./build_sysimage.sh
#
# Why not plain `julia --project=. build_sysimage.jl`?
# PackageCompiler + ModelingToolkit + Sundials can consume 5-6 GB during
# compilation. On a 6.7 GB WSL2 machine that causes OOM → freeze.
# The flags below keep Julia's heap below 4 GB and pin to 1 thread.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Pre-flight memory check ────────────────────────────────────────────────
# PackageCompiler + MTK + Sundials require ~6 GB free during the link step.
# Abort early rather than waste 15 minutes on a build that will OOM.
FREE_MB=$(awk '/^MemAvailable:/{print int($2/1024)}' /proc/meminfo)
THRESHOLD_MB=6144  # 6 GB — conservative for PackageCompiler link step

if [ "$FREE_MB" -lt "$THRESHOLD_MB" ]; then
    echo "ERROR: Insufficient free RAM for sysimage build."
    echo "  Available: ${FREE_MB} MB"
    echo "  Required:  ${THRESHOLD_MB} MB (6 GB)"
    echo ""
    echo "To increase WSL2 memory, edit %USERPROFILE%\\.wslconfig on Windows:"
    echo ""
    echo "  [wsl2]"
    echo "  memory=10GB   # ~65% of 16 GB physical RAM"
    echo "  swap=4GB      # optional safety net"
    echo ""
    echo "Check your Windows RAM first (run in PowerShell):"
    echo "  (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB"
    echo ""
    echo "After editing .wslconfig, restart WSL: wsl --shutdown (then reopen terminal)"
    exit 1
fi
echo "Pre-flight check: ${FREE_MB} MB free — OK (threshold: ${THRESHOLD_MB} MB)"

echo "=== STREAM.jl sysimage builder ==="
echo "Julia: $(julia --version)"
echo "RAM available: $(free -h | awk '/^Mem:/{print $7}')"
echo ""
echo "Building stream.so — this takes 5-15 minutes."
echo "Memory is capped at 4 GB; single-threaded to prevent WSL freeze."
echo ""

# --heap-size-hint=4G  → GC runs aggressively before 4 GB, preventing OOM
# --threads=1          → no parallel compilation (PackageCompiler is single-
#                        threaded internally but this prevents Julia startup
#                        threads from adding pressure)
# JULIA_NUM_THREADS=1  → belt-and-suspenders for any thread-pool code paths
exec env JULIA_NUM_THREADS=1 \
    julia \
        --heap-size-hint=4G \
        --threads=1 \
        --project=. \
        build_sysimage.jl
