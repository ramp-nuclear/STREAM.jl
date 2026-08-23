#!/usr/bin/env python3
"""
generate_reference.py -- Python STREAM cross-validation reference generator.

Run ONCE to obtain the simple-loop reference values for the parity testset:
  cd /home/itay/projects/Julia-STREAM/test && python3 generate_reference.py

Requires Python STREAM at ~/projects/STREAM (override via STREAM_PYTHON_PATH).


  This script is NOT in CI. It is invoked by hand at reference-update time only
 .

OUTPUT (tiers a + b + c for simple loop):
  Two pasteable const blocks, each bracketed by '# --- begin paste ---' /
  '# --- end paste ---' markers.

  Block 1 — equivalence-checklist constants for test/parity_helpers.jl:
    PYTHON_RHO_AT_REF, PYTHON_CP_AT_REF, PYTHON_MU_AT_REF, PYTHON_K_AT_REF
    (each a 3-tuple at REF_T_C = (40.0, 70.0, 100.0) degC).

  Block 2 — simple-loop reference const block for test/data/python_parity_reference.jl:
    Tier (a) scalars:
      PARITY_SIMPLE_T_OUT, PARITY_SIMPLE_MDOT, PARITY_SIMPLE_DP
    Tier (b) per-cell coolant:
      PARITY_SIMPLE_T_CELLS                 (Float64[N])
    Tier (c) per-cell CAC wall observables:
      PARITY_SIMPLE_T_WALL_LEFT             (Float64[N])
      PARITY_SIMPLE_T_WALL_RIGHT            (Float64[N])
      PARITY_SIMPLE_H_TC_LEFT               (Float64[N], W/m^2/K)
      PARITY_SIMPLE_H_TC_RIGHT              (Float64[N], W/m^2/K)
      PARITY_SIMPLE_Q_DENSITY_LEFT          (Float64[N], W/m^2)
      PARITY_SIMPLE_Q_DENSITY_RIGHT         (Float64[N], W/m^2)

    Both _LEFT and _RIGHT q constants are required so the Julia side can SUM them
    (Gap #1 mitigation: Python emits q on πD-LEFT and 0-RIGHT for one-sided
    heating; Julia splits πD/2 each side; LEFT+RIGHT totals match).

UNIT CONVENTION:
  Both sides use CELSIUS for temperatures and W/m^2 for heat flux density,
  so temperatures are emitted as-is with no conversion.

PHYSICS / TOPOLOGY:
  Pump → HeatExchanger(40°C) → ChannelAndContacts → back to Pump

  ChannelAndContacts (NOT plain Channel) is mandatory: tier (c) wall
  observables (twall_left/right, h_left/right, heatflux_left/right) are
  CAC-only state-dict keys. Note: T_left/T_right MUST be passed in
  funcs={...} so save() emits the wall-temperature keys (channel.py:628).

  HeatExchanger pins inlet T to 40°C (equivalent to Julia's TempBC).
  ChannelAndContacts computes Dittus-Boelter HTC and Darcy-Weisbach friction
  internally. Julia Channel computes friction internally too — no separate
  Friction component in either.

  Parameters matching Julia-STREAM build_loop() defaults:
    - Pump: dP = 30 kPa
    - Channel: n=10, L=0.6m, D=0.01m
    - T_wall = 373.15 K = 100 C  (T_left = T_right = 100 C, symmetric circular pipe)
    - T_inlet = 313.15 K = 40 C
    - Horizontal loop: g=0 (Julia Channel.g_acc=0 default)
    - Absolute pressure reference: 1e5 Pa
"""

import sys
import os
from functools import partial
import numpy as np

STREAM_PATH = os.environ.get(
    "STREAM_PYTHON_PATH",
    os.path.expanduser("~/projects/STREAM"),
)
sys.path.insert(0, STREAM_PATH)

# Unit conversion checks
T_INLET_C = 40.0
T_WALL_C  = 100.0

# Parameters matching Julia-STREAM build_loop() defaults
N       = 10
L_CH    = 0.6
D_H     = 0.01
DP_PUMP = 3.0e4
P_ABS   = 1.0e5

# Equivalence-checklist reference values (fluid-props tier).
# parity_helpers.jl asserts these against Julia's rho/cp/etc.
# at 1e-12 rtol. REF_T_C must match parity_helpers.jl's REF_T_C exactly.
REF_T_C = (40.0, 70.0, 100.0)

from stream.calculations import Pump, HeatExchanger
from stream.calculations.channel import ChannelAndContacts
from stream.composition.cycle import FlowGraph, flow_edge
from stream.pipe_geometry import EffectivePipe
from stream.substances import light_water
from stream.jacobians import ALG_jacobian
from stream.physical_models.pressure_drop import pressure_diff

# ChannelVar enum — the import path has moved across Python STREAM revisions.
# Try the most-likely paths first; record which branch fired so this script
# can document the working path. Extend this chain if a future
# revision moves it again.
_CHANNELVAR_IMPORT_PATH = None
try:
    from stream.calculations.channel import ChannelVar  # current main, verified during planning
    _CHANNELVAR_IMPORT_PATH = "stream.calculations.channel.ChannelVar"
except ImportError:
    try:
        from stream.calculations.channel_vars import ChannelVar  # plausible refactor target
        _CHANNELVAR_IMPORT_PATH = "stream.calculations.channel_vars.ChannelVar"
    except ImportError:
        try:
            from stream.calculations.variables import ChannelVar  # alt refactor target
            _CHANNELVAR_IMPORT_PATH = "stream.calculations.variables.ChannelVar"
        except ImportError as e:
            raise ImportError(
                "ChannelVar not found in any of:\n"
                "  stream.calculations.channel\n"
                "  stream.calculations.channel_vars\n"
                "  stream.calculations.variables\n"
                "Locate the enum in your Python STREAM checkout and extend "
                "the try/except chain in test/generate_reference.py."
            ) from e


# Julia-const printers
def _emit_julia_array(name, values, fmt="%.10f", comment_each=False, comment_prefix=""):
    """Emit a Julia const Float64[ ... ] array. One value per line if comment_each."""
    print(f"const {name} = Float64[")
    if comment_each:
        for i, v in enumerate(values):
            print(f"    {fmt % v},  # {comment_prefix}[{i+1}]")
    else:
        for v in values:
            print(f"    {fmt % v},")
    print("]")
    print()


def _emit_julia_scalar(name, value, fmt="%.10f"):
    print(f"const {name} = {fmt % value}")


def _emit_julia_tuple3(name, values, fmt="%.10f"):
    """Emit a Julia const NTuple{3, Float64} for the 3 REF_T_C values."""
    formatted = ", ".join(fmt % v for v in values)
    print(f"const {name} = ({formatted})")


# Build topology
pipe_ch = EffectivePipe.circular(length=L_CH, diameter=D_H)

pump = Pump(pressure=DP_PUMP)

# HeatExchanger pins coolant temperature to T_inlet at the pump outlet.
# Equivalent to Julia-STREAM's TempBC component which resets fluid to T_inlet
# before it enters the heated channel, breaking the circular thermal dependency.
hx = HeatExchanger(outlet=T_INLET_C, name="HX")

# ChannelAndContacts (MUST be CAC for tier-(c) wall observables;
# do NOT change to Channel). Computes Dittus-Boelter HTC self-consistently
# from flow. Friction is included via pressure_diff (Darcy-Weisbach).
# g=0 matches Julia build_loop() Channel default (no gravity term).
# T_left=T_right=T_wall: symmetric heating matches Julia's single thermal.T port
# (h_tc[i] * pi*D * dz * (T_wall - T[i])) on a circular pipe.
channel = ChannelAndContacts(
    z_boundaries=np.linspace(0, L_CH, N + 1),
    fluid=light_water,
    pipe=pipe_ch,
    pressure_func=partial(pressure_diff, g=0),
    name="Channel",
)

# FlowGraph: Pump+HX on forward edge, Channel on return edge.
# reference_node pins absolute pressure at "A" (matches Julia: pump.port_in.P ~ 1e5).
# T_left/T_right MUST be set so save() emits ChannelVar.twall_*
# keys (channel.py:628 conditional). Both are set here.
fg = FlowGraph(
    flow_edge(("A", "B"), pump, hx),
    flow_edge(("B", "A"), channel),
    funcs={
        channel: dict(
            T_left=T_WALL_C,
            T_right=T_WALL_C,
            p_abs=P_ABS,
        ),
    },
    reference_node=("A", P_ABS),
    abs_pressure_comps=[channel],
)

agr = fg.aggregator
K   = fg.kirchhoff

try:
    fg.check_gravity_mismatch()
except Exception as e:
    print(f"WARNING gravity check: {e}", file=sys.stderr)

# Initial guess
mdot_guess = 0.5
guess = fg.guess_steady_state(
    mdots={pump: mdot_guess, hx: mdot_guess, channel: mdot_guess},
    temperature=T_INLET_C,
)
# Augment with ChannelAndContacts thermal state (T_cool, h_left, h_right)
guess[channel.name].update({
    "T_cool":  np.linspace(T_INLET_C, T_INLET_C + 13, N),
    "h_left":  1.5e4 * np.ones(N),
    "h_right": 1.5e4 * np.ones(N),
})

guess_vec = agr.load(guess)
sol_vec   = agr.solve_steady(guess_vec, jac=ALG_jacobian(agr))
state     = agr.save(sol_vec)


# Extract all tiers from solver state
ch_state = state[channel.name]

# Tier (a): scalars
T_out_C  = ch_state["T_cool"][-1]

mdot     = abs(state[K.name][K.component_edge(pump)])
DP_total = DP_PUMP   # closed loop steady state: sum of dp ≡ pump dP

# Sanity (preserve existing assertions on T_out + mdot)
assert T_out_C > T_INLET_C, f"T_out {T_out_C:.2f} degC below inlet"
assert T_out_C < 180.0,     f"T_out {T_out_C:.2f} degC unreasonably high"
assert mdot > 1e-4,         f"mdot {mdot:.4f} kg/s too small"

# Tier (b): per-cell coolant T[i]
T_cells_C = [float(T_C) for T_C in ch_state["T_cool"]]
assert len(T_cells_C) == N, f"expected {N} cells, got {len(T_cells_C)}"

# Tier (c): per-cell wall observables. correction:
#
# state[ChannelVar.twall_left] / twall_right echo back EXACTLY whatever was
# passed in via funcs={channel: dict(T_left=..., T_right=...)} — see
# stream/calculations/channel.py:628-629
#     if wall_temp is not None:
#         state[ChannelVar.get("twall", direction)] = wall_temp
# When `wall_temp` is the SCALAR T_WALL_C=100.0 (as in the simple-loop's
# constant-temperature BC), the state stores the scalar verbatim — NOT a
# per-cell array. An earlier version `[T for T in scalar]`
# crashed with `TypeError: 'float' object is not iterable`.
#
# Physical interpretation: the simple-loop wall is fixed at T_WALL_C on
# every cell by construction (the funcs dict supplies a scalar BC), so
# the per-cell array is just T_WALL_C replicated N times. h_left/h_right
# and heatflux_left/heatflux_right ARE genuine per-cell arrays — they're
# computed from the cell-varying coolant temperature.
twall_left_raw  = ch_state[ChannelVar.twall_left]
twall_right_raw = ch_state[ChannelVar.twall_right]
T_wall_left_C  = (
    [float(twall_left_raw)] * N
    if np.ndim(twall_left_raw) == 0
    else [float(T_C) for T_C in twall_left_raw]
)
T_wall_right_C = (
    [float(twall_right_raw)] * N
    if np.ndim(twall_right_raw) == 0
    else [float(T_C) for T_C in twall_right_raw]
)
h_left  = [float(v) for v in ch_state[ChannelVar.h_left]]    # W/(m²·K)
h_right = [float(v) for v in ch_state[ChannelVar.h_right]]
q_density_left  = [float(v) for v in ch_state[ChannelVar.heatflux_left]]   # W/m²
q_density_right = [float(v) for v in ch_state[ChannelVar.heatflux_right]]  # W/m²

assert len(T_wall_left_C)  == N, f"expected {N} T_wall_left cells, got {len(T_wall_left_C)}"
assert len(T_wall_right_C) == N, f"expected {N} T_wall_right cells, got {len(T_wall_right_C)}"
assert len(h_left)         == N, f"expected {N} h_left cells, got {len(h_left)}"
assert len(h_right)        == N, f"expected {N} h_right cells, got {len(h_right)}"
assert len(q_density_left) == N, f"expected {N} q_left cells, got {len(q_density_left)}"
assert len(q_density_right)== N, f"expected {N} q_right cells, got {len(q_density_right)}"

# Tier (d): N/A for simple loop — no plate.

# Equivalence-checklist values: rho/cp/mu/k at REF_T_C. light_water.* take CELSIUS.
ref_T_C    = list(REF_T_C)
rho_at_ref = tuple(float(light_water.density(T))       for T in ref_T_C)
cp_at_ref  = tuple(float(light_water.specific_heat(T)) for T in ref_T_C)
mu_at_ref  = tuple(float(light_water.viscosity(T))     for T in ref_T_C)
k_at_ref   = tuple(float(light_water.conductivity(T))  for T in ref_T_C)


# Emit ready-to-paste Julia const blocks
print()
print("=" * 72)
print("Python parity reference — SIMPLE LOOP")
print("Generated by test/generate_reference.py — DO NOT EDIT BY HAND")
print("Regenerate with: cd test && python3 generate_reference.py")
print(f"ChannelVar import path used: {_CHANNELVAR_IMPORT_PATH}")
print("=" * 72)
print()

# Block 1: equivalence-checklist constants for test/parity_helpers.jl
print("# --- begin paste: parity_helpers.jl REF constants ---")
print("# Paste over the four PYTHON_*_AT_REF lines marked REGENERATE in test/parity_helpers.jl")
print(f"# REF_T_C = {REF_T_C} (Celsius); light_water.* called directly.")
# %.17g for full float64 round-trip precision: 1e-12 rtol equivalence checklist
# requires 17 significant digits or values disagree at parse boundary.
_emit_julia_tuple3("PYTHON_RHO_AT_REF", rho_at_ref, "%.17g")
_emit_julia_tuple3("PYTHON_CP_AT_REF",  cp_at_ref,  "%.17g")
_emit_julia_tuple3("PYTHON_MU_AT_REF",  mu_at_ref,  "%.17g")
_emit_julia_tuple3("PYTHON_K_AT_REF",   k_at_ref,   "%.17g")
print("# --- end paste: parity_helpers.jl REF constants ---")
print()

# Block 2: simple-loop reference const block for test/data/python_parity_reference.jl
print("# --- begin paste: test/data/python_parity_reference.jl simple-loop block ---")
print("# Simple-loop Python parity reference — tiers (a)+(b)+(c)")
print(f"# Topology: Pump → HX → ChannelAndContacts (n={N}, L={L_CH}, D={D_H}) → Pump")
print(f"# T_inlet = {T_INLET_C:.2f} K ({T_INLET_C:.1f} C); T_wall = {T_WALL_C:.2f} K ({T_WALL_C:.1f} C)")
print(f"# Solver: scipy.optimize.root (default xtol=1.49e-8)")
print()
_emit_julia_scalar("PARITY_SIMPLE_T_OUT", T_out_C)
_emit_julia_scalar("PARITY_SIMPLE_MDOT",  mdot)
_emit_julia_scalar("PARITY_SIMPLE_DP",    DP_total)
print()
_emit_julia_array("PARITY_SIMPLE_T_CELLS",         T_cells_C,       "%.10f", comment_each=True, comment_prefix="T")
_emit_julia_array("PARITY_SIMPLE_T_WALL_LEFT",     T_wall_left_C,   "%.10f", comment_each=True, comment_prefix="T_wall_left")
_emit_julia_array("PARITY_SIMPLE_T_WALL_RIGHT",    T_wall_right_C,  "%.10f", comment_each=True, comment_prefix="T_wall_right")
_emit_julia_array("PARITY_SIMPLE_H_TC_LEFT",       h_left,          "%.10f", comment_each=True, comment_prefix="h_left")
_emit_julia_array("PARITY_SIMPLE_H_TC_RIGHT",      h_right,         "%.10f", comment_each=True, comment_prefix="h_right")
_emit_julia_array("PARITY_SIMPLE_Q_DENSITY_LEFT",  q_density_left,  "%.10f", comment_each=True, comment_prefix="q_density_left  # W/m^2")
_emit_julia_array("PARITY_SIMPLE_Q_DENSITY_RIGHT", q_density_right, "%.10f", comment_each=True, comment_prefix="q_density_right # W/m^2")
print("# --- end paste: test/data/python_parity_reference.jl simple-loop block ---")
print()

# Block 3: diagnostics (NOT pasted — for human inspection only)
print("=" * 72)
print("Diagnostics (NOT pasted — for human inspection only)")
print("=" * 72)
print(f"  T_out         = {T_out_C:.6f} K  ({T_out_C:.4f} C)")
print(f"  mdot          = {mdot:.6f} kg/s")
print(f"  DP_total      = {DP_total:.1f} Pa  (closed loop ≡ DP_PUMP)")
print(f"  Re (mean)     = {float(np.mean(ch_state.get('Re',  [0]))):.0f}")
print(f"  HTC left mean = {float(np.mean(h_left)):.1f} W/m^2K")
print(f"  HTC right mean= {float(np.mean(h_right)):.1f} W/m^2K")
print(f"  T_cells range = {min(T_cells_C):.2f} .. {max(T_cells_C):.2f} K")
print(f"  T_wall L mean = {float(np.mean(T_wall_left_C)):.2f} K")
print(f"  T_wall R mean = {float(np.mean(T_wall_right_C)):.2f} K")
print(f"  q_left mean   = {float(np.mean(q_density_left)):.1f} W/m^2")
print(f"  q_right mean  = {float(np.mean(q_density_right)):.1f} W/m^2")
print()
print(f"  Equivalence-checklist values (REF_T_C = {REF_T_C} K):")
for i, T_C in enumerate(REF_T_C):
    print(f"    [{i+1}] T={T_C:.2f}degC: rho={rho_at_ref[i]:.4f} cp={cp_at_ref[i]:.4f} "
          f"mu={mu_at_ref[i]:.4e} k={k_at_ref[i]:.4f}")
