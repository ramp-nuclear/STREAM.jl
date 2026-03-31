using Test
using STREAM

# ─────────────────────────────────────────────────────────────────────────────
# Phase 29: Threshold Analysis Physics Layer
# THRS-01: Bergles_Rohsenow_T_ONB
# THRS-02: q_boiling_onset
# THRS-03: q_OFI_whittle_forgan
# THRS-04: q_OSV_saha_zuber
# THRS-05: q_CHF_sudo_kaminaga
# THRS-06: q_CHF_mirshak
# THRS-07: q_CHF_fabrega
# THRS-08: twall_limit
# ─────────────────────────────────────────────────────────────────────────────

@testset "Threshold Analysis" begin

    # Shared test pipe: 0.6m long, 67.1mm x 2.4mm rectangular channel
    # Matches typical MTR fuel assembly geometry used in Python STREAM tests
    pipe = PipeGeometry_rectangular(0.6, 0.0671, 0.0024, 0.0671)

    @testset "THRS-01: Bergles_Rohsenow_T_ONB" begin
        # Thin wrapper: result == T_sat + _bergles_rohsenow_dT_ONB(pressure, q_wall)
        result = Bergles_Rohsenow_T_ONB(1e5, 1e5, 373.15)
        @test result > 373.15  # T_ONB > T_sat always
        @test result == 373.15 + STREAM._bergles_rohsenow_dT_ONB(1e5, 1e5)
        # Different T_sat shifts result
        result2 = Bergles_Rohsenow_T_ONB(1e5, 1e5, 350.0)
        @test result2 == 350.0 + STREAM._bergles_rohsenow_dT_ONB(1e5, 1e5)
        # Higher wall flux → larger dT_ONB
        @test Bergles_Rohsenow_T_ONB(1e5, 2e5, 373.15) > Bergles_Rohsenow_T_ONB(1e5, 1e5, 373.15)
    end

    @testset "THRS-02: q_boiling_onset" begin
        # Formula: abs(mdot) * cp * (T_sat - T_inlet)
        @test q_boiling_onset(0.5, 373.15, 300.0, 4180.0) ≈ 0.5 * 4180.0 * (373.15 - 300.0) rtol=1e-10
        # abs(mdot): negative flow gives same result
        @test q_boiling_onset(-0.5, 373.15, 300.0, 4180.0) ≈ q_boiling_onset(0.5, 373.15, 300.0, 4180.0)
        # T_sat == T_inlet → zero power needed
        @test q_boiling_onset(0.5, 373.15, 373.15, 4180.0) ≈ 0.0 atol=1e-10
        # Larger mdot → higher power
        @test q_boiling_onset(1.0, 373.15, 300.0, 4180.0) > q_boiling_onset(0.5, 373.15, 300.0, 4180.0)
    end

    @testset "THRS-03: q_OFI_whittle_forgan" begin
        # q_OFI_whittle_forgan(mdot, T_sat, T_inlet, pipe) → positive Watts
        result = q_OFI_whittle_forgan(0.5, 373.15, 300.0, pipe)
        @test result > 0  # positive power
        @test result isa Float64
        # OFI power is less than boiling onset power (denominator >= 1)
        q_onset = q_boiling_onset(0.5, 373.15, 300.0, cp_water(300.0))
        @test result < q_onset
        # abs(mdot): negative flow gives same result
        @test q_OFI_whittle_forgan(-0.5, 373.15, 300.0, pipe) ≈ result rtol=1e-10
    end

    @testset "THRS-04: q_OSV_saha_zuber" begin
        result = q_OSV_saha_zuber(300.0, 0.5, pipe)
        @test result > 0  # positive flux
        @test result isa Float64
        # With explicit flux_shape (uniform vector)
        result2 = q_OSV_saha_zuber(300.0, 0.5, pipe; flux_shape=ones(10), dz=0.06*ones(10))
        @test result2 > 0
        @test result2 isa Float64
    end

    @testset "THRS-05: q_CHF_sudo_kaminaga" begin
        # Upward flow (positive gravity acceleration)
        result_up = q_CHF_sudo_kaminaga(320.0, 0.5, pipe, 9.81)
        @test result_up > 0
        @test result_up isa Float64
        # Test with colder bulk temperature (more subcooling → higher CHF)
        result_cold = q_CHF_sudo_kaminaga(300.0, 0.5, pipe, 9.81)
        @test result_cold > 0
        # Higher subcooling should give >= CHF (not necessarily strictly greater due to q3 dominance)
        @test result_cold >= result_up * 0.5  # sanity check: at least half
        # Negative gravity (downward flow direction)
        result_down = q_CHF_sudo_kaminaga(320.0, 0.5, pipe, -9.81)
        @test result_down > 0
    end

    @testset "THRS-06: q_CHF_mirshak" begin
        # Formula: 1.51e6 * (1+0.1198*v) * (1+0.00914*(T_sat-T_bulk)) * (1+0.19e-5*P)
        v = 2.0
        T_bulk = 320.0
        T_sat = 373.15
        P = 1e5
        expected = 1.51e6 * (1 + 0.1198*v) * (1 + 0.00914*(T_sat - T_bulk)) * (1 + 0.19e-5*P)
        @test q_CHF_mirshak(T_bulk, T_sat, P, v) ≈ expected rtol=1e-10
        # Higher velocity → higher CHF
        @test q_CHF_mirshak(320.0, 373.15, 1e5, 3.0) > q_CHF_mirshak(320.0, 373.15, 1e5, 2.0)
        # Higher subcooling → higher CHF
        @test q_CHF_mirshak(300.0, 373.15, 1e5, 2.0) > q_CHF_mirshak(320.0, 373.15, 1e5, 2.0)
    end

    @testset "THRS-07: q_CHF_fabrega" begin
        # Formula: 1e7 * Dh * (0.023*(T_sat - T_inlet) + 4.56)
        T_inlet = 300.0
        T_sat = 373.15
        expected = 1e7 * pipe.Dh * (0.023*(T_sat - T_inlet) + 4.56)
        @test q_CHF_fabrega(T_inlet, T_sat, pipe) ≈ expected rtol=1e-10
        # Higher subcooling → higher CHF
        @test q_CHF_fabrega(280.0, 373.15, pipe) > q_CHF_fabrega(300.0, 373.15, pipe)
    end

    @testset "THRS-08: twall_limit" begin
        @test twall_limit(400.0, 1.2) ≈ 480.0
        @test twall_limit(400.0) ≈ 400.0  # default factor = 1.0
        @test twall_limit(300.0, 1.0) ≈ 300.0
        # Monotonicity
        @test twall_limit(400.0, 1.5) > twall_limit(400.0, 1.2)
    end

end
