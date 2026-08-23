# examples/simple_loop.jl
# Minimal forced-convection loop: pump drives coolant through a heated channel.
#
# Usage:
#   julia --project examples/simple_loop.jl
#
# What this script demonstrates:
#   1. Build a single closed forced-convection loop with build_loop().
#   2. Solve the steady-state using solve_steady() with a temperature initial guess.
#   3. Print key results (T_outlet, ṁ, T_rise) and save an axial temperature profile.
#
# Physical overview:
#   Topology (series loop):
#     Pump -> HeatExchanger (T_inlet reset) -> Channel (heated) -> Pump (closed)
#
#   The Channel component solves the 1D energy balance with Dittus-Boelter HTC
#   and Darcy-Weisbach friction internally. The pump provides a fixed pressure rise.
#   The HeatExchanger resets the fluid temperature to T_INLET at the pump outlet,
#   providing the thermal boundary condition.

using STREAM
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq

using Plots
ENV["GKSwstype"] = "100"   # headless GR — no display window, avoids X11 errors
Plots.gr()

#! format: off
const N_CELLS   = 10        # axial discretization cells
const T_INLET   = 40.0      # °C coolant inlet temperature
const T_WALL    = 100.0     # °C wall temperature
const H_WALL    = 5000.0    # W/(m²K) convective HTC on the heated face
const DP_PUMP   = 3.0e4     # Pa pump pressure rise
const L_CHANNEL = 0.6       # m channel length
const D_CHANNEL = 0.01      # m hydraulic diameter
#! format: on

println("Building loop...")
ssys = build_loop(;
    n=N_CELLS,
    T_inlet=T_INLET,
    T_wall=T_WALL,
    h_wall=H_WALL,
    L_ch=L_CHANNEL,
    D_ch=D_CHANNEL,
    dP_pump=DP_PUMP,
)

T_guess = steady_state_guess(; T_inlet=T_INLET, Q_wall=1e4, ṁ_guess=0.490, n=N_CELLS)
op = [ssys.ch.T[i] => T_guess[i] for i in 1:N_CELLS]
push!(op, ssys.ch.inlet.ṁ => 0.490)

println("Solving steady state...")
sol = solve_steady(ssys, op)

if sol.retcode != ReturnCode.Success
    error("Steady-state solve failed with retcode: $(sol.retcode)")
end

T_out = sol[ssys.ch.T_out]
ṁ = abs(sol[ssys.ch.inlet.ṁ])
T_axial = [sol[ssys.ch.T[i]] for i in 1:N_CELLS]

println("Steady-state results:")
println("  T_outlet = $(round(T_out, digits=2)) °C")
println("  ṁ     = $(round(ṁ, digits=4)) kg/s")
println("  T_rise   = $(round(T_out - T_INLET, digits=2)) °C")

z_positions = range(0.0, L_CHANNEL; length=N_CELLS)
p = plot(
    z_positions,
    T_axial;
    xlabel="Axial position [m]",
    ylabel="Fluid temperature [°C]",
    title="STREAM.jl — Simple Loop Steady State",
    label="T_fluid",
    linewidth=2,
    marker=:circle,
    markersize=4,
)
hline!([T_WALL]; linestyle=:dash, label="T_wall", color=:red)
hline!([T_INLET]; linestyle=:dot, label="T_inlet", color=:blue)

mkpath("examples/output")
savefig(p, "examples/output/simple_loop_temperature.png")
println("Plot saved to examples/output/simple_loop_temperature.png")