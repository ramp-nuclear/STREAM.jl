using Test
using STREAM

@testset "Threshold Analysis" begin

    # Shared test pipe: 0.6m long, 67.1mm x 2.4mm rectangular channel
    # Matches typical MTR fuel assembly geometry used in Python STREAM tests
    pipe = PipeGeometry_rectangular(0.6, 0.0671, 0.0024, 0.0671)

    @testset "bergles_rohsenow_t_onb" begin
        # Published Bergles-Rohsenow (1964) ONB formula, re-derived from scratch with
        # explicit constants (not the private _bergles_rohsenow_dT_ONB helper, which
        # would make this circular):
        #   T_ONB = T_sat + 0.556 * (q / (1082 * p^1.156))^(0.463 * p^0.0234)
        #   with p = pressure / 1e5 (bar).
        # At pressure = 1e5 Pa, p = 1.0, so both exponents collapse:
        #   p^1.156 = 1, p^0.0234 = 1  =>  T_ONB = T_sat + 0.556 * (q / 1082)^0.463
        dT_atm(q) = 0.556 * (q / 1082.0)^0.463
        @test bergles_rohsenow_t_onb(1e5, 1e5, 373.15) ≈ 373.15 + dT_atm(1e5) rtol = 1e-10
        @test bergles_rohsenow_t_onb(1e5, 1e5, 350.0) ≈ 350.0 + dT_atm(1e5) rtol = 1e-10

        # Off-atmospheric pressure exercises the p-dependent exponents.
        p2 = 2e5 / 1e5
        expected_2bar = 372.0 + 0.556 * (5e5 / (1082.0 * p2^1.156))^(0.463 * p2^0.0234)
        @test bergles_rohsenow_t_onb(2e5, 5e5, 372.0) ≈ expected_2bar rtol = 1e-10

        # Higher heat flux raises the onset wall temperature.
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
        # Saha-Zuber (1974) OSV, computed-bulk variant. Re-derive the published
        # formula independently with explicit constants:
        #   Pe = rho*u*Dh*cp/k, u = G/rho, G = |mdot|/A   (so Pe = G*Dh*cp/k)
        #   Pe <  70000 -> X = k/Dh * 455      (Nu_c, conduction-controlled)
        #   Pe >= 70000 -> X = 0.0065 * G * cp (St_c, convection-controlled)
        #   q_OSV(cell) = X*(T_sat - T_inlet) /
        #                 (1 + X * Hp/(|mdot|*cp) * cumsum(shape*dz)/(shape*flux_enworse))
        # with T_sat = sat_temperature(1e5) (self-consistent 1-atm bulk).
        # Uniform default: 10 cells, shape = 1, dz = L/10.
        # Reported value is the minimum cell (most conservative).
        Nu_c = 455.0
        St_c = 0.0065
        T_sat_ref = sat_temperature(1e5)

        function osv_expected(T_inlet, mdot; shape, dz, flux_enworse=1.0)
            rho = rho_water(T_inlet)
            cp = cp_water(T_inlet)
            k = k_water(T_inlet)
            G = abs(mdot) / pipe.A
            pe = G * pipe.Dh * cp / k  # u = G/rho cancels the rho
            X = pe <= 7e4 ? k / pipe.Dh * Nu_c : St_c * G * cp
            dT = T_sat_ref - T_inlet
            power_factor = pipe.heated_perimeter / (abs(mdot) * cp)
            shape_factor = cumsum(shape .* dz) ./ (shape .* flux_enworse)
            cells = X .* dT ./ (1.0 .+ X .* power_factor .* shape_factor)
            return minimum(cells), pe
        end

        # High-Pe branch (Pe >= 70000): mdot = 0.5 gives Pe ~ 9.8e4 -> St_c branch.
        exp_hi, pe_hi = osv_expected(300.0, 0.5; shape=ones(10), dz=fill(pipe.L / 10, 10))
        @test pe_hi >= 7e4  # guard: this case must hit the convective branch
        @test q_OSV_saha_zuber(300.0, 0.5, pipe) ≈ exp_hi rtol = 1e-10

        # Low-Pe branch (Pe < 70000): mdot = 0.3 gives Pe ~ 5.9e4 -> Nu_c branch.
        exp_lo, pe_lo = osv_expected(300.0, 0.3; shape=ones(10), dz=fill(pipe.L / 10, 10))
        @test pe_lo < 7e4  # guard: this case must hit the conductive branch
        @test q_OSV_saha_zuber(300.0, 0.3, pipe) ≈ exp_lo rtol = 1e-10

        # Explicit flux_shape + dz path (dz = 0.06 each, shape uniform).
        exp_shape, _ = osv_expected(300.0, 0.5; shape=ones(10), dz=0.06 * ones(10))
        @test q_OSV_saha_zuber(300.0, 0.5, pipe; flux_shape=ones(10), dz=0.06 * ones(10)) ≈
            exp_shape rtol = 1e-10
    end

    @testset "q_CHF_sudo_kaminaga" begin
        # Sudo-Kaminaga (1998) plate CHF. Re-derive the published correlation from
        # scratch with explicit constants, including the four sub-correlations and
        # the direction-dependent selection.
        #   lamda = sqrt(sigma / drho / |g|)              (capillary length)
        #   drho  = rho_l - rho_v
        #   G*    = mdot / A / sqrt(lamda * drho * rho_v * |g|)
        #   dTin  = (cp_sat/hfg)*(T_sat - T_bulk),  dTout = 0 (saturated outlet)
        #   q1 = 0.005*|G*|^0.611
        #   q2 = A_ratio*|G*|*dTin            (A_ratio = A / (sum(heated_parts)*L))
        #   q3 = 0.7*A_ratio*sqrt(width/lamda)*(1+dTin)/(1+(rho_v/rho_l)^0.25)^2
        #   q4 = q1*(1 + 5000*dTout/|G*|)     (= q1 here since dTout = 0)
        #   G* >= 0 (mdot >= 0): q* = max(min(q2,q4), q3)
        #   G* <  0 (mdot <  0): q* = max(max(min(q2,q4), q1), q3)
        #   q_CHF = q* * hfg * sqrt(lamda * drho * rho_v * |g|)
        # Defaults: rho_l=958.4, rho_v=0.598, hfg=2257e3, sigma=0.059,
        #           cp_sat=4217.0, T_sat=373.15.
        rho_l = 958.4
        rho_v = 0.598
        hfg = 2257e3
        sigma = 0.059
        cp_sat = 4217.0
        T_sat = 373.15

        function sk_expected(T_bulk, mdot, gravity)
            g_abs = abs(gravity)
            drho = rho_l - rho_v
            lamda = sqrt(sigma / drho / g_abs)
            scale = sqrt(lamda * drho * rho_v * g_abs)
            A_ratio = pipe.A / (sum(pipe.heated_parts) * pipe.L)
            G_star = mdot / pipe.A / scale
            dT_inlet = (cp_sat / hfg) * (T_sat - T_bulk)
            q1 = 0.005 * abs(G_star)^0.611
            q2 = A_ratio * abs(G_star) * dT_inlet
            q3 =
                0.7 * A_ratio * sqrt(pipe.width / lamda) * (1 + dT_inlet) /
                (1 + (rho_v / rho_l)^0.25)^2
            q4 = q1  # dT_outlet = 0
            q_star =
                G_star >= 0 ? max(min(q2, q4), q3) : max(max(min(q2, q4), q1), q3)
            return q_star * hfg * scale
        end

        # Downward branch (mdot >= 0 -> G* >= 0): q* = max(min(q2,q4), q3).
        # Here min(q2,q4) = q2 dominates q3, so q2 (the subcooling term) is selected.
        @test q_CHF_sudo_kaminaga(320.0, 0.5, pipe, 9.81) ≈ sk_expected(320.0, 0.5, 9.81) rtol =
            1e-10
        # Colder bulk -> larger dT_inlet -> larger q2 -> higher CHF.
        @test q_CHF_sudo_kaminaga(300.0, 0.5, pipe, 9.81) ≈ sk_expected(300.0, 0.5, 9.81) rtol =
            1e-10
        @test q_CHF_sudo_kaminaga(300.0, 0.5, pipe, 9.81) >
            q_CHF_sudo_kaminaga(320.0, 0.5, pipe, 9.81)

        # Gravity sign alone does not flip G* (it enters only as |g|), so positive
        # mdot keeps the downward branch regardless of gravity sign.
        @test q_CHF_sudo_kaminaga(320.0, 0.5, pipe, -9.81) ≈
            sk_expected(320.0, 0.5, -9.81) rtol = 1e-10
        @test q_CHF_sudo_kaminaga(320.0, 0.5, pipe, -9.81) ≈
            q_CHF_sudo_kaminaga(320.0, 0.5, pipe, 9.81) rtol = 1e-10

        # Upward branch: negative mdot flips G* < 0, adding q1 into the max. Here
        # q1 (= 0.303) dominates min(q2,q4) and q3, so the selection genuinely
        # differs from the downward branch and yields a higher CHF.
        @test q_CHF_sudo_kaminaga(320.0, -0.5, pipe, 9.81) ≈
            sk_expected(320.0, -0.5, 9.81) rtol = 1e-10
        @test q_CHF_sudo_kaminaga(320.0, -0.5, pipe, 9.81) >
            q_CHF_sudo_kaminaga(320.0, 0.5, pipe, 9.81)
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
