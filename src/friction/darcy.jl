# darcy.jl -- the wall friction factor a channel or a resistor is handed.
#
# A `AbstractDarcyFactor` answers one question:
#
#     darcy(T_bulk, T_wall, ṁ, liquid, pipe) -> f  [dimensionless]
#
# The wall temperature and the pipe are in the signature for a reason. A friction factor
# read purely off the Reynolds number cannot express the two corrections a heated channel
# needs: `k_R`, the geometric correction on the Reynolds fed to each branch, and `k_H`, the
# viscosity correction, which compares the viscosity at the wall against the one in the bulk
# and needs the heated and wet perimeters to weight it. That is the same reason
# [`HTC`](@ref) hands over an `h` rather than a Nusselt number.
#
# The correlations themselves stay in friction.jl, taking a Reynolds number and nothing
# else. [`FromReynolds`](@ref) is the lift from one to the other.

"""
    AbstractDarcyFactor

A wall friction model. Subtypes are callable as

    darcy(T_bulk, T_wall, ṁ, liquid, pipe) -> f

with temperatures in °C, `ṁ` in kg/s, `liquid` an [`AbstractLiquid`](@ref) and `pipe` a
[`PipeGeometry`](@ref). The Reynolds number is formed internally at the bulk temperature.

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

Lift a callable `f(T_bulk, T_wall, ṁ, liquid, pipe) -> f_darcy` into a [`AbstractDarcyFactor`](@ref),
for a correlation not worth its own type.
"""
struct FromFunction{F} <: AbstractDarcyFactor
    f::F
end

(d::FromFunction)(T_bulk, T_wall, ṁ, liquid, pipe) = d.f(T_bulk, T_wall, ṁ, liquid, pipe)

"""
    FromReynolds(correlation; k_R=1.0) <: AbstractDarcyFactor

Close a Reynolds-only friction correlation into a [`AbstractDarcyFactor`](@ref). The Reynolds number
is taken at the bulk temperature and scaled by `k_R` before it reaches the correlation, which
is how Python STREAM applies its geometric correction.

# Arguments
- `correlation`: the correlation to close, called as `(Re) -> f`
- `k_R`: geometric correction on the Reynolds number, default 1.0 (a circular duct)
"""
struct FromReynolds{C} <: AbstractDarcyFactor
    correlation::C
    k_R::Float64
end

FromReynolds(correlation; k_R=1.0) = FromReynolds(correlation, Float64(k_R))

function (d::FromReynolds)(T_bulk, T_wall, ṁ, liquid, pipe)
    return d.correlation(Re(liquid, T_bulk, ṁ, pipe.A, pipe.Dh) * d.k_R)
end

"""
    Blasius(; k_R=1.0) -> FromReynolds

Blasius turbulent smooth-pipe friction, `f = 0.3164·Re^(-0.25)`.
"""
Blasius(; k_R=1.0) = FromReynolds(blasius, k_R)

"""
    Laminar(; k_R=1.0) -> FromReynolds

Hagen-Poiseuille laminar friction, `f = 64/Re`. Goes to infinity at no flow, which is correct
for the factor but not something a solver can integrate through. Use
[`RegimeDependent`](@ref) for flow that reverses.
"""
Laminar(; k_R=1.0) = FromReynolds(laminar, k_R)

"""
    Turbulent(; epsilon=0.0, k_R=1.0) -> FromReynolds

Colebrook-White turbulent friction at relative roughness `epsilon`.
"""
function Turbulent(; epsilon=0.0, k_R=1.0)
    return FromReynolds(Re -> turbulent(Re, epsilon), k_R)
end

"""
    RectangularLaminar(geom) -> FromReynolds

Laminar friction in a rectangular duct, `f = 64/(Re·k_R)`, with `k_R` from the duct's aspect
ratio. Equivalent to `Laminar(; k_R=rectangular_correction(geom.depth/geom.width))`.
"""
function RectangularLaminar(geom::PipeGeometry)
    return FromReynolds(rectangular_laminar(geom), 1.0)
end

"""
    RegimeDependent(; laminar=laminar, turbulent=turbulent,
                            re_bounds=(2000.0, 5000.0), k_R=1.0,
                            viscosity=nothing) <: AbstractDarcyFactor

Switch between a laminar and a turbulent friction branch on the bulk Reynolds number, the way
Python STREAM's `regime_dependent_friction` does: laminar at or below `re_bounds[1]`,
turbulent above `re_bounds[2]`, and a linear blend in between via
[`flow_regime_blend`](@ref).

Two things make this the model to reach for when the flow reverses. It guards the no-flow
point, where the bare `64/Re` would otherwise be infinite, and the blend keeps the factor
continuous across the transition so a stiff solver does not read a kink there and reject the
step.

Given a `viscosity` correction, the result is multiplied by
`viscosity(heated_perimeter/wet_perimeter, μ(T_wall)/μ(T_bulk))`. Pass
[`viscosity_correction`](@ref) to get the standard one. The default is `nothing`, matching
Python's `k_H=None`, so the correction is opt-in and no existing result moves.

# Arguments
- `laminar`, `turbulent`: the two branch correlations, each called as `(Re) -> f`
- `re_bounds`: `(re_lo, re_hi)` transition band on the bulk Reynolds number
- `k_R`: geometric correction on the Reynolds fed to each branch
- `viscosity`: optional `(heat_wet_ratio, mu_ratio) -> K_H`
"""
struct RegimeDependent{L,T,V} <: AbstractDarcyFactor
    laminar::L
    turbulent::T
    re_bounds::Tuple{Float64,Float64}
    k_R::Float64
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
    return RegimeDependent(laminar, turbulent, bounds, Float64(k_R), viscosity)
end

function (d::RegimeDependent)(T_bulk, T_wall, ṁ, liquid, pipe)
    Re_bulk = Re(liquid, T_bulk, ṁ, pipe.A, pipe.Dh)
    ReK = Re_bulk * d.k_R
    # Feed the laminar branch a finite Reynolds at no-flow so the bare 64/Re never forms an
    # Inf while the not-taken branch is traced. For every Re > 0 this is just ReK.
    ReK_lam = Base.ifelse(Re_bulk <= 0, one(ReK), ReK)
    f = flow_regime_blend(Re_bulk, d.re_bounds, d.laminar(ReK_lam), d.turbulent(ReK))
    f = Base.ifelse(Re_bulk <= 0, zero(f), f)
    d.viscosity === nothing && return f
    mu_ratio = μ(liquid, T_wall) / μ(liquid, T_bulk)
    return f * d.viscosity(pipe.heated_perimeter / pipe.wet_perimeter, mu_ratio)
end

# A model that does not read the wall temperature can be handed the bulk in its place, which
# is what a channel with no wall of its own does.
(d::AbstractDarcyFactor)(T_bulk, ṁ, liquid, pipe) = d(T_bulk, T_bulk, ṁ, liquid, pipe)
