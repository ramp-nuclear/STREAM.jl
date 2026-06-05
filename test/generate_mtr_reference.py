#!/usr/bin/env python3
"""
generate_mtr_reference.py -- Python STREAM MTR coupled plate reference values

Emits per-quantity Python references
covering all tiers (a)+(b)+(c)+(d) for the 3 MTR scenarios
(symmetric / asymmetric / one-sided). Output is bracketed by
"# --- begin paste ---" / "# --- end paste ---" markers
manually regenerated and pasted
into test/data/python_parity_reference.jl.

Run ONCE on the developer machine to obtain reference values:
  cd /home/itay/projects/Julia-STREAM/test && python generate_mtr_reference.py

This generator is NOT in CI -- it is run on the developer machine
when Python STREAM HEAD's physics changes; output is committed to the
Julia-side reference data file.

Requires Python STREAM at ~/projects/STREAM.

UNIT CONVENTION: Python STREAM = Celsius. Julia-STREAM = Kelvin.
All temperature outputs converted to Kelvin before printing.
HTC values [W/(m^2 K)] and heat-flux density [W/m^2] are unit-base
independent; they are emitted verbatim.

TOPOLOGY (all scenarios):
  Loop L: Pump_L -> HeatExchanger_L -> ChannelAndContacts_L -> Pump_L (closed)
  Loop R: Pump_R -> HeatExchanger_R -> ChannelAndContacts_R -> Pump_R (closed)
  Plate: HeatDiffusion coupled via plate() (sym / asym) or one_sided_connection() (onesided)

PLATE GEOMETRY / MATERIAL (aluminum cladding, single uniform layer):
  nz=10, nx=3, Lz=0.6 m, Lx=0.00127 m (1.27 mm), y=0.07 m
  rho_s=2700, cp_s=900, k_s=200 W/mK
  power=1e4 W (10 kW), power_shape uniform (1/30 each cell)

CHANNEL GEOMETRY (both channels identical):
  Rectangular: edge1=0.07 m, edge2=0.00127 m, heated_edge=0.07 m, both faces heated.
  Dh = 4*area/wet_perimeter = 4*(0.07*0.00127) / (2*(0.07+0.00127)) ~= 0.002495 m
  L=0.6 m, n=10, dP=30 kPa, g=0 (horizontal), P_abs=1e5 Pa
"""

import sys
import os
from functools import partial
import numpy as np

STREAM_PATH = os.path.expanduser("~/projects/STREAM")
sys.path.insert(0, STREAM_PATH)

# ---------------------------------------------------------------
# Module-level constants
# ---------------------------------------------------------------
NZ, NX = 10, 3
LZ, LX, Y_LEN = 0.6, 0.00127, 0.07
POWER = 1e4
DP_PUMP = 3.0e4
P_ABS = 1.0e5
# D_H = 0.01  # OLD: circular approximation (incorrect)
# Correct MTR rectangular geometry: Dh = 4*area/wet_perimeter
# area = 0.07 * 0.00127 = 8.89e-5 m^2, wet = 2*(0.07+0.00127) = 0.14254 m, Dh ~= 0.002495 m

T_INLET_L_C = 40.0       # all scenarios left channel inlet (Celsius)
T_INLET_R_C = 40.0       # symmetric and one-sided right channel inlet (Celsius)
T_INLET_R_ASYM_C = 90.0  # asymmetric right channel inlet (Celsius)

T_INLET_L_K = T_INLET_L_C + 273.15
T_INLET_R_K = T_INLET_R_C + 273.15
T_INLET_R_ASYM_K = T_INLET_R_ASYM_C + 273.15

assert abs(T_INLET_L_K - 313.15) < 1e-9
assert abs(T_INLET_R_ASYM_K - 363.15) < 1e-9

from stream.calculations import Pump, HeatExchanger, Kirchhoff
from stream.calculations.channel import ChannelAndContacts
from stream.calculations.heat_diffusion import Fuel, Solid
from stream.composition.cycle import FlowGraph, flow_edge
from stream.composition.mtr_geometry import plate, one_sided_connection
from stream.aggregator import CalculationGraph
from stream.pipe_geometry import EffectivePipe
from stream.substances import light_water
from stream.jacobians import ALG_jacobian
from stream.physical_models.pressure_drop import pressure_diff

# ChannelVar enum -- required for tier (c) per-cell wall observable extraction.
# Two known import paths in Python STREAM HEAD versions; fall back gracefully.
try:
    from stream.calculations.channel import ChannelVar
    _CHANNELVAR_IMPORT_PATH = "stream.calculations.channel"
except ImportError:
    from stream.calculations.channel_vars import ChannelVar  # fallback path
    _CHANNELVAR_IMPORT_PATH = "stream.calculations.channel_vars"

# ---------------------------------------------------------------
# Shared component construction (built once, reused across scenarios)
# ---------------------------------------------------------------
material = Solid(density=2700.0, specific_heat=900.0, conductivity=200.0)

power_shape_np = np.ones((NZ, NX)) / (NZ * NX)
assert abs(power_shape_np.sum() - 1.0) < 1e-9, f"power_shape sum = {power_shape_np.sum()}"

z_bounds = np.linspace(0, LZ, NZ + 1)
x_bounds = np.linspace(0, LX, NX + 1)
# Correct MTR rectangular channel geometry matching Julia PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
# edge1=0.07 m (plate width), edge2=0.00127 m (channel gap), heated_edge=0.07 m (both faces)
# Dh = 4*(0.07*0.00127) / (2*(0.07+0.00127)) ~= 0.002495 m
pipe_ch = EffectivePipe.rectangular(
    length=LZ,
    edge1=Y_LEN,         # 0.07 m (plate width)
    edge2=LX,            # 0.00127 m (channel gap)
    heated_edge=Y_LEN,   # 0.07 m (plate width, both faces heated)
)


def _build_channel_and_loop(name_suffix: str, T_inlet_C: float):
    """Build a fresh Pump + HeatExchanger + ChannelAndContacts for one loop.

    Returns (pump, hx, channel, FlowGraph).
    Note: fresh objects per scenario -- Python STREAM components carry state.
    Each Kirchhoff node receives a unique name (via k_constructor) so that
    multiple FlowGraph aggregators can be combined without NonUniqueCalculationNameError.

    Verification: plate() / symmetric_plate() /
    one_sided_connection() all auto-wire T_left/T_right via _pair_connection
    graph edges; therefore funcs={channel: dict(p_abs=P_ABS)} is sufficient and
    NO T_left/T_right augmentation is needed for tier (c) twall_left/twall_right
    state-dict keys to populate.
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
        k_constructor=partial(Kirchhoff, name=f"Kirchhoff_{name_suffix}"),
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


def _hydraulic_guess(fg, pump, hx, channel, T_inlet_C: float, mdot_guess: float = 0.5) -> dict:
    """Build hydraulic initial guess for one loop using FlowGraph.guess_steady_state.

    Returns a state dict covering Kirchhoff, pump, HX, and channel hydraulic state.
    The channel thermal state (T_cool, h_left, h_right) is then augmented separately.
    """
    state = fg.guess_steady_state(
        mdots={pump: mdot_guess, hx: mdot_guess, channel: mdot_guess},
        temperature=T_inlet_C,
    )
    # Augment channel with thermal profile guess
    state[channel.name].update({
        "T_cool":  np.linspace(T_inlet_C, T_inlet_C + 10, NZ),
        "h_left":  1.5e4 * np.ones(NZ),
        "h_right": 1.5e4 * np.ones(NZ),
    })
    return state


def _fuel_guess(fuel, T_C: float) -> dict:
    """Build fuel initial state guess."""
    return {
        fuel.name: {
            "T": np.full((NZ, NX), T_C + 5.0),
            "T_wall_left": np.full(NZ, T_C + 3.0),
            "T_wall_right": np.full(NZ, T_C + 3.0),
        }
    }


def _solve_scenario(agr, state_guess, jac=True):
    """Solve steady state; return (sol_vec, state)."""
    guess_vec = agr.load(state_guess)
    jac_fn = ALG_jacobian(agr) if jac else None
    sol_vec = agr.solve_steady(guess_vec, jac=jac_fn)
    state = agr.save(sol_vec)
    return sol_vec, state


# ---------------------------------------------------------------
# Julia const-block emitter helpers
# ---------------------------------------------------------------

def _emit_julia_scalar(name: str, value: float, fmt: str = "%.10f"):
    print(f"const {name} = {fmt % value}")


def _emit_julia_array(name: str, values, fmt: str = "%.10f", comment_each: bool = False, comment_prefix: str = ""):
    """Emit a Julia const Float64[ ... ] array. One value per line."""
    print(f"const {name} = Float64[")
    if comment_each:
        for i, v in enumerate(values):
            print(f"    {fmt % v},  # {comment_prefix}[{i+1}]")
    else:
        for v in values:
            print(f"    {fmt % v},")
    print("]")
    print()


def _emit_julia_matrix(name: str, mat, fmt: str = "%.10f", row_comment: bool = True):
    """Emit a Julia const Float64[ ; ; ] matrix literal of shape (NZ, NX).

    Julia matrix-literal `;` row separator. Reading: PARITY_NAME[z, x] is row z, col x.
    Python `state[fuel.name]["T"]` is shape (NZ, NX) row-major; iterating
    `for z in range(NZ): row = mat[z, :]` and printing each row separated by `;`
    reproduces the exact (z, x) tuple-index parity in the Julia consumer.
    """
    print(f"const {name} = Float64[")
    nz_local, nx_local = mat.shape
    for z in range(nz_local):
        row_vals = " ".join(fmt % v for v in mat[z, :])
        comment = f";  # row z={z+1}" if row_comment else ";"
        print(f"    {row_vals}{comment}")
    print(f"]  # size ({nz_local}, {nx_local})")
    print()


# ---------------------------------------------------------------
# Symmetric MTR: plate() with both channels at 40 C
# ---------------------------------------------------------------
print("Running Symmetric coupling...")
pump_l_01, hx_l_01, ch_l_01, fg_l_01 = _build_channel_and_loop("L_01", T_INLET_L_C)
pump_r_01, hx_r_01, ch_r_01, fg_r_01 = _build_channel_and_loop("R_01", T_INLET_R_C)
fuel_01 = _build_fuel("Fuel_01")

plate_cg_01 = plate(ch_l_01, ch_r_01, fuel_01)
power_cg_01 = CalculationGraph.from_decoupled(fuel_01, funcs={fuel_01: dict(power=POWER)})

agr_01 = fg_l_01.aggregator + fg_r_01.aggregator + plate_cg_01 + power_cg_01
K_l_01 = fg_l_01.kirchhoff
K_r_01 = fg_r_01.kirchhoff

guess_01 = {
    **_hydraulic_guess(fg_l_01, pump_l_01, hx_l_01, ch_l_01, T_INLET_L_C),
    **_hydraulic_guess(fg_r_01, pump_r_01, hx_r_01, ch_r_01, T_INLET_R_C),
    **_fuel_guess(fuel_01, T_INLET_L_C),
}
sol_vec_01, state_01 = _solve_scenario(agr_01, guess_01)

T_outlet_l_K_sym = state_01[ch_l_01.name]["T_cool"][-1] + 273.15
T_outlet_r_K_sym = state_01[ch_r_01.name]["T_cool"][-1] + 273.15
mdot_l_sym = abs(state_01[K_l_01.name][K_l_01.component_edge(pump_l_01)])
mdot_r_sym = abs(state_01[K_r_01.name][K_r_01.component_edge(pump_r_01)])
T_plate_sym = state_01[fuel_01.name]["T"]  # (NZ, NX) in Celsius
T_plate_center_K_sym = T_plate_sym[NZ // 2][NX // 2] + 273.15

# Sanity assertions
assert T_outlet_l_K_sym > T_INLET_L_K, f"symmetric: T_outlet_l {T_outlet_l_K_sym:.2f} K below inlet"
assert T_outlet_r_K_sym > T_INLET_R_K, f"symmetric: T_outlet_r {T_outlet_r_K_sym:.2f} K below inlet"
assert mdot_l_sym > 1e-4, f"symmetric: mdot_l {mdot_l_sym:.4f} kg/s too small"
assert mdot_r_sym > 1e-4, f"symmetric: mdot_r {mdot_r_sym:.4f} kg/s too small"
assert T_plate_center_K_sym > T_INLET_L_K, f"symmetric: T_plate_center below inlet"
# Symmetry: both channels should be nearly identical (<1% relative diff in T_outlet)
assert abs(T_outlet_l_K_sym - T_outlet_r_K_sym) / T_outlet_l_K_sym < 0.01, (
    f"symmetric: T_outlet asymmetry = {abs(T_outlet_l_K_sym - T_outlet_r_K_sym):.4f} K -- expected symmetric"
)

# --- Symmetric: per-cell extraction (tier b/c/d) ---
ch_l_01_state = state_01[ch_l_01.name]
ch_r_01_state = state_01[ch_r_01.name]

T_cells_l_K_sym = [T + 273.15 for T in ch_l_01_state["T_cool"]]
T_cells_r_K_sym = [T + 273.15 for T in ch_r_01_state["T_cool"]]

# tier (c) -- correction:
#
# An earlier version assumed plate() auto-wires BOTH T_left AND T_right into
# each channel via _pair_connection graph edges. That was wrong. The actual
# plate() topology is (stream/composition/mtr_geometry.py:38-66):
#
#     (channel_l, fuel, vars_("T_left", "h_left"))    # ch_L sends T_left/h_left to fuel
#     (channel_r, fuel, vars_("T_right", "h_right"))  # ch_R sends T_right/h_right to fuel
#     (fuel, channel_l, vars_("T_right",))            # fuel -> ch_L's T_RIGHT only
#     (fuel, channel_r, vars_("T_left",))             # fuel -> ch_R's T_LEFT only
#
# The "outer" face of each channel is unconnected -- it's adiabatic by
# construction (no heat source on that side). Per channel.py:628 the
# state[ChannelVar.twall_X] key only exists when wall_temp is not None,
# so the adiabatic side has NO twall/heatflux key in the state dict.
#
# Physical mapping:
#   channel_L: thermally-connected wall = RIGHT (faces fuel plate); LEFT is adiabatic
#   channel_R: thermally-connected wall = LEFT  (faces fuel plate); RIGHT is adiabatic
#
# Adiabatic-wall convention for the emitted reference values (matches the
# Julia steady-state solution under MTK's default zero-flux BC on
# unconnected thermal ports):
#   T_wall_adiabatic = T_cool (zero net flux <=> wall in equilibrium with bulk)
#   q_density_adiabatic = 0
#   h_adiabatic mirrors the connected side (Python's _other_if_none, used
#                in channel.py:691 for the calculate-time HTC, returns the
#                same h on both sides; we keep that convention here).
T_wall_right_l_sym = [T + 273.15 for T in ch_l_01_state[ChannelVar.twall_right]]
h_left_l_sym       = list(ch_l_01_state[ChannelVar.h_left])
h_right_l_sym      = list(ch_l_01_state[ChannelVar.h_right])
q_right_l_sym      = list(ch_l_01_state[ChannelVar.heatflux_right])
# adiabatic LEFT wall of channel_L
T_wall_left_l_sym  = list(T_cells_l_K_sym)        # T_wall = T_cool, in Kelvin
q_left_l_sym       = [0.0] * NZ                   # zero heat flux

T_wall_left_r_sym  = [T + 273.15 for T in ch_r_01_state[ChannelVar.twall_left]]
h_left_r_sym       = list(ch_r_01_state[ChannelVar.h_left])
h_right_r_sym      = list(ch_r_01_state[ChannelVar.h_right])
q_left_r_sym       = list(ch_r_01_state[ChannelVar.heatflux_left])
# adiabatic RIGHT wall of channel_R
T_wall_right_r_sym = list(T_cells_r_K_sym)
q_right_r_sym      = [0.0] * NZ

# tier (d) -- plate-side T(z,x), Celsius -> Kelvin via numpy broadcast
T_plate_K_sym = state_01[fuel_01.name]["T"] + 273.15  # shape (NZ, NX)
assert not np.isnan(T_plate_K_sym).any(), "symmetric plate has NaN -- scipy 'success' with NaN"

print("  symmetric OK")

# ---------------------------------------------------------------
# Asymmetric MTR: right channel HX outlet = 90 C
# ---------------------------------------------------------------
print("Running Asymmetric coupling (right channel 90 C)...")
pump_l_02, hx_l_02, ch_l_02, fg_l_02 = _build_channel_and_loop("L_02", T_INLET_L_C)
pump_r_02, hx_r_02, ch_r_02, fg_r_02 = _build_channel_and_loop("R_02", T_INLET_R_ASYM_C)
fuel_02 = _build_fuel("Fuel_02")

plate_cg_02 = plate(ch_l_02, ch_r_02, fuel_02)
power_cg_02 = CalculationGraph.from_decoupled(fuel_02, funcs={fuel_02: dict(power=POWER)})

agr_02 = fg_l_02.aggregator + fg_r_02.aggregator + plate_cg_02 + power_cg_02
K_l_02 = fg_l_02.kirchhoff
K_r_02 = fg_r_02.kirchhoff

T_plate_avg_C = (T_INLET_L_C + T_INLET_R_ASYM_C) / 2  # 65 C
T_plate_02 = np.full((NZ, NX), T_plate_avg_C + 2.0)   # 67 C uniform
guess_02 = {
    **_hydraulic_guess(fg_l_02, pump_l_02, hx_l_02, ch_l_02, T_INLET_L_C),
    **_hydraulic_guess(fg_r_02, pump_r_02, hx_r_02, ch_r_02, T_INLET_R_ASYM_C),
    fuel_02.name: {
        "T": T_plate_02,
        "T_wall_left":  np.full(NZ, T_plate_avg_C + 2.0),  # ~67 C
        "T_wall_right": np.full(NZ, T_plate_avg_C + 2.0),  # ~67 C
    },
}

sol_vec_02, state_02 = _solve_scenario(agr_02, guess_02)

T_outlet_l_K_asym = state_02[ch_l_02.name]["T_cool"][-1] + 273.15
T_outlet_r_K_asym = state_02[ch_r_02.name]["T_cool"][-1] + 273.15
mdot_l_asym = abs(state_02[K_l_02.name][K_l_02.component_edge(pump_l_02)])
mdot_r_asym = abs(state_02[K_r_02.name][K_r_02.component_edge(pump_r_02)])

T_plate_asym = state_02[fuel_02.name]["T"]  # (NZ, NX) in Celsius
T_plate_center_K_asym = T_plate_asym[NZ // 2][NX // 2] + 273.15

# Asymmetry assertion: right side of plate (x-index NX-1=2) should be hotter than left (x-index 0)
# because right channel is at 90 C vs 40 C on the left
assert T_plate_asym[NZ // 2][NX - 1] > T_plate_asym[NZ // 2][0], (
    f"asymmetric: Expected T_plate right > left; got right={T_plate_asym[NZ//2][NX-1]:.2f} C, "
    f"left={T_plate_asym[NZ//2][0]:.2f} C"
)

# --- Asymmetric: per-cell extraction (tier b/c/d) ---
ch_l_02_state = state_02[ch_l_02.name]
ch_r_02_state = state_02[ch_r_02.name]

T_cells_l_K_asym = [T + 273.15 for T in ch_l_02_state["T_cool"]]
T_cells_r_K_asym = [T + 273.15 for T in ch_r_02_state["T_cool"]]

# tier (c) -- same plate() topology as symmetric: ch_L's RIGHT wall and
# ch_R's LEFT wall are connected to the fuel; opposite walls are adiabatic.
# See symmetric block above for the API discovery / convention rationale.
T_wall_right_l_asym = [T + 273.15 for T in ch_l_02_state[ChannelVar.twall_right]]
h_left_l_asym       = list(ch_l_02_state[ChannelVar.h_left])
h_right_l_asym      = list(ch_l_02_state[ChannelVar.h_right])
q_right_l_asym      = list(ch_l_02_state[ChannelVar.heatflux_right])
T_wall_left_l_asym  = list(T_cells_l_K_asym)
q_left_l_asym       = [0.0] * NZ

T_wall_left_r_asym  = [T + 273.15 for T in ch_r_02_state[ChannelVar.twall_left]]
h_left_r_asym       = list(ch_r_02_state[ChannelVar.h_left])
h_right_r_asym      = list(ch_r_02_state[ChannelVar.h_right])
q_left_r_asym       = list(ch_r_02_state[ChannelVar.heatflux_left])
T_wall_right_r_asym = list(T_cells_r_K_asym)
q_right_r_asym      = [0.0] * NZ

T_plate_K_asym = state_02[fuel_02.name]["T"] + 273.15
assert not np.isnan(T_plate_K_asym).any(), "asymmetric plate has NaN"

print("  asymmetric OK")

# ---------------------------------------------------------------
# One-sided MTR: left face only, right adiabatic
# ---------------------------------------------------------------
print("Running One-sided coupling (left face only)...")
pump_l_03, hx_l_03, ch_l_03, fg_l_03 = _build_channel_and_loop("L_03", T_INLET_L_C)
fuel_03 = _build_fuel("Fuel_03")

onesided_cg_03 = one_sided_connection(ch_l_03, fuel_03, fuel_side="left")
power_cg_03 = CalculationGraph.from_decoupled(fuel_03, funcs={fuel_03: dict(power=POWER)})

agr_03 = fg_l_03.aggregator + onesided_cg_03 + power_cg_03
K_l_03 = fg_l_03.kirchhoff

guess_03 = {
    **_hydraulic_guess(fg_l_03, pump_l_03, hx_l_03, ch_l_03, T_INLET_L_C, mdot_guess=0.5),
    **_fuel_guess(fuel_03, T_INLET_L_C),
}

sol_vec_03, state_03 = _solve_scenario(agr_03, guess_03)

T_outlet_l_K_onesided = state_03[ch_l_03.name]["T_cool"][-1] + 273.15
mdot_l_onesided = abs(state_03[K_l_03.name][K_l_03.component_edge(pump_l_03)])
T_plate_onesided = state_03[fuel_03.name]["T"]  # (NZ, NX) in Celsius
T_plate_center_K_onesided = T_plate_onesided[NZ // 2][NX // 2] + 273.15

assert T_outlet_l_K_onesided > T_INLET_L_K, (
    f"one-sided: T_outlet {T_outlet_l_K_onesided:.2f} K below inlet"
)
assert mdot_l_onesided > 1e-4, f"one-sided: mdot {mdot_l_onesided:.4f} kg/s too small"

# --- One-sided: only left channel exists (no right loop) ---
ch_l_03_state = state_03[ch_l_03.name]
T_cells_l_K_onesided = [T + 273.15 for T in ch_l_03_state["T_cool"]]

# tier (c) -- one_sided_connection(fuel_side="left") wires ONLY the channel's
# LEFT wall to the fuel (mtr_geometry.py:198: fuel_var = "T_left"). The
# RIGHT wall is adiabatic, so state[twall_right] / state[heatflux_right] do
# not exist. See symmetric block for the adiabatic-wall convention rationale.
T_wall_left_l_os  = [T + 273.15 for T in ch_l_03_state[ChannelVar.twall_left]]
h_left_l_os       = list(ch_l_03_state[ChannelVar.h_left])
h_right_l_os      = list(ch_l_03_state[ChannelVar.h_right])
q_left_l_os       = list(ch_l_03_state[ChannelVar.heatflux_left])
T_wall_right_l_os = list(T_cells_l_K_onesided)
q_right_l_os      = [0.0] * NZ

# tier (d) -- plate T(z,x). one_sided_connection is an edge-channel reduced model:
# the channel is heated on its connected face only, but the plate is cooled on BOTH
# faces (the far face by the channel's connected-side h via _other_if_none, into an
# unmodelled equivalent twin). Julia reproduces this with single_channel_connection,
# so the plate-T matches this reference at normal tolerance.
T_plate_K_onesided = state_03[fuel_03.name]["T"] + 273.15
assert not np.isnan(T_plate_K_onesided).any(), "one-sided plate has NaN"

print("  one-sided OK")

# ---------------------------------------------------------------
# Emit ready-to-paste Julia const blocks
# ---------------------------------------------------------------
print()
print("=" * 72)
print("Python parity reference -- MTR (3 variants)")
print("Generated by test/generate_mtr_reference.py -- DO NOT EDIT BY HAND")
print("Regenerate with: cd test && python3 generate_mtr_reference.py")
print(f"ChannelVar imported from: {_CHANNELVAR_IMPORT_PATH}")
print("=" * 72)
print()

# Block 0: shared rectangular geometry (used by all 3 MTR scenarios for assert_equivalence_geometry)
print("# --- begin paste: test/data/python_parity_reference.jl MTR geometry ---")
print(f"# Rectangular MTR: L={LZ}, edge1={Y_LEN}, edge2={LX}, heated_edge={Y_LEN}")
print(f"# Computed: Dh = 4*area/wet_perim ~= 0.002495 m; both faces heated.")
_emit_julia_scalar("PARITY_MTR_GEOM_DH",       pipe_ch.hydraulic_diameter, "%.10e")
_emit_julia_scalar("PARITY_MTR_GEOM_AREA",     pipe_ch.area,          "%.10e")
_emit_julia_scalar("PARITY_MTR_GEOM_WETPERIM", pipe_ch.wet_perimeter, "%.10e")
print(f"const PARITY_MTR_GEOM_HEATED = ({pipe_ch.heated_parts[0]:.10e}, {pipe_ch.heated_parts[1]:.10e})")
print("# --- end paste: MTR geometry ---")
print()

# Block 1: Symmetric scenario
print("# --- begin paste: test/data/python_parity_reference.jl MTR symmetric ---")
print(f"# Symmetric MTR: T_inlet_l = T_inlet_r = {T_INLET_L_K} K; power = {POWER} W")
_emit_julia_scalar("PARITY_MTR_SYM_T_OUT_L", T_outlet_l_K_sym)
_emit_julia_scalar("PARITY_MTR_SYM_T_OUT_R", T_outlet_r_K_sym)
_emit_julia_scalar("PARITY_MTR_SYM_MDOT_L",  mdot_l_sym)
_emit_julia_scalar("PARITY_MTR_SYM_MDOT_R",  mdot_r_sym)
_emit_julia_scalar("PARITY_MTR_SYM_DP",      DP_PUMP)
print()
_emit_julia_array("PARITY_MTR_SYM_T_CELLS_L",      T_cells_l_K_sym, comment_each=True, comment_prefix="T_l")
_emit_julia_array("PARITY_MTR_SYM_T_CELLS_R",      T_cells_r_K_sym, comment_each=True, comment_prefix="T_r")
_emit_julia_array("PARITY_MTR_SYM_T_WALL_LEFT_L",  T_wall_left_l_sym)
_emit_julia_array("PARITY_MTR_SYM_T_WALL_RIGHT_L", T_wall_right_l_sym)
_emit_julia_array("PARITY_MTR_SYM_H_TC_LEFT_L",    h_left_l_sym)
_emit_julia_array("PARITY_MTR_SYM_H_TC_RIGHT_L",   h_right_l_sym)
_emit_julia_array("PARITY_MTR_SYM_Q_LEFT_L",       q_left_l_sym)   # W/m^2
_emit_julia_array("PARITY_MTR_SYM_Q_RIGHT_L",      q_right_l_sym)
_emit_julia_array("PARITY_MTR_SYM_T_WALL_LEFT_R",  T_wall_left_r_sym)
_emit_julia_array("PARITY_MTR_SYM_T_WALL_RIGHT_R", T_wall_right_r_sym)
_emit_julia_array("PARITY_MTR_SYM_H_TC_LEFT_R",    h_left_r_sym)
_emit_julia_array("PARITY_MTR_SYM_H_TC_RIGHT_R",   h_right_r_sym)
_emit_julia_array("PARITY_MTR_SYM_Q_LEFT_R",       q_left_r_sym)
_emit_julia_array("PARITY_MTR_SYM_Q_RIGHT_R",      q_right_r_sym)
_emit_julia_matrix("PARITY_MTR_SYM_T_PLATE",       T_plate_K_sym)  # (NZ, NX)
print("# --- end paste: MTR symmetric ---")
print()

# Block 2: Asymmetric scenario (right channel inlet 363.15 K = 90 C)
print("# --- begin paste: test/data/python_parity_reference.jl MTR asymmetric ---")
print(f"# Asymmetric MTR: T_inlet_l = {T_INLET_L_K} K, T_inlet_r = {T_INLET_R_ASYM_K} K")
_emit_julia_scalar("PARITY_MTR_ASYM_T_OUT_L", T_outlet_l_K_asym)
_emit_julia_scalar("PARITY_MTR_ASYM_T_OUT_R", T_outlet_r_K_asym)
_emit_julia_scalar("PARITY_MTR_ASYM_MDOT_L",  mdot_l_asym)
_emit_julia_scalar("PARITY_MTR_ASYM_MDOT_R",  mdot_r_asym)
_emit_julia_scalar("PARITY_MTR_ASYM_DP",      DP_PUMP)
print()
_emit_julia_array("PARITY_MTR_ASYM_T_CELLS_L",      T_cells_l_K_asym, comment_each=True, comment_prefix="T_l")
_emit_julia_array("PARITY_MTR_ASYM_T_CELLS_R",      T_cells_r_K_asym, comment_each=True, comment_prefix="T_r")
_emit_julia_array("PARITY_MTR_ASYM_T_WALL_LEFT_L",  T_wall_left_l_asym)
_emit_julia_array("PARITY_MTR_ASYM_T_WALL_RIGHT_L", T_wall_right_l_asym)
_emit_julia_array("PARITY_MTR_ASYM_H_TC_LEFT_L",    h_left_l_asym)
_emit_julia_array("PARITY_MTR_ASYM_H_TC_RIGHT_L",   h_right_l_asym)
_emit_julia_array("PARITY_MTR_ASYM_Q_LEFT_L",       q_left_l_asym)
_emit_julia_array("PARITY_MTR_ASYM_Q_RIGHT_L",      q_right_l_asym)
_emit_julia_array("PARITY_MTR_ASYM_T_WALL_LEFT_R",  T_wall_left_r_asym)
_emit_julia_array("PARITY_MTR_ASYM_T_WALL_RIGHT_R", T_wall_right_r_asym)
_emit_julia_array("PARITY_MTR_ASYM_H_TC_LEFT_R",    h_left_r_asym)
_emit_julia_array("PARITY_MTR_ASYM_H_TC_RIGHT_R",   h_right_r_asym)
_emit_julia_array("PARITY_MTR_ASYM_Q_LEFT_R",       q_left_r_asym)
_emit_julia_array("PARITY_MTR_ASYM_Q_RIGHT_R",      q_right_r_asym)
_emit_julia_matrix("PARITY_MTR_ASYM_T_PLATE",       T_plate_K_asym)
print("# --- end paste: MTR asymmetric ---")
print()

# Block 3: One-sided scenario (left channel only)
print("# --- begin paste: test/data/python_parity_reference.jl MTR one-sided ---")
print(f"# One-sided MTR: only left channel; T_inlet_l = {T_INLET_L_K} K")
print(f"# Edge-channel reduced model: channel heated on its connected face only, plate cooled")
print(f"# on BOTH faces (far face via the connected-side h, into an unmodelled equivalent twin).")
print(f"# Julia reproduces this with single_channel_connection; all rows match at normal tolerance.")
_emit_julia_scalar("PARITY_MTR_ONESIDED_T_OUT_L", T_outlet_l_K_onesided)
_emit_julia_scalar("PARITY_MTR_ONESIDED_MDOT_L",  mdot_l_onesided)
_emit_julia_scalar("PARITY_MTR_ONESIDED_DP",      DP_PUMP)
print()
_emit_julia_array("PARITY_MTR_ONESIDED_T_CELLS_L",      T_cells_l_K_onesided, comment_each=True, comment_prefix="T_l")
_emit_julia_array("PARITY_MTR_ONESIDED_T_WALL_LEFT_L",  T_wall_left_l_os)
_emit_julia_array("PARITY_MTR_ONESIDED_T_WALL_RIGHT_L", T_wall_right_l_os)
_emit_julia_array("PARITY_MTR_ONESIDED_H_TC_LEFT_L",    h_left_l_os)
_emit_julia_array("PARITY_MTR_ONESIDED_H_TC_RIGHT_L",   h_right_l_os)
_emit_julia_array("PARITY_MTR_ONESIDED_Q_LEFT_L",       q_left_l_os)
_emit_julia_array("PARITY_MTR_ONESIDED_Q_RIGHT_L",      q_right_l_os)
_emit_julia_matrix("PARITY_MTR_ONESIDED_T_PLATE",       T_plate_K_onesided)
print("# --- end paste: MTR one-sided ---")
print()
print("=" * 72)
print("Diagnostics (NOT pasted -- for human inspection only)")
print("=" * 72)
print(f"  SYM:      T_out_l = {T_outlet_l_K_sym:.4f} K, mdot_l = {mdot_l_sym:.6f} kg/s, T_plate_center = {T_plate_K_sym[NZ//2, NX//2]:.4f} K")
print(f"  ASYM:     T_out_l = {T_outlet_l_K_asym:.4f} K, T_out_r = {T_outlet_r_K_asym:.4f} K, T_plate_center = {T_plate_K_asym[NZ//2, NX//2]:.4f} K")
print(f"  ONESIDED: T_out_l = {T_outlet_l_K_onesided:.4f} K (edge-channel, plate cooled both faces), T_plate_center = {T_plate_K_onesided[NZ//2, NX//2]:.4f} K")
