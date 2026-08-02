# darcy.jl -- the wall friction factor a channel or a resistor is handed.
#
# A `DarcyFactor` answers one question:
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
# else. [`ReynoldsFactor`](@ref) is the lift from one to the other.

"""
    DarcyFactor

A wall friction model. Subtypes are callable as

    darcy(T_bulk, T_wall, ṁ, liquid, pipe) -> f

with temperatures in °C, `ṁ` in kg/s, `liquid` an [`AbstractLiquid`](@ref) and `pipe` a
[`PipeGeometry`](@ref). The Reynolds number is formed internally at the bulk temperature.

Shipped models: [`ReynoldsFactor`](@ref) and the named correlations built on it
([`BlasiusFriction`](@ref), [`LaminarFriction`](@ref), [`TurbulentFriction`](@ref),
[`RectangularLaminarFriction`](@ref)), and [`RegimeDependentFriction`](@ref) to switch
between a laminar and a turbulent branch.

To add your own, either subtype this and define the call, or wrap a closure in
[`FunctionDarcy`](@ref).
"""
abstract type DarcyFactor end

"""
    FunctionDarcy(f) <: DarcyFactor

Lift a callable `f(T_bulk, T_wall, ṁ, liquid, pipe) -> f_darcy` into a [`DarcyFactor`](@ref),
for a correlation not worth its own type.
"""
struct FunctionDarcy{F} <: DarcyFactor
    f::F
end

(d::FunctionDarcy)(T_bulk, T_wall, ṁ, liquid, pipe) = d.f(T_bulk, T_wall, ṁ, liquid, pipe)

"""
    ReynoldsFactor(correlation; k_R=1.0) <: DarcyFactor

Close a Reynolds-only friction correlation into a [`DarcyFactor`](@ref). The Reynolds number
is taken at the bulk temperature and scaled by `k_R` before it reaches the correlation, which
is how Python STREAM applies its geometric correction.

# Arguments
- `correlation`: the correlation to close, called as `(Re) -> f`
- `k_R`: geometric correction on the Reynolds number, default 1.0 (a circular duct)
"""
struct ReynoldsFactor{C} <: DarcyFactor
    correlation::C
    k_R::Float64
end

ReynoldsFactor(correlation; k_R=1.0) = ReynoldsFactor(correlation, Float64(k_R))

function (d::ReynoldsFactor)(T_bulk, T_wall, ṁ, liquid, pipe)
    return d.correlation(Re(liquid, T_bulk, ṁ, pipe.A, pipe.Dh) * d.k_R)
end

"""
    BlasiusFriction(; k_R=1.0) -> ReynoldsFactor

Blasius turbulent smooth-pipe friction, `f = 0.3164·Re^(-0.25)`.
"""
BlasiusFriction(; k_R=1.0) = ReynoldsFactor(blasius_friction, k_R)

"""
    LaminarFriction(; k_R=1.0) -> ReynoldsFactor

Hagen-Poiseuille laminar friction, `f = 64/Re`. Goes to infinity at no flow, which is correct
for the factor but not something a solver can integrate through. Use
[`RegimeDependentFriction`](@ref) for flow that reverses.
"""
LaminarFriction(; k_R=1.0) = ReynoldsFactor(laminar_friction, k_R)

"""
    TurbulentFriction(; epsilon=0.0, k_R=1.0) -> ReynoldsFactor

Colebrook-White turbulent friction at relative roughness `epsilon`.
"""
function TurbulentFriction(; epsilon=0.0, k_R=1.0)
    return ReynoldsFactor(Re -> turbulent_friction(Re, epsilon), k_R)
end

"""
    RectangularLaminarFriction(geom) -> ReynoldsFactor

Laminar friction in a rectangular duct, `f = 64/(Re·k_R)`, with `k_R` from the duct's aspect
ratio. Equivalent to `LaminarFriction(; k_R=rectangular_laminar_correction(geom.depth/geom.width))`.
"""
function RectangularLaminarFriction(geom::PipeGeometry)
    return ReynoldsFactor(laminar_friction_rectangular(geom), 1.0)
end

"""
    RegimeDependentFriction(; laminar=laminar_friction, turbulent=turbulent_friction,
                            re_bounds=(2000.0, 5000.0), k_R=1.0,
                            viscosity=nothing) <: DarcyFactor

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
struct RegimeDependentFriction{L,T,V} <: DarcyFactor
    laminar::L
    turbulent::T
    re_bounds::Tuple{Float64,Float64}
    k_R::Float64
    viscosity::V
end

function RegimeDependentFriction(;
    laminar=laminar_friction,
    turbulent=turbulent_friction,
    re_bounds=(2000.0, 5000.0),
    k_R=1.0,
    viscosity=nothing,
)
    bounds = (Float64(re_bounds[1]), Float64(re_bounds[2]))
    return RegimeDependentFriction(laminar, turbulent, bounds, Float64(k_R), viscosity)
end

function (d::RegimeDependentFriction)(T_bulk, T_wall, ṁ, liquid, pipe)
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
(d::DarcyFactor)(T_bulk, ṁ, liquid, pipe) = d(T_bulk, T_bulk, ṁ, liquid, pipe)
