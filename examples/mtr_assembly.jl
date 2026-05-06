# examples/mtr_assembly.jl
# MTR fuel assembly: HeatDiffusion plate coupled to two ChannelAndContacts via plate().
#
# Usage:
#   julia --project examples/mtr_assembly.jl
#
# What this script demonstrates:
#   1. Define rectangular MTR channel geometry with PipeGeometry_rectangular.
#   2. Build a ChannelAndContacts for each coolant face (left and right).
#   3. Build a HeatDiffusion plate for the aluminum fuel meat.
#   4. Couple channels to plate using plate() (two-channel symmetric_plate variant)
#      and solve the coupled thermal-hydraulic steady state.
#
# Physical overview:
#   Topology (MTR plate-fuel assembly):
#     Two independent water channels (left, right) flow along an aluminum plate.
#     Uniform fission heat is deposited in the plate and conducted to both faces.
#     Each face is in convective contact with its adjacent channel (ChannelAndContacts).
#     Separate Pump + HeatExchanger loops drive flow in each channel independently.
#
#   Geometry:
#     Plate: L=0.6 m axial, Lx=1.27 mm thick, y=0.07 m half-width
#     Channel: rectangular duct with Dh derived from y and gap=Lx
#     Material: aluminum (rho=2700, cp=900, k=200)
#
#   Expected result (symmetric BCs):
#     Left and right outlet temperatures equal (~317.9 K)
#     Plate center temperature > fluid outlet (plate is the heat source)

using STREAM
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using Plots
ENV["GKSwstype"] = "100"   # headless GR — no display window, avoids X11 errors
gr()

# =============================================================================
# SECTION 1: Parameters
# =============================================================================

#! format: off
const NZ        = 10        # axial cells
const NX        = 3         # lateral cells in plate
const T_INLET   = 313.15    # K (40 degC) coolant inlet temperature
const DP_PUMP   = 3.0e4     # Pa pump pressure rise
const POWER     = 1.0e4     # W total fission power deposited in the plate
# MTR plate geometry (rectangular channel)
const L_PLATE   = 0.6       # m axial length
const Y_PLATE   = 0.07      # m plate half-width (heated perimeter)
const LX_PLATE  = 0.00127   # m plate thickness (gap between channels)
# Aluminum plate material
const RHO_AL    = 2700.0    # kg/m^3
const CP_AL     = 900.0     # J/(kg*K)
const K_AL      = 200.0     # W/(m*K)
#! format: on

# =============================================================================
# SECTION 2: Build and compile
# =============================================================================

println("Building MTR assembly...")

# Step 1: Define rectangular channel geometry.
# PipeGeometry_rectangular(L, y, gap, wetted_perimeter)
# Dh = 2*gap*y / (gap + y) for rectangular duct (approximation).
geom = PipeGeometry_rectangular(L_PLATE, Y_PLATE, LX_PLATE, Y_PLATE)

# Step 2: Fuel plate — uniform normalized power shape.
ps = fill(1.0 / (NZ * NX), NZ, NX)
@named hd = HeatDiffusion(;
    nz=NZ,
    nx=NX,
    Lz=L_PLATE,
    Lx=LX_PLATE,
    y=Y_PLATE,
    rho_s=RHO_AL,
    cp_s=CP_AL,
    k_s=K_AL,
    power_shape=ps,
    power=POWER,
)

# Step 3: Left and right coolant channels (ChannelAndContacts provides thermal ports).
@named cac_l = ChannelAndContacts(; n=NZ, geometry=geom)
@named cac_r = ChannelAndContacts(; n=NZ, geometry=geom)

# Step 4: Thermal coupling via plate().
# plate(ch_left, ch_right, fuel; name) wires:
#   ch_left.thermal_right[i]  <-> fuel.thermal_left[i]
#   ch_right.thermal_left[i]  <-> fuel.thermal_right[i]
# For a single-channel symmetric assembly, use symmetric_plate(cac, fuel; name) instead.
@named rods = plate(cac_l, cac_r, hd)

# Step 5: Complete hydraulic loops (pump + heat exchanger for each channel).
@named pump_l = Pump(DP_PUMP)
@named hx_l = HeatExchanger(T_INLET)
@named pump_r = Pump(DP_PUMP)
@named hx_r = HeatExchanger(T_INLET)

conns = [
    connect(pump_l.outlet, hx_l.inlet),
    connect(hx_l.outlet, rods.cac_l.inlet),
    connect(rods.cac_l.outlet, pump_l.inlet),
    pump_l.inlet.P ~ 1.0e5,
    connect(pump_r.outlet, hx_r.inlet),
    connect(hx_r.outlet, rods.cac_r.inlet),
    connect(rods.cac_r.outlet, pump_r.inlet),
    pump_r.inlet.P ~ 1.0e5,
    rods.hd.power ~ POWER,
]
@named sys = compose(System(conns, t; name=:mtr_example), pump_l, hx_l, pump_r, hx_r, rods)
ssys = mtkcompile(sys)

# =============================================================================
# SECTION 3: Initial guess and solve
# =============================================================================

T_w = 315.0
op = vcat(
    [ssys.rods.hd.T[i, j] => T_w for i in 1:NZ for j in 1:NX],
    [ssys.rods.cac_l.T[i] => T_w for i in 1:NZ],
    [ssys.rods.cac_r.T[i] => T_w for i in 1:NZ],
    [ssys.rods.cac_l.inlet.mdot => +0.250],
    [ssys.rods.cac_r.inlet.mdot => +0.250],
)

println("Solving steady state...")
sol = solve_steady(ssys, op)

if sol.retcode != ReturnCode.Success
    error("Steady-state solve failed with retcode: $(sol.retcode)")
end

# =============================================================================
# SECTION 4: Extract and print results
# =============================================================================

T_out_l = sol[ssys.rods.cac_l.T_out]
T_out_r = sol[ssys.rods.cac_r.T_out]
T_center = sol[ssys.rods.hd.T[NZ ÷ 2, (NX + 1) ÷ 2]]

println("Steady-state results:")
println("  Left channel T_out  = $(round(T_out_l - 273.15, digits=2)) degC")
println("  Right channel T_out = $(round(T_out_r - 273.15, digits=2)) degC")
println("  Plate center T      = $(round(T_center - 273.15, digits=2)) degC")
println("  T_plate_center > T_fluid: $(T_center > T_out_l)")

# =============================================================================
# SECTION 5: Plot axial temperature profiles
# =============================================================================

T_plate_center_col = [sol[ssys.rods.hd.T[i, (NX + 1) ÷ 2]] for i in 1:NZ]
T_fluid_l = [sol[ssys.rods.cac_l.T[i]] for i in 1:NZ]
T_fluid_r = [sol[ssys.rods.cac_r.T[i]] for i in 1:NZ]
z = range(0.0, L_PLATE; length=NZ)

p = plot(z, T_plate_center_col .- 273.15; label="Plate center", linewidth=2, color=:red)
plot!(p, z, T_fluid_l .- 273.15; label="Left channel", linewidth=2, color=:blue)
plot!(
    p,
    z,
    T_fluid_r .- 273.15;
    label="Right channel",
    linewidth=2,
    color=:green,
    linestyle=:dash,
)
xlabel!(p, "Axial position [m]")
ylabel!(p, "Temperature [degC]")
title!(p, "STREAM.jl — MTR Assembly Steady State")

mkpath("examples/output")
savefig(p, "examples/output/mtr_assembly_temperature.png")
println("Plot saved to examples/output/mtr_assembly_temperature.png")
