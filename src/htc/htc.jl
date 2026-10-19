"""
    AbstractHTC

A wall heat transfer coefficient model. Subtypes are callable as

    htc(T_wall, T_bulk, ṁ, liquid, duct) -> h [W/(m²·K)]

with temperatures in °C, `ṁ` in kg/s, `liquid` an [`AbstractLiquid`](@ref) and `duct` the
channel's [`Duct`](@ref). A channel also passes the local pressure, as a sixth argument, which
every model but [`SubcooledBoiling`](@ref) ignores.

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

Lift a callable `f(T_wall, T_bulk, ṁ, liquid, duct) -> h` into an [`AbstractHTC`](@ref), for a
correlation not worth its own type.

# Examples
A named function prints as its name, and an anonymous one as "a correlation":
```jldoctest
julia> HTC.FromFunction((T_wall, T_bulk, ṁ, liquid, duct) -> 5000.0)
HTC.FromFunction(a correlation)
```
"""
struct FromFunction{F} <: AbstractHTC
    f::F
end

(htc::FromFunction)(T_wall, T_bulk, ṁ, liquid, duct) = htc.f(T_wall, T_bulk, ṁ, liquid, duct)

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

`nusselt` is called as `(Re, Pr, T_wall, T_bulk, duct) -> Nu`. Correlations written as
`(Re, Pr, args...)` ignore the trailing arguments.

# Arguments
- `nusselt`: the correlation to close
- `basis`: [`AtFilm`](@ref) (default) or [`AtBulk`](@ref)
"""
struct FromNusselt{N,B<:PropertyBasis} <: AbstractHTC
    nusselt::N
    basis::B
end

FromNusselt(nusselt; basis::PropertyBasis=AtFilm()) = FromNusselt(nusselt, basis)

function (htc::FromNusselt)(T_wall, T_bulk, ṁ, liquid, duct)
    T_prop = property_temperature(htc.basis, T_wall, T_bulk)
    Nu = htc.nusselt(Re(liquid, T_prop, ṁ, duct), Pr(liquid, T_prop), T_wall, T_bulk, duct)
    return Nu * κ(liquid, T_prop) / hydraulic_diameter(duct)
end

"""
    DittusBoelter(; basis=AtFilm()) -> FromNusselt

Dittus-Boelter turbulent forced convection, `Nu = 0.023·Re^0.8·Pr^0.4`.

# Examples
```jldoctest
julia> HTC.DittusBoelter()
HTC.FromNusselt(dittus_boelter), at the film temperature
```
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
    FullyDevelopedLaminar(; basis=AtBulk()) -> FromNusselt

Fully-developed laminar flow in a rectangular duct, corrected for its aspect ratio, from
[`fully_developed_laminar_nusselt`](@ref). Only a rectangular duct has one.

The bulk basis is the default because that is where a laminar branch is evaluated in Python
STREAM, and it is the branch that matters most: at low Reynolds number the film and bulk
temperatures are furthest apart.
"""
function FullyDevelopedLaminar(; basis::PropertyBasis=AtBulk())
    return FromNusselt(fully_developed_laminar_nusselt, basis)
end

"""
    DevelopingLaminar(; develop_length, basis=AtBulk()) -> FromNusselt

Thermally developing laminar flow in a rectangular duct, `develop_length` metres from the
heated entrance, from [`developing_laminar_nusselt`](@ref).
"""
function DevelopingLaminar(; develop_length, basis::PropertyBasis=AtBulk())
    return FromNusselt(_DevelopingNu(develop_length), basis)
end

"""
    Elenbaas(; g=G_EARTH, basis=AtFilm()) <: AbstractHTC

Elenbaas natural convection between symmetrically heated parallel vertical plates, so in a
rectangular duct only.

The plate gap `S`, the duct's `depth`, is the length scale throughout: Ra is taken on `S` and
`h = Nu·κ/S`. The duct's length is the heated length. [`RegimeDependent`](@ref) reads a natural
branch at the bulk instead of the film.

# Arguments
- `g`: gravitational acceleration [m/s²]
- `basis`: where the coolant properties are read, [`AtFilm`](@ref) (default) or [`AtBulk`](@ref)

# Returns
An `Elenbaas` model, callable like any [`AbstractHTC`](@ref).
"""
struct Elenbaas{B<:PropertyBasis} <: AbstractHTC
    g::Float64
    basis::B
end

Elenbaas(; g=G_EARTH, basis::PropertyBasis=AtFilm()) = Elenbaas(Float64(g), basis)

function (htc::Elenbaas)(T_wall, T_bulk, ṁ, liquid, duct::Duct{<:Rectangular})
    gap = duct.shape.depth
    T_prop = property_temperature(htc.basis, T_wall, T_bulk)
    Gr_val = Gr(ρ(liquid, T_prop), μ(liquid, T_prop), β(liquid, T_prop),
                T_wall, T_bulk, gap, htc.g)
    Nu = elenbaas_nusselt(Ra(Gr_val, Pr(liquid, T_prop)), gap, duct.L)
    return Nu * κ(liquid, T_prop) / gap
end

"""
    _with_basis(model, basis) -> AbstractHTC

The same correlation as `model`, reading its coolant properties at `basis` rather than at its
own: at the bulk temperature for [`AtBulk`](@ref), at the film for [`AtFilm`](@ref). A model
with no property basis, such as a user-defined one or `nothing`, comes back as it is.
"""
_with_basis(m::FromNusselt, basis) = FromNusselt(m.nusselt, basis)
_with_basis(m::Elenbaas, basis) = Elenbaas(m.g, basis)
_with_basis(m, basis) = m

"""
    RegimeDependent(; laminar, turbulent, natural=nothing, re_bounds=(2000.0, 5000.0),
                       g=G_EARTH) <: AbstractHTC

A heat transfer coefficient that picks its correlation by flow regime.

It uses `laminar` at low Reynolds number, `turbulent` at high, a linear blend of the two
across `re_bounds`, and `natural` convection wherever buoyancy outweighs the forced flow.

Two Reynolds numbers are involved, for different questions. Whether the flow is laminar or
turbulent is a property of the flow as a whole, so the blend reads the Reynolds number at the
bulk temperature. Whether natural convection takes over is decided by `Gr/Re² > 1`, tested
as `Gr > Re²` so that it holds at zero flow too: buoyancy acts in the film next to the wall,
and the comparison only sets like against like when Gr and Re are both read there, at the
film temperature, with the duct's hydraulic diameter as the length.

Each branch reads its coolant properties at one fixed temperature, whatever basis its model
was built with: laminar and natural convection at the bulk, turbulent at the film. A model
with no property basis of its own is used as given.

# Arguments
- `laminar`, `turbulent`: the two forced-convection models
- `natural`: optional natural-convection model
- `re_bounds`: `(re_lo, re_hi)` transition band on the bulk Reynolds number
- `g`: gravitational acceleration [m/s²], used only when `natural` is given

# Examples
It prints each branch with the temperature its properties are read at:
```jldoctest
julia> HTC.RegimeDependent(; laminar=HTC.ConstantNusselt(), turbulent=HTC.DittusBoelter())
HTC.RegimeDependent, blending across Re = 2000.0 to 5000.0
  laminar:   constant Nu = 8.235, at the bulk temperature
  turbulent: dittus_boelter, at the film temperature
```
"""
struct RegimeDependent{L<:AbstractHTC,T<:AbstractHTC,N} <: AbstractHTC
    laminar::L
    turbulent::T
    natural::N
    re_bounds::Tuple{Float64,Float64}
    g::Float64
end

function RegimeDependent(;
    laminar::AbstractHTC,
    turbulent::AbstractHTC,
    natural::Union{AbstractHTC,Nothing}=nothing,
    re_bounds=(2000.0, 5000.0),
    g=G_EARTH,
)
    bounds = (Float64(re_bounds[1]), Float64(re_bounds[2]))
    return RegimeDependent(
        _with_basis(laminar, AtBulk()), _with_basis(turbulent, AtFilm()),
        _with_basis(natural, AtBulk()), bounds, Float64(g),
    )
end

function (htc::RegimeDependent)(T_wall, T_bulk, ṁ, liquid, duct)
    h_forced = flow_regime_blend(
        Re(liquid, T_bulk, ṁ, duct), htc.re_bounds,
        htc.laminar(T_wall, T_bulk, ṁ, liquid, duct),
        htc.turbulent(T_wall, T_bulk, ṁ, liquid, duct),
    )
    htc.natural === nothing && return h_forced
    T_film = film_temperature(T_wall, T_bulk)
    Gr_film = Gr(ρ(liquid, T_film), μ(liquid, T_film), β(liquid, T_film),
                 T_wall, T_bulk, hydraulic_diameter(duct), htc.g)
    return ifelse(
        # Not Gr / Re² > 1, which divides by zero when the flow stops.
        Gr_film > Re(liquid, T_film, ṁ, duct)^2,
        htc.natural(T_wall, T_bulk, ṁ, liquid, duct),
        h_forced,
    )
end

"""
    Maximal(models...) <: AbstractHTC

The largest `h` of several models, for a wall cooled by whichever mechanism happens to win.

# Examples
Forced convection or natural convection, whichever is larger:
```jldoctest
julia> HTC.Maximal(HTC.DittusBoelter(), HTC.Elenbaas())
the largest of dittus_boelter, at the film temperature; Elenbaas natural convection, at the film temperature
```
"""
struct Maximal{T<:Tuple} <: AbstractHTC
    models::T
end

Maximal(models::AbstractHTC...) = Maximal(models)

function (htc::Maximal)(T_wall, T_bulk, ṁ, liquid, duct)
    return reduce(max, (m(T_wall, T_bulk, ṁ, liquid, duct) for m in htc.models))
end

"""
    SubcooledBoiling(single_phase, q_scb) <: AbstractHTC

Partial subcooled boiling layered on top of a single-phase model: `single_phase` below the
onset of nucleate boiling, and that value scaled by the Bergles-Rohsenow partial boiling
factor at or above it.

Needs the local pressure, which the channel supplies, so this model is called with the
extra-argument form `(T_wall, T_bulk, ṁ, liquid, duct, P)`.

# Arguments
- `single_phase`: the underlying [`AbstractHTC`](@ref)
- `q_scb`: subcooled boiling heat flux closure `(T_wall, sat, Re) -> q`, e.g. from
  [`regime_dependent_q_scb`](@ref). `sat` is the coolant's [`Liquid`](@ref) snapshot at
  saturation at the local pressure, and `Re` the bulk Reynolds number.

# Examples
```jldoctest
julia> spl = HTC.RegimeDependent(; laminar=HTC.ConstantNusselt(), turbulent=HTC.DittusBoelter());

julia> scb = HTC.SubcooledBoiling(spl, HTC.regime_dependent_q_scb())
HTC.SubcooledBoiling, partial boiling above the onset of nucleate boiling, on
  HTC.RegimeDependent, blending across Re = 2000.0 to 5000.0
    laminar:   constant Nu = 8.235, at the bulk temperature
    turbulent: dittus_boelter, at the film temperature

julia> print(scb)   # the one-line form, as inside another model's printout
subcooled boiling on HTC.RegimeDependent(constant Nu = 8.235, at the bulk temperature | dittus_boelter, at the film temperature)
```
"""
struct SubcooledBoiling{H<:AbstractHTC,Q} <: AbstractHTC
    single_phase::H
    q_scb::Q
end

# Without a pressure there is nothing to boil against, so this degenerates to single phase.
function (htc::SubcooledBoiling)(T_wall, T_bulk, ṁ, liquid, duct)
    return htc.single_phase(T_wall, T_bulk, ṁ, liquid, duct)
end

function (htc::SubcooledBoiling)(T_wall, T_bulk, ṁ, liquid, duct, P)
    h_spl = htc.single_phase(T_wall, T_bulk, ṁ, liquid, duct)
    return _scb_corrected(h_spl, htc.q_scb, T_wall, T_bulk, ṁ, liquid, duct, P)
end

# Models that do not care about pressure ignore the extra argument, so a channel can always
# pass it and let the model decide.
(htc::AbstractHTC)(T_wall, T_bulk, ṁ, liquid, duct, P) = htc(T_wall, T_bulk, ṁ, liquid, duct)

# #### Printing

_basis_words(::AtFilm) = "at the film temperature"
_basis_words(::AtBulk) = "at the bulk temperature"

# A named function prints as its name; a closure or a callable struct as itself, if it says
# more than its type.
function _correlation_name(f)
    f isa Function || return sprint(show, f)
    name = string(nameof(f))
    return startswith(name, "#") ? "a correlation" : name
end

Base.show(io::IO, m::FromFunction) = print(io, "HTC.FromFunction(", _correlation_name(m.f), ")")
Base.show(io::IO, m::FromNusselt) =
    print(io, _correlation_name(m.nusselt), ", ", _basis_words(m.basis))
Base.show(io::IO, m::Elenbaas) =
    print(io, "Elenbaas natural convection, ", _basis_words(m.basis))
Base.show(io::IO, m::Maximal) = print(io, "the largest of ", join(m.models, "; "))
Base.show(io::IO, m::RegimeDependent) =
    print(io, "HTC.RegimeDependent(", m.laminar, " | ", m.turbulent,
          m.natural === nothing ? "" : " | $(m.natural)", ")")
Base.show(io::IO, m::SubcooledBoiling) = print(io, "subcooled boiling on ", m.single_phase)

function Base.show(io::IO, ::MIME"text/plain", m::RegimeDependent)
    lo, hi = m.re_bounds
    print(io, "HTC.RegimeDependent, blending across Re = ", lo, " to ", hi)
    print(io, "\n  laminar:   ", m.laminar)
    print(io, "\n  turbulent: ", m.turbulent)
    m.natural === nothing || print(io, "\n  natural:   ", m.natural, ", where Gr > Re²")
end

function Base.show(io::IO, ::MIME"text/plain", m::SubcooledBoiling)
    print(io, "HTC.SubcooledBoiling, partial boiling above the onset of nucleate boiling, on")
    inner = sprint(show, MIME("text/plain"), m.single_phase)
    print(io, "\n  ", replace(inner, "\n" => "\n  "))
end

Base.show(io::IO, ::MIME"text/plain", m::FromNusselt) =
    print(io, "HTC.FromNusselt(", _correlation_name(m.nusselt), "), ", _basis_words(m.basis))
