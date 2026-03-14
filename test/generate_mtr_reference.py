#!/usr/bin/env python3
"""
generate_mtr_reference.py -- Python STREAM MTR coupled plate reference values

Run ONCE to obtain reference values for Julia-STREAM Phase 12 validation:
  cd /home/itay/projects/Julia-STREAM/test && python generate_mtr_reference.py

Requires Python STREAM at ~/projects/STREAM.

UNIT CONVENTION: Python STREAM = Celsius. Julia-STREAM = Kelvin.
All outputs converted to Kelvin before printing.

TOPOLOGY (all scenarios):
  Loop L: Pump_L → HeatExchanger_L → ChannelAndContacts_L → Pump_L (closed)
  Loop R: Pump_R → HeatExchanger_R → ChannelAndContacts_R → Pump_R (closed)
  Plate: HeatDiffusion coupled via plate() or one_sided_connection()

PLATE GEOMETRY / MATERIAL (aluminum cladding, single uniform layer):
  nz=10, nx=3, Lz=0.6 m, Lx=0.00127 m (1.27 mm), y=0.07 m
  rho_s=2700, cp_s=900, k_s=200 W/mK
  power=1e4 W (10 kW), power_shape uniform (1/30 each cell)

CHANNEL GEOMETRY (both channels identical):
  D=0.01 m, L=0.6 m, n=10, dP=30 kPa, g=0 (horizontal), P_abs=1e5 Pa
"""

import sys
import os
from functools import partial
import numpy as np

STREAM_PATH = os.path.expanduser("~/projects/STREAM")
sys.path.insert(0, STREAM_PATH)

# ─────────────────────────────────────────────────────────────────
# Module-level constants
# ─────────────────────────────────────────────────────────────────
NZ, NX = 10, 3
LZ, LX, Y_LEN = 0.6, 0.00127, 0.07
POWER = 1e4
DP_PUMP = 3.0e4
P_ABS = 1.0e5
D_H = 0.01

T_INLET_L_C = 40.0       # VAL-01/02/03 left channel inlet (Celsius)
T_INLET_R_C = 40.0       # VAL-01/03 right channel inlet (Celsius)
T_INLET_R_ASYM_C = 90.0  # VAL-02 right channel inlet (Celsius)

T_INLET_L_K = T_INLET_L_C + 273.15
T_INLET_R_K = T_INLET_R_C + 273.15
T_INLET_R_ASYM_K = T_INLET_R_ASYM_C + 273.15

assert abs(T_INLET_L_K - 313.15) < 1e-9
assert abs(T_INLET_R_ASYM_K - 363.15) < 1e-9

from stream.calculations import Pump, HeatExchanger
from stream.calculations.channel import ChannelAndContacts
from stream.calculations.heat_diffusion import Fuel, Solid
from stream.composition.cycle import FlowGraph, flow_edge
from stream.composition.mtr_geometry import plate, one_sided_connection
from stream.aggregator import CalculationGraph
from stream.pipe_geometry import EffectivePipe
from stream.substances import light_water
from stream.jacobians import ALG_jacobian
from stream.physical_models.pressure_drop import pressure_diff

# ─────────────────────────────────────────────────────────────────
# Shared component construction (built once, reused across scenarios)
# ─────────────────────────────────────────────────────────────────
material = Solid(density=2700.0, specific_heat=900.0, conductivity=200.0)

power_shape_np = np.ones((NZ, NX)) / (NZ * NX)
assert abs(power_shape_np.sum() - 1.0) < 1e-9, f"power_shape sum = {power_shape_np.sum()}"

z_bounds = np.linspace(0, LZ, NZ + 1)
x_bounds = np.linspace(0, LX, NX + 1)
pipe_ch = EffectivePipe.circular(length=LZ, diameter=D_H)


def _build_channel_and_loop(name_suffix: str, T_inlet_C: float):
    """Build a fresh Pump + HeatExchanger + ChannelAndContacts for one loop.

    Returns (pump, hx, channel, FlowGraph).
    Note: fresh objects per scenario — Python STREAM components carry state.
    """
    pump = Pump(pressure=DP_PUMP, name=f"Pump_{name_suffix}")
    hx = HeatExchanger(outlet=T_inlet_C, name=f"HX_{name_suffix}")
    channel = ChannelAndContacts(
        z_boundaries=z_bounds,
        fluid=light_water,
        pipe=pipe_ch,
        pressure_func=partial(pressure_diff, g=0),
        name=f"Channel_{name_suffix}",
    )
    fg = FlowGraph(
        flow_edge(("A", "B"), pump, hx),
        flow_edge(("B", "A"), channel),
        funcs={
            channel: dict(
                p_abs=P_ABS,
            ),
        },
        reference_node=("A", P_ABS),
        abs_pressure_comps=[channel],
    )
    return pump, hx, channel, fg


def _build_fuel(name: str = "Fuel") -> Fuel:
    """Build a Fuel object (fresh per scenario)."""
    return Fuel(
        z_boundaries=z_bounds,
        x_boundaries=x_bounds,
        material=material,
        y_length=Y_LEN,
        power_shape=power_shape_np,
        name=name,
    )


def _initial_guess(channels, pumps, hxs, fuel, T_inlet_C: float, mdot_guess: float = 0.5):
    """Assemble a combined initial state guess for a two-loop MTR system."""
    state = {}
    for ch in channels:
        state[ch.name] = {
            "T_cool":  np.linspace(T_inlet_C, T_inlet_C + 10, NZ),
            "h_left":  1.5e4 * np.ones(NZ),
            "h_right": 1.5e4 * np.ones(NZ),
            "pressure": -DP_PUMP * np.ones(NZ),
        }
    for comp in [*pumps, *hxs]:
        state[comp.name] = {"Tin": T_inlet_C, "pressure": DP_PUMP}
    state[fuel.name] = {
        "T": np.full((NZ, NX), T_inlet_C + 5.0),
        "T_wall_left": np.full(NZ, T_inlet_C + 3.0),
        "T_wall_right": np.full(NZ, T_inlet_C + 3.0),
    }
    return state


def _solve_scenario(agr, state_guess, jac=True):
    """Solve steady state; return (agr, sol_vec, state)."""
    guess_vec = agr.load(state_guess)
    jac_fn = ALG_jacobian(agr) if jac else None
    sol_vec = agr.solve_steady(guess_vec, jac=jac_fn)
    state = agr.save(sol_vec)
    return sol_vec, state


# ─────────────────────────────────────────────────────────────────
# VAL-01: Symmetric coupling — plate() with both channels at 40°C
# ─────────────────────────────────────────────────────────────────
print("Running VAL-01: Symmetric coupling...")
pump_l_01, hx_l_01, ch_l_01, fg_l_01 = _build_channel_and_loop("L_01", T_INLET_L_C)
pump_r_01, hx_r_01, ch_r_01, fg_r_01 = _build_channel_and_loop("R_01", T_INLET_R_C)
fuel_01 = _build_fuel("Fuel_01")

plate_cg_01 = plate(ch_l_01, ch_r_01, fuel_01)
power_cg_01 = CalculationGraph.from_decoupled(fuel_01, funcs={fuel_01: dict(power=POWER)})

full_cg_01 = fg_l_01.aggregator + fg_r_01.aggregator + plate_cg_01 + power_cg_01
agr_01 = full_cg_01.to_aggregator()
K_l_01 = fg_l_01.kirchhoff
K_r_01 = fg_r_01.kirchhoff

guess_01 = _initial_guess(
    [ch_l_01, ch_r_01], [pump_l_01, pump_r_01], [hx_l_01, hx_r_01], fuel_01, T_INLET_L_C
)
sol_vec_01, state_01 = _solve_scenario(agr_01, guess_01)

T_outlet_l_K_sym = state_01[ch_l_01.name]["T_cool"][-1] + 273.15
T_outlet_r_K_sym = state_01[ch_r_01.name]["T_cool"][-1] + 273.15
mdot_l_sym = abs(state_01[K_l_01.name][K_l_01.component_edge(pump_l_01)])
mdot_r_sym = abs(state_01[K_r_01.name][K_r_01.component_edge(pump_r_01)])
T_plate_sym = state_01[fuel_01.name]["T"]  # (NZ, NX) in Celsius
T_plate_center_K_sym = T_plate_sym[NZ // 2][NX // 2] + 273.15

# Sanity assertions
assert T_outlet_l_K_sym > T_INLET_L_K, f"VAL-01: T_outlet_l {T_outlet_l_K_sym:.2f} K below inlet"
assert T_outlet_r_K_sym > T_INLET_R_K, f"VAL-01: T_outlet_r {T_outlet_r_K_sym:.2f} K below inlet"
assert mdot_l_sym > 1e-4, f"VAL-01: mdot_l {mdot_l_sym:.4f} kg/s too small"
assert mdot_r_sym > 1e-4, f"VAL-01: mdot_r {mdot_r_sym:.4f} kg/s too small"
assert T_plate_center_K_sym > T_INLET_L_K, f"VAL-01: T_plate_center below inlet"
# Symmetry: both channels should be nearly identical (<1% relative diff in T_outlet)
assert abs(T_outlet_l_K_sym - T_outlet_r_K_sym) / T_outlet_l_K_sym < 0.01, (
    f"VAL-01: T_outlet asymmetry = {abs(T_outlet_l_K_sym - T_outlet_r_K_sym):.4f} K — expected symmetric"
)
print("  VAL-01 OK")

# ─────────────────────────────────────────────────────────────────
# VAL-02: Asymmetric coupling — right channel HX outlet = 90°C
# ─────────────────────────────────────────────────────────────────
print("Running VAL-02: Asymmetric coupling (right channel 90°C)...")
pump_l_02, hx_l_02, ch_l_02, fg_l_02 = _build_channel_and_loop("L_02", T_INLET_L_C)
pump_r_02, hx_r_02, ch_r_02, fg_r_02 = _build_channel_and_loop("R_02", T_INLET_R_ASYM_C)
fuel_02 = _build_fuel("Fuel_02")

plate_cg_02 = plate(ch_l_02, ch_r_02, fuel_02)
power_cg_02 = CalculationGraph.from_decoupled(fuel_02, funcs={fuel_02: dict(power=POWER)})

full_cg_02 = fg_l_02.aggregator + fg_r_02.aggregator + plate_cg_02 + power_cg_02
agr_02 = full_cg_02.to_aggregator()
K_l_02 = fg_l_02.kirchhoff

guess_02 = _initial_guess(
    [ch_l_02, ch_r_02], [pump_l_02, pump_r_02], [hx_l_02, hx_r_02], fuel_02,
    T_INLET_L_C  # left-side reference for fuel guess
)
# Right side guess: use right channel inlet
guess_02[ch_r_02.name]["T_cool"] = np.linspace(T_INLET_R_ASYM_C, T_INLET_R_ASYM_C + 10, NZ)
guess_02[hx_r_02.name] = {"Tin": T_INLET_R_ASYM_C, "pressure": DP_PUMP}
guess_02[pump_r_02.name] = {"Tin": T_INLET_R_ASYM_C, "pressure": DP_PUMP}
guess_02[fuel_02.name]["T"] = np.full((NZ, NX), (T_INLET_L_C + T_INLET_R_ASYM_C) / 2 + 5.0)

sol_vec_02, state_02 = _solve_scenario(agr_02, guess_02)

T_plate_asym = state_02[fuel_02.name]["T"]  # (NZ, NX) in Celsius
T_plate_center_K_asym = T_plate_asym[NZ // 2][NX // 2] + 273.15

# Asymmetry assertion: right side of plate (x-index NX-1=2) should be hotter than left (x-index 0)
# because right channel is at 90°C vs 40°C on the left
assert T_plate_asym[NZ // 2][NX - 1] > T_plate_asym[NZ // 2][0], (
    f"VAL-02: Expected T_plate right > left; got right={T_plate_asym[NZ//2][NX-1]:.2f} C, "
    f"left={T_plate_asym[NZ//2][0]:.2f} C"
)
print("  VAL-02 OK")

# ─────────────────────────────────────────────────────────────────
# VAL-03: One-sided coupling — left face only, right adiabatic
# ─────────────────────────────────────────────────────────────────
print("Running VAL-03: One-sided coupling (left face only)...")
pump_l_03, hx_l_03, ch_l_03, fg_l_03 = _build_channel_and_loop("L_03", T_INLET_L_C)
fuel_03 = _build_fuel("Fuel_03")

onesided_cg_03 = one_sided_connection(ch_l_03, fuel_03, fuel_side="left")
power_cg_03 = CalculationGraph.from_decoupled(fuel_03, funcs={fuel_03: dict(power=POWER)})

full_cg_03 = fg_l_03.aggregator + onesided_cg_03 + power_cg_03
agr_03 = full_cg_03.to_aggregator()
K_l_03 = fg_l_03.kirchhoff

guess_03 = {}
guess_03[ch_l_03.name] = {
    "T_cool":  np.linspace(T_INLET_L_C, T_INLET_L_C + 15, NZ),
    "h_left":  1.5e4 * np.ones(NZ),
    "h_right": 1.5e4 * np.ones(NZ),
    "pressure": -DP_PUMP * np.ones(NZ),
}
guess_03[pump_l_03.name] = {"Tin": T_INLET_L_C, "pressure": DP_PUMP}
guess_03[hx_l_03.name] = {"Tin": T_INLET_L_C, "pressure": DP_PUMP}
guess_03[fuel_03.name] = {
    "T": np.full((NZ, NX), T_INLET_L_C + 5.0),
    "T_wall_left": np.full(NZ, T_INLET_L_C + 3.0),
    "T_wall_right": np.full(NZ, T_INLET_L_C + 3.0),
}

sol_vec_03, state_03 = _solve_scenario(agr_03, guess_03)

T_outlet_l_K_onesided = state_03[ch_l_03.name]["T_cool"][-1] + 273.15
mdot_l_onesided = abs(state_03[K_l_03.name][K_l_03.component_edge(pump_l_03)])
T_plate_onesided = state_03[fuel_03.name]["T"]  # (NZ, NX) in Celsius
T_plate_center_K_onesided = T_plate_onesided[NZ // 2][NX // 2] + 273.15

assert T_outlet_l_K_onesided > T_INLET_L_K, (
    f"VAL-03: T_outlet {T_outlet_l_K_onesided:.2f} K below inlet"
)
assert mdot_l_onesided > 1e-4, f"VAL-03: mdot {mdot_l_onesided:.4f} kg/s too small"
print("  VAL-03 OK")

# ─────────────────────────────────────────────────────────────────
# Print block — format ready to paste into runtests.jl
# ─────────────────────────────────────────────────────────────────
print()
print("=" * 60)
print("Python STREAM reference values for Phase 12 (paste into runtests.jl)")
print("=" * 60)
print()
print("# VAL-01: Symmetric")
print(f"  val01_T_outlet_l_ref = {T_outlet_l_K_sym:.4f}   # K")
print(f"  val01_T_outlet_r_ref = {T_outlet_r_K_sym:.4f}   # K")
print(f"  val01_mdot_l_ref     = {mdot_l_sym:.6f}  # kg/s")
print(f"  val01_mdot_r_ref     = {mdot_r_sym:.6f}  # kg/s")
print(f"  val01_T_plate_center = {T_plate_center_K_sym:.4f}   # K")
print()
print("# VAL-02: Asymmetric (right channel 90°C)")
print(f"  val02_T_plate_center = {T_plate_center_K_asym:.4f}   # K")
print(f"  # Assert: T_plate left face < T_plate right face (qualitative)")
print()
print("# VAL-03: One-sided (left face only)")
print(f"  val03_T_outlet_ref   = {T_outlet_l_K_onesided:.4f}   # K")
print(f"  val03_mdot_ref       = {mdot_l_onesided:.6f}  # kg/s")
print(f"  val03_T_plate_center = {T_plate_center_K_onesided:.4f}   # K")
