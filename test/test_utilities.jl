using Test
using STREAM
import STREAM: rebin_extensive, cosine_power_shape

# Phase 62 — Conservation invariants for the rebin/cosine helpers.
#
# Per RESEARCH Pitfall 6, this file tests ONLY sum-conservation. Different
# separable-pass orderings can produce per-cell values that differ at ULP,
# which is fine — we do not assert per-cell equivalence between orderings.
#
# Per D-25 + project memory `feedback_power_shape_trust_caller.md`, this file
# does NOT add validation tests on negative / NaN / shape-mismatch inputs.
# The caller-trust contract means those are explicitly the caller's problem,
# not a function-level guard.

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
    # For nz=10, mid cells 5 and 6 are tallest; both should exceed the
    # extremes at i=1 and i=10.
    @test M[5, 1] > M[1, 1]
    @test M[5, 1] > M[10, 1]
    @test M[6, 1] > M[1, 1]
    @test M[6, 1] > M[10, 1]

    # amplitude scaling is linear.
    M2 = cosine_power_shape(nz, nx; amplitude=2.5)
    @test all(isapprox.(M2, 2.5 .* M; rtol=1e-12))
end
