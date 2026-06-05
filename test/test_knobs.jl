using Test
using STREAM
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D
using OrdinaryDiffEq
using SteadyStateDiffEq

@testset "design_knob declaration" begin
    outer_d = @design_knob outer_d = 0.02
    @test ModelingToolkit.isparameter(outer_d)
    @test string(outer_d) == "outer_d"
    @test ModelingToolkit.hasdefault(outer_d)
    @test ModelingToolkit.getdefault(outer_d) == 0.02

    @test_throws ArgumentError (@macroexpand @design_knob 0.02)
end

@testset "knob_defaults collects stored defaults" begin
    a = @design_knob a = 1.5
    b = @design_knob b = 0.003
    defs = knob_defaults([a, b])
    @test length(defs) == 2
    @test isequal(defs[1].first, a) && defs[1].second == 1.5
    @test isequal(defs[2].first, b) && defs[2].second == 0.003
end

# A shared knob drives geometry in two composed components and stays a single
# un-namespaced parameter, the cross-component case W7 is built for.
function _knob_fluid(D_in; name)
    @variables Tf(t) qf(t) Twf(t) A(t)
    area = pi * D_in^2 / 4
    dh = D_in
    Re = abs(0.3) * dh / (area * mu_water(Tf))
    Pr = cp_water(Tf) * mu_water(Tf) / k_water(Tf)
    h = 0.023 * Re^0.8 * Pr^0.4 * k_water(Tf) / dh
    System([D(Tf) ~ 0.3 * cp_water(Tf) * (320.0 - Tf) + qf, qf ~ h * area * (Twf - Tf),
            A ~ area], t, [Tf, qf, Twf, A], []; name)
end
function _knob_solid(D_out; name)
    @variables Ts(t) q(t) Tw(t) G(t)
    System([D(Ts) ~ 1500.0 - q, q ~ 100.0 * D_out * (Ts - Tw), G ~ 100.0 * D_out],
           t, [Ts, q, Tw, G], []; name)
end

@testset "shared knob propagates across compose + remake" begin
    outer_d = @design_knob outer_d = 0.02
    @named fluid = _knob_fluid(outer_d)
    @named solid = _knob_solid(outer_d)
    @named root = System([fluid.Twf ~ solid.Tw, fluid.qf ~ solid.q], t, [], [];
                         systems = [fluid, solid])
    ssys = mtkcompile(root)

    # one shared parameter, not fluid.outer_d + solid.outer_d
    ps = parameters(ssys)
    @test length(ps) == 1
    @test string(only(ps)) == "outer_d"

    guesses = Pair[ssys.fluid.Tf => 330, ssys.solid.Ts => 360, ssys.fluid.Twf => 350,
                   ssys.fluid.qf => 1500, ssys.solid.Tw => 350, ssys.solid.q => 1500]

    # runs on the declared default with no knob supplied beyond knob_defaults
    op = [knob_defaults([outer_d]); guesses]
    prob = SteadyStateProblem(ssys, op; warn_initialize_determined = false,
                              build_initializeprob = false)
    sol = solve(prob, DynamicSS(Rodas5P()); abstol = 1e-10, reltol = 1e-10)
    @test isapprox(sol[ssys.fluid.A], pi * 0.02^2 / 4; rtol = 1e-9)
    @test isapprox(sol[ssys.solid.G], 100.0 * 0.02; rtol = 1e-9)

    # one remake moves geometry in BOTH components
    sol2 = solve(remake(prob; p = [outer_d => 0.025]), DynamicSS(Rodas5P());
                 abstol = 1e-10, reltol = 1e-10)
    @test isapprox(sol2[ssys.fluid.A], pi * 0.025^2 / 4; rtol = 1e-9)
    @test isapprox(sol2[ssys.solid.G], 100.0 * 0.025; rtol = 1e-9)
end
