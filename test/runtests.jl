# test/runtests.jl — thin orchestrator (Phase 55 close)
# All test logic lives in the individual test_*.jl files.
#
# 14-file Phase 55 final layout (per Python STREAM rules + 55-CONTEXT.md D-17..D-22):
#   - Per-component unit tests: geometry, pump, resistors, misc, heat_diffusion, flapper,
#     channels (consolidated Channel + CHF + CAC + _channel_core + sign-safety), connectors,
#     point_kinetics (component-only after Phase 55 trim).
#   - Library tests: fluids, correlations, thresholds (renamed from analysis).
#   - Composition: composition (rewritten under Phase 55 D-18).
#   - Integration: integration (NEW; absorbs examples/solvers/loss_of_flow/subcooled_boiling
#     + TF-06/07 from point_kinetics).
#   - External-reference validation: validation (untouched; Phase 56's deliverable).

include("test_geometry.jl")
include("test_connectors.jl")
include("test_fluids.jl")
include("test_channels.jl")
include("test_pump.jl")
include("test_flapper.jl")
include("test_resistors.jl")
include("test_misc.jl")
include("test_heat_diffusion.jl")
include("test_determinacy.jl")
include("test_correlations.jl")
include("test_thresholds.jl")
include("test_composition.jl")
include("test_validation.jl")
include("test_integration.jl")
include("test_point_kinetics.jl")
