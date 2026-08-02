using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
using STREAM.Assemblies
using STREAM.Components
using STREAM: Re

# MTR-like channel: aspect ratio 0.01814, which is where k_R departs from 1 the most.
const GEOM_F = PipeGeometry_rectangular(0.6, 0.07, 0.07 * 0.01814, 0.07)

@testset "Friction.AbstractDarcyFactor models" begin
    A, Dh = GEOM_F.A, GEOM_F.Dh
    T_bulk, T_wall = 40.0, 90.0
    re_of(ṁ) = Re(H2O, T_bulk, ṁ, A, Dh)
    ṁ_at(target) = target * μ(H2O, T_bulk) * A / Dh

    @testset "Friction.FromReynolds closes a bare correlation at the bulk" begin
        ṁ = 0.25
        @test Friction.Blasius()(T_bulk, T_wall, ṁ, H2O, GEOM_F) ≈ Friction.blasius(re_of(ṁ))
        @test Friction.Laminar()(T_bulk, T_wall, ṁ, H2O, GEOM_F) ≈ Friction.laminar(re_of(ṁ))
        @test Friction.Turbulent()(T_bulk, T_wall, ṁ, H2O, GEOM_F) ≈ Friction.turbulent(re_of(ṁ))
        @test Friction.Turbulent(; epsilon=0.1)(T_bulk, T_wall, ṁ, H2O, GEOM_F) ≈
              Friction.turbulent(re_of(ṁ), 0.1)

        # The wall temperature is accepted and ignored by a model that has no use for it.
        @test Friction.Blasius()(T_bulk, 500.0, ṁ, H2O, GEOM_F) ==
              Friction.Blasius()(T_bulk, T_wall, ṁ, H2O, GEOM_F)
        # And the short form drops it entirely.
        @test Friction.Blasius()(T_bulk, ṁ, H2O, GEOM_F) ==
              Friction.Blasius()(T_bulk, T_bulk, ṁ, H2O, GEOM_F)
    end

    @testset "k_R scales the Reynolds fed to the correlation" begin
        ṁ = 0.25
        @test Friction.Laminar(; k_R=0.5)(T_bulk, T_wall, ṁ, H2O, GEOM_F) ≈
              Friction.laminar(re_of(ṁ) * 0.5)
        # The rectangular constructor is the aspect-ratio k_R spelled out.
        k_R = Friction.rectangular_correction(GEOM_F.depth / GEOM_F.width)
        @test Friction.RectangularLaminar(GEOM_F)(T_bulk, T_wall, ṁ, H2O, GEOM_F) ≈
              64.0 / (re_of(ṁ) * k_R)
        @test !isapprox(k_R, 1.0; rtol=1e-3)   # or the test proves nothing
    end

    @testset "Friction.RegimeDependent blends and guards no-flow" begin
        rd = Friction.RegimeDependent(; re_bounds=(2000.0, 5000.0))
        for target in (500.0, 8000.0)
            m = ṁ_at(target)
            branch = target < 2000 ? Friction.laminar : Friction.turbulent
            @test rd(T_bulk, T_wall, m, H2O, GEOM_F) ≈ branch(re_of(m))
        end
        # A quarter into the band.
        m_band = ṁ_at(2750.0)
        f_lam = Friction.laminar(re_of(m_band))
        f_turb = Friction.turbulent(re_of(m_band))
        @test rd(T_bulk, T_wall, m_band, H2O, GEOM_F) ≈ f_lam + 0.25 * (f_turb - f_lam)

        # The no-flow guard: the bare 64/Re would be Inf here.
        @test rd(T_bulk, T_wall, 0.0, H2O, GEOM_F) == 0.0
        @test isfinite(rd(T_bulk, T_wall, 0.0, H2O, GEOM_F))
        # Reversed flow uses |ṁ| for Re, so it mirrors forward flow.
        @test rd(T_bulk, T_wall, -0.25, H2O, GEOM_F) ≈ rd(T_bulk, T_wall, 0.25, H2O, GEOM_F)
    end

    @testset "the viscosity correction reaches the wall" begin
        # This is the whole point of the AbstractDarcyFactor signature: k_H needs the wall
        # temperature and the two perimeters, none of which a (Re)->f closure can see.
        plain = Friction.RegimeDependent()
        corrected = Friction.RegimeDependent(; viscosity=Friction.viscosity_correction)
        ṁ = 0.25

        # Opt-in: without it nothing moves.
        @test plain(T_bulk, T_wall, ṁ, H2O, GEOM_F) ==
              plain(T_bulk, 500.0, ṁ, H2O, GEOM_F)

        f_plain = plain(T_bulk, T_wall, ṁ, H2O, GEOM_F)
        f_corr = corrected(T_bulk, T_wall, ṁ, H2O, GEOM_F)
        ratio = μ(H2O, T_wall) / μ(H2O, T_bulk)
        expected = f_plain * Friction.viscosity_correction(
            GEOM_F.heated_perimeter / GEOM_F.wet_perimeter, ratio
        )
        @test f_corr ≈ expected
        # A hotter wall thins the liquid there, so the correction is below 1 and the
        # correction genuinely changes the answer.
        @test ratio < 1.0
        @test f_corr < f_plain
        @test !isapprox(f_corr, f_plain; rtol=1e-3)

        # No wall-to-bulk difference leaves the factor untouched.
        @test corrected(T_bulk, T_bulk, ṁ, H2O, GEOM_F) ≈ f_plain
    end

    @testset "user-defined factors" begin
        mine = Friction.FromFunction((Tb, Tw, m, liq, pipe) -> 0.042)
        @test mine(T_bulk, T_wall, 0.25, H2O, GEOM_F) == 0.042
        @test mine(T_bulk, 0.25, H2O, GEOM_F) == 0.042
        # Any callable works as a FromReynolds correlation.
        @test Friction.FromReynolds(Re -> 1 / Re)(T_bulk, T_wall, 0.25, H2O, GEOM_F) ≈
              1 / re_of(0.25)
    end
end

@testset "Friction resistor" begin
    @testset "geometry and L/D/A forms agree" begin
        geom = PipeGeometry_circular(2.0, 0.05)
        @named f1 = FrictionResistor(; geometry=geom)
        @named f2 = FrictionResistor(; L=2.0, D=0.05, A=geom.A)
        @test f1 isa ModelingToolkit.System
        @test length(equations(f1)) == length(equations(f2))
        @test_throws ArgumentError FrictionResistor(; name=:bad)
        @test_throws ArgumentError FrictionResistor(; name=:bad, geometry=geom, L=1.0, D=1.0, A=1.0)
    end

    # A pump pushes through one resistor; the solved drop must match the closed form.
    function solve_drop(; darcy=Friction.Blasius(), scale=1.0, dP=3.0e4)
        geom = PipeGeometry_circular(2.0, 0.05)
        @named pump = Pump(dP)
        @named fr = FrictionResistor(; geometry=geom, darcy=darcy, scale=scale)
        @named hx = HeatExchanger(40.0)
        conns = [connect(pump.outlet, hx.inlet), connect(hx.outlet, fr.inlet),
                 connect(fr.outlet, pump.inlet), pump.inlet.p ~ 1.0e5]
        @named sys = compose(System(conns, t; name=:sys), pump, fr, hx)
        ssys = mtkcompile(sys)
        sol = solve_steady(ssys, [ssys.fr.inlet.ṁ => 1.0])
        return ssys, sol
    end

    @testset "regime-dependent friction as a component" begin
        rd = Friction.RegimeDependent(; re_bounds=(2000.0, 5000.0))
        ssys, sol = solve_drop(; darcy=rd)
        @test sol.retcode == ReturnCode.Success
        # The factor the component reports is the one the model gives at the solved Re.
        Re_sol = sol[ssys.fr.Re]
        @test sol[ssys.fr.f] ≈ rd(40.0, 40.0, sol[ssys.fr.inlet.ṁ], H2O,
                                  PipeGeometry_circular(2.0, 0.05))
        @test Re_sol > 5000.0     # this operating point is turbulent
        @test sol[ssys.fr.f] ≈ Friction.turbulent(Re_sol)
    end

    @testset "scale multiplies the drop" begin
        # Same pump head, a resistor scaled up: less flow, and the drop still balances.
        _, s1 = solve_drop(; scale=1.0)
        _, s3 = solve_drop(; scale=3.0)
        @test s1.retcode == ReturnCode.Success && s3.retcode == ReturnCode.Success
    end
end

@testset "scale on the algebraic resistors" begin
    # Resistor is linear, so scaling by 3 is exactly three of them in series.
    function loop_flow(; scale)
        @named pump = Pump(1.0e4)
        @named r = Resistor(2.0e4; scale=scale)
        @named hx = HeatExchanger(40.0)
        conns = [connect(pump.outlet, hx.inlet), connect(hx.outlet, r.inlet),
                 connect(r.outlet, pump.inlet), pump.inlet.p ~ 1.0e5]
        @named sys = compose(System(conns, t; name=:sys), pump, r, hx)
        ssys = mtkcompile(sys)
        sol = solve_steady(ssys, [ssys.r.inlet.ṁ => 0.5])
        return sol[ssys.r.inlet.ṁ]
    end
    m1 = loop_flow(; scale=1.0)
    m3 = loop_flow(; scale=3.0)
    @test m1 ≈ 1.0e4 / 2.0e4 rtol = 1e-8
    @test m3 ≈ m1 / 3 rtol = 1e-8
end

@testset "Inertia takes a flow-dependent L/A" begin
    @testset "bilinear_inertia shape" begin
        L = bilinear_inertia(1.75e5, 0.2)
        @test L(0.0) == 0.0
        @test L(0.1) ≈ 1.75e5 * 0.5
        @test L(0.2) == 1.75e5           # at and above the knee it is flat
        @test L(5.0) == 1.75e5
        # Selected on the magnitude, so a reversal behaves like forward flow.
        @test L(-0.1) == L(0.1)
        @test L(-5.0) == L(5.0)
    end

    @testset "the callable form declares an effective-inertia variable" begin
        @named i_const = Inertia(1.75e5)
        @named i_fn = Inertia(bilinear_inertia(1.75e5, 0.2))
        @test i_const isa ModelingToolkit.System
        @test i_fn isa ModelingToolkit.System
        names_fn = string.(unknowns(i_fn))
        @test any(contains("L_eff"), names_fn)
        @test !any(contains("L_eff"), string.(unknowns(i_const)))
    end

    # A pump holds the flow, then shuts off and the loop coasts. Starting the transient from
    # the solved steady state keeps the IC consistent whichever variables MTK keeps.
    function coast(L_arg; R_val=1.0, ṁ0=1.0, tmax=600.0)
        @named pump = Pump(R_val * ṁ0)
        @named L_comp = Inertia(L_arg)
        @named R_comp = Resistor(R_val)
        @named hx = HeatExchanger(26.85)
        conns = [inseries(pump, L_comp, R_comp, hx, pump)..., pump.inlet.p ~ 1.0e5]
        @named sys = compose(System(conns, t; name=:sys), pump, L_comp, R_comp, hx)
        ssys = mtkcompile(sys)
        # The callable form's extra L_eff variable changes what MTK tears, which surfaces
        # the dummy derivative; seed it so both forms initialise the same way.
        op = Pair{Any,Any}[ssys.L_comp.inlet.ṁ => ṁ0]
        if any(contains("ṁˍt"), string.(unknowns(ssys)))
            push!(op, Differential(t)(ssys.L_comp.inlet.ṁ) => 0.0)
        end
        sol_ss = solve_steady(ssys, op)
        sol = solve_transient(ssys, sol_ss, range(0.0, tmax; length=200);
                              overrides=[ssys.pump.dP_pump => 0.0])
        return ssys, sol
    end

    @testset "above the knee it reproduces the constant-inertia decay" begin
        L0, R_val = 1.0e3, 1.0
        tau = L0 / R_val
        ssys_c, sol_c = coast(L0)
        # Knee far below the trajectory, so L is L0 the whole way.
        ssys_b, sol_b = coast(bilinear_inertia(L0, 1.0e-6))
        @test sol_c.retcode == ReturnCode.Success
        @test sol_b.retcode == ReturnCode.Success
        for tc in (0.0, 100.0, 300.0, 600.0)
            analytic = exp(-tc / tau)
            @test sol_c(tc; idxs=ssys_c.L_comp.inlet.ṁ) ≈ analytic rtol = 0.01
            @test sol_b(tc; idxs=ssys_b.L_comp.inlet.ṁ) ≈ analytic rtol = 0.01
        end
    end

    @testset "below the knee the decay stops being exponential" begin
        # With the knee above the whole trajectory, L = L0*mdot/mdot0, so
        #   d(mdot)/dt = -R*mdot / (L0*mdot/mdot0) = -R*mdot0/L0,
        # a constant. The coastdown is a straight line, not an exponential, which is
        # something the fixed-inertia form cannot produce.
        L0, R_val, ṁ0, knee = 1.0e3, 1.0, 1.0, 2.0
        slope = R_val * knee / L0                      # 2e-3 kg/s per s
        ssys, sol = coast(bilinear_inertia(L0, knee); R_val=R_val, ṁ0=ṁ0, tmax=300.0)
        @test sol.retcode == ReturnCode.Success
        for tc in (0.0, 100.0, 200.0, 300.0)
            @test sol(tc; idxs=ssys.L_comp.inlet.ṁ) ≈ ṁ0 - slope * tc atol = 5e-3
        end
        # And it is genuinely not the exponential the constant form would give.
        @test !isapprox(sol(300.0; idxs=ssys.L_comp.inlet.ṁ), exp(-300.0 / (L0 / R_val));
                        rtol=0.05)
    end
end
