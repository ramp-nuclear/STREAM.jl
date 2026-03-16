using Test
using STREAM
import STREAM: PipeGeometry_rectangular, PipeGeometry_circular

@testset "PHY-01: PipeGeometry_rectangular geometry" begin
    # MTR geometry: edge1=0.07 m (plate width), edge2=0.00127 m (channel gap), heated_edge=0.07 m
    geo = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
    # area = 0.07 * 0.00127 = 8.89e-5 m²
    @test isapprox(geo.A, 0.07 * 0.00127; rtol=1e-4)
    # wet_perimeter = 2*(0.07 + 0.00127) = 0.14254 m
    @test isapprox(geo.wet_perimeter, 2.0 * (0.07 + 0.00127); rtol=1e-4)
    # Dh = 4*area/wet_perimeter ≈ 0.002495 m
    @test isapprox(geo.Dh, 4.0 * (0.07 * 0.00127) / (2.0 * (0.07 + 0.00127)); rtol=1e-4)
    # width = max(edge1, edge2) = 0.07; depth = min(edge1, edge2) = 0.00127
    @test geo.width == 0.07
    @test geo.depth == 0.00127
    # two-sided: heated_parts = (heated_edge, heated_edge)
    @test geo.heated_parts == (0.07, 0.07)
    # one_sided=:left
    geo_l = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07, one_sided=:left)
    @test geo_l.heated_parts == (0.07, 0.0)
    # one_sided=:right
    geo_r = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07, one_sided=:right)
    @test geo_r.heated_parts == (0.0, 0.07)
    # invalid one_sided throws
    @test_throws Exception PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07, one_sided=:bad_value)
end

@testset "PHY-01: PipeGeometry_circular geometry" begin
    geo = PipeGeometry_circular(1.0, 0.01)
    # Dh == D for circular pipe
    @test isapprox(geo.Dh, 0.01; rtol=1e-10)
    # wet_perimeter = π*D
    @test isapprox(geo.wet_perimeter, π * 0.01; rtol=1e-10)
    # heated_parts symmetric split
    @test isapprox(geo.heated_parts[1], π * 0.01 / 2; rtol=1e-10)
    @test isapprox(geo.heated_parts[2], π * 0.01 / 2; rtol=1e-10)
    # area = π*D²/4
    @test isapprox(geo.A, π * 0.01^2 / 4; rtol=1e-10)
    # circular: width == depth == D
    @test geo.width == 0.01
    @test geo.depth == 0.01
end
