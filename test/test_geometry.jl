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
    @test duct.heated == (0.07, 0.07)
    @test heated_perimeter(duct) == 0.14
    @test Duct(0.6, Rectangular(0.07, 0.00127); heated=0.063).heated == (0.063, 0.063)
    @test Duct(0.6, Rectangular(0.07, 0.00127); heated=(0.07, 0)).heated == (0.07, 0.0)
    @test Duct(0.6, Rectangular(0.07, 0.00127); heated=(0, 0.07)).heated == (0.0, 0.07)
end

@testset "circular duct" begin
    duct = Duct(1.0, Circular(0.01))
    # Dh = D exactly for a circle, and A = π D² / 4 = 7.853981633974483e-5 m^2.
    @test hydraulic_diameter(duct) == 0.01
    @test isapprox(flow_area(duct), 7.853981633974483e-5; rtol=1e-12)
    @test isapprox(wetted_perimeter(duct), π * 0.01; rtol=1e-12)
    # The whole perimeter is heated, and counted as the left face, as in Python STREAM.
    @test duct.heated == (π * 0.01, 0.0)
    # A circle has no aspect ratio to give.
    @test_throws MethodError aspect_ratio(duct)
end

@testset "effective duct" begin
    shape = Effective(; area=1.0, wetted_perimeter=1.0)
    duct = Duct(1.2, shape; heated=(0, 1.0))
    @test hydraulic_diameter(duct) == 4.0
    @test flow_area(duct) == 1.0
    @test heated_perimeter(duct) == 1.0
    # There is no sensible default heated perimeter for a shape known only by its area.
    @test_throws ArgumentError Duct(1.2, shape)
end

@testset "knob-driven duct" begin
    # Evaluate a symbolic expression at a knob value. Compiling it folds irrationals like π.
    at(expr, knob, val) = Symbolics.build_function(expr, knob; expression=Val{false})(val)

    d = @design_knob d = 0.02
    pipe = Duct(0.6, Circular(d))
    @test pipe.shape isa Circular{Num}
    @test hydraulic_diameter(pipe) isa Num
    @test flow_area(pipe) isa Num
    @test pipe.heated[1] isa Num
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
    @test isapprox(at(rect.heated[1], gap, 0.0025), 0.0665; rtol=1e-12)
end

@testset "a fixed duct stays Float64" begin
    @test Duct(1.0, Circular(1 // 100)) isa Duct{Circular{Float64},Float64}
    @test Duct(1, Rectangular(0.07, 0.00127)) isa Duct{Rectangular{Float64},Float64}
end
