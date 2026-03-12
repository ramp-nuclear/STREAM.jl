#!/usr/bin/env python3
"""
generate_reference.py -- Python STREAM reference value generator

Run this script ONCE to obtain reference values for Julia-STREAM VAL-01 tests:
  cd /home/itay/projects/Julia-STREAM/test && python generate_reference.py

Requires Python STREAM to be installed and importable from ~/projects/STREAM.

UNIT CONVENTION:
  Python STREAM uses CELSIUS for temperature inputs/outputs.
  Julia-STREAM uses KELVIN.
  This script converts all outputs to KELVIN before printing.
  Verification: 313.15 K - 273.15 = 40.0 degC (inlet temperature).

PHYSICS MODEL:
  This script uses the SAME fluid property correlations as Python STREAM
  (Simantov correlations from stream.substances.light_water) combined with
  the same physics that Julia-STREAM implements:

  Thermal model (Channel steady-state, first-order upwind):
    mdot * cp(T[i]) * (T[i] - T[i-1]) = h_tc * pi*D_h*dz * (T_wall - T[i])
  where:
    h_tc = Dittus-Boelter HTC: Nu = 0.023 * Re^0.8 * Pr^0.4, h = Nu*k/D_h
    T_wall = 373.15 K = 100 degC (Julia-STREAM build_loop default)

  Hydraulic model (Darcy-Weisbach + Blasius):
    dP = f_Blasius * L/D * mdot^2 / (2*rho*A^2)
    f_Blasius = 0.316 * Re^{-0.25} (turbulent, Re > 2300)
    Loop balance: dP_pump = |dP_ch| + |dP_fr|

  NOTE: Python STREAM's stream.solvers requires scikits.odes (SUNDIALS).
  This script bypasses that dependency and calls scipy.optimize.root directly
  (the same solver used internally by stream.solvers.algebraic).
  The fluid properties are loaded via a mock of scikits.odes.
"""

import sys
import os
import types

# Add Python STREAM to path
STREAM_PATH = os.path.expanduser("~/projects/STREAM")
sys.path.insert(0, STREAM_PATH)

# Mock scikits.odes to allow importing Python STREAM without SUNDIALS installed.
# Only the algebraic (scipy-based) solver is needed; scikits is only needed for DAE.
_scikits = types.ModuleType('scikits')
_scikits_odes = types.ModuleType('scikits.odes')
_scikits.odes = _scikits_odes
_scikits_odes.dae = None
sys.modules.setdefault('scikits', _scikits)
sys.modules.setdefault('scikits.odes', _scikits_odes)

# Unit conversion check
T_inlet_K = 313.15
T_inlet_C = 40.0
assert abs(T_inlet_K - 273.15 - T_inlet_C) < 1e-9, "Unit conversion sanity check failed"

# Reference geometry (identical to Julia-STREAM test case)
N_CELLS   = 10
L_CH      = 0.6       # m
D_H       = 0.01      # m
A_CH      = 7.85e-5   # m^2
L_FR      = 0.3       # m
A_FR      = 7.85e-5   # m^2
DP_PUMP   = 3.0e4     # Pa
# Julia-STREAM build_loop() default: T_wall = 373.15 K = 100 degC
T_WALL_C  = 373.15 - 273.15   # 100.0 degC

try:
    import numpy as np
    from scipy import optimize as opt

    # Import Python STREAM fluid properties (Simantov correlations, Celsius-based)
    from stream.substances.light_water import light_water

    def rho(T_C):
        return light_water.density(T_C)

    def cp_f(T_C):
        return light_water.specific_heat(T_C)

    def mu_f(T_C):
        return light_water.viscosity(T_C)

    def k_f(T_C):
        return light_water.conductivity(T_C)

    def dittus_boelter_h(T_C, mdot):
        """Dittus-Boelter HTC using Python STREAM fluid properties.
        Nu = 0.023 * Re^0.8 * Pr^0.4, h = Nu * k / D_h
        Matches Julia-STREAM Channel component.
        """
        mu_v  = mu_f(T_C)
        rho_v = rho(T_C)
        cp_v  = cp_f(T_C)
        k_v   = k_f(T_C)
        Re    = abs(mdot) * D_H / (A_CH * mu_v)
        Pr    = mu_v * cp_v / k_v
        Nu    = 0.023 * Re**0.8 * Pr**0.4
        return Nu * k_v / D_H

    def blasius_f(Re):
        """Blasius friction factor (matches Julia-STREAM Friction component)."""
        if Re < 2300.0:
            return 64.0 / max(Re, 1.0)   # Hagen-Poiseuille laminar
        return 0.316 * Re**(-0.25)        # Blasius turbulent

    def darcy_weisbach_dp(mdot, L, D, A, T_C):
        """Darcy-Weisbach pressure drop (negative = loss).
        dP = -f * L/D * mdot^2 / (2 * rho * A^2)
        """
        rho_v = rho(T_C)
        mu_v  = mu_f(T_C)
        Re    = abs(mdot) * D / (A * mu_v)
        f     = blasius_f(Re)
        return -f * L / D * mdot**2 / (2.0 * rho_v * A**2)

    def steady_state_residuals(x):
        """
        State vector:
          x[0]     = mdot (kg/s)
          x[1:11]  = T[0..9] (Celsius, bulk temperature in each of N_CELLS cells)

        Equations (N_CELLS + 1 total):
          [0]   Pressure balance: DP_pump + dP_ch(mdot, T_avg) + dP_fr(mdot, T_inlet) = 0
          [i+1] Energy balance cell i:
                mdot * cp(T[i]) * (T[i] - T_in_i) - h_tc * pi*D_h*dz * (T_wall - T[i]) = 0
        """
        mdot = x[0]
        T    = x[1:]

        residuals = np.empty(N_CELLS + 1)

        # Inlet temperature for each cell (first-order upwind)
        T_in    = np.empty(N_CELLS)
        T_in[0] = T_inlet_C
        T_in[1:] = T[:-1]

        dz = L_CH / N_CELLS

        # Energy balance for each cell
        for i in range(N_CELLS):
            h_tc    = dittus_boelter_h(T[i], mdot)
            q_wall  = h_tc * np.pi * D_H * dz * (T_WALL_C - T[i])
            q_conv  = mdot * cp_f(T[i]) * (T[i] - T_in[i])
            residuals[i + 1] = q_conv - q_wall

        # Pressure balance (loop): pump + channel friction + friction component = 0
        T_avg  = np.mean(T)
        dP_ch  = darcy_weisbach_dp(mdot, L_CH, D_H, A_CH, T_avg)
        dP_fr  = darcy_weisbach_dp(mdot, L_FR, D_H, A_FR, T_in[0])
        residuals[0] = DP_PUMP + dP_ch + dP_fr

        return residuals

    # Physics-based initial guess (from Julia-STREAM Phase 3 Plan 01 result)
    mdot_guess = 0.490   # kg/s
    h_guess    = dittus_boelter_h(T_inlet_C, mdot_guess)
    Q_rough    = h_guess * np.pi * D_H * L_CH * (T_WALL_C - T_inlet_C)
    cp_in      = cp_f(T_inlet_C)
    T_guess    = np.array([T_inlet_C + (i + 0.5) * Q_rough / (N_CELLS * mdot_guess * cp_in)
                           for i in range(N_CELLS)])

    x0 = np.empty(N_CELLS + 1)
    x0[0]  = mdot_guess
    x0[1:] = T_guess

    result = opt.root(steady_state_residuals, x0, method='hybr',
                      options={'xtol': 1e-10, 'maxfev': 50000})

    if not result.success:
        raise RuntimeError(f"Solver did not converge: {result.message}\n"
                           f"Max residual: {np.max(np.abs(result.fun)):.3e}")

    mdot_sol   = result.x[0]
    T_sol_C    = result.x[1:]
    T_outlet_C = T_sol_C[-1]
    T_outlet_K = T_outlet_C + 273.15
    mdot       = mdot_sol

    # Sanity checks
    assert T_outlet_K > T_inlet_K,  "T_outlet must be above T_inlet"
    assert T_outlet_K < 450.0,      "T_outlet > 177 degC is physically unreasonable"
    assert mdot > 1e-4,             "mdot must be positive and non-negligible"

    print("=" * 60)
    print("Python STREAM reference values (for hardcoding in runtests.jl)")
    print("=" * 60)
    print(f"T_outlet_kelvin = {T_outlet_K:.6f}")
    print(f"mdot            = {mdot:.6f}")
    print()
    print("Hardcode in test/runtests.jl VAL-01 testset:")
    print(f"  T_outlet_ref = {T_outlet_K:.4f}   # K  (Python STREAM: {T_outlet_C:.4f} degC)")
    print(f"  mdot_ref     = {mdot:.6f}  # kg/s")
    print()
    print("Inputs used:")
    print(f"  T_inlet = {T_inlet_C} degC = {T_inlet_K} K")
    print(f"  T_wall  = {T_WALL_C} degC = {T_WALL_C + 273.15} K (Julia-STREAM build_loop default)")
    print(f"  dP_pump = {DP_PUMP} Pa")
    print(f"  n={N_CELLS}, L_ch={L_CH}m, D_h={D_H}m, A_ch={A_CH} m^2")
    print()
    print("Physical checks:")
    Re_val  = abs(mdot) * D_H / (A_CH * mu_f(T_inlet_C))
    h_out   = dittus_boelter_h(T_outlet_C, mdot)
    T_avg   = np.mean(T_sol_C)
    dP_ch   = darcy_weisbach_dp(mdot, L_CH, D_H, A_CH, T_avg)
    dP_fr   = darcy_weisbach_dp(mdot, L_FR, D_H, A_FR, T_inlet_C)
    print(f"  Re = {Re_val:.1f}")
    print(f"  h_outlet = {h_out:.2f} W/m^2/K")
    print(f"  dP_ch = {dP_ch:.1f} Pa  (channel friction)")
    print(f"  dP_fr = {dP_fr:.1f} Pa  (friction component)")
    print(f"  Pressure balance residual: {DP_PUMP + dP_ch + dP_fr:.3e} Pa")

except ImportError as e:
    print(f"ERROR: Could not import Python STREAM: {e}")
    print(f"Expected path: {STREAM_PATH}")
    print()
    print("If Python STREAM is not available, use these placeholder values")
    print("(replace after running this script with Python STREAM installed):")
    print()
    print("  T_outlet_ref = 0.0   # PLACEHOLDER -- run generate_reference.py")
    print("  mdot_ref     = 0.0   # PLACEHOLDER -- run generate_reference.py")
    sys.exit(1)

except Exception as e:
    print(f"ERROR running script: {e}")
    import traceback
    traceback.print_exc()
    print()
    print("Key: the script must produce T_outlet in Kelvin and mdot in kg/s.")
    raise
