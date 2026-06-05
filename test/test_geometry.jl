using Test
using STREAM
using STREAM: PipeGeometry_rectangular, PipeGeometry_circular
using ModelingToolkit

@testset "PipeGeometry_rectangular geometry" begin
    geo = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
    @test isapprox(geo.A, 0.07 * 0.00127; rtol=1e-4)
    @test isapprox(geo.wet_perimeter, 2.0 * (0.07 + 0.00127); rtol=1e-4)
    @test isapprox(geo.Dh, 4.0 * (0.07 * 0.00127) / (2.0 * (0.07 + 0.00127)); rtol=1e-4)
    @test geo.width == 0.07
    @test geo.depth == 0.00127
    @test geo.heated_parts == (0.07, 0.07)
    geo_l = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07, one_sided=:left)
    @test geo_l.heated_parts == (0.07, 0.0)
    geo_r = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07, one_sided=:right)
    @test geo_r.heated_parts == (0.0, 0.07)
    @test_throws Exception PipeGeometry_rectangular(
        0.6, 0.07, 0.00127, 0.07, one_sided=:bad_value
    )
end

@testset "PipeGeometry_circular geometry" begin
    geo = PipeGeometry_circular(1.0, 0.01)
    @test isapprox(geo.Dh, 0.01; rtol=1e-10)
    @test isapprox(geo.wet_perimeter, π * 0.01; rtol=1e-10)
    @test isapprox(geo.heated_parts[1], π * 0.01; rtol=1e-10)
    @test isapprox(geo.heated_parts[2], 0; atol=1e-10)
    @test isapprox(geo.A, π * 0.01^2 / 4; rtol=1e-10)
    @test geo.width == 0.01
    @test geo.depth == 0.01
end

@testset "PipeGeometry symbolic (knob-driven)" begin
    # evaluate a symbolic geometry field at a knob value (compiles the expression,
    # so irrationals like pi fold to a number)
    at(expr, knob, val) = Symbolics.build_function(expr, knob; expression=Val{false})(val)

    # circular pipe whose diameter is a design knob
    d = @design_knob d = 0.02
    geo = PipeGeometry_circular(0.6, d)
    @test geo isa PipeGeometry{Num}
    @test geo.Dh isa Num
    @test geo.A isa Num
    @test geo.heated_parts[1] isa Num
    # width/depth resolve to the knob's nominal value
    @test geo.width == 0.02
    @test geo.depth == 0.02
    # evaluated at the knob default, the symbolic geometry matches the fixed geometry
    num = PipeGeometry_circular(0.6, 0.02)
    @test isapprox(at(geo.A, d, 0.02), num.A; rtol=1e-12)
    @test isapprox(at(geo.Dh, d, 0.02), num.Dh; rtol=1e-12)

    # rectangular channel with a knob gap: all flow fields promote to Num,
    # width/depth order by nominal values
    gap = @design_knob gap = 0.0025
    rect = PipeGeometry_rectangular(0.6, 0.0665, gap, 0.0665)
    @test rect isa PipeGeometry{Num}
    @test rect.A isa Num
    @test rect.width == 0.0665
    @test rect.depth == 0.0025
    rnum = PipeGeometry_rectangular(0.6, 0.0665, 0.0025, 0.0665)
    @test isapprox(at(rect.Dh, gap, 0.0025), rnum.Dh; rtol=1e-12)

    # one-sided promotion keeps a symbolic heated_parts tuple
    one = PipeGeometry_rectangular(0.6, 0.0665, gap, 0.0665; one_sided=:left)
    @test one.heated_parts[1] isa Num
    @test isapprox(at(one.heated_parts[2], gap, 0.0025), 0.0; atol=1e-12)
end

@testset "fixed PipeGeometry stays Float64" begin
    @test PipeGeometry_circular(1.0, 0.01) isa PipeGeometry{Float64}
    @test PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07) isa PipeGeometry{Float64}
end
