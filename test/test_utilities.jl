using Test
using STREAM
import STREAM: rebin_extensive, rebin_intensive, cosine_power_shape, cosine_T_wall_profile

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


# =====================================================================
# Phase 63 — rebin_intensive + cosine_T_wall_profile testsets.
#
# Mirrors CONS-01..04 testset discipline. Per D-15 / D-16 + caller-trust
# memory: no NaN / negative / shape-mismatch tests. INT-05 implements the
# cross-check identity with rebin_extensive (the mean<->sum duality).
# =====================================================================

@testset "INT-01: rebin_intensive uniform-input preservation across reshape regimes" begin
    rtol = 1e-12

    # (a) identity 4 -> 4
    @test all(isapprox.(rebin_intensive(ones(4), 4), 1.0; rtol=rtol))

    # (b) integer up 3 -> 9
    @test all(isapprox.(rebin_intensive(ones(3), 9), 1.0; rtol=rtol))

    # (c) integer down 9 -> 3
    @test all(isapprox.(rebin_intensive(ones(9), 3), 1.0; rtol=rtol))

    # (d) non-integer up 7 -> 13
    @test all(isapprox.(rebin_intensive(ones(7), 13), 1.0; rtol=rtol))

    # (e) non-integer down 13 -> 7
    @test all(isapprox.(rebin_intensive(ones(13), 7), 1.0; rtol=rtol))
end

@testset "INT-02: rebin_intensive area-weighted mean conservation for non-uniform inputs" begin
    rtol = 1e-12

    # (a) identity 4 -> 4
    v = rand(4)
    @test isapprox(sum(rebin_intensive(v, 4)) / 4, sum(v) / 4; rtol=rtol)

    # (b) integer up 3 -> 9
    v = rand(3)
    @test isapprox(sum(rebin_intensive(v, 9)) / 9, sum(v) / 3; rtol=rtol)

    # (c) integer down 9 -> 3
    v = rand(9)
    @test isapprox(sum(rebin_intensive(v, 3)) / 3, sum(v) / 9; rtol=rtol)

    # (d) non-integer up 7 -> 13
    v = rand(7)
    @test isapprox(sum(rebin_intensive(v, 13)) / 13, sum(v) / 7; rtol=rtol)

    # (e) non-integer down 13 -> 7
    v = rand(13)
    @test isapprox(sum(rebin_intensive(v, 7)) / 7, sum(v) / 13; rtol=rtol)
end

@testset "INT-03: rebin_intensive identity fast-path is byte-exact" begin
    v = [1.0, 2.0, 3.0, 4.0]
    @test rebin_intensive(v, 4) == v
end

@testset "INT-04: rebin_intensive 2D area-weighted mean conservation" begin
    rtol = 1e-12

    # (a) integer up 3x5 -> 9x15
    M = rand(3, 5)
    out = rebin_intensive(M, (9, 15))
    @test isapprox(sum(out) / (9 * 15), sum(M) / (3 * 5); rtol=rtol)

    # (b) integer down 9x15 -> 3x5
    M = rand(9, 15)
    out = rebin_intensive(M, (3, 5))
    @test isapprox(sum(out) / (3 * 5), sum(M) / (9 * 15); rtol=rtol)

    # (c) non-integer 7x7 -> 13x11
    M = rand(7, 7)
    out = rebin_intensive(M, (13, 11))
    @test isapprox(sum(out) / (13 * 11), sum(M) / (7 * 7); rtol=rtol)
end

@testset "INT-05: rebin_intensive <-> rebin_extensive cross-check (D-15)" begin
    # For any v of length N and any target M:
    #   rebin_intensive(v, M) .* N == rebin_extensive(v, M) .* M
    # Derivation: ones(N) sanity -- LHS = N*ones(M), RHS = N*ones(M).
    # The mirror form .* M ≈ .* N would only hold when M==N.
    rtol = 1e-12

    # (a) identity 4 -> 4
    N, MM = 4, 4
    v = rand(N)
    @test isapprox(rebin_intensive(v, MM) .* N, rebin_extensive(v, MM) .* MM; rtol=rtol)

    # (b) integer up 3 -> 9
    N, MM = 3, 9
    v = rand(N)
    @test isapprox(rebin_intensive(v, MM) .* N, rebin_extensive(v, MM) .* MM; rtol=rtol)

    # (c) integer down 9 -> 3
    N, MM = 9, 3
    v = rand(N)
    @test isapprox(rebin_intensive(v, MM) .* N, rebin_extensive(v, MM) .* MM; rtol=rtol)

    # (d) non-integer up 7 -> 13
    N, MM = 7, 13
    v = rand(N)
    @test isapprox(rebin_intensive(v, MM) .* N, rebin_extensive(v, MM) .* MM; rtol=rtol)

    # (e) non-integer down 13 -> 7
    N, MM = 13, 7
    v = rand(N)
    @test isapprox(rebin_intensive(v, MM) .* N, rebin_extensive(v, MM) .* MM; rtol=rtol)
end

@testset "CT-01: cosine_T_wall_profile shape and amplitude scaling" begin
    rtol = 1e-12

    # length
    c = cosine_T_wall_profile(10; amplitude=1.0)
    @test length(c) == 10

    # all non-negative
    @test all(c .>= 0)

    # mirror-symmetric about midplane (cell-centered cos^2)
    @test isapprox(c, reverse(c); rtol=rtol)

    # amplitude scales the peak linearly
    c1 = cosine_T_wall_profile(10; amplitude=1.0, peaking_factor=1.0)
    c2 = cosine_T_wall_profile(10; amplitude=2.0, peaking_factor=1.0)
    @test isapprox(maximum(c2), 2 * maximum(c1); rtol=rtol)

    # peaking_factor folds into amplitude (CD-02 thin-alias contract)
    c3 = cosine_T_wall_profile(10; amplitude=1.0, peaking_factor=2.0)
    @test isapprox(c3, c2; rtol=rtol)
end
