# Standalone proof: VAL-02 two-plate steady reaches solve_steady Success after Plan 58-04.
# This bypasses the test_validation.jl try/catch block that VAL-01's pre-existing
# BoundsError exits early (documented out-of-scope in 58-03-SUMMARY).
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using ModelingToolkit: connect
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
import STREAM: Pump, HeatExchanger, ChannelAndContacts, HeatDiffusion,
                PipeGeometry_rectangular, solve_steady, cp_water

nz_v02 = 10
nx_v02 = 3
T_in_v02 = 313.15
power_per_plate = 1e4

@named pump_v02 = Pump(3.0e4)
@named hx_v02 = HeatExchanger(T_in_v02)
@named cac_v02 = ChannelAndContacts(;
    n=nz_v02, geometry=PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07))
ps_v02 = fill(1.0 / (nz_v02 * nx_v02), nz_v02, nx_v02)
@named hd1 = HeatDiffusion(; nz=nz_v02, nx=nx_v02,
    Lz=0.6, Lx=0.00127, y=0.07,
    rho_s=2700.0, cp_s=900.0, k_s=200.0,
    power_shape=ps_v02, power=power_per_plate)
@named hd2 = HeatDiffusion(; nz=nz_v02, nx=nx_v02,
    Lz=0.6, Lx=0.00127, y=0.07,
    rho_s=2700.0, cp_s=900.0, k_s=200.0,
    power_shape=ps_v02, power=power_per_plate)

conns_v02 = [
    connect(pump_v02.port_out, hx_v02.port_in),
    connect(hx_v02.port_out, cac_v02.port_in),
    connect(cac_v02.port_out, pump_v02.port_in),
    pump_v02.port_in.P ~ 1.0e5,
    [connect(getproperty(hd1, Symbol(:thermal_left, i)),
             getproperty(cac_v02, Symbol(:thermal_left, i))) for i in 1:nz_v02]...,
    [connect(getproperty(hd2, Symbol(:thermal_left, i)),
             getproperty(cac_v02, Symbol(:thermal_right, i))) for i in 1:nz_v02]...,
    hd1.power ~ power_per_plate,
    hd2.power ~ power_per_plate,
]
@named sys_v02 = compose(System(conns_v02, t; name=:val02_sys),
                         pump_v02, hx_v02, cac_v02, hd1, hd2)
ssys_v02 = mtkcompile(sys_v02; fully_determined=true)
println("compile OK n_eqs=", length(equations(ssys_v02)),
        " n_unk=",  length(unknowns(ssys_v02)))

T_guess_v02 = T_in_v02 + 10.0
op_v02 = vcat(
    [ssys_v02.hd1.T[i, j] => T_guess_v02 for i in 1:nz_v02 for j in 1:nx_v02],
    [ssys_v02.hd2.T[i, j] => T_guess_v02 for i in 1:nz_v02 for j in 1:nx_v02],
    [ssys_v02.cac_v02.T[i] => T_guess_v02 for i in 1:nz_v02],
    [ssys_v02.cac_v02.port_in.mdot => +0.250],
)
sol_v02 = solve_steady(ssys_v02, op_v02)
println("solve retcode = ", sol_v02.retcode)

mdot_v02 = sol_v02[ssys_v02.cac_v02.port_in.mdot]
cp_v02 = cp_water(T_in_v02)
T_rise_expected_v02 = (power_per_plate + power_per_plate) / (mdot_v02 * cp_v02)
T_rise_actual = sol_v02[ssys_v02.cac_v02.T_out] - T_in_v02
println("T_rise expected = ", T_rise_expected_v02, "  actual = ", T_rise_actual,
        "  isapprox(rtol=0.05): ", isapprox(T_rise_actual, T_rise_expected_v02; rtol=0.05))
