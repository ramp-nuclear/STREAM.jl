# Determinism setup for the whole suite. runtests.jl includes this first so a run reduces
# floating-point the same way on any machine and any rand() draws the same numbers.

using Random
using LinearAlgebra

# Fix the BLAS thread count so the dot-product reduction order does not change with a machine's
# core count. A borderline stiff solve can land on Success at one core count and Unstable at
# another from the different rounding alone, which is how the same code and the same package
# versions can pass on a laptop and fail on a CI runner. Holding the count constant removes that
# variable. STREAM_BLAS_THREADS lets the cross-machine stress run sweep it on purpose; everything
# else defaults to one thread.
BLAS.set_num_threads(parse(Int, get(ENV, "STREAM_BLAS_THREADS", "1")))

# Seed the global RNG so the property tests that build random matrices draw the same values every
# run. A failure is then reproducible from the seed without rerunning until it reappears.
Random.seed!(20260620)
