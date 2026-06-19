using Test
using STREAM
using STREAM: PipeGeometry_rectangular, PipeGeometry_circular
using ModelingToolkit

@testset "PipeGeometry_rectangular geometry" begin
    geo = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
    @test isapprox(geo.A, 0.07 * 0.00127; rtol=1e-4)
    @test isapprox(geo.wet_perimeter, 2.0 * (0.07 + 0.00127); rtol=1e-4)
    @test isapprox(geo.Dh, 4.0 * (0.07 * 0.00127) / (2.0 * (0.07 + 0.00127)); rtol=1e-4)
    # Independent hand-computed anchor for a 70 mm by 1.27 mm duct, Dh = 4 * A / wetted_perimeter.
    #   A  = 0.07 * 0.00127       = 8.89e-5 m^2
    #   Pw = 2 * (0.07 + 0.00127) = 0.14254 m
    #   Dh = 4 * 8.89e-5 / 0.14254 = 0.0024947383190683323 m
    # The number below was worked out by hand from these dimensions, not copied from the source.
    @test isapprox(geo.A, 8.89e-5; rtol=1e-12)
    @test isapprox(geo.Dh, 0.0024947383190683323; rtol=1e-12)
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
    # Independent hand-computed anchor for a 10 mm circular pipe. Dh = D exactly for a circle, and
    #   A = pi * D^2 / 4 = pi * (0.01)^2 / 4 = 7.853981633974483e-5 m^2
    # worked out by hand, not copied from the source formula.
    @test isapprox(geo.Dh, 0.01; rtol=1e-12)
    @test isapprox(geo.A, 7.853981633974483e-5; rtol=1e-12)
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
    # width/depth are symbolic too (circular: both equal the diameter knob)
    @test geo.width isa Num
    @test geo.depth isa Num
    @test isapprox(at(geo.width, d, 0.02), 0.02; rtol=1e-12)
    @test isapprox(at(geo.depth, d, 0.03), 0.03; rtol=1e-12)   # scans with the knob
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
    # depth is the gap knob and scans; width is the fixed plate edge
    @test rect.depth isa Num
    @test isapprox(at(rect.width, gap, 0.0025), 0.0665; rtol=1e-12)
    @test isapprox(at(rect.depth, gap, 0.0025), 0.0025; rtol=1e-12)
    @test isapprox(at(rect.depth, gap, 0.0010), 0.0010; rtol=1e-12)   # gap knob scans depth
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
