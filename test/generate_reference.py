#!/usr/bin/env python3
"""
generate_reference.py -- Python STREAM reference value generator

Run ONCE to obtain reference values for Julia-STREAM VAL-01 cross-validation:
  cd /home/itay/projects/Julia-STREAM/test && python generate_reference.py

Requires Python STREAM at ~/projects/STREAM.

UNIT CONVENTION:
  Python STREAM: CELSIUS.  Julia-STREAM: KELVIN.
  Outputs are converted to Kelvin before printing.

PHYSICS / TOPOLOGY:
  Pump → HeatExchanger(40°C) → ChannelAndContacts → back to Pump

  HeatExchanger pins inlet temperature to 40°C, equivalent to Julia-STREAM's TempBC.
  ChannelAndContacts computes Dittus-Boelter HTC and Darcy-Weisbach friction internally.
  Julia Channel also computes friction internally — no separate Friction component in either.

  Parameters matching Julia-STREAM build_loop() defaults:
    - Pump: dP = 30 kPa
    - Channel: n=10, L=0.6m, D=0.01m, A=7.85e-5 m²
    - T_wall = 373.15 K = 100 C  (T_left = T_right = 100 C, symmetric circular pipe)
    - T_inlet = 313.15 K = 40 C
    - Horizontal loop: g=0 (Julia Channel.g_acc=0 default)
    - Absolute pressure reference: 1e5 Pa
"""

import sys
import os
from functools import partial
import numpy as np

STREAM_PATH = os.path.expanduser("~/projects/STREAM")
sys.path.insert(0, STREAM_PATH)

# Unit conversion checks
T_INLET_C = 40.0
T_WALL_C  = 100.0
T_INLET_K = T_INLET_C + 273.15
T_WALL_K  = T_WALL_C  + 273.15
assert abs(T_INLET_K - 313.15) < 1e-9
assert abs(T_WALL_K  - 373.15) < 1e-9

# Parameters matching Julia-STREAM build_loop() defaults
N       = 10
L_CH    = 0.6
D_H     = 0.01
DP_PUMP = 3.0e4
P_ABS   = 1.0e5

from stream.calculations import Pump, HeatExchanger
from stream.calculations.channel import ChannelAndContacts
from stream.composition.cycle import FlowGraph, flow_edge
from stream.pipe_geometry import EffectivePipe
from stream.substances import light_water
from stream.jacobians import ALG_jacobian
from stream.physical_models.pressure_drop import pressure_diff

pipe_ch = EffectivePipe.circular(length=L_CH, diameter=D_H)

pump = Pump(pressure=DP_PUMP)

# HeatExchanger pins coolant temperature to T_inlet at the pump outlet.
# Equivalent to Julia-STREAM's TempBC component which resets fluid to T_inlet
# before it enters the heated channel, breaking the circular thermal dependency.
hx = HeatExchanger(outlet=T_INLET_C, name="HX")

# ChannelAndContacts: computes Dittus-Boelter HTC self-consistently from flow.
# Friction is already included internally via pressure_diff (Darcy-Weisbach).
# g=0: Julia build_loop() Channel uses pure Darcy-Weisbach, no gravity term.
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
# reference_node pins absolute pressure at "A" (matches Julia: pump.inlet.P ~ 1e5).
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
    print(f"WARNING gravity check: {e}")

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

# Extract results
T_outlet_C = state[channel.name]["T_cool"][-1]
T_outlet_K = T_outlet_C + 273.15
mdot       = abs(state[K.name][K.component_edge(pump)])

assert T_outlet_K > T_INLET_K, f"T_outlet {T_outlet_K:.2f} K below inlet"
assert T_outlet_K < 450.0,     f"T_outlet {T_outlet_K:.2f} K unreasonably high"
assert mdot > 1e-4,            f"mdot {mdot:.4f} kg/s too small"

print("=" * 60)
print("Python STREAM reference values (hardcode in runtests.jl)")
print("=" * 60)
print(f"T_outlet_kelvin = {T_outlet_K:.6f}")
print(f"mdot            = {mdot:.6f}")
print()
print(f"  T_outlet_ref = {T_outlet_K:.4f}   # K  (Python: {T_outlet_C:.4f} C)")
print(f"  mdot_ref     = {mdot:.6f}  # kg/s")
print()
ch = state[channel.name]
print(f"  Re (mean)  = {float(np.mean(ch.get('Re', [0]))):.0f}")
print(f"  HTC (mean) = {float(np.mean(ch.get('h_left', [0]))):.1f} W/m2K")
