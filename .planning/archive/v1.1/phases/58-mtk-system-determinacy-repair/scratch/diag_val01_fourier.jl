# Phase 58 — Scenario D — VAL-01 HD Fourier topology diagnostic
#
# Lifts test/test_validation.jl:842-903 verbatim into a standalone script.
# Builds: HeatDiffusion (power=0.0) + 2*nz ConstantTemperature, both faces.
# As-is the system is structurally underdetermined (Δ=-1) because hd_v01.power(t)
# is declared as @variables in HeatDiffusion (heat_diffusion.jl:145) but no
# closing equation pins it. With `hd_v01.power ~ 0.0` appended the system is Δ=0.
#
# R-1 mitigation: explicit `using ModelingToolkit: connect` to disambiguate from
# Sockets.connect (Phase 57 D-04 #1). Belt-and-suspenders for daemon AND cold-start.

using ModelingToolkit
using ModelingToolkit: t_nounits as t
using ModelingToolkit: connect
using STREAM
import STREAM: HeatDiffusion, ConstantTemperature

function build_val01(; pin_power::Bool=false)
    nz_v01 = 10
    nx_v01 = 5
    Lx_v01 = 0.00127
    Lz_v01 = 0.6
    y_v01  = 0.07
    T_wall = 300.0

    ps_v01 = fill(1.0 / (nz_v01 * nx_v01), nz_v01, nx_v01)
    @named hd_v01 = HeatDiffusion(;
        nz=nz_v01, nx=nx_v01,
        Lz=Lz_v01, Lx=Lx_v01, y=y_v01,
        rho_s=2700.0, cp_s=900.0, k_s=200.0,
        power_shape=ps_v01, power=0.0,
    )
    ct_l = [ConstantTemperature(T_wall; name=Symbol(:ct_l_, i)) for i in 1:nz_v01]
    ct_r = [ConstantTemperature(T_wall; name=Symbol(:ct_r_, i)) for i in 1:nz_v01]

    conns_v01 = Equation[
        [connect(ct_l[i].thermal, getproperty(hd_v01, Symbol(:thermal_left,  i))) for i in 1:nz_v01]...,
        [connect(ct_r[i].thermal, getproperty(hd_v01, Symbol(:thermal_right, i))) for i in 1:nz_v01]...,
    ]
    pin_power && push!(conns_v01, hd_v01.power ~ 0.0)

    @named sys_v01 = compose(System(conns_v01, t; name=:val01_sys), ct_l..., ct_r..., hd_v01)
    return sys_v01
end

println("\n=== Scenario D: VAL-01 HD Fourier ===\n")

println("-- as-is (no hd_v01.power pin) --")
sys_broken = build_val01(; pin_power=false)
ssys_broken = mtkcompile(sys_broken; fully_determined=false)
n_eq = length(equations(ssys_broken)); n_uk = length(unknowns(ssys_broken))
n_init = length(ModelingToolkit.initialization_equations(ssys_broken))
println("  Δ=", n_eq - n_uk, "  n_eqs=", n_eq, "  n_unknowns=", n_uk, "  n_init_eqs=", n_init)

print("  fully_determined=true: ")
try
    mtkcompile(sys_broken; fully_determined=true)
    println("PASS (unexpected)")
catch e
    println("FAIL — ", typeof(e))
end

println("\n-- with hd_v01.power ~ 0.0 pin --")
sys_pinned = build_val01(; pin_power=true)
ssys_pinned = mtkcompile(sys_pinned; fully_determined=false)
n_eq = length(equations(ssys_pinned)); n_uk = length(unknowns(ssys_pinned))
n_init = length(ModelingToolkit.initialization_equations(ssys_pinned))
println("  Δ=", n_eq - n_uk, "  n_eqs=", n_eq, "  n_unknowns=", n_uk, "  n_init_eqs=", n_init)

print("  fully_determined=true: ")
try
    mtkcompile(sys_pinned; fully_determined=true)
    println("PASS")
catch e
    println("FAIL — ", typeof(e))
end
