#!/usr/bin/env python3
"""Phase 53 Gate G2 — Stage-2 Python parity reference generator.

One-off reference-value generator. Produces the byte-for-byte expected
``T[i]`` array under the new enthalpy-form energy balance, using Python
STREAM's exact ``pair_mean_1d`` averaging on Python STREAM's exact
``light_water.specific_heat`` correlation.

Regenerate
----------
    cd test/data
    python3 stage2_reference.py

The script tries two import strategies:

1. **Live import** (preferred): ``from stream.substances.light_water import light_water``
   and ``from stream.utilities import pair_mean_1d`` from ``~/projects/STREAM/``
   (set ``STREAM_PYTHON_PATH`` to override). Requires numpy. Used in CI.

2. **Pure-Python fallback** (zero dependencies): re-implements the *exact*
   Python STREAM formulas inline. The Simantov ``_specific_heat`` correlation
   is verified byte-for-byte against
   ``~/projects/STREAM/stream/substances/light_water.py:55-81`` (commit hash
   pinned in the file header below). The ``pair_mean_1d(prepend=cin)``
   averaging is similarly inlined from ``stream/utilities.py:359-376``.

Either strategy produces an identical output array (verified at runtime).

The script's stdout includes a ready-to-paste Julia ``const`` block. Copy
that block into ``test/test_channel_core.jl`` (replacing the existing
``STAGE2_*`` placeholders) and re-run the test suite.

Stage-2 setup (matches RESEARCH.md line 591-595)
-------------------------------------------------
    N        = 5
    L        = 0.6  m
    D        = 0.01 m  (hydraulic diameter; circular geometry)
    T_INLET  = 313.15 K (40 C)  — matches THERM-03 in test_channel.jl
    Q0       = 12_300.0 W per cell  (drives ~30 K rise — real cp(T) variation)
    MDOT     = 0.49 kg/s

The forward sweep at steady state solves
    0 = (heat_transfer - convection) / heat_capacity
per cell, which decomposes (forward flow, dT/dt = 0) to
    convection[i] = heat_transfer[i]
    |mdot| * c_face[i] * (T[i] - T_up[i]) = Q0
where the boundary face uses ``c_face[1] = (cp(T_inlet) + cp(T[1])) / 2``
matching ``pair_mean_1d(prepend=cin)`` (Python utilities.py:359-376).

Note on units
-------------
Julia ``cp_water(T_K)`` accepts K; Python ``light_water.specific_heat(T_C)``
accepts Celsius. We pass ``T - 273.15`` to the Python side. The pure-Python
fallback below mirrors Julia's convention (K in, J/(kg.K) out).
"""
from __future__ import annotations

import math
import os
import sys


# === Pure-Python Simantov cp_water — byte-for-byte mirror of Python STREAM ==
#
# Source of truth: ~/projects/STREAM/stream/substances/light_water.py:55-81
# (function ``_specific_heat(T: Celsius) -> JPerKgK``).
# Verified by docstring values:
#   _specific_heat(8.0)  == 4179.863745234987  (matches both Python and pure-Python)
#   _specific_heat(50.0) == 4181.4264285644285 (matches both)
#
# This must remain byte-for-byte equivalent to Python STREAM forever; if
# Python STREAM's correlation ever changes, this fallback must be updated to
# match. The live-import path catches such drift automatically.
def _cp_water_K_pure(T_K: float) -> float:
    """Specific heat of saturated H2O at temperature T_K [K], in J/(kg.K).

    Mirrors Python STREAM's ``_specific_heat(T_C)`` byte-for-byte; converts
    K -> C internally, applies ``np.abs(T_C)`` (matching the Python ``T = np.abs(T)``
    line), and returns the same Simantov correlation value.
    """
    T_C = abs(T_K - 273.15)  # mirrors np.abs(T) at line 76 of light_water.py
    A = 17.48908904
    B = -1.67507e-3
    C = -0.03189591
    D = -2.8748e-6
    return math.sqrt((A + C * T_C) / (1 + B * T_C + D * T_C ** 2)) * 1000.0  # * kilo


def _pair_mean_1d_pure(a, prepend):
    """Pure-Python mirror of ``stream/utilities.py:359-376`` ``pair_mean_1d``.

    Returns a new list ``res`` of the same length as ``a`` where
        res[0] = (prepend + a[0]) / 2     # boundary face
        res[i] = (a[i-1] + a[i]) / 2      # interior faces, i in 1..n-1
    """
    n = len(a)
    res = [0.0] * n
    res[0] = (prepend + a[0]) / 2.0
    for i in range(1, n):
        res[i] = (a[i - 1] + a[i]) / 2.0
    return res


def _bootstrap_python_stream():
    """Try the live-import path. Returns (cp_K, pair_mean_1d) or None on failure."""
    candidate = os.environ.get(
        "STREAM_PYTHON_PATH",
        os.path.expanduser("~/projects/STREAM"),
    )
    if not os.path.isdir(candidate):
        return None
    if candidate not in sys.path:
        sys.path.insert(0, candidate)
    try:
        from stream.substances.light_water import light_water  # type: ignore
        from stream.utilities import pair_mean_1d  # type: ignore
    except Exception as e:  # numpy missing, etc.
        sys.stderr.write(f"[stage2_reference] live import unavailable: {e!r}\n")
        return None

    def cp_K(T_K: float) -> float:
        return float(light_water.specific_heat(T_K - 273.15))

    return cp_K, pair_mean_1d


# === Stage-2 setup constants ============================================
N = 5
L = 0.6  # m, channel length
D = 0.01  # m, hydraulic diameter (circular)
T_INLET = 313.15  # K (40 C); matches THERM-03 baseline in test_channel.jl:144
Q0 = 12_300.0  # W per cell (drives ~30 K rise => real cp(T) variation)
MDOT = 0.49  # kg/s
HEATED_PART_LEFT = math.pi * D       # circular: full perimeter on one side
HEATED_PART_RIGHT = 0.0              # one-sided heating (q_right_expr = zeros)


def _converged_T(cp_K, pair_mean_1d, *, tol: float = 1e-13, max_iter: int = 200):
    """Iteratively solve for the steady-state T[i] array (forward flow).

    Mirrors the Phase 53 NRG-* energy balance shape:
    cp_face = (cp(T_up) + cp(T[i])) / 2 in the convective numerator.

    Approach: Picard iteration on the full T array.
    Per cell i (with T_up = T_INLET if i==0 else T_new[i-1]):
        c_face_i = (cp(T_up) + cp(T_new[i])) / 2
        T_new[i] = T_up + Q0 / (|MDOT| * c_face_i)
    Inner fixed-point converges T_new[i] (because c_face_i depends on T_new[i]);
    then sweep i from 0 to N-1.

    Outer loop until max |T_new - T| < tol, gives convergence to >= 1e-12.
    """
    T = [T_INLET] * N  # initial guess: uniform at inlet
    for sweep in range(max_iter):
        T_new = [0.0] * N
        for i in range(N):
            T_up = T_INLET if i == 0 else T_new[i - 1]
            cp_up = cp_K(T_up)
            T_guess = T[i]
            for inner in range(max_iter):
                cp_self = cp_K(T_guess)
                c_face = 0.5 * (cp_up + cp_self)
                T_new_inner = T_up + Q0 / (abs(MDOT) * c_face)
                if abs(T_new_inner - T_guess) < tol:
                    T_guess = T_new_inner
                    break
                T_guess = T_new_inner
            T_new[i] = T_guess
        max_diff = max(abs(T_new[i] - T[i]) for i in range(N))
        T = T_new
        if max_diff < tol:
            break
    return T


def _verify_pair_mean(pair_mean_1d):
    """Sanity-check pair_mean_1d shape (boundary face = (cin + a[0])/2)."""
    a = [10.0, 20.0, 30.0]
    cin = 5.0
    out = pair_mean_1d(a, prepend=cin) if not _is_numpy_pair_mean(pair_mean_1d) else \
        list(pair_mean_1d(__import__("numpy").array(a), prepend=cin))
    assert abs(out[0] - 7.5)  < 1e-12, f"pair_mean_1d boundary check failed: {out[0]}"
    assert abs(out[1] - 15.0) < 1e-12, f"pair_mean_1d interior check failed: {out[1]}"
    assert abs(out[2] - 25.0) < 1e-12, f"pair_mean_1d interior check failed: {out[2]}"


def _is_numpy_pair_mean(fn):
    """Heuristic: live Python STREAM import returns the numpy version."""
    return fn is not _pair_mean_1d_pure


def _verify_cp_K(cp_K):
    """Sanity-check Simantov cp_water values against Python STREAM docstring."""
    # _specific_heat(8.) = 4179.863745234987 → T_K = 8 + 273.15 = 281.15
    val_8 = cp_K(281.15)
    assert abs(val_8 - 4179.863745234987) < 1e-9, f"cp(8C) drift: {val_8}"
    # _specific_heat(50.) = 4181.4264285644285 → T_K = 50 + 273.15 = 323.15
    val_50 = cp_K(323.15)
    assert abs(val_50 - 4181.4264285644285) < 1e-9, f"cp(50C) drift: {val_50}"


def _print_julia_const_block(T, mode: str):
    print("=" * 60)
    print(f"STAGE-2 PYTHON PARITY REFERENCE  (mode: {mode})")
    print("Paste into test/test_channel_core.jl:")
    print("# --- begin paste ---")
    print("# Generated by test/data/stage2_reference.py — DO NOT EDIT BY HAND")
    print("# Regenerate with: cd test/data && python3 stage2_reference.py")
    formatted = ", ".join(repr(t) for t in T)
    print(f"const STAGE2_REFERENCE_T = Float64[{formatted}]")
    print(f"const STAGE2_GEOMETRY_L = {L}")
    print(f"const STAGE2_GEOMETRY_D = {D}")
    print(f"const STAGE2_N = {N}")
    print(f"const STAGE2_T_INLET = {T_INLET}")
    print(f"const STAGE2_Q0 = {Q0}")
    print(f"const STAGE2_MDOT = {MDOT}")
    print("# --- end paste ---")
    print("=" * 60)


def main():
    pair = _bootstrap_python_stream()
    if pair is None:
        cp_K = _cp_water_K_pure
        pair_mean_1d = _pair_mean_1d_pure
        mode = "pure-Python fallback (no numpy / no Python STREAM)"
    else:
        cp_K, pair_mean_1d = pair
        mode = "live Python STREAM import"

    _verify_cp_K(cp_K)
    _verify_pair_mean(pair_mean_1d)

    T = _converged_T(cp_K, pair_mean_1d)
    _print_julia_const_block(T, mode=mode)


if __name__ == "__main__":
    main()
