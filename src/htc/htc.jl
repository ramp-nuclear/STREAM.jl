"""
    AbstractHTC

A wall heat transfer coefficient model. Subtypes are callable as

    htc(T_wall, T_bulk, ṁ, Dh, A, liquid) -> h [W/(m²·K)]
    htc(T_wall, T_bulk, ṁ, Dh, A, liquid, P, g) -> h [W/(m²·K)]

with temperatures in °C, `ṁ` in kg/s, `Dh` and `A` the channel's hydraulic diameter and flow
area, and `liquid` an [`AbstractLiquid`](@ref). A channel uses the second form, adding the
local static pressure `P` [Pa] and its gravity `g` [m/s²], positive when positive flow climbs
against gravity. A model that needs neither defines only the first form and the second falls
back to it. [`SubcooledBoiling`](@ref) reads `P`, and [`Elenbaas`](@ref) and
[`RegimeDependent`](@ref) read `g`.

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

# Examples
A named function prints as its name, and an anonymous one as "a correlation":
```jldoctest
julia> HTC.FromFunction((T_wall, T_bulk, ṁ, Dh, A, liquid) -> 5000.0)
HTC.FromFunction(a correlation)
```
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
    Elenbaas(geom; basis=AtFilm()) <: AbstractHTC

Elenbaas natural convection between symmetrically heated parallel vertical plates.

The plate gap `S = geom.depth` is the length scale throughout: Ra is taken on `S` and
`h = Nu·κ/S`. Gravity comes with the call, from the channel, and only its size is used, so
it is called as `(T_wall, T_bulk, ṁ, Dh, A, liquid, P, g)`. Called without `g` it throws.
[`RegimeDependent`](@ref) reads a natural branch at the bulk instead of the film.

# Arguments
- `geom`: channel geometry; `geom.depth` is the gap and `geom.L` the heated length
- `basis`: where the coolant properties are read, [`AtFilm`](@ref) (default) or [`AtBulk`](@ref)

# Returns
An `Elenbaas` model, callable like any [`AbstractHTC`](@ref).
"""
struct Elenbaas{B<:PropertyBasis} <: AbstractHTC
    gap::Float64
    heated_length::Float64
    basis::B
end

Elenbaas(geom::PipeGeometry; basis::PropertyBasis=AtFilm()) = Elenbaas(geom.depth, geom.L, basis)

function (htc::Elenbaas)(T_wall, T_bulk, ṁ, Dh, A, liquid)
    throw(ArgumentError("Elenbaas needs gravity: call it as (T_wall, T_bulk, ṁ, Dh, A, " *
                        "liquid, P, g), as a channel does"))
end

function (htc::Elenbaas)(T_wall, T_bulk, ṁ, Dh, A, liquid, P, g)
    T_prop = property_temperature(htc.basis, T_wall, T_bulk)
    Gr_val = Gr(ρ(liquid, T_prop), μ(liquid, T_prop), β(liquid, T_prop),
                T_wall, T_bulk, htc.gap, abs(g))
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
_with_basis(m::Elenbaas, basis) = Elenbaas(m.gap, m.heated_length, basis)
_with_basis(m, basis) = m

@doc raw"""
    RegimeDependent(; laminar, turbulent, natural=nothing, re_bounds=(2000.0, 5000.0),
                       geom, gz_band=(0.01, 0.1)) <: AbstractHTC

A heat transfer coefficient that picks its forced-convection correlation by flow regime and
adds buoyancy to it.

The forced value ``h_f`` is `laminar` at low Reynolds number, `turbulent` at high, and a
linear blend of the two across `re_bounds` on the bulk Reynolds number. A `natural` model's
value ``h_n`` combines with it by Churchill's rule [Churchill1977](@cite):

```math
h = (h_f^3 + h_n^3)^{1/3} \; \text{(aiding)}, \qquad h = \max((h_f^3 - h_n^3)^{1/3}, h_n) \; \text{(opposing)}
```

Buoyancy aids the flow when it pushes the same way, as in heated upflow, and opposes it
otherwise. The direction comes from the sign of `g`, so a model with a `natural` branch is
called as `(T_wall, T_bulk, ṁ, Dh, A, liquid, P, g)`, which is how a channel calls it.
Called without `g` it throws. As the through-flow dies, ``h`` hands over to ``h_n`` along a
smooth step in the Graetz number ``Gz = Re \, Pr \, D_h / L`` across `gz_band`.
[Mixed convection](@ref) explains each of these choices.

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

# Examples
It prints each branch with the temperature its properties are read at:
```jldoctest
julia> geom = PipeGeometry_rectangular(0.6, 0.067, 0.0024, 0.063);

julia> HTC.RegimeDependent(; laminar=HTC.ConstantNusselt(), turbulent=HTC.DittusBoelter(), geom)
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
    heated_length::Float64
    gz_band::Tuple{Float64,Float64}
end

function RegimeDependent(;
    laminar::AbstractHTC,
    turbulent::AbstractHTC,
    natural::Union{AbstractHTC,Nothing}=nothing,
    re_bounds=(2000.0, 5000.0),
    geom::PipeGeometry,
    gz_band=(0.01, 0.1),
)
    return RegimeDependent(
        _with_basis(laminar, AtBulk()), _with_basis(turbulent, AtFilm()),
        _with_basis(natural, AtBulk()), re_bounds, geom.L, gz_band,
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

"""
    _forced(htc::RegimeDependent, Re_bulk, args...) -> h

The forced-convection value: `laminar` and `turbulent`, each called with `args`, blended
across `re_bounds` on `Re_bulk`.
"""
function _forced(htc::RegimeDependent, Re_bulk, args...)
    return flow_regime_blend(Re_bulk, htc.re_bounds, htc.laminar(args...), htc.turbulent(args...))
end

function (htc::RegimeDependent)(T_wall, T_bulk, ṁ, Dh, A, liquid)
    htc.natural === nothing || throw(ArgumentError(
        "a RegimeDependent with a natural branch needs gravity for the direction of " *
        "buoyancy: call it as (T_wall, T_bulk, ṁ, Dh, A, liquid, P, g), as a channel does"))
    return _forced(htc, Re(liquid, T_bulk, ṁ, A, Dh), T_wall, T_bulk, ṁ, Dh, A, liquid)
end

function (htc::RegimeDependent)(T_wall, T_bulk, ṁ, Dh, A, liquid, P, g)
    Re_bulk = Re(liquid, T_bulk, ṁ, A, Dh)
    h_forced = _forced(htc, Re_bulk, T_wall, T_bulk, ṁ, Dh, A, liquid, P, g)
    htc.natural === nothing && return h_forced
    h_nat = htc.natural(T_wall, T_bulk, ṁ, Dh, A, liquid, P, g)
    aiding = (h_forced^3 + h_nat^3)^(1 / 3)
    opposing = max(max(h_forced^3 - h_nat^3, zero(h_nat))^(1 / 3), h_nat)
    # A wall hotter than the bulk pushes the fluid beside it up, and a positive g means
    # positive flow runs up.
    opposed = sign(g) * ṁ * (T_wall - T_bulk) < 0
    h_mixed = ifelse(opposed, opposing, aiding)
    Gz = Re_bulk * Pr(liquid, T_bulk) * Dh / htc.heated_length
    # The flip between aiding and opposing happens at ṁ = 0, where Gz = 0 and the weight is
    # already zero, so h has no jump there.
    w = _smooth_step(log10(Gz), log10(htc.gz_band[1]), log10(htc.gz_band[2]))
    return w * h_mixed + (1 - w) * h_nat
end

"""
    Maximal(models...) <: AbstractHTC

The largest `h` of several models, for a wall cooled by whichever mechanism happens to win.

# Examples
Forced convection or natural convection in a 2.4 mm gap, whichever is larger:
```jldoctest
julia> geom = PipeGeometry_rectangular(0.6, 0.067, 0.0024, 0.063);

julia> HTC.Maximal(HTC.DittusBoelter(), HTC.Elenbaas(geom))
the largest of dittus_boelter, at the film temperature; Elenbaas natural convection, gap 2.4 mm, at the film temperature
```
"""
struct Maximal{T<:Tuple} <: AbstractHTC
    models::T
end

Maximal(models::AbstractHTC...) = Maximal(models)

function (htc::Maximal)(T_wall, T_bulk, ṁ, Dh, A, liquid)
    return reduce(max, (m(T_wall, T_bulk, ṁ, Dh, A, liquid) for m in htc.models))
end

function (htc::Maximal)(T_wall, T_bulk, ṁ, Dh, A, liquid, P, g)
    return reduce(max, (m(T_wall, T_bulk, ṁ, Dh, A, liquid, P, g) for m in htc.models))
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
- `q_scb`: subcooled boiling heat flux closure `(T_wall, sat, Re) -> q`, e.g. from
  [`regime_dependent_q_scb`](@ref). `sat` is the coolant's [`Liquid`](@ref) snapshot at
  saturation at the local pressure, and `Re` the bulk Reynolds number.

# Examples
```jldoctest
julia> geom = PipeGeometry_rectangular(0.6, 0.067, 0.0024, 0.063);

julia> spl = HTC.RegimeDependent(; laminar=HTC.ConstantNusselt(), turbulent=HTC.DittusBoelter(), geom);

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
function (htc::SubcooledBoiling)(T_wall, T_bulk, ṁ, Dh, A, liquid)
    return htc.single_phase(T_wall, T_bulk, ṁ, Dh, A, liquid)
end

function (htc::SubcooledBoiling)(T_wall, T_bulk, ṁ, Dh, A, liquid, P)
    h_spl = htc.single_phase(T_wall, T_bulk, ṁ, Dh, A, liquid)
    return _scb_corrected(h_spl, htc.q_scb, T_wall, T_bulk, ṁ, Dh, A, liquid, P)
end

function (htc::SubcooledBoiling)(T_wall, T_bulk, ṁ, Dh, A, liquid, P, g)
    h_spl = htc.single_phase(T_wall, T_bulk, ṁ, Dh, A, liquid, P, g)
    return _scb_corrected(h_spl, htc.q_scb, T_wall, T_bulk, ṁ, Dh, A, liquid, P)
end

# Models that do not care about pressure or gravity ignore the extra arguments, so a channel
# can always pass them and let the model decide.
(htc::AbstractHTC)(T_wall, T_bulk, ṁ, Dh, A, liquid, P) = htc(T_wall, T_bulk, ṁ, Dh, A, liquid)
(htc::AbstractHTC)(T_wall, T_bulk, ṁ, Dh, A, liquid, P, g) =
    htc(T_wall, T_bulk, ṁ, Dh, A, liquid, P)

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
    print(io, "Elenbaas natural convection, gap ", round(1e3 * m.gap; sigdigits=4), " mm, ",
          _basis_words(m.basis))
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
    m.natural === nothing ||
        print(io, "\n  natural:   ", m.natural, ", combined by Churchill's rule")
end

function Base.show(io::IO, ::MIME"text/plain", m::SubcooledBoiling)
    print(io, "HTC.SubcooledBoiling, partial boiling above the onset of nucleate boiling, on")
    inner = sprint(show, MIME("text/plain"), m.single_phase)
    print(io, "\n  ", replace(inner, "\n" => "\n  "))
end

Base.show(io::IO, ::MIME"text/plain", m::FromNusselt) =
    print(io, "HTC.FromNusselt(", _correlation_name(m.nusselt), "), ", _basis_words(m.basis))
