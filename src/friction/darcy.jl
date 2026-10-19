"""
    AbstractDarcyFactor

A wall friction model. Subtypes are callable as

    darcy(T_wall, T_bulk, ṁ, liquid, duct) -> f

with temperatures in °C, `ṁ` in kg/s, `liquid` an [`AbstractLiquid`](@ref) and `duct` a
[`Duct`](@ref), the same arguments an [`AbstractHTC`](@ref) takes. The Reynolds number is
formed internally at the bulk temperature. A model that ignores the wall can also be called as
`darcy(T_bulk, ṁ, liquid, duct)`.

Shipped models: [`FromReynolds`](@ref) and the named correlations built on it
([`Blasius`](@ref), [`Laminar`](@ref), [`Turbulent`](@ref),
[`RectangularLaminar`](@ref)), and [`RegimeDependent`](@ref) to switch
between a laminar and a turbulent branch.

To add your own, either subtype this and define the call, or wrap a closure in
[`FromFunction`](@ref).
"""
abstract type AbstractDarcyFactor end

"""
    FromFunction(f) <: AbstractDarcyFactor

Lift a callable `f(T_wall, T_bulk, ṁ, liquid, duct) -> f_darcy` into a [`AbstractDarcyFactor`](@ref),
for a correlation not worth its own type.

# Examples
A named function prints as its name, and an anonymous one as "a correlation":
```jldoctest
julia> Friction.FromFunction((T_wall, T_bulk, ṁ, liquid, duct) -> 0.02)
Friction.FromFunction(a correlation)
```
"""
struct FromFunction{F} <: AbstractDarcyFactor
    f::F
end

(d::FromFunction)(T_wall, T_bulk, ṁ, liquid, duct) = d.f(T_wall, T_bulk, ṁ, liquid, duct)

"""
    FromReynolds(correlation; k_R=1.0) <: AbstractDarcyFactor

Close a Reynolds-only friction correlation into an [`AbstractDarcyFactor`](@ref). The Reynolds
number is taken at the bulk temperature and scaled by `k_R` before it reaches the correlation,
which is how Python STREAM applies its geometric correction.

# Arguments
- `correlation`: the correlation to close, called as `(Re) -> f`
- `k_R`: geometric correction on the Reynolds number: a number, or a function of the duct
  such as [`rectangular_correction`](@ref). Default 1.0, a circular duct.

# Examples
```jldoctest
julia> Friction.Blasius(; k_R=0.7)
Friction.FromReynolds(blasius), Re scaled by k_R = 0.7

julia> print(Friction.Blasius(; k_R=0.7))   # the one-line form, as inside another printout
blasius, Re scaled by k_R = 0.7
```
"""
struct FromReynolds{C,K} <: AbstractDarcyFactor
    correlation::C
    k_R::K
end

FromReynolds(correlation; k_R=1.0) = FromReynolds(correlation, _k_R(k_R))

function (d::FromReynolds)(T_wall, T_bulk, ṁ, liquid, duct)
    return d.correlation(Re(liquid, T_bulk, ṁ, duct) * _k_R(d.k_R, duct))
end

"""
    _k_R(k_R) -> k_R
    _k_R(k_R, duct) -> Real

A model's `k_R` as stored, a `Float64` or a function, and its value for one duct.
"""
_k_R(k::Real) = Float64(k)
_k_R(k) = k
_k_R(k::Real, duct) = k
_k_R(k, duct) = k(duct)

"""
    Blasius(; k_R=1.0) -> FromReynolds

Blasius turbulent smooth-pipe friction, `f = 0.3164·Re^(-0.25)`.
"""
Blasius(; k_R=1.0) = FromReynolds(blasius; k_R)

"""
    Laminar(; k_R=1.0) -> FromReynolds

Hagen-Poiseuille laminar friction, `f = 64/Re`. Goes to infinity at no flow, which is correct
for the factor but not something a solver can integrate through. Use
[`RegimeDependent`](@ref) for flow that reverses.
"""
Laminar(; k_R=1.0) = FromReynolds(laminar; k_R)

"""
    Turbulent(; epsilon=0.0, k_R=1.0) -> FromReynolds

Colebrook-White turbulent friction at relative roughness `epsilon`.
"""
function Turbulent(; epsilon=0.0, k_R=1.0)
    return FromReynolds(Re -> turbulent(Re, epsilon); k_R)
end

"""
    RectangularLaminar() -> FromReynolds

Laminar friction corrected for the duct's shape, `f = 64/(Re·k_R)` with `k_R` from
[`rectangular_correction`](@ref). A circular duct gets `64/Re`.
Equivalent to `Laminar(; k_R=rectangular_correction)`.
"""
RectangularLaminar() = FromReynolds(laminar, rectangular_correction)

"""
    RegimeDependent(; laminar=laminar, turbulent=turbulent,
                            re_bounds=(2000.0, 5000.0), k_R=1.0,
                            viscosity=nothing) <: AbstractDarcyFactor

Switch between a laminar and a turbulent friction branch on the bulk Reynolds number.

It is laminar at or below `re_bounds[1]`, turbulent above `re_bounds[2]`, and a linear blend
in between via [`flow_regime_blend`](@ref), as Python STREAM's `regime_dependent_friction`
does.

Two things make this the model to reach for when the flow reverses. It guards the no-flow
point, where the bare `64/Re` would otherwise be infinite, and the blend keeps the factor
continuous across the transition so a stiff solver does not read a kink there and reject the
step.

Given a `viscosity` correction, the result is multiplied by
`viscosity(heated_perimeter/wetted_perimeter, μ(T_wall)/μ(T_bulk))`. Pass
[`viscosity_correction`](@ref) to get the standard one. The default is `nothing`, matching
Python's `k_H=None`, so the correction is opt-in and no existing result moves.

# Arguments
- `laminar`, `turbulent`: the two branch correlations, each called as `(Re) -> f`
- `re_bounds`: `(re_lo, re_hi)` transition band on the bulk Reynolds number
- `k_R`: geometric correction on the Reynolds fed to each branch, a number or a function of
  the duct such as [`rectangular_correction`](@ref)
- `viscosity`: optional `(heat_wet_ratio, mu_ratio) -> K_H`

# Examples
Corrected for the duct's aspect ratio and for a heated wall:
```jldoctest
julia> Friction.RegimeDependent(; k_R=Friction.rectangular_correction,
                                  viscosity=Friction.viscosity_correction)
Friction.RegimeDependent(laminar | turbulent, blending across Re = 2000.0 to 5000.0, k_R from rectangular_correction, with the heated-wall viscosity correction)
```
"""
struct RegimeDependent{L,T,K,V} <: AbstractDarcyFactor
    laminar::L
    turbulent::T
    re_bounds::Tuple{Float64,Float64}
    k_R::K
    viscosity::V
end

function RegimeDependent(;
    laminar=laminar,
    turbulent=turbulent,
    re_bounds=(2000.0, 5000.0),
    k_R=1.0,
    viscosity=nothing,
)
    bounds = (Float64(re_bounds[1]), Float64(re_bounds[2]))
    return RegimeDependent(laminar, turbulent, bounds, _k_R(k_R), viscosity)
end

function (d::RegimeDependent)(T_wall, T_bulk, ṁ, liquid, duct)
    Re_bulk = Re(liquid, T_bulk, ṁ, duct)
    ReK = Re_bulk * _k_R(d.k_R, duct)
    # Feed the laminar branch a finite Reynolds at no-flow so the bare 64/Re never forms an
    # Inf while the not-taken branch is traced. For every Re > 0 this is just ReK.
    ReK_lam = ifelse(Re_bulk <= 0, one(ReK), ReK)
    f = flow_regime_blend(Re_bulk, d.re_bounds, d.laminar(ReK_lam), d.turbulent(ReK))
    f = ifelse(Re_bulk <= 0, zero(f), f)
    d.viscosity === nothing && return f
    mu_ratio = μ(liquid, T_wall) / μ(liquid, T_bulk)
    return f * d.viscosity(heated_perimeter(duct) / wetted_perimeter(duct), mu_ratio)
end

# A model that does not read the wall temperature can be handed the bulk in its place, which
# is what a component with no wall of its own does.
(d::AbstractDarcyFactor)(T_bulk, ṁ, liquid, duct) = d(T_bulk, T_bulk, ṁ, liquid, duct)

# #### Printing

Base.show(io::IO, d::FromFunction) = print(io, "Friction.FromFunction(", _correlation_name(d.f), ")")
# How a model's k_R reads in its printout, and nothing for the uncorrected 1.
_k_R_words(k::Real) = k == 1 ? "" : "k_R = $(round(k; sigdigits=4))"
_k_R_words(k) = "k_R from $(_correlation_name(k))"

function Base.show(io::IO, d::FromReynolds)
    print(io, _correlation_name(d.correlation))
    k = _k_R_words(d.k_R)
    isempty(k) || print(io, ", Re scaled by ", k)
end

function Base.show(io::IO, d::RegimeDependent)
    lo, hi = d.re_bounds
    print(io, "Friction.RegimeDependent(", _correlation_name(d.laminar), " | ",
          _correlation_name(d.turbulent), ", blending across Re = ", lo, " to ", hi)
    k = _k_R_words(d.k_R)
    isempty(k) || print(io, ", ", k)
    d.viscosity === nothing || print(io, ", with the heated-wall viscosity correction")
    print(io, ")")
end

function Base.show(io::IO, ::MIME"text/plain", d::FromReynolds)
    print(io, "Friction.FromReynolds(", _correlation_name(d.correlation), ")")
    k = _k_R_words(d.k_R)
    isempty(k) || print(io, ", Re scaled by ", k)
end
