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

Read properties at the bulk temperature. Python STREAM closes its laminar branch this way.
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
    Elenbaas(geom; g=G_EARTH) <: AbstractHTC

Elenbaas natural convection between parallel vertical plates.

Buoyancy is driven by the bulk-to-wall difference, so Gr and the properties behind it are
taken at the bulk temperature, matching Python STREAM. `geom.depth` is the plate gap,
`geom.L` the heated length, and `geom.Dh` the Grashof characteristic length.
"""
struct Elenbaas <: AbstractHTC
    gap::Float64
    heated_length::Float64
    Dh_gr::Float64
    g::Float64
end

function Elenbaas(geom::PipeGeometry; g=G_EARTH)
    return Elenbaas(geom.depth, geom.L, geom.Dh, Float64(g))
end

function (htc::Elenbaas)(T_wall, T_bulk, ṁ, Dh, A, liquid)
    Ra_val = Ra(Gr(liquid, T_bulk, T_wall, htc.Dh_gr, htc.g), Pr(liquid, T_bulk))
    Nu = elenbaas_nusselt(Ra_val, htc.gap, htc.heated_length)
    return Nu * κ(liquid, T_bulk) / Dh
end

"""
    RegimeDependent(; laminar, turbulent, natural=nothing, re_bounds=(2000.0, 5000.0),
                       geom, g=G_EARTH) <: AbstractHTC

Switch between laminar, turbulent and natural convection, the way Python STREAM's
`regime_dependent_h_spl` does.

The regime is selected on the **bulk** Reynolds number and the two forced branches are
blended across `re_bounds` by [`flow_regime_blend`](@ref). Each branch is a full `AbstractHTC`, so
where it reads its properties is its own business: that is how the laminar branch ends up at
bulk and the turbulent one at film without this model having to know.

Given a `natural` model, buoyancy takes over wherever `Gr/Re² > 1`.

# Arguments
- `laminar`, `turbulent`: the two forced-convection models
- `natural`: optional natural-convection model
- `re_bounds`: `(re_lo, re_hi)` transition band on the bulk Reynolds number
- `geom`: channel geometry; `geom.Dh` is the Grashof characteristic length
- `g`: gravitational acceleration [m/s²], used only when `natural` is given
"""
struct RegimeDependent{L<:AbstractHTC,T<:AbstractHTC,N} <: AbstractHTC
    laminar::L
    turbulent::T
    natural::N
    re_bounds::Tuple{Float64,Float64}
    Dh_gr::Float64
    g::Float64
end

function RegimeDependent(;
    laminar::AbstractHTC,
    turbulent::AbstractHTC,
    natural::Union{AbstractHTC,Nothing}=nothing,
    re_bounds=(2000.0, 5000.0),
    geom::PipeGeometry,
    g=G_EARTH,
)
    bounds = (Float64(re_bounds[1]), Float64(re_bounds[2]))
    return RegimeDependent(laminar, turbulent, natural, bounds, geom.Dh, Float64(g))
end

function (htc::RegimeDependent)(T_wall, T_bulk, ṁ, Dh, A, liquid)
    Re_bulk = Re(liquid, T_bulk, ṁ, A, Dh)
    h_forced = flow_regime_blend(
        Re_bulk, htc.re_bounds,
        htc.laminar(T_wall, T_bulk, ṁ, Dh, A, liquid),
        htc.turbulent(T_wall, T_bulk, ṁ, Dh, A, liquid),
    )
    htc.natural === nothing && return h_forced
    Gr_val = Gr(liquid, T_bulk, T_wall, htc.Dh_gr, htc.g)
    return ifelse(
        Gr_val / Re_bulk^2 > 1,
        htc.natural(T_wall, T_bulk, ṁ, Dh, A, liquid),
        h_forced,
    )
end

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

"""
    SubcooledBoiling(single_phase, q_scb) <: AbstractHTC

Partial subcooled boiling layered on top of a single-phase model: `single_phase` below the
onset of nucleate boiling, and that value scaled by the Bergles-Rohsenow partial boiling
factor at or above it.

Needs the local pressure, which the channel supplies, so this model is called with the
extra-argument form `(T_wall, T_bulk, ṁ, Dh, A, liquid, P)`.

# Arguments
- `single_phase`: the underlying [`AbstractHTC`](@ref)
- `q_scb`: subcooled boiling heat flux closure `(T_wall, T_sat, Re) -> q`, e.g. from
  [`regime_dependent_q_scb`](@ref)
"""
struct SubcooledBoiling{H<:AbstractHTC,Q} <: AbstractHTC
    single_phase::H
    q_scb::Q
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
