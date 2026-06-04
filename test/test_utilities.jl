using Test
using STREAM
using STREAM: rebin_extensive, rebin_intensive, cosine_power_shape, cosine_T_wall_profile

# Invariants for the rebin / cosine helpers. We check that extensive rebinning
# preserves the total and intensive rebinning preserves the value; per-cell
# numbers can differ at ULP between separable-pass orderings, which is fine.
# Inputs are trusted, so there are no negative / NaN / shape-mismatch tests.

@testset "INT-00: split-a-cell contract (extensive halves, intensive copies)" begin
    # Splitting one cell in two: an amount halves, a value copies.
    @test rebin_extensive([10.0], 2) == [5.0, 5.0]
    @test rebin_intensive([10.0], 2) == [10.0, 10.0]
    # Merging two cells: amounts add, values average.
    @test rebin_extensive([3.0, 7.0], 1) == [10.0]
    @test rebin_intensive([3.0, 7.0], 1) == [5.0]
end

@testset "CONS-02: rebin_extensive identity (target_shape == size(M))" begin
    # Strict equality on a random 4x6 Float64 matrix.
    M = rand(4, 6)
    out = rebin_extensive(M, size(M))
    @test out == M
    @test eltype(out) === Float64
    @test size(out) == (4, 6)
end

@testset "CONS-01: rebin_extensive sum-conservation across all reshape regimes" begin
    rtol = 1e-12

    # (a) identity 4x4 -> 4x4
    M = rand(4, 4)
    @test isapprox(sum(rebin_extensive(M, (4, 4))), sum(M); rtol=rtol)

    # (b) integer up 3x3 -> 9x9
    M = rand(3, 3)
    @test isapprox(sum(rebin_extensive(M, (9, 9))), sum(M); rtol=rtol)

    # (c) integer down 9x9 -> 3x3
    M = rand(9, 9)
    @test isapprox(sum(rebin_extensive(M, (3, 3))), sum(M); rtol=rtol)

    # (d) non-integer up 5x5 -> 7x3
    M = rand(5, 5)
    @test isapprox(sum(rebin_extensive(M, (7, 3))), sum(M); rtol=rtol)

    # (e) non-integer down 4x6 -> 7x5
    M = rand(4, 6)
    @test isapprox(sum(rebin_extensive(M, (7, 5))), sum(M); rtol=rtol)

    # (f) 1xN row degenerate: 1x8 -> 1x3 and 1x8 -> 5x8
    M = rand(1, 8)
    @test isapprox(sum(rebin_extensive(M, (1, 3))), sum(M); rtol=rtol)
    @test isapprox(sum(rebin_extensive(M, (5, 8))), sum(M); rtol=rtol)

    # (g) Nx1 column degenerate: 8x1 -> 3x1 and 8x1 -> 8x5
    M = rand(8, 1)
    @test isapprox(sum(rebin_extensive(M, (3, 1))), sum(M); rtol=rtol)
    @test isapprox(sum(rebin_extensive(M, (8, 5))), sum(M); rtol=rtol)

    # (h) all-zeros: zeros(4,6) -> 7x5  (sum stays zero)
    M = zeros(4, 6)
    @test sum(rebin_extensive(M, (7, 5))) == 0.0

    # (i) all-ones: ones(4,6) -> 7x5  (sum = 24)
    M = ones(4, 6)
    @test isapprox(sum(rebin_extensive(M, (7, 5))), sum(M); rtol=rtol)
end

@testset "CONS-03: rebin_extensive uniform input scales by area ratio" begin
    # rebin_extensive(ones(a,b), (c,d)) == (a*b / (c*d)) * ones(c,d)
    a, b = 3, 4
    c, d = 7, 5
    out = rebin_extensive(ones(a, b), (c, d))
    expected = (a * b) / (c * d)
    @test size(out) == (c, d)
    @test all(isapprox.(out, expected; rtol=1e-12))
end

@testset "CONS-04: cosine_power_shape shape + axial cosine + uniform-along-x" begin
    nz, nx = 10, 5
    M = cosine_power_shape(nz, nx; amplitude=1.0)

    # shape + element type
    @test size(M) == (nz, nx)
    @test eltype(M) === Float64

    # uniform along x: every column equals column 1.
    for j in 1:nx
        @test M[:, j] == M[:, 1]
    end

    # peak near axial center (cell-centered cos^2 peaks at i = nz/2).
    @test M[5, 1] > M[1, 1]
    @test M[5, 1] > M[10, 1]
    @test M[6, 1] > M[1, 1]
    @test M[6, 1] > M[10, 1]

    # amplitude scaling is linear.
    M2 = cosine_power_shape(nz, nx; amplitude=2.5)
    @test all(isapprox.(M2, 2.5 .* M; rtol=1e-12))
end

@testset "INT-01: rebin_intensive keeps a constant field constant across reshapes" begin
    rtol = 1e-12
    @test all(isapprox.(rebin_intensive(ones(4), 4), 1.0; rtol=rtol))   # 4 -> 4
    @test all(isapprox.(rebin_intensive(ones(3), 9), 1.0; rtol=rtol))   # up 3 -> 9
    @test all(isapprox.(rebin_intensive(ones(9), 3), 1.0; rtol=rtol))   # down 9 -> 3
    @test all(isapprox.(rebin_intensive(ones(7), 13), 1.0; rtol=rtol))  # up 7 -> 13
    @test all(isapprox.(rebin_intensive(ones(13), 7), 1.0; rtol=rtol))  # down 13 -> 7
end

@testset "INT-02: rebin_intensive preserves the average" begin
    # Each target cell holds the area-weighted average of the source it covers,
    # so the average over the whole vector is unchanged: sum(out)/M == sum(v)/N.
    rtol = 1e-12
    for (N, M) in ((4, 4), (3, 9), (9, 3), (7, 13), (13, 7))
        v = rand(N)
        @test isapprox(sum(rebin_intensive(v, M)) / M, sum(v) / N; rtol=rtol)
    end
end

@testset "INT-03: rebin_intensive n -> n is the identity" begin
    v = [1.0, 2.0, 3.0, 4.0]
    @test rebin_intensive(v, 4) == v
end

@testset "INT-04: rebin_intensive 2D preserves the average" begin
    rtol = 1e-12
    for (src, tgt) in (((3, 5), (9, 15)), ((9, 15), (3, 5)), ((7, 7), (13, 11)))
        M = rand(src...)
        out = rebin_intensive(M, tgt)
        @test isapprox(sum(out) / prod(tgt), sum(M) / prod(src); rtol=rtol)
    end
end

@testset "INT-06: non-uniform edges (extensive sum, intensive value)" begin
    rtol = 1e-12
    src = [0.0, 0.2, 0.5, 1.0]   # 3 unequal source cells
    tgt = [0.0, 0.5, 1.0]        # 2 uniform target cells
    v = [10.0, 20.0, 30.0]

    # extensive: total preserved even on a non-uniform source
    @test isapprox(sum(rebin_extensive(v, src, tgt)), sum(v); rtol=rtol)
    # intensive: a constant field stays constant on any grid
    @test all(isapprox.(rebin_intensive(fill(7.0, 3), src, tgt), 7.0; rtol=rtol))

    # passing uniform edges reproduces the (v, n) forms exactly
    su = collect(range(0.0, 1.0; length=4))
    tu = collect(range(0.0, 1.0; length=3))
    @test isapprox(rebin_extensive(v, su, tu), rebin_extensive(v, 2); rtol=rtol)
    @test isapprox(rebin_intensive(v, su, tu), rebin_intensive(v, 2); rtol=rtol)
end

@testset "CT-01: cosine_T_wall_profile shape and amplitude scaling" begin
    rtol = 1e-12

    c = cosine_T_wall_profile(10; amplitude=1.0)
    @test length(c) == 10
    @test all(c .>= 0)

    # mirror-symmetric about midplane (cell-centered cos^2)
    @test isapprox(c, reverse(c); rtol=rtol)

    # amplitude scales the peak linearly
    c2 = cosine_T_wall_profile(10; amplitude=2.0)
    @test isapprox(maximum(c2), 2 * maximum(c); rtol=rtol)
end
