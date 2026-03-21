using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using DifferentialEquations
using STREAM
import STREAM: Channel, HeatDiffusion, PipeGeometry_rectangular
const SciMLBase = DifferentialEquations.SciMLBase

# Free constants used by Phase 3 VAL tests
T_outlet_ref = 327.7894  # K  (Python STREAM: 54.6394 °C)
mdot_ref     = 0.609289  # kg/s

# ─────────────────────────────────────────────────────────────────
# VAL-01: Steady-state T_outlet and mdot within 1% of Python STREAM
# Reference: generate_reference.py (T_wall=373.15K, T_inlet=313.15K,
#            dP_pump=30kPa, n=10, L=0.6m, D=0.01m, g=0)
# ─────────────────────────────────────────────────────────────────
@testset "VAL-01: Steady-state matches Python STREAM within 1%" begin
    n = 10; T_inlet = 313.15
    ssys = build_loop(T_inlet=T_inlet)
    T_guess = steady_state_guess(T_inlet=T_inlet, Q_wall=1e4, mdot_guess=0.490, n=n)
    op = [ssys.ch.T[i] => T_guess[i] for i in 1:n]
    push!(op, ssys.ch.port_in.mdot => 0.490)
    sol = solve_steady(ssys, op)

    T_out = sol[ssys.ch.T_out]
    mdot  = abs(sol[ssys.ch.port_in.mdot])
    @test isapprox(T_out, T_outlet_ref; rtol=0.01)
    @test isapprox(mdot,  mdot_ref;     rtol=0.01)
end

# ─────────────────────────────────────────────────────────────────
# VAL-02: Transient T_outlet rises after T_wall step change
# (callable T_wall pattern — T_wall_fn wired at build time)
# ─────────────────────────────────────────────────────────────────
@testset "VAL-02: Transient T_outlet rises after T_wall step" begin
    n = 10; T_inlet = 313.15

    # Step-change: T_wall from 373.15 to 393.15 at t=10s via callable
    T_wall_0 = 373.15; T_wall_final = 393.15; t_step = 10.0
    T_wall_step = t -> t < t_step ? T_wall_0 : T_wall_final

    # Use a scalar-T_wall system for the steady-state solve (consistent ICs at T_wall_0),
    # then switch to the callable system for the transient.
    ssys_ss = build_loop_transient(T_inlet=T_inlet, T_wall_0=T_wall_0)
    ssys    = build_loop_transient(T_inlet=T_inlet, T_wall_fn=T_wall_step)

    T_guess = steady_state_guess(T_inlet=T_inlet, Q_wall=1e4, mdot_guess=0.490, n=n)
    op_guess = [ssys_ss.ch.T[i] => T_guess[i] for i in 1:n]
    push!(op_guess, ssys_ss.ch.port_in.mdot => 0.490)
    sol_ss = solve_steady(ssys_ss, op_guess)
    # Use Pair{Any,Any} so the callable parameter can be mixed with Float64 values
    op_ic = Pair{Any,Any}[ssys.ch.T[i] => sol_ss[ssys_ss.ch.T[i]] for i in 1:n]
    push!(op_ic, ssys.ch.port_in.mdot => sol_ss[ssys_ss.ch.port_in.mdot])
    T_wall_sym = last(parameters(ssys))   # T_wall_callable is the last parameter
    push!(op_ic, T_wall_sym => T_wall_step)

    t_arr = range(0.0, 60.0, length=600)
    sol = solve_transient(ssys, op_ic, t_arr)
    @test sol.retcode == ReturnCode.Success
    T_ts = sol[ssys.ch.T_out, :]
    @test !any(isnan, T_ts)
    @test T_ts[end] > T_ts[1]   # outlet rises after T_wall step
end

# ─────────────────────────────────────────────────────────────────
# VAL-01: Symmetric MTR — HeatDiffusion + two ChannelAndContacts
# Both channels at 313.15 K inlet, 10 kW, nz=10, nx=3, D=0.01 m
# Reference: generate_mtr_reference.py (Python STREAM)
# ─────────────────────────────────────────────────────────────────
@testset "VAL-01: Symmetric MTR — HeatDiffusion + two ChannelAndContacts" begin
    # Quantitative validation against Python STREAM reference (generate_mtr_reference.py).
    # Both use rectangular MTR geometry (y=0.07 m heated_parts) — 1% tolerance.
    # Physics sanity checks also retained:
    #   - Both channels heat up (T_out > T_in = 313.15 K)
    #   - Symmetric: T_out_l == T_out_r within 0.1%
    #   - Plate center is hotter than fluid outlet
    #   - Energy balance: T_rise ≈ P/(mdot*cp) with P=5 kW per channel

    nz = 10; nx = 3
    T_in = 313.15
    @named pump_l = Pump(3.0e4)
    @named hx_l   = HeatExchanger(T_bc=T_in)
    @named cac_l  = ChannelAndContacts(n=nz, geometry=PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07))
    @named pump_r = Pump(3.0e4)
    @named hx_r   = HeatExchanger(T_bc=T_in)
    @named cac_r  = ChannelAndContacts(n=nz, geometry=PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07))
    ps = fill(1.0 / (nz * nx), nz, nx)
    @named hd = HeatDiffusion(nz=nz, nx=nx, Lz=0.6, Lx=0.00127, y=0.07,
                               rho_s=2700.0, cp_s=900.0, k_s=200.0,
                               power_shape=ps, power=1e4)
    conns = [
        connect(pump_l.port_out, hx_l.port_in),
        connect(hx_l.port_out, cac_l.port_in),
        connect(cac_l.port_out, pump_l.port_in),
        pump_l.port_in.P ~ 1.0e5,
        connect(pump_r.port_out, hx_r.port_in),
        connect(hx_r.port_out, cac_r.port_in),
        connect(cac_r.port_out, pump_r.port_in),
        pump_r.port_in.P ~ 1.0e5,
        [connect(getproperty(hd, Symbol(:thermal_left,  i)),
                 getproperty(cac_l, Symbol(:thermal_left, i))) for i in 1:nz]...,
        [connect(getproperty(hd, Symbol(:thermal_right, i)),
                 getproperty(cac_r, Symbol(:thermal_left, i))) for i in 1:nz]...,
    ]
    @named sys = compose(System(conns, t; name=:mtr_val01), pump_l, hx_l, cac_l, pump_r, hx_r, cac_r, hd)
    ssys = mtkcompile(sys; fully_determined=false)

    # Minimal op: only actual unknowns (plate T, fluid T, mdot).
    # Re/Nu/h_tc are observed (computed), T_out is observed — not unknowns; guesses ignored.
    # Correct mdot sign: port_in.mdot > 0 for fluid entering (forward flow).
    # Magnitude ~0.250 kg/s from Darcy-Weisbach at Dh≈2.495mm (rectangular), dP=30 kPa.
    T_w = 315.0
    op = vcat(
        [ssys.hd.T[i, j]          => T_w   for i in 1:nz for j in 1:nx],
        [ssys.cac_l.T[i]          => T_w   for i in 1:nz],
        [ssys.cac_r.T[i]          => T_w   for i in 1:nz],
        [ssys.cac_l.port_in.mdot  => +0.250],
        [ssys.cac_r.port_in.mdot  => +0.250],
    )
    sol = solve_steady(ssys, op)

    @test sol.retcode == ReturnCode.Success

    T_out_l  = sol[ssys.cac_l.T_out]
    T_out_r  = sol[ssys.cac_r.T_out]
    mdot_l   = sol[ssys.cac_l.port_in.mdot]
    mdot_r   = sol[ssys.cac_r.port_in.mdot]
    T_center = sol[ssys.hd.T[nz÷2, (nx+1)÷2]]   # [5, 2] for nz=10, nx=3

    # Reference constants from generate_mtr_reference.py (rectangular MTR geometry, y=0.07 m)
    # Regenerated with EffectivePipe.rectangular(0.6, 0.07, 0.00127, 0.07); Dh ≈ 2.495 mm
    val01_T_outlet_l_ref = 317.8871   # K — left channel outlet temperature
    val01_T_outlet_r_ref = 317.8871   # K — right channel outlet temperature
    val01_mdot_l_ref     = 0.252547   # kg/s — left channel mass flow
    val01_mdot_r_ref     = 0.252547   # kg/s — right channel mass flow
    val01_T_plate_center = 322.5997   # K — plate center temperature (mid-axial, mid-lateral)
    @test isapprox(T_out_l,  val01_T_outlet_l_ref; rtol=0.01)
    @test isapprox(T_out_r,  val01_T_outlet_r_ref; rtol=0.01)
    @test isapprox(mdot_l,   val01_mdot_l_ref;     rtol=0.01)
    @test isapprox(mdot_r,   val01_mdot_r_ref;     rtol=0.01)
    @test isapprox(T_center, val01_T_plate_center;  rtol=0.01)

    # Physics sanity checks
    @test T_out_l > T_in
    @test T_out_r > T_in
    @test isapprox(T_out_l, T_out_r; rtol=0.001)
    @test mdot_l > 0.0
    @test mdot_r > 0.0
    @test T_center > T_out_l
    # Energy balance: each channel receives 5 kW; T_rise = P/(mdot*cp)
    cp_approx = cp_water(T_in)
    T_rise_expected = 5000.0 / (mdot_l * cp_approx)
    @test isapprox(T_out_l - T_in, T_rise_expected; rtol=0.05)
end

# ─────────────────────────────────────────────────────────────────
# VAL-02: Asymmetric MTR — right channel inlet at 90°C (363.15 K)
# Right side of plate must be hotter than left side.
# ─────────────────────────────────────────────────────────────────
@testset "VAL-02: Asymmetric MTR — right channel at 363.15 K inlet" begin
    # Asymmetric BCs: left inlet 313.15 K (40°C), right inlet 363.15 K (90°C).
    # Physics validation: right plate face hotter than left face (right channel dominates).

    nz = 10; nx = 3
    T_in_l = 313.15; T_in_r = 363.15
    @named pump_l = Pump(3.0e4)
    @named hx_l   = HeatExchanger(T_bc=T_in_l)
    @named cac_l  = ChannelAndContacts(n=nz, geometry=PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07))
    @named pump_r = Pump(3.0e4)
    @named hx_r   = HeatExchanger(T_bc=T_in_r)
    @named cac_r  = ChannelAndContacts(n=nz, geometry=PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07))
    ps = fill(1.0 / (nz * nx), nz, nx)
    @named hd = HeatDiffusion(nz=nz, nx=nx, Lz=0.6, Lx=0.00127, y=0.07,
                               rho_s=2700.0, cp_s=900.0, k_s=200.0,
                               power_shape=ps, power=1e4)
    conns = [
        connect(pump_l.port_out, hx_l.port_in),
        connect(hx_l.port_out, cac_l.port_in),
        connect(cac_l.port_out, pump_l.port_in),
        pump_l.port_in.P ~ 1.0e5,
        connect(pump_r.port_out, hx_r.port_in),
        connect(hx_r.port_out, cac_r.port_in),
        connect(cac_r.port_out, pump_r.port_in),
        pump_r.port_in.P ~ 1.0e5,
        [connect(getproperty(hd, Symbol(:thermal_left,  i)),
                 getproperty(cac_l, Symbol(:thermal_left, i))) for i in 1:nz]...,
        [connect(getproperty(hd, Symbol(:thermal_right, i)),
                 getproperty(cac_r, Symbol(:thermal_left, i))) for i in 1:nz]...,
    ]
    @named sys = compose(System(conns, t; name=:mtr_val02), pump_l, hx_l, cac_l, pump_r, hx_r, cac_r, hd)
    ssys = mtkcompile(sys; fully_determined=false)

    # Asymmetric initial guess: right side at ~363 K, left at ~313 K
    # mdot guess ~0.250 kg/s matches new Dh≈2.495mm rectangular geometry at dP=30 kPa
    op = vcat(
        [ssys.hd.T[i, j]          => 318.15 for i in 1:nz for j in 1:(nx-1)],
        [ssys.hd.T[i, nx]         => 368.15 for i in 1:nz],
        [ssys.cac_l.T[i]          => 318.15 for i in 1:nz],
        [ssys.cac_r.T[i]          => 368.15 for i in 1:nz],
        [ssys.cac_l.port_in.mdot  => +0.250],
        [ssys.cac_r.port_in.mdot  => +0.250],
    )
    sol = solve_steady(ssys, op)

    @test sol.retcode == ReturnCode.Success

    T_plate_left_col  = sol[ssys.hd.T[nz÷2, 1]]
    T_plate_right_col = sol[ssys.hd.T[nz÷2, nx]]
    T_center_02       = sol[ssys.hd.T[nz÷2, (nx+1)÷2]]

    # Reference constants from generate_mtr_reference.py (rectangular MTR geometry, y=0.07 m)
    # Regenerated with EffectivePipe.rectangular(0.6, 0.07, 0.00127, 0.07); Dh ≈ 2.495 mm
    val02_T_plate_center = 347.6125   # K — plate center temperature (asymmetric: right channel 363.15 K)
    @test isapprox(T_center_02, val02_T_plate_center; rtol=0.01)

    # Right column must be hotter than left column (right channel at 90°C drives right face hot)
    @test T_plate_right_col > T_plate_left_col
    # Left outlet must be above left inlet (left channel at 40°C is heated by plate)
    @test sol[ssys.cac_l.T_out] > T_in_l
    # Right outlet warmer than left inlet at minimum
    @test sol[ssys.cac_r.T_out] > T_in_l
end

# ─────────────────────────────────────────────────────────────────
# VAL-03: One-sided MTR — only left channel coupled; thermal_right adiabatic
# ─────────────────────────────────────────────────────────────────
@testset "VAL-03: One-sided MTR — left channel only, thermal_right adiabatic" begin
    # One-sided geometry: only thermal_left[i] connected to cac_l; thermal_right[i] free (adiabatic).
    # All 10 kW deposited in the plate exits only through the left face.
    # Physics validation:
    #   - T_out_l > T_in (10 kW heats the single channel)
    #   - T_plate_center > T_out_l (plate is hotter than fluid)
    #   - thermal_right Q_flow == 0 (adiabatic right face)
    #   - Energy balance: T_rise = 10 kW / (mdot * cp)

    nz = 10; nx = 3
    T_in = 313.15
    @named pump_l = Pump(3.0e4)
    @named hx_l   = HeatExchanger(T_bc=T_in)
    @named cac_l  = ChannelAndContacts(n=nz, geometry=PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07))
    ps = fill(1.0 / (nz * nx), nz, nx)
    @named hd = HeatDiffusion(nz=nz, nx=nx, Lz=0.6, Lx=0.00127, y=0.07,
                               rho_s=2700.0, cp_s=900.0, k_s=200.0,
                               power_shape=ps, power=1e4)
    conns = [
        connect(pump_l.port_out, hx_l.port_in),
        connect(hx_l.port_out, cac_l.port_in),
        connect(cac_l.port_out, pump_l.port_in),
        pump_l.port_in.P ~ 1.0e5,
        [connect(getproperty(hd, Symbol(:thermal_left, i)),
                 getproperty(cac_l, Symbol(:thermal_left, i))) for i in 1:nz]...,
    ]
    @named sys = compose(System(conns, t; name=:mtr_val03), pump_l, hx_l, cac_l, hd)
    ssys = mtkcompile(sys; fully_determined=false)

    # Minimal op: plate T, fluid T, mdot (positive = forward flow)
    # mdot guess ~0.250 kg/s matches new Dh≈2.495mm rectangular geometry at dP=30 kPa
    T_w = 317.0
    op = vcat(
        [ssys.hd.T[i, j]         => T_w   for i in 1:nz for j in 1:nx],
        [ssys.cac_l.T[i]         => T_w   for i in 1:nz],
        [ssys.cac_l.port_in.mdot => +0.250],
    )
    sol = solve_steady(ssys, op)

    @test sol.retcode == ReturnCode.Success

    T_out_l_03  = sol[ssys.cac_l.T_out]
    mdot_l_03   = sol[ssys.cac_l.port_in.mdot]
    T_center_03 = sol[ssys.hd.T[nz÷2, (nx+1)÷2]]

    # Reference constants from generate_mtr_reference.py (rectangular MTR geometry, y=0.07 m)
    # Regenerated with EffectivePipe.rectangular(0.6, 0.07, 0.00127, 0.07); Dh ≈ 2.495 mm
    # NOTE: Python one_sided_connection() distributes heat to BOTH plate faces (physically wrong
    # for one-sided coupling). Julia correctly connects only thermal_left[i] to cac_l.
    # As a result, Julia T_out (~322.6 K) differs from Python T_out (~317.9 K):
    #   Julia energy balance: T_rise = 10kW / (mdot * cp) ≈ 9.4 K → T_out ≈ 322.6 K (correct)
    #   Python one_sided: T_rise ≈ 4.7 K → T_out ≈ 317.9 K (wrong — only half heat exits via cac_l)
    # Per STATE.md decision: use energy balance as truth; Python T_out assertion omitted.
    val03_mdot_ref       = 0.252547   # kg/s — left channel mass flow (hydraulics correct in Python)
    @test isapprox(mdot_l_03,   val03_mdot_ref;       rtol=0.01)
    # VAL-03: T_max analytical assertion — adiabatic face is hottest point for one-sided cooling.
    # For one-sided coupling (left face = T_wall, right face = adiabatic), uniform volumetric q,
    # steady-state analytical solution: T_max = T_wall_avg + q_total * Lx / (2 * k_s * A)
    # where A = y * Lz = 0.07 * 0.6 = 0.042 m² (plate face area).
    # NOTE on Python STREAM discrepancy: Python one_sided_connection distributes heat to BOTH faces
    # even for one-sided coupling, giving a physically incorrect (lower) T_center. Julia uses the
    # correct one-sided formulation. T_max = T_wall_avg + q*Lx/(2*k_s*A) is the correct reference.
    T_max_numerical = sol[ssys.hd.T[nz÷2, nx]]   # j=nx is adiabatic (right) face — hottest point
    left_syms_v03 = [getproperty(ssys.cac_l, Symbol(:thermal_left, i)) for i in 1:nz]
    T_wall_vals_v03 = [sol[left_syms_v03[i].T] for i in 1:nz]
    T_wall_avg_v03 = sum(T_wall_vals_v03) / nz
    A_v03 = 0.07 * 0.6              # y * Lz = 0.042 m²
    T_max_analytical = T_wall_avg_v03 + 1e4 * 0.00127 / (2 * 200.0 * A_v03)
    # Expected: ΔT ≈ 0.756 K above T_wall_avg (small but physically correct for high-k aluminum)
    @test isapprox(T_max_numerical, T_max_analytical; rtol=0.01)

    @test T_out_l_03 > T_in
    @test mdot_l_03 > 0.0
    @test T_center_03 > T_out_l_03
    # Energy balance: full 10 kW goes to one channel
    cp_approx = cp_water(T_in)
    T_rise_expected = 1e4 / (mdot_l_03 * cp_approx)
    @test isapprox(T_out_l_03 - T_in, T_rise_expected; rtol=0.05)

    # Unconnected right face must be adiabatic (Q_flow == 0)
    right_syms = [getproperty(ssys.hd, Symbol(:thermal_right, i)) for i in 1:nz]
    for i in 1:nz
        @test isapprox(sol[right_syms[i].Q_flow], 0.0; atol=1e-6)
    end
end

# ─────────────────────────────────────────────────────────────────
# VAL-01: HeatDiffusion transient — Fourier series validation
# Pure plate (no fluid): both faces pinned at T_wall, power=0, uniform IC T0.
# Plate relaxes toward T_wall via pure diffusion.
# Assert T_center(t) matches analytical 1D Fourier series at 4 time points.
# ─────────────────────────────────────────────────────────────────
@testset "VAL-01: HeatDiffusion transient — Fourier series validation" begin
    # MTR aluminum plate parameters — consistent with all existing VAL tests
    nz_v01 = 10; nx_v01 = 5
    k_s_v01  = 200.0;   rho_s_v01 = 2700.0;  cp_s_v01 = 900.0
    Lx_v01   = 0.00127; Lz_v01    = 0.6;     y_v01    = 0.07
    T_wall   = 300.0;   T0        = 400.0    # 100 K step-down for clear signal

    # Diffusivity and thermal time constant
    alpha_v01 = k_s_v01 / (rho_s_v01 * cp_s_v01)   # ≈ 8.23e-5 m²/s
    tau_v01   = Lx_v01^2 / (π^2 * alpha_v01)        # ≈ 0.002 s

    # Fourier series analytical reference (symmetric BCs, no power, center x=Lx/2):
    # T(Lx/2, t) = T_wall + (4/π)(T0-T_wall) Σ_{k=0}^{N-1} [(-1)^k/(2k+1)] exp(-α((2k+1)π/Lx)²t)
    function fourier_T_center(t_val)
        result = T_wall
        for k in 0:49
            n = 2k + 1
            result += (4/π) * (T0 - T_wall) * ((-1)^k / n) * exp(-alpha_v01 * (n*π/Lx_v01)^2 * t_val)
        end
        return result
    end

    # Build isolated plate with ConstantTemperature BCs on both faces, power=0
    ps_v01 = fill(1.0 / (nz_v01 * nx_v01), nz_v01, nx_v01)
    @named hd_v01 = HeatDiffusion(nz=nz_v01, nx=nx_v01, Lz=Lz_v01, Lx=Lx_v01, y=y_v01,
                                   rho_s=rho_s_v01, cp_s=cp_s_v01, k_s=k_s_v01,
                                   power_shape=ps_v01, power=0.0)
    ct_l = [ConstantTemperature(name=Symbol(:ct_l_, i), T=T_wall) for i in 1:nz_v01]
    ct_r = [ConstantTemperature(name=Symbol(:ct_r_, i), T=T_wall) for i in 1:nz_v01]
    conns_v01 = [
        [connect(ct_l[i].thermal, getproperty(hd_v01, Symbol(:thermal_left,  i))) for i in 1:nz_v01]...,
        [connect(ct_r[i].thermal, getproperty(hd_v01, Symbol(:thermal_right, i))) for i in 1:nz_v01]...,
    ]
    @named sys_v01 = compose(System(conns_v01, t; name=:val01_sys), ct_l..., ct_r..., hd_v01)
    ssys_v01 = mtkcompile(sys_v01; fully_determined=false)

    # Uniform initial condition: all plate cells at T0
    op_ic_v01 = [ssys_v01.hd_v01.T[i, j] => T0 for i in 1:nz_v01 for j in 1:nx_v01]

    # Time span and assertion checkpoints (in seconds)
    t_checkpoints = [0.5*tau_v01, tau_v01, 2*tau_v01, 5*tau_v01]
    tspan_v01 = (0.0, 5.0*tau_v01 * 1.01)  # slight overshoot to include endpoint

    prob_v01 = ODEProblem(ssys_v01, op_ic_v01, tspan_v01; warn_initialize_determined=false)
    sol_v01 = solve(prob_v01, Rodas5P(); initializealg=SciMLBase.NoInit(),
                    saveat=t_checkpoints)
    @test sol_v01.retcode == ReturnCode.Success

    # Assert T_center at each checkpoint vs Fourier series
    T_center_sym = ssys_v01.hd_v01.T[nz_v01÷2, (nx_v01+1)÷2]
    T_center_series = sol_v01[T_center_sym, :]
    for (k, t_k) in enumerate(t_checkpoints)
        T_num = T_center_series[k]
        T_ref = fourier_T_center(t_k)
        @test isapprox(T_num, T_ref; rtol=0.01)
    end

    # Solution must approach T_wall by 5τ
    @test isapprox(T_center_series[end], T_wall; rtol=0.01)
end

# ─────────────────────────────────────────────────────────────────
# VAL-02: Two HeatDiffusion plates connected to one ChannelAndContacts
# Topology: thermal_left[i] → hd1 (plate 1); thermal_right[i] → hd2 (plate 2).
# Both faces of the single CAC are simultaneously active.
# This is the first test exercising the Phase 10 two-sided upgrade end-to-end.
# ─────────────────────────────────────────────────────────────────
@testset "VAL-02: Two-plate one-channel topology — both faces active" begin
    nz_v02 = 10; nx_v02 = 3
    T_in_v02 = 313.15
    power_per_plate = 1e4   # W each → 20 kW total to one channel

    @named pump_v02 = Pump(3.0e4)
    @named hx_v02   = HeatExchanger(T_bc=T_in_v02)
    @named cac_v02  = ChannelAndContacts(n=nz_v02,
                          geometry=PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07))
    ps_v02 = fill(1.0 / (nz_v02 * nx_v02), nz_v02, nx_v02)
    @named hd1 = HeatDiffusion(nz=nz_v02, nx=nx_v02, Lz=0.6, Lx=0.00127, y=0.07,
                                rho_s=2700.0, cp_s=900.0, k_s=200.0,
                                power_shape=ps_v02, power=power_per_plate)
    @named hd2 = HeatDiffusion(nz=nz_v02, nx=nx_v02, Lz=0.6, Lx=0.00127, y=0.07,
                                rho_s=2700.0, cp_s=900.0, k_s=200.0,
                                power_shape=ps_v02, power=power_per_plate)

    conns_v02 = [
        # Hydraulic loop
        connect(pump_v02.port_out, hx_v02.port_in),
        connect(hx_v02.port_out,   cac_v02.port_in),
        connect(cac_v02.port_out,  pump_v02.port_in),
        pump_v02.port_in.P       ~ 1.0e5,
        # hd1 left face → cac thermal_left (hd1 is on the left of the channel)
        [connect(getproperty(hd1,     Symbol(:thermal_left,  i)),
                 getproperty(cac_v02, Symbol(:thermal_left,  i))) for i in 1:nz_v02]...,
        # hd2 left face → cac thermal_right (hd2 is on the right of the channel, facing inward)
        [connect(getproperty(hd2,     Symbol(:thermal_left,  i)),
                 getproperty(cac_v02, Symbol(:thermal_right, i))) for i in 1:nz_v02]...,
    ]
    @named sys_v02 = compose(System(conns_v02, t; name=:val02_sys), pump_v02, hx_v02, cac_v02, hd1, hd2)
    ssys_v02 = mtkcompile(sys_v02; fully_determined=false)

    # Initial guess: plate T slightly above T_in, mdot +0.250 (rectangular MTR at 30 kPa)
    T_guess_v02 = T_in_v02 + 10.0
    op_v02 = vcat(
        [ssys_v02.hd1.T[i, j]          => T_guess_v02 for i in 1:nz_v02 for j in 1:nx_v02],
        [ssys_v02.hd2.T[i, j]          => T_guess_v02 for i in 1:nz_v02 for j in 1:nx_v02],
        [ssys_v02.cac_v02.T[i]          => T_guess_v02 for i in 1:nz_v02],
        [ssys_v02.cac_v02.port_in.mdot  => +0.250],
    )
    sol_v02 = solve_steady(ssys_v02, op_v02)

    # Assertion 1: solver converged
    @test sol_v02.retcode == ReturnCode.Success

    # Assertion 2: energy balance — both plates heat the single channel
    mdot_v02 = sol_v02[ssys_v02.cac_v02.port_in.mdot]
    cp_v02 = cp_water(T_in_v02)
    T_rise_expected_v02 = (power_per_plate + power_per_plate) / (mdot_v02 * cp_v02)
    @test isapprox(sol_v02[ssys_v02.cac_v02.T_out] - T_in_v02, T_rise_expected_v02; rtol=0.05)

    # Assertion 3: each plate center hotter than fluid midpoint (plate has internal source)
    mid = nz_v02 ÷ 2
    lat = (nx_v02 + 1) ÷ 2
    @test sol_v02[ssys_v02.hd1.T[mid, lat]] > sol_v02[ssys_v02.cac_v02.T[mid]]
    @test sol_v02[ssys_v02.hd2.T[mid, lat]] > sol_v02[ssys_v02.cac_v02.T[mid]]

    # Assertion 4: Q_flow < 0 on connected faces (heat flows FROM plate TO fluid, MTK convention)
    # hd1: thermal_left[i] is connected → Q_flow < 0
    # hd2: thermal_left[i] is connected → Q_flow < 0
    for i in 1:nz_v02
        @test sol_v02[getproperty(ssys_v02.hd1, Symbol(:thermal_left, i)).Q_flow] < 0.0
        @test sol_v02[getproperty(ssys_v02.hd2, Symbol(:thermal_left, i)).Q_flow] < 0.0
    end
end
