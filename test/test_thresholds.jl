using Test
using STREAM

@testset "Threshold Analysis" begin

    # Shared test pipe: 0.6m long, 67.1mm x 2.4mm rectangular channel
    # Matches typical MTR fuel assembly geometry used in Python STREAM tests
    pipe = PipeGeometry_rectangular(0.6, 0.0671, 0.0024, 0.0671)

    # Anchors below come from Python STREAM run under conda env stream-env
    # (the project at ~/projects/STREAM, imported as `stream`). Each expected number
    # was printed by calling the matching Python function with inputs that mirror the
    # Julia inputs exactly, then pasted here. Julia and Python share the same formulas
    # and IEEE-double constants, so they agree to ~13-16 significant figures; the
    # rtol = 1e-9 below is set by that agreement, not tuned to pass. The OFI integral
    # is the one exception (two different adaptive quadratures) and gets rtol = 1e-7.

    @testset "bergles_rohsenow_t_onb" begin
        # Anchor: Python physical_models...temperatures.Bergles_Rohsenow_dT_ONB(pressure, q).
        # Julia adds dT to T_sat; Python adds the same dT (in K) to Tsat (in C). The dT is
        # what the correlation actually produces, so we anchor T_ONB = base + Python dT.
        # Bergles_Rohsenow_dT_ONB(1e5, 1e5) -> 4.520927784528019
        dT_1e5_1e5 = 4.520927784528019
        @test bergles_rohsenow_t_onb(1e5, 1e5, 100.0) ≈ 100.0 + dT_1e5_1e5 rtol = 1e-9
        @test bergles_rohsenow_t_onb(1e5, 1e5, 76.85) ≈ 76.85 + dT_1e5_1e5 rtol = 1e-9

        # Off-atmospheric pressure exercises the p-dependent exponents.
        # Bergles_Rohsenow_dT_ONB(2e5, 5e5) -> 6.84338482835126
        dT_2e5_5e5 = 6.84338482835126
        @test bergles_rohsenow_t_onb(2e5, 5e5, 98.85) ≈ 98.85 + dT_2e5_5e5 rtol = 1e-9

        # Bergles_Rohsenow_dT_ONB(1e5, 2e5) -> 6.2316701544241235 (higher flux -> higher dT).
        @test bergles_rohsenow_t_onb(1e5, 2e5, 100.0) ≈ 100.0 + 6.2316701544241235 rtol = 1e-9
        @test bergles_rohsenow_t_onb(1e5, 2e5, 100.0) >
            bergles_rohsenow_t_onb(1e5, 1e5, 100.0)
    end

    @testset "q_boiling_onset" begin
        @test q_boiling_onset(0.5, 100.0, 26.85, 4180.0) ≈ 0.5 * 4180.0 * (100.0 - 26.85) rtol =
            1e-10
        @test q_boiling_onset(-0.5, 100.0, 26.85, 4180.0) ≈
            q_boiling_onset(0.5, 100.0, 26.85, 4180.0)
        @test q_boiling_onset(0.5, 100.0, 100.0, 4180.0) ≈ 0.0 atol = 1e-10
        @test q_boiling_onset(1.0, 100.0, 26.85, 4180.0) >
            q_boiling_onset(0.5, 100.0, 26.85, 4180.0)
    end

    @testset "q_OFI_whittle_forgan" begin
        # Anchor: Python physical_models.thresholds.Whittle_Forgan_OFI with the same pipe,
        # ṁ=0.5, and cp = light_water.specific_heat integrated over the same physical
        # range. Both sides now take Celsius, so the Python call used the same inlet=26.85,
        # sat=100.0. cp(26.85) = 4177.78 on both, confirming the same Simantov correlation.
        # Whittle_Forgan_OFI(...) -> 135474.34677914483.
        result = q_OFI_whittle_forgan(0.5, 100.0, 26.85, pipe)
        @test result ≈ 135474.34677914483 rtol = 1e-7  # two adaptive quadratures
        # ṁ sign does not change OFI (the function takes |ṁ| and |G|).
        @test q_OFI_whittle_forgan(-0.5, 100.0, 26.85, pipe) ≈ result rtol = 1e-10
        # OFI power stays below the boiling-onset power for the same channel.
        q_onset = q_boiling_onset(0.5, 100.0, 26.85, cₚ(H2O, 26.85))
        @test result < q_onset
    end

    @testset "q_OSV_saha_zuber" begin
        # Anchor: Python physical_models.thresholds.Saha_Zuber_OSV_computed_bulk, fed a
        # Liquid carrying STREAM's own ρ/cₚ/k at T_inlet=26.85 and
        # Tsat(H2O, 1e5) = 99.63 (so the Python coolant matches Julia bit-for-bit).
        # Pipe and 10-cell uniform flux match the Julia inputs. Reported value is the
        # minimum cell. (Python's numba `directed` was monkeypatched to its plain-numpy
        # equivalent so the function would run; the formula is untouched.)
        #
        # The two branches of the Pe<>70000 switch are still exercised. ṁ=0.5 hits the
        # convective St_c branch; ṁ=0.3 hits the conductive Nu_c branch. We keep an
        # explicit Pe guard so a future constant change that silently flips the branch is
        # caught rather than passing on the wrong branch.
        Nu_c = 455.0
        St_c = 0.0065
        function pe_at(ṁ)
            G = abs(ṁ) / pipe.A
            return G * pipe.Dh * cₚ(H2O, 26.85) / κ(H2O, 26.85)
        end

        # High-Pe (convective) branch: Saha_Zuber_OSV_computed_bulk(ṁ=0.5) -> 1443852.2363455354
        @test pe_at(0.5) >= 7e4  # guard: must be the convective St_c branch
        @test q_OSV_saha_zuber(26.85, 0.5, pipe) ≈ 1443852.2363455354 rtol = 1e-9

        # Low-Pe (conductive) branch: Saha_Zuber_OSV_computed_bulk(ṁ=0.3) -> 899904.7329676608
        @test pe_at(0.3) < 7e4  # guard: must be the conductive Nu_c branch
        @test q_OSV_saha_zuber(26.85, 0.3, pipe) ≈ 899904.7329676608 rtol = 1e-9

        # Explicit flux_shape + dz path (dz = 0.06 each, uniform shape). Same total length
        # as the uniform default, so Python returns the same value:
        # Saha_Zuber_OSV_computed_bulk(ṁ=0.5, dz=0.06) -> 1443852.2363455354
        @test q_OSV_saha_zuber(26.85, 0.5, pipe; flux_shape=ones(10), dz=0.06 * ones(10)) ≈
            1443852.2363455354 rtol = 1e-9
    end

    @testset "q_CHF_sudo_kaminaga" begin
        # Anchor: Python physical_models.thresholds.Sudo_Kaminaga_CHF, fed a sat_coolant
        # Liquid carrying exactly the Julia defaults (rho_l=958.4, rho_v=0.598, hfg=2257e3,
        # sigma=0.059, cp_sat=4217.0, T_sat=100.0) and the same pipe. The Julia function is
        # scalar (one cell); Python is vectorized over the cell axis, so each Python anchor
        # was taken from a single-element T_bulk array, which is the exact per-cell
        # restriction of the Python function (T_bulk[0] == T_bulk[-1]).
        #
        # q4 outlet term: Python sets dT_outlet = (cp/hfg)*(Tsat[-1] - T_bulk[-1]), the
        # outlet cell's subcooling, NOT zero, so the Julia scalar function uses the cell's
        # own subcooling to match Python per cell. The two q4-binding cases below pin this
        # down: with a zero outlet term q4 collapses to q1 and they give a different number,
        # so they fail unless the outlet subcooling is carried through.

        # Downward branch, q2 selected (subcooling term dominates):
        # Sudo_Kaminaga_CHF(T_bulk=[320], ṁ=0.5, g=9.81) -> 1391788.0650769984
        @test q_CHF_sudo_kaminaga(46.85, 0.5, pipe, 9.81) ≈ 1391788.0650769984 rtol = 1e-9
        # Colder bulk -> larger subcooling -> higher CHF.
        # Sudo_Kaminaga_CHF(T_bulk=[300], ṁ=0.5, g=9.81) -> 1915508.8797814196
        @test q_CHF_sudo_kaminaga(26.85, 0.5, pipe, 9.81) ≈ 1915508.8797814196 rtol = 1e-9
        @test q_CHF_sudo_kaminaga(26.85, 0.5, pipe, 9.81) >
            q_CHF_sudo_kaminaga(46.85, 0.5, pipe, 9.81)

        # q4-binding cases (NONZERO outlet subcooling). Large ṁ grows q2 past q4, so q4
        # is the selected (most limiting) sub-correlation. These exercise the corrected
        # outlet term: q4 = q1*(1 + 5000*dT_outlet/|G*|) with dT_outlet > 0.
        # Sudo_Kaminaga_CHF(T_bulk=[300], ṁ=5.0, g=9.81) -> 11350154.095336435
        @test q_CHF_sudo_kaminaga(26.85, 5.0, pipe, 9.81) ≈ 11350154.095336435 rtol = 1e-9
        # Sudo_Kaminaga_CHF(T_bulk=[300], ṁ=8.0, g=9.81) -> 14693105.002503937
        @test q_CHF_sudo_kaminaga(26.85, 8.0, pipe, 9.81) ≈ 14693105.002503937 rtol = 1e-9

        # Upward branch: negative ṁ flips G* < 0, folding q1 into the max, so the
        # selection genuinely differs from the downward branch and yields a higher CHF.
        # Sudo_Kaminaga_CHF(T_bulk=[320], ṁ=-0.5, g=9.81) -> 2567664.771611573
        @test q_CHF_sudo_kaminaga(46.85, -0.5, pipe, 9.81) ≈ 2567664.771611573 rtol = 1e-9
        @test q_CHF_sudo_kaminaga(46.85, -0.5, pipe, 9.81) >
            q_CHF_sudo_kaminaga(46.85, 0.5, pipe, 9.81)

        # Gravity enters Julia only as |g| (Julia takes abs(gravity) for the capillary
        # length), so flipping the gravity sign leaves the result unchanged for positive
        # ṁ. This is a Julia-internal choice: Python does NOT abs g and returns NaN for
        # negative g, so this assertion is a Julia self-check, not a Python anchor.
        @test q_CHF_sudo_kaminaga(46.85, 0.5, pipe, -9.81) ≈
            q_CHF_sudo_kaminaga(46.85, 0.5, pipe, 9.81) rtol = 1e-10
    end

    @testset "q_CHF_mirshak" begin
        # Anchor: Python physical_models.thresholds.Mirshak_CHF(T_bulk=320, T_sat=100.0,
        # pressure=1e5, v=2.0) -> 3309506.2042568396.
        @test q_CHF_mirshak(46.85, 100.0, 1e5, 2.0) ≈ 3309506.2042568396 rtol = 1e-9
        # Higher velocity -> higher CHF.
        @test q_CHF_mirshak(46.85, 100.0, 1e5, 3.0) >
            q_CHF_mirshak(46.85, 100.0, 1e5, 2.0)
        # Higher subcooling -> higher CHF.
        @test q_CHF_mirshak(26.85, 100.0, 1e5, 2.0) >
            q_CHF_mirshak(46.85, 100.0, 1e5, 2.0)
    end

    @testset "q_CHF_fabrega" begin
        # Anchor: Python physical_models.thresholds.Fabrega_CHF(Tin=300, T_sat=100.0,
        # Dh=pipe.hydraulic_diameter) -> 289290.4023021582.
        @test q_CHF_fabrega(26.85, 100.0, pipe) ≈ 289290.4023021582 rtol = 1e-9
        # Colder inlet -> larger subcooling -> higher CHF.
        @test q_CHF_fabrega(6.85, 100.0, pipe) > q_CHF_fabrega(26.85, 100.0, pipe)
    end

    @testset "twall_limit" begin
        # T_bulk + factor*(T_wall - T_bulk): a 100 degree rise worsened by 1.2 becomes 120.
        @test twall_limit(26.85, 126.85, 1.2) ≈ 146.85
        @test twall_limit(26.85, 126.85) ≈ 126.85          # factor 1.0 is the identity
        @test twall_limit(26.85, 26.85, 5.0) ≈ 26.85       # no rise to worsen
        @test twall_limit(26.85, 126.85, 1.5) > twall_limit(26.85, 126.85, 1.2)
        # Equivalent to Python's T_bulk + q*factor/h under q = h*(T_wall - T_bulk).
        T_b, T_w, h, f = 26.85, 126.85, 25000.0, 1.3
        q = h * (T_w - T_b)
        @test twall_limit(T_b, T_w, f) ≈ T_b + q * f / h
    end
end

@testset "ChannelState and wrappers" begin
    pipe = PipeGeometry_rectangular(0.6, 0.0671, 0.0024, 0.0671)
    n = 5

    state = ChannelState(;
        n=n,
        T_bulk=fill(46.85, n),
        T_wall=fill(66.85, n),
        T_wall_left=fill(66.85, n),
        T_wall_right=fill(61.85, n),
        T_sat=fill(100.0, n),
        T_ONB=fill(106.85, n),
        T_inlet=26.85,
        P=fill(1e5, n),
        q_flux=fill(5e5, n),
        q_flux_left=fill(5e5, n),
        q_flux_right=fill(4e5, n),
        ṁ=0.5,
        velocity=fill(3.0, n),
        pipe=pipe,
        gravity=9.81,
    )

    @testset "ChannelState construction" begin
        @test state.n == n
        @test length(state.T_bulk) == n
        @test state.T_inlet == 26.85
        @test state.ṁ == 0.5
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
            (1 + 0.00914 * (100.0 - 46.85)) *
            (1 + 0.19e-5 * 1e5)
        @test result[1] ≈ expected_val rtol = 1e-10
    end

    @testset "fabrega_chf wrapper" begin
        result = fabrega_chf(state)
        @test length(result) == n
        @test all(result .> 0)
        expected_val = 1e7 * pipe.Dh * (0.023 * (100.0 - 26.85) + 4.56)
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
        expected_val = abs(0.5) * cₚ(H2O, 46.85) * (100.0 - 26.85)
        @test result[1] ≈ expected_val rtol = 1e-8
    end

    @testset "OFI_power wrapper" begin
        result = OFI_power(state)
        @test result isa Float64
        @test result > 0
        q_onset = q_boiling_onset(0.5, 100.0, 26.85, cₚ(H2O, 26.85))
        @test result < q_onset
    end

    @testset "twall_limit wrapper (ChannelState overload)" begin
        # Fixture: T_bulk 46.85, T_wall_left 66.85, T_wall_right 61.85. The left face is
        # hotter, so it sets the limit: 46.85 + 1.2*20 = 70.85.
        result = twall_limit(state; inhomogeneity_factor=1.2)
        @test length(result) == n
        @test all(result .≈ 70.85)
        # Factor 1.0 gives back the hotter face untouched.
        result_default = twall_limit(state)
        @test all(result_default .≈ 66.85)
    end
end

@testset "chfr helper" begin
    pipe = PipeGeometry_rectangular(0.6, 0.0671, 0.0024, 0.0671)
    n = 3
    state = ChannelState(;
        n=n,
        T_bulk=fill(46.85, n),
        T_wall=fill(66.85, n),
        T_wall_left=fill(66.85, n),
        T_wall_right=fill(61.85, n),
        T_sat=fill(100.0, n),
        T_ONB=fill(106.85, n),
        T_inlet=26.85,
        P=fill(1e5, n),
        q_flux=fill(5e5, n),
        q_flux_left=fill(5e5, n),
        q_flux_right=fill(4e5, n),
        ṁ=0.5,
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
        T_bulk=fill(46.85, n),
        T_wall=fill(66.85, n),
        T_wall_left=fill(66.85, n),
        T_wall_right=fill(61.85, n),
        T_sat=fill(100.0, n),
        T_ONB=fill(106.85, n),
        T_inlet=26.85,
        P=fill(1e5, n),
        q_flux=fill(0.0, n),
        q_flux_left=fill(0.0, n),
        q_flux_right=fill(0.0, n),
        ṁ=0.5,
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
        T_bulk=fill(46.85, n),
        T_wall=fill(66.85, n),
        T_wall_left=fill(66.85, n),
        T_wall_right=fill(61.85, n),
        T_sat=fill(100.0, n),
        T_ONB=fill(106.85, n),
        T_inlet=26.85,
        P=fill(1e5, n),
        q_flux=fill(5e5, n),
        q_flux_left=fill(5e5, n),
        q_flux_right=fill(4e5, n),
        ṁ=0.5,
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
