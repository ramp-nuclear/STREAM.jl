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
