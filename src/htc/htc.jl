"""
    AbstractHTC

A wall heat transfer coefficient model. Subtypes are callable as

    htc(T_wall, T_bulk, ṁ, Dh, A, liquid) -> h [W/(m²·K)]

with temperatures in °C, `ṁ` in kg/s, `Dh` and `A` the channel's hydraulic diameter and flow
area, and `liquid` an [`AbstractLiquid`](@ref).

Shipped models: [`FromNusselt`](@ref) and the named correlations built on it
([`DittusBoelter`](@ref), [`ConstantNusselt`](@ref), [`FullyDevelopedLaminar`](@ref),
[`DevelopingLaminar`](@ref)), [`Elenbaas`](@ref) for natural convection,
[`RegimeDependent`](@ref) to switch between them, [`Maximal`](@ref), and
[`SubcooledBoiling`](@ref) to add partial boiling on top of any of them.

To add your own, either subtype this and define the call, or wrap a closure in
[`FromFunction`](@ref).
"""
abstract type AbstractHTC end

"""
    FromFunction(f) <: AbstractHTC

Lift a callable `f(T_wall, T_bulk, ṁ, Dh, A, liquid) -> h` into an [`AbstractHTC`](@ref), for a
correlation not worth its own type.
"""
struct FromFunction{F} <: AbstractHTC
    f::F
end

function (htc::FromFunction)(T_wall, T_bulk, ṁ, Dh, A, liquid)
    return htc.f(T_wall, T_bulk, ṁ, Dh, A, liquid)
end

"""
    film_temperature(T_wall, T_bulk) -> °C

Midway between the wall and the bulk, `(T_wall + T_bulk)/2`. Named rather than inlined so
the convention is one place to find and to change.
"""
film_temperature(T_wall, T_bulk) = (T_wall + T_bulk) / 2

"""
    PropertyBasis

Where a model reads the coolant properties that close a Nusselt number into an `h`:
[`AtFilm`](@ref) or [`AtBulk`](@ref).
"""
abstract type PropertyBasis end

"""
    AtFilm <: PropertyBasis

Read properties at the film temperature, `(T_wall + T_bulk)/2`. The usual choice for forced
convection, and what turbulent correlations are normally fitted against.
"""
struct AtFilm <: PropertyBasis end

"""
    AtBulk <: PropertyBasis

Read properties at the bulk temperature. [`RegimeDependent`](@ref) reads its laminar and
natural branches this way.
"""
struct AtBulk <: PropertyBasis end

property_temperature(::AtFilm, T_wall, T_bulk) = film_temperature(T_wall, T_bulk)
property_temperature(::AtBulk, T_wall, T_bulk) = T_bulk

"""
    FromNusselt(nusselt; basis=AtFilm()) <: AbstractHTC

Close a Nusselt correlation into a heat transfer coefficient, `h = Nu·κ/Dh`, reading Re, Pr
and κ at the temperature `basis` names.

`nusselt` is called as `(Re, Pr, T_wall, T_bulk) -> Nu`. Correlations written as
`(Re, Pr, args...)` absorb the trailing temperatures unchanged.

# Arguments
- `nusselt`: the correlation to close
- `basis`: [`AtFilm`](@ref) (default) or [`AtBulk`](@ref)
"""
struct FromNusselt{N,B<:PropertyBasis} <: AbstractHTC
    nusselt::N
    basis::B
end

FromNusselt(nusselt; basis::PropertyBasis=AtFilm()) = FromNusselt(nusselt, basis)

function (htc::FromNusselt)(T_wall, T_bulk, ṁ, Dh, A, liquid)
    T_prop = property_temperature(htc.basis, T_wall, T_bulk)
    Nu = htc.nusselt(Re(liquid, T_prop, ṁ, A, Dh), Pr(liquid, T_prop), T_wall, T_bulk)
    return Nu * κ(liquid, T_prop) / Dh
end

"""
    DittusBoelter(; basis=AtFilm()) -> FromNusselt

Dittus-Boelter turbulent forced convection, `Nu = 0.023·Re^0.8·Pr^0.4`.
"""
DittusBoelter(; basis::PropertyBasis=AtFilm()) = FromNusselt(dittus_boelter, basis)

"""
    ConstantNusselt(; Nu=8.235, basis=AtFilm()) -> FromNusselt

A fixed Nusselt number, the fully-developed laminar value for parallel plates by default.
"""
function ConstantNusselt(; Nu=8.235, basis::PropertyBasis=AtFilm())
    return FromNusselt(constant_Nusselt(; Nu=Nu), basis)
end

"""
    FullyDevelopedLaminar(geom; basis=AtBulk()) -> FromNusselt

Fully-developed laminar flow in a rectangular channel, corrected for aspect ratio.

The bulk basis is the default because that is where a laminar branch is evaluated in Python
STREAM, and it is the branch that matters most: at low Reynolds number the film and bulk
temperatures are furthest apart.
"""
function FullyDevelopedLaminar(geom::PipeGeometry; basis::PropertyBasis=AtBulk())
    return FromNusselt(fully_developed_laminar_nusselt(geom), basis)
end

"""
    DevelopingLaminar(geom; develop_length, basis=AtBulk()) -> FromNusselt

Thermally developing laminar flow over `develop_length`, corrected for aspect ratio.
"""
function DevelopingLaminar(geom::PipeGeometry; develop_length,
                           basis::PropertyBasis=AtBulk())
    return FromNusselt(developing_laminar_nusselt(geom; develop_length=develop_length), basis)
end

"""
    Elenbaas(geom; g=G_EARTH, basis=AtFilm()) <: AbstractHTC

Elenbaas natural convection between symmetrically heated parallel vertical plates.

The plate gap `S = geom.depth` is the length scale throughout: Ra is taken on `S` and
`h = Nu·κ/S`. [`RegimeDependent`](@ref) reads a natural branch at the bulk instead of the
film.

# Arguments
- `geom`: channel geometry; `geom.depth` is the gap and `geom.L` the heated length
- `g`: gravitational acceleration [m/s²]
- `basis`: where the coolant properties are read, [`AtFilm`](@ref) (default) or [`AtBulk`](@ref)

# Returns
An `Elenbaas` model, callable like any [`AbstractHTC`](@ref).
"""
struct Elenbaas{B<:PropertyBasis} <: AbstractHTC
    gap::Float64
    heated_length::Float64
    g::Float64
    basis::B
end

function Elenbaas(geom::PipeGeometry; g=G_EARTH, basis::PropertyBasis=AtFilm())
    return Elenbaas(geom.depth, geom.L, Float64(g), basis)
end

function (htc::Elenbaas)(T_wall, T_bulk, ṁ, Dh, A, liquid)
    T_prop = property_temperature(htc.basis, T_wall, T_bulk)
    Gr_val = Gr(ρ(liquid, T_prop), μ(liquid, T_prop), β(liquid, T_prop),
                T_wall, T_bulk, htc.gap, htc.g)
    Nu = elenbaas_nusselt(Ra(Gr_val, Pr(liquid, T_prop)), htc.gap, htc.heated_length)
    return Nu * κ(liquid, T_prop) / htc.gap
end

"""
    _with_basis(model, basis) -> AbstractHTC

The same correlation as `model`, reading its coolant properties at `basis` rather than at its
own: at the bulk temperature for [`AtBulk`](@ref), at the film for [`AtFilm`](@ref). A model
with no property basis, such as a user-defined one or `nothing`, comes back as it is.
"""
_with_basis(m::FromNusselt, basis) = FromNusselt(m.nusselt, basis)
_with_basis(m::Elenbaas, basis) = Elenbaas(m.gap, m.heated_length, m.g, basis)
_with_basis(m, basis) = m

"""
    RegimeDependent(; laminar, turbulent, natural=nothing, re_bounds=(2000.0, 5000.0),
                       geom, gz_band=(0.01, 0.1)) <: AbstractHTC

A heat transfer coefficient that picks its forced-convection correlation by flow regime and
adds buoyancy on top: `laminar` at low Reynolds number, `turbulent` at high, a linear blend
of the two across `re_bounds` on the bulk Reynolds number, and `natural` convection
combined with that forced value.

With a `natural` model, forced and natural convection combine by Churchill's rule,
`h³ = h_f³ ± h_n³`. The sign depends on whether buoyancy helps the flow or works against it:

- **Aiding**, buoyancy along the flow: `h = (h_f³ + h_n³)^(1/3)`. Heated upflow, or cooled
  downflow.
- **Opposing**, buoyancy against the flow: `h = max((h_f³ - h_n³)^(1/3), h_n)`. Heated
  downflow, or cooled upflow. Past the point where `h_n` reaches `2^(-1/3)·h_f` the near-wall
  flow separates and natural convection governs, so the value is floored at `h_n`.

Both keep the wall balance `h·(T_wall - T_bulk)` rising with the wall temperature, so every
cell's balance has one solution. The signs follow laminar mixed convection. In turbulent flow
buoyancy acts the other way round, but there `h_n` is too small beside `h_f` to matter.

Which way the flow runs is the channel's to say, and a [`ChannelAndContacts`](@ref) sets it
from its own `g`. A model that was never handed to a channel treats buoyancy as aiding.

As the through-flow dies, the value hands over to the pure `natural` model. The handover
reads the Graetz number `Gz = Re·Pr·Dh/L` on the bulk and is a smooth step across `gz_band`,
taken on log10. The band is a choice, not a correlation: well below any circulating flow,
and wide enough that `h` stays continuous where the flow reverses.

Each branch reads its coolant properties at one fixed temperature, whatever basis its model
was built with: laminar and natural convection at the bulk, turbulent at the film. A model
with no property basis of its own is used as given.

# Arguments
- `laminar`, `turbulent`: the two forced-convection models
- `natural`: optional natural-convection model
- `re_bounds`: `(re_lo, re_hi)` transition band on the bulk Reynolds number
- `geom`: channel geometry; `geom.L` is the heated length in the Graetz number
- `gz_band`: `(gz_lo, gz_hi)` over which the value hands over to pure natural convection

# Returns
A `RegimeDependent` model, callable like any [`AbstractHTC`](@ref).
"""
struct RegimeDependent{L<:AbstractHTC,T<:AbstractHTC,N} <: AbstractHTC
    laminar::L
    turbulent::T
    natural::N
    re_bounds::Tuple{Float64,Float64}
    heated_length::Float64
    gz_band::Tuple{Float64,Float64}
    # +1 when positive ṁ runs upward, -1 when downward, 0 when not known or horizontal.
    flow_up::Float64
end

function RegimeDependent(;
    laminar::AbstractHTC,
    turbulent::AbstractHTC,
    natural::Union{AbstractHTC,Nothing}=nothing,
    re_bounds=(2000.0, 5000.0),
    geom::PipeGeometry,
    gz_band=(0.01, 0.1),
)
    bounds = (Float64(re_bounds[1]), Float64(re_bounds[2]))
    gz = (Float64(gz_band[1]), Float64(gz_band[2]))
    return RegimeDependent(
        _with_basis(laminar, AtBulk()), _with_basis(turbulent, AtFilm()),
        _with_basis(natural, AtBulk()), bounds, Float64(geom.L), gz, 0.0,
    )
end

"""
    _smooth_step(x, x0, x1) -> [0, 1]

The C1 cubic step `3s² - 2s³` with `s = (x - x0)/(x1 - x0)` clamped to `[0, 1]`: zero below
`x0`, one above `x1`, with zero slope at both ends.
"""
function _smooth_step(x, x0, x1)
    s = min(max((x - x0) / (x1 - x0), zero(x)), one(x))
    return s * s * (3 - 2 * s)
end

function (htc::RegimeDependent)(T_wall, T_bulk, ṁ, Dh, A, liquid)
    Re_bulk = Re(liquid, T_bulk, ṁ, A, Dh)
    h_forced = flow_regime_blend(
        Re_bulk, htc.re_bounds,
        htc.laminar(T_wall, T_bulk, ṁ, Dh, A, liquid),
        htc.turbulent(T_wall, T_bulk, ṁ, Dh, A, liquid),
    )
    htc.natural === nothing && return h_forced
    h_nat = htc.natural(T_wall, T_bulk, ṁ, Dh, A, liquid)
    aiding = (h_forced^3 + h_nat^3)^(1 / 3)
    opposing = max(max(h_forced^3 - h_nat^3, zero(h_nat))^(1 / 3), h_nat)
    # A wall hotter than the bulk pushes the fluid beside it up.
    opposed = htc.flow_up * ṁ * (T_wall - T_bulk) < 0
    h_mixed = ifelse(opposed, opposing, aiding)
    Gz = Re_bulk * Pr(liquid, T_bulk) * Dh / htc.heated_length
    # The flip between aiding and opposing happens at ṁ = 0, where Gz = 0 and the weight is
    # already zero, so h has no jump there.
    w = _smooth_step(log10(Gz), log10(htc.gz_band[1]), log10(htc.gz_band[2]))
    return w * h_mixed + (1 - w) * h_nat
end

"""
    _oriented(model, flow_up) -> AbstractHTC

`model` told which way its channel's flow runs: `flow_up` is +1 when positive `ṁ` runs
upward, -1 when downward, 0 when horizontal. Only a [`RegimeDependent`](@ref) uses it, and
the models that wrap one pass it through. Anything else comes back unchanged.
"""
function _oriented(m::RegimeDependent, flow_up)
    return RegimeDependent(m.laminar, m.turbulent, m.natural, m.re_bounds, m.heated_length,
                           m.gz_band, Float64(flow_up))
end
_oriented(m, flow_up) = m

"""
    Maximal(models...) <: AbstractHTC

The largest `h` of several models, for a wall cooled by whichever mechanism happens to win.
"""
struct Maximal{T<:Tuple} <: AbstractHTC
    models::T
end

Maximal(models::AbstractHTC...) = Maximal(models)

function (htc::Maximal)(T_wall, T_bulk, ṁ, Dh, A, liquid)
    return reduce(max, (m(T_wall, T_bulk, ṁ, Dh, A, liquid) for m in htc.models))
end

_oriented(m::Maximal, flow_up) = Maximal(map(x -> _oriented(x, flow_up), m.models))

"""
    SubcooledBoiling(single_phase, q_scb) <: AbstractHTC

Partial subcooled boiling layered on top of a single-phase model: `single_phase` below the
onset of nucleate boiling, and that value scaled by the Bergles-Rohsenow partial boiling
factor at or above it.

Needs the local pressure, which the channel supplies, so this model is called with the
extra-argument form `(T_wall, T_bulk, ṁ, Dh, A, liquid, P)`.

# Arguments
- `single_phase`: the underlying [`AbstractHTC`](@ref)
- `q_scb`: subcooled boiling heat flux closure `(T_wall, sat, Re) -> q`, e.g. from
  [`regime_dependent_q_scb`](@ref). `sat` is the coolant's [`Liquid`](@ref) snapshot at
  saturation at the local pressure, and `Re` the bulk Reynolds number.
"""
struct SubcooledBoiling{H<:AbstractHTC,Q} <: AbstractHTC
    single_phase::H
    q_scb::Q
end

function _oriented(m::SubcooledBoiling, flow_up)
    return SubcooledBoiling(_oriented(m.single_phase, flow_up), m.q_scb)
end

# Without a pressure there is nothing to boil against, so this degenerates to single phase.
function (htc::SubcooledBoiling)(T_wall, T_bulk, ṁ, Dh, A, liquid)
    return htc.single_phase(T_wall, T_bulk, ṁ, Dh, A, liquid)
end

function (htc::SubcooledBoiling)(T_wall, T_bulk, ṁ, Dh, A, liquid, P)
    h_spl = htc.single_phase(T_wall, T_bulk, ṁ, Dh, A, liquid)
    return _scb_corrected(h_spl, htc.q_scb, T_wall, T_bulk, ṁ, Dh, A, liquid, P)
end

# Models that do not care about pressure ignore the extra argument, so a channel can always
# pass it and let the model decide.
(htc::AbstractHTC)(T_wall, T_bulk, ṁ, Dh, A, liquid, P) = htc(T_wall, T_bulk, ṁ, Dh, A, liquid)
