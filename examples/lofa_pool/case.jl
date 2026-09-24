# The pool LOFA case that run.jl and timings.jl share, included after `using STREAM` and
# `using STREAM.Components`. Every value marked PLACEHOLDER is one, and none describes a
# plant.
const DH = STREAM.DecayHeat

#! format: off
const case = (
    L=0.6,                    # PLACEHOLDER heated length [m]
    n=10,                     # axial cells
    nx=4,                     # lateral cells per plate
    rho_s=2700.0,             # PLACEHOLDER plate density [kg/m³]
    cp_s=900.0,               # PLACEHOLDER plate specific heat [J/(kg·K)]
    k_s=180.0,                # PLACEHOLDER plate conductivity [W/(m·K)]
    T_pool=35.0,              # PLACEHOLDER pool temperature [°C]
    p_pool=1.7e5,             # PLACEHOLDER absolute pressure at the core top [Pa]
    P_rated=2.8e6,            # PLACEHOLDER rated power [W], enough to boil the hot plate
    dP_pump=3.9e4,            # PLACEHOLDER pump head at design flow [Pa]
    flywheel_L_over_A=2.5e4,  # PLACEHOLDER flywheel L/A [1/m], sets the coastdown
    primary_dp=3.0e4,         # PLACEHOLDER primary piping drop at design flow [Pa]
    riser_L=0.6,              # riser height [m], equal to L so the loop closes in elevation
    riser_D=0.3,              # PLACEHOLDER riser diameter [m]
    flapper_open_at=1.5,      # PLACEHOLDER primary flow that opens the flapper [kg/s]
    flapper_f=1.0,            # PLACEHOLDER flapper open-state loss coefficient
    flapper_area=0.03,        # PLACEHOLDER flapper flow area [m²]
    flapper_open_time=2.0,    # PLACEHOLDER time the flapper takes to open [s]
    trip_fraction=0.85,       # PLACEHOLDER low-flow trip, as a fraction of design flow
    Lambda=U235_LAMBDA,       # PLACEHOLDER generation time [s]
    beta_k=U235_BETA_K,       # PLACEHOLDER delayed neutron fractions
    lambda_k=U235_LAMBDA_K,   # PLACEHOLDER precursor decay constants [1/s]
    types=(
        # The type that makes most of the power and takes most of the flow.
        high=(
            N=40,                     # PLACEHOLDER channels of this type in the core
            width=0.066,              # PLACEHOLDER channel width [m]
            gap=0.0027,               # PLACEHOLDER channel gap [m]
            heated_width=0.063,       # PLACEHOLDER heated width of each face [m]
            plate_thickness=0.00127,  # PLACEHOLDER [m]
            ppf=1.4,                  # PLACEHOLDER axial power peaking factor, in [1, π/2]
            power_fraction=0.9,       # PLACEHOLDER share of P_rated
            orifice_dp=2.0e3,         # PLACEHOLDER inlet orifice drop at design flow [Pa]
            design_ṁ=0.356,           # PLACEHOLDER design flow per channel [kg/s]
        ),
        # Throttled harder at its inlet, so the two types balance across the core.
        low=(
            N=10,
            width=0.066,
            gap=0.0027,
            heated_width=0.063,
            plate_thickness=0.00127,
            ppf=1.3,
            power_fraction=0.1,
            orifice_dp=6.25e3,
            design_ṁ=0.2,
        ),
    ),
)

const rod_delay = 0.1              # PLACEHOLDER from trip signal to rod motion [s]
const rod_insertion = 0.5          # PLACEHOLDER rod insertion time [s]
const rod_worth = -0.06            # PLACEHOLDER total scram reactivity
const captures_per_fission = 0.5   # PLACEHOLDER U238 captures per fission
const t_end = 300.0                # simulated time [s]
const n_saved = 3001               # saved time points, 0.1 s apart so the trip is resolved
const forced_fraction = 0.05       # OFI and OSV skip flows under this share of design
#! format: on

rod(τ) = rod_worth * clamp((τ - rod_delay) / rod_insertion, 0.0, 1.0)
scram_worth(state, t_state, t) = state === :SCRAM ? rod(t - t_state) : 0.0

"""
    controls() -> (ctrl, source)

A fresh `ReactivityController` for the scram, on a machine of its own, and the decay heat
source that reads its trip time. The source holds fission products and U238 capture only: after the scram the kinetics
already carry the fission tail from the delayed neutrons, so adding `DecayHeat.Fissions`
would count it twice.
"""
function controls()
    haskey(ENV, "STREAM_DECAY_HEAT_STANDARDS") || error(
        "set STREAM_DECAY_HEAT_STANDARDS to the directory holding the decay heat " *
        "tables: the fission product term, the largest contribution, is read from them",
    )
    ctrl = ReactivityController(scram_worth; machine=StateMachine())
    heat = DH.FissionProducts(DH.ANS14, DH.U235) + DH.U238CaptureChain(captures_per_fission)
    return ctrl, DH.DecayHeatSource(heat, ctrl; P0=1.0)
end
