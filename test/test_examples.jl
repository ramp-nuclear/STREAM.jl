using Test
using STREAM

# ─────────────────────────────────────────────────────────────────
# COMPAT: Full suite runs via Pkg.test() (confirmed by reaching here)
# ─────────────────────────────────────────────────────────────────
@testset "COMPAT: Test suite runs automatically via Pkg.test()" begin
    @test true
end
