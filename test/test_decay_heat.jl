using Test
using STREAM
using STREAM.DecayHeat
using STREAM.Components: ReactivityController, SCRAM_at_power, change_state
using STREAM.Examples
using OrdinaryDiffEq: ReturnCode

# The published tables are not distributed with this package, so the testsets that read one
# run only when STREAM_DECAY_HEAT_STANDARDS points at a directory holding them. Python STREAM
# skips its own decay heat file the same way, for the same reason.
const DH_STANDARDS = get(ENV, "STREAM_DECAY_HEAT_STANDARDS", "")
const DH_HAVE_STANDARDS = !isempty(DH_STANDARDS) && isdir(DH_STANDARDS)

# Sums of α/λ per table, in MeV/fission, transcribed from the "Contents" table of the
# DecayHeatStandards README that ships beside the CSVs. Published to four decimals, hence
# the atol below. The JAERI-91 rows come from Table 4.16 of JAERI-M 91-034 and cover thermal
# fission of U235 and fast fission of U238.
const DH_TABLE_SUMS = [
    (ANS14, U235, 23, 13.4395),
    (ANS73, U235, 23, 13.1823),
    (JAERI91, U235, 33, 12.9568),
    (JAERI91, U235_beta, 33, 6.5183),
    (JAERI91, U235_gamma, 33, 6.4376),
    (ANS14, U238, 23, 17.6789),
    (JAERI91, U238, 33, 16.1342),
    (JAERI91, U238_gamma, 33, 7.8191),
]

@testset "Decay Heat" begin

    # Anchors below are the values Python STREAM asserts in its own doctests, at
    # stream/physical_models/decay_heat/{activation,actinides,fission_products}.py. Both codes
    # evaluate the same closed form in IEEE doubles, so they agree far past the eight digits
    # the doctests print; rtol = 1e-8 is set by how many digits Python shows, not by tuning.

    @testset "Activation" begin
        # activation.profile(lamda_U239 := 4.91e-04): f(0, inf) -> 1.0,
        # f(1000, inf) -> 0.61201407, f(0, 0) -> 0.0
        act = Activation(4.91e-4)
        @test act(0, Inf) ≈ 1.0 rtol = 1e-8
        @test act(1000, Inf) ≈ 0.61201407 rtol = 1e-8
        @test act(0, 0) == 0.0

        # T defaults to saturation, so the one-argument call is the T = Inf column.
        @test act(1000) == act(1000, Inf)

        # A finite irradiation saturates towards the infinite one from below.
        @test act(0, 1000) < act(0, 10_000) < act(0, Inf)

        # Scalar in, scalar out, with broadcasting over a vector of times.
        @test act.([0.0, 1000.0]) == [act(0.0), act(1000.0)]
    end

    @testset "DoubleDecay" begin
        # activation.double_decay_profile(4.91e-04, 3.41e-06): f(0, inf) -> 1.0,
        # f(1000, inf) -> 0.99928541, f(0, 0) -> 0.0
        dd = DoubleDecay(4.91e-4, 3.41e-6)
        @test dd(0, Inf) ≈ 1.0 rtol = 1e-8
        @test dd(1000, Inf) ≈ 0.99928541 rtol = 1e-8
        @test dd(0, 0) == 0.0

        # The daughter outlives the parent, so it is still near its peak where the parent has
        # decayed away.
        @test dd(1000, Inf) > Activation(4.91e-4)(1000, Inf)
    end

    @testset "Actinides" begin
        # actinides.contribution(0.005)(0, inf).item() -> 0.004325
        @test Actinides(0.005)(0, Inf) ≈ 0.004325 rtol = 1e-8

        # At saturation both profiles are 1, so the value is R times the two deposited
        # energies, 0.460 + 0.405 MeV.
        @test Actinides(1.0)(0, Inf) ≈ 0.865 rtol = 1e-8

        # Linear in captures per fission.
        @test Actinides(0.01)(3600, Inf) ≈ 2 * Actinides(0.005)(3600, Inf)
    end

    @testset "FissionProducts from group constants" begin
        # fp_inner_(t=0., T=np.inf, lamda=np.ones(1), alpha=np.ones(1)) -> array([1.])
        @test FissionProducts([1.0], [1.0])(0.0, Inf) == 1.0

        # One group of α/λ is that group's Activation profile scaled.
        one_group = FissionProducts([0.1], [0.5])
        @test one_group(7.0, 100.0) ≈ 5.0 * Activation(0.1)(7.0, 100.0)

        # No irradiation, no inventory, whatever the groups are.
        @test FissionProducts([1.0, 2.0], [3.0, 4.0])(1.0, 0.0) == 0.0

        # Negative α are least-squares fit coefficients, not yields, and pass through.
        @test FissionProducts([1.0, 2.0], [1.0, -0.25])(0.0, Inf) ≈ 1.0 - 0.125

        @test_throws DimensionMismatch FissionProducts([1.0, 2.0], [1.0])
    end

    @testset "Sum and scale" begin
        act = Activation(4.91e-4)
        acs = Actinides(0.005)
        fps = FissionProducts([1.0], [1.0])

        total = act + acs + fps
        @test total isa Sum
        @test total(100.0, Inf) ≈ act(100.0, Inf) + acs(100.0, Inf) + fps(100.0, Inf)

        # Folding stays flat rather than nesting Sum inside Sum.
        @test length(total.parts) == 3
        @test length(((act + acs) + (fps + act)).parts) == 4

        # sum falls out of `+`.
        @test sum([act, acs, fps])(100.0, Inf) == total(100.0, Inf)

        # A scaled contribution is a one-term Sum; scaling it again multiplies the weight.
        scaled = 200.0 * act
        @test scaled isa Sum
        @test scaled.parts == (act,)
        @test scaled(100.0, Inf) ≈ 200.0 * act(100.0, Inf)
        @test (act * 200.0)(100.0, Inf) == scaled(100.0, Inf)
        @test (8 * 9 * act).weights == (72.0,)

        # Scaling a sum scales each weight, so the result stays one level deep.
        both = 3.0 * (act + acs)
        @test both.weights == (3.0, 3.0)
        @test both.parts == (act, acs)
        at(model) = model(100.0, Inf)
        mixed = act + 2 * acs + 0.5 * (fps + act)
        @test mixed.weights == (1.0, 2.0, 0.5, 0.5)
        @test at(mixed) ≈ at(act) + 2 * at(acs) + 0.5 * (at(fps) + at(act))
    end

    @testset "Fissions interpolation" begin
        times, profile = [0.0, 1.0, 2.0], [1.0, 0.5, 0.25]

        # Linear reproduces np.interp, which is what Python STREAM evaluates a profile with.
        lin = Fissions(times, profile; interpolation=Linear())
        @test lin(0.5) ≈ 0.75
        @test lin(1.5) ≈ 0.375

        # The default departs from Python: the profile is a sum of decaying exponentials,
        # and a straight line between samples always overshoots one.
        fis = Fissions(times, profile)
        @test fis.interpolation isa LogLinear
        @test fis(0.5) < lin(0.5)
        @test fis(1.5) < lin(1.5)

        # Both agree at the samples and are held flat outside the grid.
        for f in (fis, lin)
            @test f(0.0) == 1.0
            @test f(1.0) == 0.5
            @test f(2.0) == 0.25
            @test f(-5.0) == 1.0
            @test f(99.0) == 0.25

            # Operation time has no meaning for a prompt profile and is ignored.
            @test f(0.5, 0.0) == f(0.5, Inf)
        end

        # These samples are exp(-t·ln2), so the log form should land on it exactly and the
        # straight line should sit above it.
        @test fis(0.5) ≈ 0.5^0.5 rtol = 1e-14
        @test fis(1.5) ≈ 0.5^1.5 rtol = 1e-14

        @test_throws DimensionMismatch Fissions([0.0, 1.0], [1.0])
    end

    @testset "Fissions interpolation over a decayed tail" begin
        # `_PROFILE_CUTOFF` leaves exact zeros once the profile dies, and a zero has no
        # logarithm. Those segments have to stay finite rather than going to -Inf or NaN.
        fis = Fissions([0.0, 1.0, 2.0, 3.0], [1.0, 1e-3, 0.0, 0.0])
        @test isfinite(fis(1.5))
        @test 0.0 <= fis(1.5) <= 1e-3
        @test fis(2.5) == 0.0
        @test fis(2.0) == 0.0
    end

    @testset "Fissions from a point-kinetics solve" begin
        # Mirrors the two Python hypothesis properties in its test_decay_heat.py, run at
        # fixed kinetic parameters rather than generated ones.
        times = range(0.0, 10.0; length=50)
        critical = Fissions(times, ReactivityController())
        @test all(isapprox.(critical.(times), 1.0; rtol=1e-6))

        shutdown = ReactivityController((s, ts, t) -> -0.001)
        subcritical = Fissions(range(0.0, 1.0; length=10), shutdown)
        power = subcritical.(subcritical.times)
        @test power[1] ≈ 1.0 rtol = 1e-6
        @test all(diff(power) .<= 0)

        # A bare callable of time is as good a control as a ReactivityController.
        @test all(isapprox.(Fissions(times, t -> 0.0).(times), 1.0; rtol=1e-6))

        # The interpolation mode reaches through the solving constructor, and the two modes
        # agree at the samples they share.
        parity = Fissions(times, ReactivityController(); interpolation=Linear())
        @test parity.interpolation isa Linear
        @test parity.profile == critical.profile
    end

    @testset "DecayHeatSource" begin
        # Actinides at R = 1 is 0.865 MeV/fission at saturation and needs no table, so
        # every assertion here runs whether or not the standards package is present.
        model = Actinides(1.0)
        saturated = model(0.0, Inf)
        @test saturated ≈ 0.865 rtol = 1e-12

        @testset "the fission rate carries the units" begin
            src = DecayHeatSource(model, ReactivityController(); P0=1.0, Q=200.0)
            @test src.Φ ≈ 0.005 rtol = 1e-12
            @test src(0.0) ≈ saturated / 200 rtol = 1e-12

            # P0 sets the units, so a core rated in Watts gives Watts out.
            watts = DecayHeatSource(model, ReactivityController(); P0=1e7, Q=200.0)
            @test watts(0.0) ≈ 1e7 / 200 * saturated rtol = 1e-12
            @test watts(0.0) ≈ 1e7 * src(0.0) rtol = 1e-12
        end

        @testset "an untripped controller holds the saturated value" begin
            # A reactor at power carries a saturated inventory, so the source is flat
            # until something trips it, however far the simulation has run.
            src = DecayHeatSource(model, ReactivityController(); P0=1.0)
            @test src(0.0) == src(50.0) == src(1e6)
            @test src(0.0) ≈ saturated / 200 rtol = 1e-12
        end

        @testset "the clock starts when the controller scrams" begin
            trip = SCRAM_at_power(0.5)
            ctrl = ReactivityController((s, ts, t) -> 0.0; state_machine=trip)
            src = DecayHeatSource(model, ctrl; P0=1.0)
            @test src(20.0) ≈ saturated / 200 rtol = 1e-12   # still :NORMAL

            change_state(ctrl, 10.0, 1.0, 0.0)               # over the limit, so :SCRAM
            @test ctrl.state === :SCRAM
            @test ctrl.t_state == 10.0

            @test src(30.0) ≈ 0.005 * model(20.0, Inf) rtol = 1e-12
            @test src(30.0) < src(20.0)
        end

        @testset "the trip is continuous in value, and trial times clamp" begin
            # The decay curve starts at its saturated value, so switching the clock on
            # changes the slope and not the number. A solver trialling a time behind
            # t_state gets the same answer the untripped branch gave it.
            trip = SCRAM_at_power(0.5)
            ctrl = ReactivityController((s, ts, t) -> 0.0; state_machine=trip)
            src = DecayHeatSource(model, ctrl; P0=1.0)
            before = src(10.0)
            change_state(ctrl, 10.0, 1.0, 0.0)
            @test src(10.0) == before
            @test src(9.0) == before      # trial step behind the trip
            @test src(-1.0) == before
            @test decay_time(src, 9.0) == 0.0
            @test decay_time(src, 12.5) == 2.5
        end

        @testset "a known trip time needs no state machine" begin
            # A controller built already in the shutdown state is a fixed trip.
            fixed = ReactivityController(
                (s, ts, t) -> 0.0; initial_state=:SCRAM, initial_time=5.0
            )
            src = DecayHeatSource(model, fixed; P0=1.0)
            @test src(5.0) ≈ saturated / 200 rtol = 1e-12
            @test src(1005.0) ≈ 0.005 * model(1000.0, Inf) rtol = 1e-12
            @test src.([5.0, 1005.0]) == [src(5.0), src(1005.0)]
        end

        @testset "a finite irradiation leaves less behind" begin
            fixed = ReactivityController(
                (s, ts, t) -> 0.0; initial_state=:SCRAM, initial_time=0.0
            )
            brief = DecayHeatSource(model, fixed; P0=1.0, T=100.0)
            saturating = DecayHeatSource(model, fixed; P0=1.0, T=Inf)
            @test brief(0.0) < saturating(0.0)
            @test brief(0.0) ≈ 0.005 * model(0.0, 100.0) rtol = 1e-12
        end

        @testset "contributions sum before they are converted" begin
            fixed = ReactivityController(
                (s, ts, t) -> 0.0; initial_state=:SCRAM, initial_time=0.0
            )
            act = Activation(5.16e-3)
            total = DecayHeatSource(model + 0.5 * act, fixed; P0=1.0)
            parts = (
                DecayHeatSource(model, fixed; P0=1.0),
                DecayHeatSource(0.5 * act, fixed; P0=1.0),
            )
            @test total(300.0) ≈ sum(part(300.0) for part in parts) rtol = 1e-12
        end
    end

    @testset "standards directory" begin
        saved = DecayHeat.STANDARDS_DIR[]
        try
            DecayHeat.STANDARDS_DIR[] = ""
            @test_throws ArgumentError standards_dir()
            standards_dir!("/nowhere/in/particular")
            @test standards_dir() == "/nowhere/in/particular"
        finally
            DecayHeat.STANDARDS_DIR[] = saved
        end
    end

    @testset "reading a table" begin
        mktempdir() do dir
            @test_throws ArgumentError read_standard(ANS73, U238; dir=dir)

            # Python STREAM ships an empty file for combinations it has no table for, so an
            # empty file has to read the same as a missing one.
            touch(joinpath(dir, "U238_ans73.csv"))
            @test_throws ArgumentError read_standard(ANS73, U238; dir=dir)

            # Columns are found by name, so their order in the file does not matter.
            write(joinpath(dir, "U235_ans73.csv"), "alpha,lamda\n2.0,1.0\n4.0,3.0\n")
            λ, α = read_standard(ANS73, U235; dir=dir)
            @test λ == [1.0, 3.0]
            @test α == [2.0, 4.0]
            @test FissionProducts(ANS73, U235; dir=dir)(0.0, Inf) ≈ 2.0 / 1.0 + 4.0 / 3.0

            write(joinpath(dir, "U235_ans14.csv"), "lambda,alpha\n1.0,1.0\n")
            @test_throws ArgumentError read_standard(ANS14, U235; dir=dir)
        end
    end

    @testset "A tripped loop keeps its decay heat" begin
        # The whole point of the port. A reactor scrammed from power drops prompt fission
        # to nothing in seconds, and what is left holding the fuel up is decay heat. Run
        # the same trip twice, once with a source and once without, and compare.
        #
        # The contribution is data free, so this runs with or without the standards.
        P0 = 1.0
        model = Actinides(1.0) + FissionProducts([0.5, 0.01], [3.0, 0.05])
        # A controller born in :SCRAM is a trip at t = 0, and the reactivity is deep enough
        # that the delayed groups are the only thing holding power up.
        scrammed() = ReactivityController(
            (s, ts, t) -> -0.05; initial_state=:SCRAM, initial_time=0.0
        )
        times = range(0.0, 60.0; length=25)
        mesh = (n=3, nz=3, nx=2)
        hottest(sol, ssys, i) =
            maximum(sol[ssys.rods.fuel.T[j, k], i] for j in 1:(mesh.nz), k in 1:(mesh.nx))

        ctrl = scrammed()
        source = DecayHeatSource(model, ctrl; P0=P0)
        ssys, ic = build_loop_pk(ctrl; mesh..., P0=P0, power_input=source)
        sol = solve_transient(ssys, ic, times)
        @test sol.retcode == ReturnCode.Success

        @testset "the operating point splits P0 between fission and decay" begin
            @test sol[ssys.pk.P_total, 1] ≈ P0 rtol = 1e-9
            @test sol[ssys.pk.P, 1] ≈ P0 - source(0.0) rtol = 1e-9
            # Worth a few percent of rated power, which is the order decay heat comes in at.
            @test 0.01 < source(0.0) / P0 < 0.15
        end

        @testset "prompt power collapses and decay heat is what remains" begin
            @test sol[ssys.pk.P, end] < 1e-6 * P0
            @test sol[ssys.pk.P_total, end] ≈ source(times[end]) rtol = 1e-4
            @test sol[ssys.pk.P_total, end] > 0.01 * P0
            # Monotone decay: nothing puts power back in after the trip.
            totals = sol[ssys.pk.P_total, :]
            @test all(diff(totals) .<= 0)
        end

        @testset "the fuel stays hot, where without decay heat it would not" begin
            ctrl_bare = scrammed()
            ssys_bare, ic_bare = build_loop_pk(ctrl_bare; mesh..., P0=P0)
            sol_bare = solve_transient(ssys_bare, ic_bare, times)
            @test sol_bare.retcode == ReturnCode.Success

            T_inlet = 20.0
            # With no source the plate relaxes to the coolant it sits in.
            @test hottest(sol_bare, ssys_bare, length(times)) ≈ T_inlet atol = 0.1
            # With one it does not.
            last = length(times)
            @test hottest(sol, ssys, last) > T_inlet + 1.0
            @test hottest(sol, ssys, last) > hottest(sol_bare, ssys_bare, last)
        end
    end

    if !DH_HAVE_STANDARDS
        @info "STREAM_DECAY_HEAT_STANDARDS is unset, skipping the standards testsets"
    else
        @testset "published tables" begin
            for (standard, source, groups, table_sum) in DH_TABLE_SUMS
                λ, α = read_standard(standard, source; dir=DH_STANDARDS)
                @test length(λ) == groups
                @test length(α) == groups

                # At shutdown after an infinite irradiation every exponential is 1, so the
                # contribution collapses to the sum the README tabulates.
                fps = FissionProducts(standard, source; dir=DH_STANDARDS)
                @test fps(0.0, Inf) ≈ table_sum atol = 5e-5
                @test fps(0.0, Inf) ≈ sum(α ./ λ)
            end
        end

        @testset "fission products against the shutdown percentages" begin
            # Python: fp_percent([0.0, hour, day, week]) close to [6.5, 1.3, 0.5, 0.3] at
            # rtol=1e-1, with fp = contribution(Standard.ANS14, Source.U235) and Q = 200 MeV.
            fps = FissionProducts(ANS14, U235; dir=DH_STANDARDS)
            Q = 200.0
            percent = [100 * fps(t, Inf) / Q for t in (0.0, 3600.0, 86400.0, 604800.0)]
            @test all(isapprox.(percent, [6.5, 1.3, 0.5, 0.3]; rtol=1e-1))

            @test fps(1.0, 0.0) == 0.0
        end

        @testset "contributions fall off monotonically" begin
            # Python asserts this over logspace(-8, 8) for an Al28 activation profile, the
            # actinides at R = 1, and the ANS-5.1-2014 U235 fission products.
            times = 10.0 .^ range(-8, 8; length=50)
            models = (
                Activation(5.16e-3),
                Actinides(1.0),
                FissionProducts(ANS14, U235; dir=DH_STANDARDS),
            )
            for model in models
                @test all(diff(model.(times)) .<= 0)
            end
        end

        @testset "the beta and gamma splits nearly add up to the total" begin
            # U235_jaeri91 is the report's own (B+G) column, rounded independently of its
            # BETA and GAMMA columns, so the three tables agree only to their shared 4
            # significant figures. The README puts that at 0.007% on the shutdown value; the
            # gap widens with cooling time and reaches 6e-4 by a day, which is what sets the
            # tolerance here. Loose as it is, a swapped table would be out by percents.
            beta = FissionProducts(JAERI91, U235_beta; dir=DH_STANDARDS)
            gamma = FissionProducts(JAERI91, U235_gamma; dir=DH_STANDARDS)
            total = FissionProducts(JAERI91, U235; dir=DH_STANDARDS)
            for t in (0.0, 3600.0, 86400.0)
                @test (beta + gamma)(t, Inf) ≈ total(t, Inf) rtol = 1e-3
            end
        end
    end
end
