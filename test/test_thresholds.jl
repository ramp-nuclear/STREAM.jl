using Test
using STREAM
using STREAM.Assemblies
using STREAM.Components
using STREAM.Substances
using STREAM.Thresholds
using STREAM.Components: Channel  # explicit: Base.Channel also exists
using STREAM.Examples
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq: ReturnCode

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
        # Liquid carrying STREAM's own ρ/cₚ/k at 26.85 °C and Tsat(H2O, 1e5) = 99.63 in all
        # ten cells, so the Python coolant matches Julia bit-for-bit. Pipe and uniform flux
        # match the Julia inputs. The value checked is the last cell, which has the most heat
        # picked up upstream. (Python's numba `directed` was monkeypatched to its plain-numpy
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

        coolant = H2O(fill(26.85, 10), fill(1e5, 10))

        # High-Pe (convective) branch: Saha_Zuber_OSV_computed_bulk(ṁ=0.5) -> 1443852.2363455354
        @test pe_at(0.5) >= 7e4  # guard: must be the convective St_c branch
        osv = q_OSV_saha_zuber(26.85, 0.5, pipe, coolant)
        @test length(osv) == 10
        @test last(osv) ≈ 1443852.2363455354 rtol = 1e-9

        # Low-Pe (conductive) branch: Saha_Zuber_OSV_computed_bulk(ṁ=0.3) -> 899904.7329676608
        @test pe_at(0.3) < 7e4  # guard: must be the conductive Nu_c branch
        @test last(q_OSV_saha_zuber(26.85, 0.3, pipe, coolant)) ≈ 899904.7329676608 rtol = 1e-9

        # Explicit flux_shape + dz path (dz = 0.06 each, uniform shape). Same total length
        # as the uniform default, so Python returns the same value:
        # Saha_Zuber_OSV_computed_bulk(ṁ=0.5, dz=0.06) -> 1443852.2363455354
        explicit = q_OSV_saha_zuber(
            26.85, 0.5, pipe, coolant; flux_shape=ones(10), dz=0.06 * ones(10)
        )
        @test last(explicit) ≈ 1443852.2363455354 rtol = 1e-9

        # Reversed flow picks up its heat from the other end, so a uniform channel gives the
        # same profile mirrored.
        @test q_OSV_saha_zuber(26.85, -0.5, pipe, coolant) ≈ reverse(osv) rtol = 1e-12
    end

    # The saturated coolant the Sudo-Kaminaga anchors were generated against: the rounded
    # book values for water near 1 atm, which differ from H2O(100.0) in the fourth digit.
    sat_water = Liquid(; ρ=958.4, ρᵥ=0.598, cₚ=4217.0, hfg=2257e3, σ=0.059, Tsat=100.0)

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
        @test q_CHF_sudo_kaminaga(46.85, 0.5, pipe, 9.81, sat_water) ≈ 1391788.0650769984 rtol = 1e-9
        # Colder bulk -> larger subcooling -> higher CHF.
        # Sudo_Kaminaga_CHF(T_bulk=[300], ṁ=0.5, g=9.81) -> 1915508.8797814196
        @test q_CHF_sudo_kaminaga(26.85, 0.5, pipe, 9.81, sat_water) ≈ 1915508.8797814196 rtol = 1e-9
        @test q_CHF_sudo_kaminaga(26.85, 0.5, pipe, 9.81, sat_water) >
            q_CHF_sudo_kaminaga(46.85, 0.5, pipe, 9.81, sat_water)

        # q4-binding cases (NONZERO outlet subcooling). Large ṁ grows q2 past q4, so q4
        # is the selected (most limiting) sub-correlation. These exercise the corrected
        # outlet term: q4 = q1*(1 + 5000*dT_outlet/|G*|) with dT_outlet > 0.
        # Sudo_Kaminaga_CHF(T_bulk=[300], ṁ=5.0, g=9.81) -> 11350154.095336435
        @test q_CHF_sudo_kaminaga(26.85, 5.0, pipe, 9.81, sat_water) ≈ 11350154.095336435 rtol = 1e-9
        # Sudo_Kaminaga_CHF(T_bulk=[300], ṁ=8.0, g=9.81) -> 14693105.002503937
        @test q_CHF_sudo_kaminaga(26.85, 8.0, pipe, 9.81, sat_water) ≈ 14693105.002503937 rtol = 1e-9

        # Upward branch: negative ṁ flips G* < 0, folding q1 into the max, so the
        # selection genuinely differs from the downward branch and yields a higher CHF.
        # Sudo_Kaminaga_CHF(T_bulk=[320], ṁ=-0.5, g=9.81) -> 2567664.771611573
        @test q_CHF_sudo_kaminaga(46.85, -0.5, pipe, 9.81, sat_water) ≈ 2567664.771611573 rtol = 1e-9
        @test q_CHF_sudo_kaminaga(46.85, -0.5, pipe, 9.81, sat_water) >
            q_CHF_sudo_kaminaga(46.85, 0.5, pipe, 9.81, sat_water)

        # Gravity enters Julia only as |g| (Julia takes abs(gravity) for the capillary
        # length), so flipping the gravity sign leaves the result unchanged for positive
        # ṁ. This is a Julia-internal choice: Python does NOT abs g and returns NaN for
        # negative g, so this assertion is a Julia self-check, not a Python anchor.
        @test q_CHF_sudo_kaminaga(46.85, 0.5, pipe, -9.81, sat_water) ≈
            q_CHF_sudo_kaminaga(46.85, 0.5, pipe, 9.81, sat_water) rtol = 1e-10
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

    @testset "bergles_rohsenow_t_onb on a ChannelState" begin
        result = bergles_rohsenow_t_onb(state)
        @test length(result) == n
        # T_ONB from Bergles-Rohsenow must be > T_sat for non-zero q
        @test all(result .> state.T_sat)
    end

    @testset "q_CHF_mirshak on a ChannelState" begin
        result = q_CHF_mirshak(state)
        @test length(result) == n
        @test all(result .> 0)
        expected_val =
            1.51e6 *
            (1 + 0.1198 * 3.0) *
            (1 + 0.00914 * (100.0 - 46.85)) *
            (1 + 0.19e-5 * 1e5)
        @test result[1] ≈ expected_val rtol = 1e-10
    end

    @testset "q_CHF_fabrega on a ChannelState" begin
        result = q_CHF_fabrega(state)
        @test length(result) == n
        @test all(result .> 0)
        expected_val = 1e7 * pipe.Dh * (0.023 * (100.0 - 26.85) + 4.56)
        @test result[1] ≈ expected_val rtol = 1e-10
    end

    @testset "q_CHF_sudo_kaminaga on a ChannelState" begin
        # Per cell, like the other correlations: the state method builds the saturated
        # snapshot from the channel's own saturation state and hands the whole profile over.
        result = q_CHF_sudo_kaminaga(state)
        @test length(result) == n
        @test all(result .> 0)

        # q2/q3 read the inlet subcooling and q4 the outlet, so a channel that heats along
        # its length is not the same as a uniform one at either end temperature. The fixture
        # is uniform in T_bulk, so build a sloped one to tell them apart.
        warming = collect(range(40.0, 70.0; length=n))
        sloped = ChannelState(; n=n, T_bulk=warming, T_wall=fill(90.0, n),
            T_wall_left=fill(90.0, n), T_wall_right=fill(85.0, n),
            T_sat=fill(100.0, n), T_ONB=fill(106.85, n), T_inlet=40.0, P=fill(1e5, n),
            q_flux=fill(5e5, n), q_flux_left=fill(5e5, n), q_flux_right=fill(4e5, n),
            ṁ=0.5, velocity=fill(3.0, n), pipe=pipe, gravity=9.81)

        # The state method takes its saturated properties from the coolant at the channel's
        # own saturation state, so the explicit call needs the same snapshot to agree.
        sat = H2O(fill(100.0, n), fill(1e5, n))
        @test q_CHF_sudo_kaminaga(sloped) ≈
              q_CHF_sudo_kaminaga(warming, 0.5, pipe, 9.81, sat) rtol = 1e-12

        # The inlet always matters: q2 and q3 both read it.
        @test !isapprox(q_CHF_sudo_kaminaga(sloped),
                        q_CHF_sudo_kaminaga(fill(last(warming), n), 0.5, pipe, 9.81, sat);
                        rtol=1e-6)

        # The outlet only shows up when q4 is the selected sub-correlation, which needs a
        # high enough flow for q2 to grow past it. At ṁ = 0.5 both ends give the same answer,
        # so a test there would pass no matter which end q4 was fed.
        flat = q_CHF_sudo_kaminaga(fill(40.0, n), 0.5, pipe, 9.81, sat)
        warm = q_CHF_sudo_kaminaga([fill(40.0, n - 1); 70.0], 0.5, pipe, 9.81, sat)
        @test flat ≈ warm rtol = 1e-12
        fast_flat = q_CHF_sudo_kaminaga(fill(40.0, n), 5.0, pipe, 9.81, sat)
        fast_warm = q_CHF_sudo_kaminaga([fill(40.0, n - 1); 70.0], 5.0, pipe, 9.81, sat)
        @test !isapprox(fast_flat, fast_warm; rtol=1e-6)
        # Hotter outlet means less subcooling to absorb, so a lower limit.
        @test all(fast_warm .< fast_flat)

        # A one-cell profile and a scalar call are the same thing.
        one_cell = H2O(100.0, 1e5)
        @test only(q_CHF_sudo_kaminaga([46.85], 0.5, pipe, 9.81, H2O([100.0], [1e5]))) ≈
              q_CHF_sudo_kaminaga(46.85, 0.5, pipe, 9.81, one_cell)
    end

    @testset "q_boiling_onset on a ChannelState" begin
        result = q_boiling_onset(state)
        @test length(result) == n
        @test all(result .> 0)
        # cₚ at the inlet temperature, as Python takes it
        expected_val = abs(0.5) * cₚ(H2O, 26.85) * (100.0 - 26.85)
        @test result[1] ≈ expected_val rtol = 1e-8
    end

    @testset "q_OFI_whittle_forgan on a ChannelState" begin
        result = q_OFI_whittle_forgan(state)
        @test result isa Float64
        @test result > 0
        q_onset = q_boiling_onset(0.5, 100.0, 26.85, cₚ(H2O, 26.85))
        @test result < q_onset

        # Pressure falls along the channel, so T_sat does too, and OFI has to read the
        # downstream cell. The fixture above is uniform in T_sat and cannot tell the ends
        # apart, so use a sloped profile and check both flow directions pick their own
        # outlet. Reading the wrong end silently overstates the margin.
        sloped = collect(range(110.0, 90.0; length=n))   # hot inlet, cooler outlet
        fwd = ChannelState(; n=n, T_bulk=fill(46.85, n), T_wall=fill(66.85, n),
            T_wall_left=fill(66.85, n), T_wall_right=fill(61.85, n),
            T_sat=sloped, T_ONB=fill(106.85, n), T_inlet=26.85, P=fill(1e5, n),
            q_flux=fill(5e5, n), q_flux_left=fill(5e5, n), q_flux_right=fill(4e5, n),
            ṁ=0.5, velocity=fill(3.0, n), pipe=pipe, gravity=9.81)
        rev = ChannelState(; n=n, T_bulk=fwd.T_bulk, T_wall=fwd.T_wall,
            T_wall_left=fwd.T_wall_left, T_wall_right=fwd.T_wall_right,
            T_sat=sloped, T_ONB=fwd.T_ONB, T_inlet=fwd.T_inlet, P=fwd.P,
            q_flux=fwd.q_flux, q_flux_left=fwd.q_flux_left, q_flux_right=fwd.q_flux_right,
            ṁ=-0.5, velocity=fwd.velocity, pipe=pipe, gravity=9.81)

        @test q_OFI_whittle_forgan(fwd) ≈
              q_OFI_whittle_forgan(0.5, last(sloped), 26.85, pipe) rtol = 1e-12
        @test q_OFI_whittle_forgan(rev) ≈
              q_OFI_whittle_forgan(-0.5, first(sloped), 26.85, pipe) rtol = 1e-12
        # The two ends really do differ, so the assertions above have teeth.
        @test !isapprox(q_OFI_whittle_forgan(fwd), q_OFI_whittle_forgan(rev); rtol=1e-6)
    end

    @testset "twall_limit on a ChannelState" begin
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

@testset "ChannelState from a solved channel" begin
    # Built from a solution rather than by hand, which is what exercises the extraction.
    geo = PipeGeometry_circular(0.6, 0.01)
    ssys = build_loop(; n=5)
    op = Pair{Any,Any}[ssys.ch.T[i] => 40.0 for i in 1:5]
    push!(op, ssys.ch.inlet.ṁ => 0.5)
    sol = solve_steady(ssys, op)

    # A plain Channel has no `velocity` variable (only ChannelAndContacts declares it), so
    # the extraction has to fall back to the signed `v` and take its magnitude.
    state = ChannelState(sol, ssys.ch; pipe=geo)
    @test state.n == 5
    @test length(state.T_bulk) == 5
    @test all(state.velocity .>= 0)
    # T_inlet is the coolant arriving from the heat exchanger, not the first cell, which
    # has already taken up some heat.
    @test state.T_inlet ≈ sol[ssys.bc.outlet.T]
    @test state.T_inlet < first(state.T_bulk)
    @test state.gravity == G_EARTH
    @test state.ṁ > 0

    # A circular pipe puts the whole heated perimeter on one face, so the other has zero
    # area. That face carries no flux; dividing by its area would give NaN and poison
    # q_flux, and through it every CHF ratio.
    @test all(iszero, state.q_flux_right)
    @test all(isfinite, state.q_flux)
    @test all(state.q_flux .> 0)
    @test all(isfinite, chfr(q_CHF_mirshak)(state))

    # Without a geometry there is no area at all, so both faces read zero.
    bare = ChannelState(sol, ssys.ch)
    @test all(iszero, bare.q_flux)

    # Run the loop backwards and the coolant enters at the last cell. The heat exchanger
    # sets both of its ports, so what reaches the channel is still its 40 °C, while the
    # first cell is now the hot end.
    back = build_loop(; n=5, dP_pump=-3.0e4)
    op_back = Pair{Any,Any}[back.ch.T[i] => 40.0 for i in 1:5]
    push!(op_back, back.ch.inlet.ṁ => -0.5)
    reversed = ChannelState(solve_steady(back, op_back), back.ch; pipe=geo)
    @test reversed.ṁ < 0
    @test reversed.T_inlet ≈ 40.0
    @test reversed.T_inlet < last(reversed.T_bulk) < first(reversed.T_bulk)
end

@testset "ChannelState over a transient reads each saved time" begin
    # A coasting loop: the pump head is removed at t = 0 and the channel's own momentum
    # carries the flow down, so every flow-dependent limit has to move with it. The reader
    # this replaces froze ṁ and T_inlet at the first saved time.
    n = 5
    geo = PipeGeometry_circular(0.6, 0.01)
    ssys = build_loop(; n=n)
    op = Pair{Any,Any}[ssys.ch.T[i] => 40.0 for i in 1:n]
    push!(op, ssys.ch.inlet.ṁ => 0.5)
    sol_ss = solve_steady(ssys, op)
    sol = solve_transient(
        ssys, sol_ss, range(0.0, 0.5; length=6); overrides=[ssys.pump.dP_pump => 0.0]
    )
    @test sol.retcode == ReturnCode.Success
    ṁ = sol[ssys.ch.inlet.ṁ, :]
    # The flow has to fall for the rest of this to prove anything.
    @test ṁ[end] < 0.5 * ṁ[1]

    @testset "at saved time $k" for k in (1, 3, length(sol.t))
        s = ChannelState(sol, ssys.ch; pipe=geo, index=k)
        @test s.ṁ == ṁ[k]
        @test s.T_inlet == sol[ssys.ch.T_in, k]
        @test s.T_bulk == [sol[ssys.ch.T[i], k] for i in 1:n]
    end
    # A transient has many instants, so asking for the state without saying which is an
    # error rather than a guess.
    @test_throws ArgumentError ChannelState(sol, ssys.ch; pipe=geo)

    # Channel-level results stack into a vector over time, per-cell ones into [cell, time].
    result = threshold_analysis(
        sol, ssys.ch; pipe=geo,
        osv=q_OSV_saha_zuber, ofi=q_OFI_whittle_forgan, sk=q_CHF_sudo_kaminaga,
        onb=bergles_rohsenow_t_onb,
    )
    nt = length(sol.t)
    @test size(result.ofi) == (nt,)
    @test size(result.osv) == (n, nt)
    @test size(result.sk) == (n, nt)
    @test size(result.onb) == (n, nt)
    # Stacking loses nothing: column k of each result is exactly what the correlation gives
    # for the state at saved time k on its own.
    @testset "column $k is the state at saved time $k" for k in (1, nt)
        s = ChannelState(sol, ssys.ch; pipe=geo, index=k)
        @test result.osv[:, k] == q_OSV_saha_zuber(s)
        @test result.ofi[k] == q_OFI_whittle_forgan(s)
        @test result.sk[:, k] == q_CHF_sudo_kaminaga(s)
    end
    # The regression: limits that depend on the flow follow it down instead of repeating
    # their t = 0 value.
    @test result.osv[:, end] != result.osv[:, 1]
    @test result.sk[:, end] != result.sk[:, 1]

    # A steady solution still gives one value per cell.
    steady = threshold_analysis(sol_ss, ssys.ch; pipe=geo, sk=q_CHF_sudo_kaminaga)
    @test steady.sk == q_CHF_sudo_kaminaga(ChannelState(sol_ss, ssys.ch; pipe=geo))
end

@testset "worst_case finds the smallest margin and where it is" begin
    margin = [3.0 2.0 5.0;
              4.0 1.5 6.0]   # [cell, time]
    times = [0.0, 1.0, 2.0]
    @test worst_case(margin; times=times) == (value=1.5, cell=2, time=1.0)
    @test worst_case(margin) == (value=1.5, cell=2, time=2)
    # A vector with times is a channel-level result over time; without, it is per cell.
    @test worst_case([2.0, 0.5, 1.0]; times=times) == (value=0.5, cell=nothing, time=1.0)
    @test worst_case([2.0, 0.5, 1.0]) == (value=0.5, cell=2, time=nothing)
end

@testset "ChannelState says so when the channel has no wall temperature" begin
    # ChannelHeatFlux prescribes its flux, so nothing closes T_wall_left/T_wall_right and
    # mtkcompile drops them. MTK's own complaint is "Symbol ... is not present in the
    # system", which does not tell you that the channel variant is the problem.
    n = 4
    geo = PipeGeometry_circular(0.6, 0.01)
    @named pump = Pump(3.0e4)
    @named bc = HeatExchanger(20.0)
    @named chf = ChannelHeatFlux(; n=n, geometry=geo)
    conns = Equation[
        inseries(pump, bc, chf, pump)...,
        pump.inlet.p ~ 1.0e5,
        [chf.q_left[i] ~ 1.0e4 for i in 1:n]...,
        [chf.q_right[i] ~ 0.0 for i in 1:n]...,
    ]
    @named sys = compose(System(conns, t; name=:chf_loop), pump, bc, chf)
    ssys = mtkcompile(sys)
    ic = Pair{Any,Any}[
        [ssys.chf.T[i] => 20.0 for i in 1:n]...,
        ssys.chf.inlet.ṁ => 0.5,
    ]
    sol = solve_steady(ssys, ic)
    @test sol.retcode == ReturnCode.Success

    err = try
        ChannelState(sol, ssys.chf; pipe=geo)
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("ChannelHeatFlux", err.msg)
    @test occursin("chf", err.msg)
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

    ratio_fn = chfr(q_CHF_mirshak; direction=:max)
    ratios = ratio_fn(state)
    @test length(ratios) == n
    @test all(ratios .> 0)

    ratio_left = chfr(q_CHF_mirshak; direction=:left)(state)
    ratio_right = chfr(q_CHF_mirshak; direction=:right)(state)
    ratio_total = chfr(q_CHF_mirshak; direction=:total)(state)
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
    @test_throws ArgumentError chfr(q_CHF_mirshak; direction=:bad)(state)
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

    manual_result = (mirshak=q_CHF_mirshak(state), onb=bergles_rohsenow_t_onb(state))
    @test manual_result.mirshak isa AbstractArray
    @test manual_result.onb isa AbstractArray
    @test length(manual_result.mirshak) == n
    @test length(manual_result.onb) == n

    mirshak_chfr = chfr(q_CHF_mirshak; direction=:max)
    chfr_result = mirshak_chfr(state)
    @test length(chfr_result) == n
    @test all(chfr_result .> 0)
end

@testset "bergles_rohsenow_t_onb where the wall is not heating the coolant" begin
    # After a scram the coolant can run hotter than parts of the plate and the flux turns
    # negative. No onset is possible there, and the correlation's fractional power has no
    # real value, so those cells report Inf rather than throwing.
    n = 3
    q = [5.0e4, 0.0, -3.0e3]
    s = ChannelState(;
        n=n, T_bulk=fill(60.0, n), T_wall=fill(62.0, n), T_wall_left=fill(62.0, n),
        T_wall_right=fill(62.0, n), T_sat=fill(115.0, n), T_ONB=fill(120.0, n),
        T_inlet=35.0, P=fill(1.7e5, n), q_flux=q, q_flux_left=q, q_flux_right=q, ṁ=0.01,
        velocity=fill(0.05, n), pipe=nothing, gravity=9.81,
    )
    onb = bergles_rohsenow_t_onb(s)
    @test onb[1] ≈ bergles_rohsenow_t_onb(1.7e5, 5.0e4, 115.0)
    @test onb[2] == Inf
    @test onb[3] == Inf
end

@testset "ChannelState methods match Python's analysis wrappers" begin
    # One MTR channel state, handed to stream.analysis.thresholds and to these methods: ten
    # cells, 35 °C entering, the same peaked flux on both faces, h = 20 kW/(m²·K), and the
    # bulk temperature from the energy balance, in forward and in reversed flow. The anchors
    # are Python's values in the first and last cell (OFI is one number for the channel).
    # Python's numba `directed` was swapped for its plain-numpy equivalent so it would run.
    n = 10
    pipe = PipeGeometry_rectangular(0.6, 0.066, 0.0027, 0.063)
    dz = pipe.L / n
    q = 6e5 .* (0.6 .+ 0.8 .* sin.(π .* ((1:n) .- 0.5) ./ n))
    P = collect(range(1.75e5, 1.70e5; length=n))
    function state(mdot)
        Q = 2 .* q .* 0.063 .* dz
        rise = cumsum(mdot >= 0 ? Q : reverse(Q)) ./ (abs(mdot) * 4180.0)
        T = 35.0 .+ (mdot >= 0 ? rise : reverse(rise))
        T_wall = T .+ q ./ 2e4
        return ChannelState(; n=n, T_bulk=T, T_wall=T_wall, T_wall_left=T_wall,
            T_wall_right=T_wall, T_sat=Tsat.(H2O, P), T_ONB=zeros(n), T_inlet=35.0, P=P,
            q_flux=q, q_flux_left=q, q_flux_right=q, ṁ=mdot,
            velocity=abs.(mdot ./ (ρ.(H2O, T) .* pipe.A)), pipe=pipe, gravity=G_EARTH)
    end

    python = (
        fwd=(sk=(1575471.0316344758, 1574952.2515598466), mirshak=(4298321.690663347, 3539713.6901751636), fabrega=(333346.31419618346, 332279.23286491574), ofi=(106174.83495312576,), osv=(3484558.9884553887, 844883.2366385899), osv_inhom=(3616141.236466625, 978269.1429811876), bp=(120652.9254573937, 119322.67811411698), onb_margin=(-63.98777757353153, -31.522506478884353), onb_margin_factors=(-62.482424247888034, -30.05672162179306), twall=(63.315724255662005, 94.9831513183468)),
        rev=(sk=(971670.8135107204, 968000.8153377083), mirshak=(1191100.746008034, 3093477.0998318987), fabrega=(333346.31419618346, 332279.23286491574), ofi=(31263.625506709213,), osv=(284995.9638613336, 2223314.46786654), osv_inhom=(338031.07959110854, 2426017.02511434), bp=(33891.27119589711, 33517.606211830614), onb_margin=(54.406916625634935, -57.53127968556058), onb_margin_factors=(55.91226995127843, -56.06549482846927), twall=(181.71041845482847, 68.97437811167059)),
    )

    ends(v) = length(v) == 1 ? (only(v),) : (first(v), last(v))
    for (label, mdot) in ((:fwd, 0.356), (:rev, -0.1))
        s = state(mdot)
        wall = twall_limit.(s.T_bulk, s.T_wall_left, 1.2)
        onb = bergles_rohsenow_t_onb(s; direction=:left, onb_factor=1.3, inhomogeneity_factor=1.2)
        julia = (
            sk=q_CHF_sudo_kaminaga(s),
            mirshak=q_CHF_mirshak(s),
            fabrega=q_CHF_fabrega(s),
            ofi=[q_OFI_whittle_forgan(s)],
            osv=q_OSV_saha_zuber(s; direction=:left),
            osv_inhom=q_OSV_saha_zuber(s; direction=:left, inhomogeneity_factor=1.2),
            bp=q_boiling_onset(s),
            # Python reports the margin T_wall - T_ONB.
            onb_margin=s.T_wall_left .- bergles_rohsenow_t_onb(s; direction=:left),
            onb_margin_factors=wall .- onb,
            twall=twall_limit(s; inhomogeneity_factor=1.2),
        )
        @testset "$label $k" for k in keys(python[label])
            rtol = k === :ofi ? 1e-7 : 1e-9  # two adaptive quadratures for OFI
            @test all(isapprox.(ends(julia[k]), python[label][k]; rtol=rtol))
        end
    end
end
