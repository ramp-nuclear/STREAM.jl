using Test
using STREAM
using STREAM.Assemblies
using ModelingToolkit

@testset "rectangular duct" begin
    duct = Duct(0.6, Rectangular(0.07, 0.00127))
    # Hand-computed for a 70 mm by 1.27 mm duct, Dh = 4A / P_wet:
    #   A  = 0.07 * 0.00127        = 8.89e-5 m^2
    #   Pw = 2 * (0.07 + 0.00127)  = 0.14254 m
    #   Dh = 4 * 8.89e-5 / 0.14254 = 0.0024947383190683323 m
    @test isapprox(flow_area(duct), 8.89e-5; rtol=1e-12)
    @test isapprox(wetted_perimeter(duct), 0.14254; rtol=1e-12)
    @test isapprox(hydraulic_diameter(duct), 0.0024947383190683323; rtol=1e-12)
    @test aspect_ratio(duct) ≈ 0.00127 / 0.07

    # The edges go in either order; width is the longer.
    @test Rectangular(0.00127, 0.07) == Rectangular(0.07, 0.00127)
    @test duct.shape.width == 0.07
    @test duct.shape.depth == 0.00127

    # Both long faces are heated across the width unless told otherwise.
    @test duct.heated == (left=0.07, right=0.07)
    @test heated_perimeter(duct) == 0.14
    @test Duct(0.6, Rectangular(0.07, 0.00127); heated=0.063).heated == (left=0.063, right=0.063)
    @test Duct(0.6, Rectangular(0.07, 0.00127); heated=(left=0.07,)).heated == (left=0.07,)
    @test Duct(0.6, Rectangular(0.07, 0.00127); heated=(right=0.07,)).heated == (right=0.07,)
    # An unheated duct has no faces at all.
    @test heated_perimeter(Duct(0.6, Rectangular(0.07, 0.00127); heated=(;))) == 0.0
    # Only the long walls can be heated, and no wider than they are.
    @test_throws ArgumentError Duct(0.6, Rectangular(0.07, 0.00127); heated=(top=0.07,))
    @test_throws ArgumentError Duct(0.6, Rectangular(0.07, 0.00127); heated=(left=0.08,))
    @test_throws ArgumentError Duct(0.6, Rectangular(0.07, 0.00127); heated=(left=0.0,))
end

@testset "circular duct" begin
    duct = Duct(1.0, Circular(0.01))
    # Dh = D exactly for a circle, and A = π D² / 4 = 7.853981633974483e-5 m^2.
    @test hydraulic_diameter(duct) == 0.01
    @test isapprox(flow_area(duct), 7.853981633974483e-5; rtol=1e-12)
    @test isapprox(wetted_perimeter(duct), π * 0.01; rtol=1e-12)
    # Its one wall is heated all round.
    @test duct.heated == (outer=π * 0.01,)
    @test_throws ArgumentError Duct(1.0, Circular(0.01); heated=(left=0.01,))
    # A circle has no aspect ratio to give.
    @test_throws MethodError aspect_ratio(duct)
end

@testset "effective duct" begin
    shape = Effective(; area=1.0, wetted_perimeter=1.0)
    duct = Duct(1.2, shape; heated=(right=1.0,))
    @test hydraulic_diameter(duct) == 4.0
    @test flow_area(duct) == 1.0
    @test heated_perimeter(duct) == 1.0
    # Any wall names go, since the shape has no walls of its own.
    @test Duct(1.2, shape; heated=(rod=0.5, can=0.5)).heated == (rod=0.5, can=0.5)
    # There is no sensible default heated perimeter for a shape known only by its area.
    @test_throws ArgumentError Duct(1.2, shape)
end

@testset "annular duct" begin
    # A 10 mm rod in a 16 mm tube, in either order.
    duct = Duct(1.0, Annular(0.016, 0.010))
    @test duct.shape == Annular(0.010, 0.016)
    @test hydraulic_diameter(duct) ≈ 0.006
    @test flow_area(duct) ≈ π * (0.016^2 - 0.010^2) / 4
    @test wetted_perimeter(duct) ≈ π * 0.026
    # The rod is heated by default; the tube can be too.
    @test duct.heated == (inner=π * 0.010,)
    both = Duct(1.0, Annular(0.010, 0.016); heated=(inner=π * 0.010, outer=π * 0.016))
    @test heated_perimeter(both) ≈ π * 0.026
end

@testset "knob-driven duct" begin
    # Evaluate a symbolic expression at a knob value. Compiling it folds irrationals like π.
    at(expr, knob, val) = Symbolics.build_function(expr, knob; expression=Val{false})(val)

    d = @design_knob d = 0.02
    pipe = Duct(0.6, Circular(d))
    @test pipe.shape isa Circular{Num}
    @test hydraulic_diameter(pipe) isa Num
    @test flow_area(pipe) isa Num
    @test pipe.heated.outer isa Num
    fixed = Duct(0.6, Circular(0.02))
    @test isapprox(at(flow_area(pipe), d, 0.02), flow_area(fixed); rtol=1e-12)
    @test isapprox(at(hydraulic_diameter(pipe), d, 0.03), 0.03; rtol=1e-12)

    # A knob gap orders against the plate edge at whatever value the knob takes.
    gap = @design_knob gap = 0.0025
    rect = Duct(0.6, Rectangular(0.0665, gap))
    @test rect.shape isa Rectangular{Num}
    @test isapprox(at(rect.shape.width, gap, 0.0025), 0.0665; rtol=1e-12)
    @test isapprox(at(rect.shape.depth, gap, 0.0010), 0.0010; rtol=1e-12)
    @test isapprox(at(hydraulic_diameter(rect), gap, 0.0025),
                   hydraulic_diameter(Duct(0.6, Rectangular(0.0665, 0.0025))); rtol=1e-12)
    # The default heated width follows the width, so it is symbolic too.
    @test isapprox(at(rect.heated.left, gap, 0.0025), 0.0665; rtol=1e-12)
end

@testset "a channel carries its duct" begin
    geom = Duct(0.6, Circular(0.01))
    @test duct(Components.Channel(; name=:ch, n=3, geometry=geom)) === geom
    @test duct(Components.ChannelAndContacts(; name=:cac, n=3, geometry=geom)) === geom
    @test_throws ArgumentError duct(Components.Pump(1.0; name=:pump))
end

@testset "a fixed duct stays Float64" begin
    @test Duct(1.0, Circular(1 // 100)) isa Duct{Circular{Float64},Float64}
    @test Duct(1, Rectangular(0.07, 0.00127)) isa Duct{Rectangular{Float64},Float64}
    @test Duct(1, Rectangular(0.07, 0.00127)).heated isa NamedTuple{(:left, :right),NTuple{2,Float64}}
end
