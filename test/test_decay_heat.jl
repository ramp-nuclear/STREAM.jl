using Test
using STREAM
using STREAM.DecayHeat
using STREAM.Components: ReactivityController

# The published tables are not distributed with this package, so the testsets that read one
# run only when STREAM_DECAY_HEAT_STANDARDS points at a directory holding them. Python STREAM
# skips its own decay heat file the same way, for the same reason.
const DH_STANDARDS = get(ENV, "STREAM_DECAY_HEAT_STANDARDS", "")
const DH_HAVE_STANDARDS = !isempty(DH_STANDARDS) && isdir(DH_STANDARDS)

# Sums of alpha/lamda per table, in MeV/fission, transcribed from the "Contents" table of
# PROVENANCE.md that ships beside the CSVs. Published to four decimals, hence the atol below.
const DH_TABLE_SUMS = [
    (ANS14, U235, 23, 13.4395),
    (ANS73, U235, 23, 13.1823),
    (JAERI91, U235, 33, 12.9551),
    (JAERI91, U235_beta, 33, 6.5233),
    (JAERI91, U235_gamma, 33, 6.4318),
    (ANS14, U238, 23, 17.6789),
    (JAERI91, U238_gamma, 33, 5.7556),
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

        # One group of alpha/lamda is that group's Activation profile scaled.
        one_group = FissionProducts([0.1], [0.5])
        @test one_group(7.0, 100.0) ≈ 5.0 * Activation(0.1)(7.0, 100.0)

        # No irradiation, no inventory, whatever the groups are.
        @test FissionProducts([1.0, 2.0], [3.0, 4.0])(1.0, 0.0) == 0.0

        # Negative alpha are least-squares fit coefficients, not yields, and pass through.
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

        # sum falls out of `+`, which is the point of defining `+` and nothing else.
        @test sum([act, acs, fps])(100.0, Inf) == total(100.0, Inf)

        scaled = 200.0 * act
        @test scaled isa Scaled
        @test scaled(100.0, Inf) ≈ 200.0 * act(100.0, Inf)
        @test (act * 200.0)(100.0, Inf) == scaled(100.0, Inf)
    end

    @testset "Fissions" begin
        # np.interp semantics: linear between the samples, held flat outside them.
        fis = Fissions([0.0, 1.0, 2.0], [1.0, 0.5, 0.25])
        @test fis(0.0) == 1.0
        @test fis(1.0) == 0.5
        @test fis(2.0) == 0.25
        @test fis(0.5) ≈ 0.75
        @test fis(1.5) ≈ 0.375
        @test fis(-5.0) == 1.0
        @test fis(99.0) == 0.25

        # Operation time has no meaning for a prompt profile and is ignored.
        @test fis(0.5, 0.0) == fis(0.5, Inf)

        @test_throws DimensionMismatch Fissions([0.0, 1.0], [1.0])
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
            lamda, alpha = read_standard(ANS73, U235; dir=dir)
            @test lamda == [1.0, 3.0]
            @test alpha == [2.0, 4.0]
            @test FissionProducts(ANS73, U235; dir=dir)(0.0, Inf) ≈ 2.0 / 1.0 + 4.0 / 3.0

            write(joinpath(dir, "U235_ans14.csv"), "lambda,alpha\n1.0,1.0\n")
            @test_throws ArgumentError read_standard(ANS14, U235; dir=dir)
        end
    end

    if !DH_HAVE_STANDARDS
        @info "STREAM_DECAY_HEAT_STANDARDS is unset, skipping the standards testsets"
    else
        @testset "published tables" begin
            for (standard, source, groups, table_sum) in DH_TABLE_SUMS
                lamda, alpha = read_standard(standard, source; dir=DH_STANDARDS)
                @test length(lamda) == groups
                @test length(alpha) == groups

                # At shutdown after an infinite irradiation every exponential is 1, so the
                # contribution collapses to the sum PROVENANCE.md tabulates.
                fps = FissionProducts(standard, source; dir=DH_STANDARDS)
                @test fps(0.0, Inf) ≈ table_sum atol = 5e-5
                @test fps(0.0, Inf) ≈ sum(alpha ./ lamda)
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
            # Python asserts this over logspace(-8, 8) for an Al-28 activation profile, the
            # actinides at R = 1, and the ANS-5.1-2014 U-235 fission products.
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

        @testset "the beta and gamma splits add up to the total" begin
            # PROVENANCE.md records that U235_jaeri91 was built as the row-wise sum of the
            # beta and gamma tables, so this holds by construction and catches a table swap.
            beta = FissionProducts(JAERI91, U235_beta; dir=DH_STANDARDS)
            gamma = FissionProducts(JAERI91, U235_gamma; dir=DH_STANDARDS)
            total = FissionProducts(JAERI91, U235; dir=DH_STANDARDS)
            for t in (0.0, 3600.0, 86400.0)
                @test (beta + gamma)(t, Inf) ≈ total(t, Inf) rtol = 1e-12
            end
        end
    end
end
