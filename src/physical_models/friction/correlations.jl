# friction/correlations.jl -- Friction factor correlation functions
#
# Design:
#   - Standalone named functions (blasius_friction, turbulent_friction, viscosity_correction,
#     rectangular_laminar_correction): plain Julia arithmetic, NOT @register_symbolic.
#     MTK traces through these symbolically when Re is symbolic.
#   - Factory (laminar_friction_rectangular): returns closure capturing geom-derived state.
#   - No @register_symbolic on any function in this file — all are plain arithmetic.

"""
    blasius_friction(Re) -> f_darcy

Blasius friction factor correlation for turbulent smooth-pipe flow.
Returns Darcy friction factor f = 0.3164 * Re^(-0.25).

Valid for: 4,000 < Re < 100,000.
MTK-compatible: plain arithmetic on symbolic Re traces correctly.
"""
blasius_friction(Re) = 0.3164 * Re^(-0.25)

"""
    laminar_friction(Re) -> f_darcy

Hagen-Poiseuille analytic Darcy friction factor for fully-developed laminar flow in a
circular duct, `f = 64 / Re`. Mirrors Python STREAM `friction.py::laminar_friction`
(the `k_R = 1.0` case of the regime-dependent model), which is the same pure `64 / re`.

This is the bare factor, so it goes to `Inf` as `Re -> 0`. That is the correct factor:
the physical quantity is the pressure drop `f * mdot*|mdot| / (...)`, and with
`mdot*|mdot| ~ Re^2` the product `~ (64/Re) * Re^2 ~ Re` vanishes smoothly as the flow
stops (the Hagen-Poiseuille drop is linear in velocity). The no-flow case is handled by
the caller that forms that product. For flow that reverses through `Re = 0`, use
[`regime_dependent_friction`](@ref); it guards the no-flow point.

# Arguments
- `Re`: Reynolds number

# Returns
Darcy friction factor (dimensionless).
"""
laminar_friction(Re) = 64.0 / Re

"""
    rectangular_laminar_correction(aspect_ratio) -> K_R

Scalar geometric correction factor K_R from the KAERI formula for fully-developed
laminar flow in a rectangular duct.

`aspect_ratio = depth / width`, must be in [0, 1]:
- 0.0 (thin gap limit): K_R ≈ 0.66685
- 0.01814 (MTR geometry: 0.00127/0.07): K_R ≈ 0.68544
- 0.5: K_R ≈ 1.03639
- 1.0 (square): K_R ≈ 1.12462

Use: `f_darcy = 64 / (Re * K_R)` for rectangular laminar flow.

Source: KAERI formula as used in TERMIC thermal-hydraulics code;
matches Python STREAM friction.py `rectangular_laminar_correction`.
Reference: KAERI, "Development of Research Reactor Technology", Korea Atomic Energy
Research Institute, KAERI/RR-3818/2014, 2014.
"""
function rectangular_laminar_correction(aspect_ratio::Real)
    return (
        0.88919 +
        87.656 *
        ((1 + aspect_ratio * (sqrt(2) - 1)) / (4 * (1 + aspect_ratio)) - sqrt(2) / 8)^1.9
    )^(-1)
end

"""
    laminar_friction_rectangular(geom::PipeGeometry) -> (Re) -> f_darcy

Factory returning a friction correlation for fully-developed laminar flow in a
rectangular duct.

Internally derives `aspect_ratio = geom.depth / geom.width` from the
`PipeGeometry` descriptor (where `depth = min(edge1, edge2)` and
`width = max(edge1, edge2)` for rectangular geometry; both equal `D` for
circular). Precomputes the geometric correction factor
`K_R = rectangular_laminar_correction(aspect_ratio)` at construction time.

Returns a closure `(Re) -> 64.0 / (Re * K_R)`.

This is the rectangular companion to [`laminar_friction`]: the circular factor is `64/Re`,
this one is `64/(Re*K_R)`. Both are bare `64/Re`-style factors with no no-flow guard, which
is correct for a forced-flow channel where `Re > 0` always. The plain `64/(Re*K_R)` form
keeps the residual and Jacobian for a forced-flow steady solve identical to the pre-reversal
form, which a borderline forced-flow solve (two plates in hydraulic series) relies on to
converge. A loop whose flow reverses through `Re = 0` should use `regime_dependent_friction`
instead, which guards the no-flow point in its returned closure.

Note: For circular geometry constructed via `PipeGeometry_circular(L, D)`,
`depth == width == D` so `aspect_ratio == 1.0`. `rectangular_laminar_correction(1.0)`
≈ 1.1246, giving `f ≈ 56.9/Re` (NOT the strict circular `64/Re`). Callers who
want the strict circular `64/Re` should use a raw lambda `(Re) -> 64.0 / Re`
instead of this factory.

Usage:
```julia
geom = PipeGeometry_rectangular(L, e1, e2, he)
f_fn = laminar_friction_rectangular(geom)
ChannelAndContacts(friction_correlation = f_fn, ...)
```
"""
function laminar_friction_rectangular(geom::PipeGeometry)
    aspect_ratio = geom.depth / geom.width
    k_R = rectangular_laminar_correction(aspect_ratio)
    return (Re) -> 64.0 / (Re * k_R)
end

"""
    turbulent_friction(Re, epsilon=0) -> f_darcy

Colebrook-White approximation for turbulent Darcy friction factor, as written in RELAP and
in KAERI/RR-3818/2014 page 3 chapter 2.1.2 (full reference below). `epsilon` is relative
roughness (roughness height / Dh), defaults to smooth pipe.

Returns 0.0 when `Re < 10`: the correlation is only valid for turbulent flow, and below
that threshold the `log10` terms diverge. Python guards the same way with
`np.nan_to_num` (its docstring quotes "approx <7"); the `Re < 10` floor here is a touch
more conservative and matches the published `turbulent_friction(5.0) == 0.0` reference.

The guard is written with `Base.ifelse`, not a short-circuit `&&`, so the function
stays MTK-traceable. Every channel and resistor passes a symbolic `Num` Reynolds; a
Julia `if`/`&&` on `Re` raises `non-boolean (Num) used in boolean context`.
`Base.ifelse` emits a symbolic conditional the solver evaluates each timestep, so the
turbulent branch stays finite as `Re -> 0` across a flow reversal instead of letting
`log10` run to `-Inf`. `max(Re, 10)` inside the diverging terms keeps the log10
argument finite while the not-taken branch is traced, so no `Inf`/`NaN` leaks through
the `ifelse`.

# Arguments
- `Re`: Reynolds number
- `epsilon`: relative roughness (default 0)

# Returns
Darcy friction factor (dimensionless).

Known values: `turbulent_friction(4e3) == 0.039804935964641644`,
`turbulent_friction(1e6) == 0.011649393290640643`,
`turbulent_friction(4e3, 0.1) == 0.10560870441248855`,
`turbulent_friction(5.0) == 0.0`.

Reference: KAERI, "Development of Research Reactor Technology", Korea Atomic Energy
Research Institute, KAERI/RR-3818/2014, 2014.
"""
function turbulent_friction(Re, epsilon=0)
    # Clamp the Re feeding the log10 terms so they are evaluated at a turbulent Re even
    # while tracing the not-taken branch; the ifelse zeroes the result below Re 10.
    Re_safe = max(Re, 10)
    inlog = log10(epsilon + 21.25 / Re_safe^0.9)
    outlog = log10(epsilon / 3.7 + (2.51 / Re_safe) * (1.14 - 2 * inlog))
    f = (-2 * outlog)^(-2)
    return Base.ifelse(Re < 10, zero(f), f)
end

"""
    regime_dependent_friction(; re_bounds=(2000.0, 5000.0), k_R=1.0,
                              laminar=laminar_friction, turbulent=turbulent_friction) -> (Re) -> f_darcy

Flow-regime-dependent Darcy friction closure, the faithful port of Python STREAM
`friction.py::regime_dependent_friction` (the `friction_factor("regime_dependent", ...)`
factory). Returns a single closure `(Re) -> f` switching on the bulk Reynolds number:

- `Re < re_bounds[1]`        -> laminar `laminar(Re * k_R)`
- `Re > re_bounds[2]`        -> turbulent `turbulent(Re * k_R)`
- in between                 -> linear interpolation between the laminar value at
                               `re_bounds[1]` and the turbulent value at `re_bounds[2]`

The geometric correction `k_R` scales the Reynolds fed to each branch (Python applies
`re_bulk * k_R`); `k_R = 1.0` reproduces the strict circular `64/Re` laminar factor.

Two properties matter for integrating through a flow reversal:

- the closure guards the no-flow point. At `Re = 0` the bare laminar `64/Re` is `Inf`, so
  the closure feeds its laminar branch a finite Reynolds there and returns 0 for the whole
  factor. This is the symbolic-`Num` equivalent of Python's `if mdot == 0: return 0.0` at
  the top of `regime_dependent_friction`, written with `Base.ifelse` because a Julia `if`
  on a `Num` does not trace. For every `Re > 0` the result is exactly the plain blend.
- the linear interim blend makes the friction continuous across the laminar/turbulent
  boundary. A hard single-point switch leaves a slope discontinuity at the transition Re
  that a stiff implicit solver reads as a kink and rejects (`dt` below epsilon, `NaN`
  error estimate); the blend removes it. The blend value in the transition band is an
  interpolation, not a measured correlation, so it carries a small modeling error there in
  exchange for a residual the solver can integrate across the reversal.

# Arguments
- `re_bounds`: `(re_lo, re_hi)` regime boundaries on the bulk Reynolds number.
- `k_R`: geometric correction multiplying the Reynolds fed to each branch (default 1.0).
- `laminar`: laminar branch closure `(Re) -> f` (default `laminar_friction`).
- `turbulent`: turbulent branch closure `(Re) -> f` (default `turbulent_friction`).

# Returns
A closure `(Re) -> f_darcy`.
"""
function regime_dependent_friction(; re_bounds=(2000.0, 5000.0), k_R=1.0,
                                   laminar=laminar_friction, turbulent=turbulent_friction)
    re_lo = Float64(re_bounds[1])
    re_hi = Float64(re_bounds[2])
    return (Re) -> begin
        ReK = Re * k_R
        # Feed the laminar branch a finite Reynolds at no-flow so the bare 64/Re never forms
        # an Inf while the not-taken branch is traced. For every Re > 0 this is just ReK.
        ReK_lam = Base.ifelse(Re <= 0, one(ReK), ReK)
        f_lam = laminar(ReK_lam)
        f_turb = turbulent(ReK)
        # lin_interp on the bulk Re between (re_lo, f_lam) and (re_hi, f_turb).
        f_inter = (f_turb - f_lam) / (re_hi - re_lo) * (Re - re_hi) + f_turb
        # Boundary inclusivity matches Python flow_regimes: Re <= re_lo laminar, re_hi < Re turbulent.
        f = Base.ifelse(Re <= re_lo, f_lam, Base.ifelse(Re > re_hi, f_turb, f_inter))
        # No-flow guard, the symbolic equivalent of Python's `if mdot == 0: return 0.0`.
        Base.ifelse(Re <= 0, zero(f), f)
    end
end

"""
    viscosity_correction(heat_wet_ratio, mu_ratio) -> K_H

Viscosity correction factor for friction in heated channels. Accounts for
temperature-dependent viscosity variation between wall and bulk.

# Arguments
- `heat_wet_ratio`: heated perimeter / wet perimeter
- `mu_ratio`: viscosity at wall / viscosity at bulk

# Returns
Multiplicative correction factor K_H (dimensionless).

Reference: `viscosity_correction(1.0, 1.0) == 1.0`,
`viscosity_correction(1.0, 2.0) == 1.4948492486349383`.
"""
function viscosity_correction(heat_wet_ratio, mu_ratio)
    return 1 + heat_wet_ratio * (mu_ratio^0.58 - 1)
end
