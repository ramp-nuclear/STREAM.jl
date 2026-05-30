using Test
using STREAM
import STREAM: PipeGeometry_rectangular, PipeGeometry_circular

@testset "PHY-01: PipeGeometry_rectangular geometry" begin
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

@testset "PHY-01: PipeGeometry_circular geometry" begin
    geo = PipeGeometry_circular(1.0, 0.01)
    @test isapprox(geo.Dh, 0.01; rtol=1e-10)
    @test isapprox(geo.wet_perimeter, π * 0.01; rtol=1e-10)
    @test isapprox(geo.heated_parts[1], π * 0.01; rtol=1e-10)
    @test isapprox(geo.heated_parts[2], 0; atol=1e-10)
    @test isapprox(geo.A, π * 0.01^2 / 4; rtol=1e-10)
    @test geo.width == 0.01
    @test geo.depth == 0.01
end
