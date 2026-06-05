using Test
using STREAM

@testset "Threshold Analysis" begin

    # Shared test pipe: 0.6m long, 67.1mm x 2.4mm rectangular channel
    # Matches typical MTR fuel assembly geometry used in Python STREAM tests
    pipe = PipeGeometry_rectangular(0.6, 0.0671, 0.0024, 0.0671)

    @testset "bergles_rohsenow_t_onb" begin
        result = bergles_rohsenow_t_onb(1e5, 1e5, 373.15)
        @test result == 373.15 + STREAM._bergles_rohsenow_dT_ONB(1e5, 1e5)
        result2 = bergles_rohsenow_t_onb(1e5, 1e5, 350.0)
        @test result2 == 350.0 + STREAM._bergles_rohsenow_dT_ONB(1e5, 1e5)
        @test bergles_rohsenow_t_onb(1e5, 2e5, 373.15) >
            bergles_rohsenow_t_onb(1e5, 1e5, 373.15)
    end

    @testset "q_boiling_onset" begin
        @test q_boiling_onset(0.5, 373.15, 300.0, 4180.0) ≈ 0.5 * 4180.0 * (373.15 - 300.0) rtol =
            1e-10
        @test q_boiling_onset(-0.5, 373.15, 300.0, 4180.0) ≈
            q_boiling_onset(0.5, 373.15, 300.0, 4180.0)
        @test q_boiling_onset(0.5, 373.15, 373.15, 4180.0) ≈ 0.0 atol = 1e-10
        @test q_boiling_onset(1.0, 373.15, 300.0, 4180.0) >
            q_boiling_onset(0.5, 373.15, 300.0, 4180.0)
    end

    @testset "q_OFI_whittle_forgan" begin
        result = q_OFI_whittle_forgan(0.5, 373.15, 300.0, pipe)
        @test result > 0
        q_onset = q_boiling_onset(0.5, 373.15, 300.0, cp_water(300.0))
        @test result < q_onset
        @test q_OFI_whittle_forgan(-0.5, 373.15, 300.0, pipe) ≈ result rtol = 1e-10
    end

    @testset "q_OSV_saha_zuber" begin
        result = q_OSV_saha_zuber(300.0, 0.5, pipe)
        @test result > 0
        result2 = q_OSV_saha_zuber(
            300.0, 0.5, pipe; flux_shape=ones(10), dz=0.06 * ones(10)
        )
        @test result2 > 0
    end

    @testset "q_CHF_sudo_kaminaga" begin
        # Upward flow (positive gravity acceleration)
        result_up = q_CHF_sudo_kaminaga(320.0, 0.5, pipe, 9.81)
        @test result_up > 0
        @test result_up isa Float64
        result_cold = q_CHF_sudo_kaminaga(300.0, 0.5, pipe, 9.81)
        @test result_cold > 0
        @test result_cold >= result_up * 0.5  # sanity check: at least half
        result_down = q_CHF_sudo_kaminaga(320.0, 0.5, pipe, -9.81)
        @test result_down > 0
    end

    @testset "q_CHF_mirshak" begin
        v = 2.0
        T_bulk = 320.0
        T_sat = 373.15
        P = 1e5
        expected =
            1.51e6 * (1 + 0.1198 * v) * (1 + 0.00914 * (T_sat - T_bulk)) * (1 + 0.19e-5 * P)
        @test q_CHF_mirshak(T_bulk, T_sat, P, v) ≈ expected rtol = 1e-10
        # Higher velocity → higher CHF
        @test q_CHF_mirshak(320.0, 373.15, 1e5, 3.0) >
            q_CHF_mirshak(320.0, 373.15, 1e5, 2.0)
        # Higher subcooling → higher CHF
        @test q_CHF_mirshak(300.0, 373.15, 1e5, 2.0) >
            q_CHF_mirshak(320.0, 373.15, 1e5, 2.0)
    end

    @testset "q_CHF_fabrega" begin
        T_inlet = 300.0
        T_sat = 373.15
        expected = 1e7 * pipe.Dh * (0.023 * (T_sat - T_inlet) + 4.56)
        @test q_CHF_fabrega(T_inlet, T_sat, pipe) ≈ expected rtol = 1e-10
        @test q_CHF_fabrega(280.0, 373.15, pipe) > q_CHF_fabrega(300.0, 373.15, pipe)
    end

    @testset "twall_limit" begin
        @test twall_limit(400.0, 1.2) ≈ 480.0
        @test twall_limit(400.0) ≈ 400.0
        @test twall_limit(300.0, 1.0) ≈ 300.0
        @test twall_limit(400.0, 1.5) > twall_limit(400.0, 1.2)
    end
end

@testset "ChannelState and wrappers" begin
    pipe = PipeGeometry_rectangular(0.6, 0.0671, 0.0024, 0.0671)
    n = 5

    state = ChannelState(;
        n=n,
        T_bulk=fill(320.0, n),
        T_wall=fill(340.0, n),
        T_wall_left=fill(340.0, n),
        T_wall_right=fill(335.0, n),
        T_sat=fill(373.15, n),
        T_ONB=fill(380.0, n),
        T_inlet=300.0,
        P=fill(1e5, n),
        q_flux=fill(5e5, n),
        q_flux_left=fill(5e5, n),
        q_flux_right=fill(4e5, n),
        mdot=0.5,
        velocity=fill(3.0, n),
        pipe=pipe,
        gravity=9.81,
    )

    @testset "ChannelState construction" begin
        @test state.n == n
        @test length(state.T_bulk) == n
        @test state.T_inlet == 300.0
        @test state.mdot == 0.5
        @test state.gravity == 9.81
        @test state.pipe === pipe
    end

    @testset "onb_temperature wrapper" begin
        result = onb_temperature(state)
        @test length(result) == n
        # T_ONB from Bergles-Rohsenow must be > T_sat for non-zero q
        @test all(result .> state.T_sat)
    end

    @testset "mirshak_chf wrapper" begin
        result = mirshak_chf(state)
        @test length(result) == n
        @test all(result .> 0)
        expected_val =
            1.51e6 *
            (1 + 0.1198 * 3.0) *
            (1 + 0.00914 * (373.15 - 320.0)) *
            (1 + 0.19e-5 * 1e5)
        @test result[1] ≈ expected_val rtol = 1e-10
    end

    @testset "fabrega_chf wrapper" begin
        result = fabrega_chf(state)
        @test length(result) == n
        @test all(result .> 0)
        expected_val = 1e7 * pipe.Dh * (0.023 * (373.15 - 300.0) + 4.56)
        @test result[1] ≈ expected_val rtol = 1e-10
    end

    @testset "sudo_kaminaga_chf wrapper" begin
        result = sudo_kaminaga_chf(state)
        @test length(result) == n
        @test all(result .> 0)
    end

    @testset "boiling_onset_power wrapper" begin
        result = boiling_onset_power(state)
        @test length(result) == n
        @test all(result .> 0)
        expected_val = abs(0.5) * cp_water(320.0) * (373.15 - 300.0)
        @test result[1] ≈ expected_val rtol = 1e-8
    end

    @testset "OFI_power wrapper" begin
        result = OFI_power(state)
        @test result isa Float64
        @test result > 0
        q_onset = q_boiling_onset(0.5, 373.15, 300.0, cp_water(300.0))
        @test result < q_onset
    end

    @testset "twall_limit wrapper (ChannelState overload)" begin
        result = twall_limit(state; inhomogeneity_factor=1.2)
        @test length(result) == n
        @test all(result .≈ 340.0 * 1.2)
        result_default = twall_limit(state)
        @test all(result_default .≈ 340.0)
    end
end

@testset "chfr helper" begin
    pipe = PipeGeometry_rectangular(0.6, 0.0671, 0.0024, 0.0671)
    n = 3
    state = ChannelState(;
        n=n,
        T_bulk=fill(320.0, n),
        T_wall=fill(340.0, n),
        T_wall_left=fill(340.0, n),
        T_wall_right=fill(335.0, n),
        T_sat=fill(373.15, n),
        T_ONB=fill(380.0, n),
        T_inlet=300.0,
        P=fill(1e5, n),
        q_flux=fill(5e5, n),
        q_flux_left=fill(5e5, n),
        q_flux_right=fill(4e5, n),
        mdot=0.5,
        velocity=fill(3.0, n),
        pipe=pipe,
        gravity=9.81,
    )

    ratio_fn = chfr(mirshak_chf; direction=:max)
    ratios = ratio_fn(state)
    @test length(ratios) == n
    @test all(ratios .> 0)

    ratio_left = chfr(mirshak_chf; direction=:left)(state)
    ratio_right = chfr(mirshak_chf; direction=:right)(state)
    ratio_total = chfr(mirshak_chf; direction=:total)(state)
    @test length(ratio_left) == n
    @test length(ratio_right) == n
    @test length(ratio_total) == n
    @test all(ratio_right .>= ratio_left)

    state_zero = ChannelState(;
        n=n,
        T_bulk=fill(320.0, n),
        T_wall=fill(340.0, n),
        T_wall_left=fill(340.0, n),
        T_wall_right=fill(335.0, n),
        T_sat=fill(373.15, n),
        T_ONB=fill(380.0, n),
        T_inlet=300.0,
        P=fill(1e5, n),
        q_flux=fill(0.0, n),
        q_flux_left=fill(0.0, n),
        q_flux_right=fill(0.0, n),
        mdot=0.5,
        velocity=fill(3.0, n),
        pipe=pipe,
        gravity=9.81,
    )
    ratios_zero = ratio_fn(state_zero)
    @test all(ratios_zero .== Inf)
    @test_throws ArgumentError chfr(mirshak_chf; direction=:bad)(state)
end

@testset "threshold_analysis dispatch" begin
    pipe = PipeGeometry_rectangular(0.6, 0.0671, 0.0024, 0.0671)
    n = 3
    state = ChannelState(;
        n=n,
        T_bulk=fill(320.0, n),
        T_wall=fill(340.0, n),
        T_wall_left=fill(340.0, n),
        T_wall_right=fill(335.0, n),
        T_sat=fill(373.15, n),
        T_ONB=fill(380.0, n),
        T_inlet=300.0,
        P=fill(1e5, n),
        q_flux=fill(5e5, n),
        q_flux_left=fill(5e5, n),
        q_flux_right=fill(4e5, n),
        mdot=0.5,
        velocity=fill(3.0, n),
        pipe=pipe,
        gravity=9.81,
    )

    manual_result = (mirshak=mirshak_chf(state), onb=onb_temperature(state))
    @test manual_result.mirshak isa AbstractArray
    @test manual_result.onb isa AbstractArray
    @test length(manual_result.mirshak) == n
    @test length(manual_result.onb) == n

    mirshak_chfr = chfr(mirshak_chf; direction=:max)
    chfr_result = mirshak_chfr(state)
    @test length(chfr_result) == n
    @test all(chfr_result .> 0)
end
