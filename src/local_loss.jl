# Analytic high-Re factors (Borda-Carnot expansion; Idelchik contraction closed form).
_expansion_asymptote(aratio) = (1 - aratio)^2
_contraction_asymptote(aratio) = 0.5 * (1 - aratio)^0.75

# Linear interpolation through (x1,y1)-(x2,y2), matching Python's lin_interp.
_lin_interp(x1, x2, y1, y2, x) = (y2 - y1) / (x2 - x1) * (x - x2) + y2

# Idelchik tables. Rows index the area ratio, columns the Reynolds number.
const _IDELCHIK_ARATIOS = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6]

const _IDELCHIK_42_RE = Float64[10, 15, 20, 30, 40, 50, 100, 200, 500, 1e3, 2e3, 3e3, 3300]
const _IDELCHIK_42_F = [
    3.10 3.20 3.00 2.40 2.15 1.95 1.70 1.65 1.70 2.00 1.60 1.00 0.81
    3.10 3.20 2.80 2.20 1.85 1.65 1.40 1.30 1.30 1.60 1.25 0.70 0.64
    3.10 3.10 2.60 2.00 1.60 1.40 1.20 1.10 1.10 1.30 0.95 0.60 0.50
    3.10 3.00 2.40 1.80 1.50 1.30 1.10 1.00 0.85 1.05 0.80 0.40 0.36
    3.10 2.80 2.30 1.65 1.35 1.15 0.90 0.75 0.65 0.90 0.65 0.30 0.25
    3.10 2.70 2.15 1.55 1.25 1.05 0.80 0.60 0.40 0.60 0.50 0.20 0.16
]

const _IDELCHIK_410_RE = Float64[10, 20, 30, 40, 50, 100, 200, 500, 1e3, 2e3, 4e3, 5e3, 1e4]
# Last column (Re=1e4) is overwritten with the analytic contraction factor, matching Python.
const _IDELCHIK_410_F = let
    f = [
        5.00 3.20 2.40 2.00 1.80 1.30 1.04 0.82 0.64 0.50 0.80 0.75 0.50
        5.00 3.10 2.30 1.84 1.62 1.20 0.95 0.70 0.50 0.40 0.60 0.60 0.40
        5.00 2.95 2.15 1.70 1.50 1.10 0.85 0.60 0.44 0.30 0.55 0.55 0.35
        5.00 2.80 2.00 1.60 1.40 1.00 0.78 0.50 0.35 0.25 0.45 0.50 0.30
        5.00 2.70 1.80 1.46 1.30 0.90 0.65 0.42 0.30 0.20 0.40 0.42 0.25
        5.00 2.60 1.70 1.35 1.20 0.80 0.56 0.35 0.24 0.15 0.35 0.35 0.20
    ]
    for (i, ar) in enumerate(_IDELCHIK_ARATIOS)
        f[i, end] = _contraction_asymptote(ar)
    end
    f
end

# Bilinear interpolation of f over (Re, area ratio). f[i,j]: i over ar_grid, j over re_grid.
# The caller only reaches here with re and aratio inside the grid bounds.
function _table_interp(re_grid, ar_grid, f, aratio, re)
    jr = clamp(searchsortedlast(re_grid, re), 1, length(re_grid) - 1)
    ia = clamp(searchsortedlast(ar_grid, aratio), 1, length(ar_grid) - 1)
    re1, re2 = re_grid[jr], re_grid[jr + 1]
    ar1, ar2 = ar_grid[ia], ar_grid[ia + 1]
    # Interpolate in Re at the two bracketing area ratios, then in area ratio.
    f_ar1 = _lin_interp(re1, re2, f[ia, jr], f[ia, jr + 1], re)
    f_ar2 = _lin_interp(re1, re2, f[ia + 1, jr], f[ia + 1, jr + 1], re)
    return _lin_interp(ar1, ar2, f_ar1, f_ar2, aratio)
end

# Re-regime dispatch for a sudden area change (Idelchik): analytic above the table,
# table interpolation within, and a velocity-decay extrapolation below.
function _sudden_area_factor(
    max_re, min_re, min_re_val, max_ar, min_ar, infval, analytic, table_interp, aratio, re,
)
    if re >= max_re
        return analytic(aratio)
    elseif re >= min_re && min_ar <= aratio <= max_ar
        return table_interp(aratio, re)
    else
        isapprox(re, 0.0; atol=1e-8) && return 0.0   # v=0 ⇒ no loss
        v1 = min_re_val * min_re / re
        if aratio > max_ar
            v_at_ratio = _lin_interp(max_ar, 1.0, v1, 0.0, aratio)
            return _lin_interp(min_re, max_re, v_at_ratio, analytic(aratio), re)
        elseif aratio < min_ar
            v_at_ratio = _lin_interp(min_ar, 0.0, v1, infval, aratio)
            return _lin_interp(min_re, max_re, v_at_ratio, analytic(aratio), re)
        end
        return v1
    end
end

"""
    sudden_expansion_factor(aratio, re) -> K

Idelchik table 4.2 loss coefficient for a sudden expansion, as a function of the area ratio
(smaller over larger) and the Reynolds number.

Above Re = 3300 this is the Borda-Carnot result `(1 - aratio)^2`. Within the table it is a
bilinear interpolation. Below Re = 10, or outside the tabulated area ratios, it extrapolates.
[`factor`](@ref) is what picks between this and [`sudden_contraction_factor`](@ref).
"""
function sudden_expansion_factor(aratio, re)
    return _sudden_area_factor(
        _IDELCHIK_42_RE[end], _IDELCHIK_42_RE[1], _IDELCHIK_42_F[1, 1],
        _IDELCHIK_ARATIOS[end], _IDELCHIK_ARATIOS[1], 1.0,
        _expansion_asymptote,
        (ar, r) -> _table_interp(_IDELCHIK_42_RE, _IDELCHIK_ARATIOS, _IDELCHIK_42_F, ar, r),
        aratio, re,
    )
end

"""
    sudden_contraction_factor(aratio, re) -> K

Idelchik table 4.10 loss coefficient for a sudden contraction, as a function of the area ratio
(smaller over larger) and the Reynolds number.

Above Re = 1e4 this is the closed form `0.5*(1 - aratio)^0.75`, which also overwrites the table's
last column so the two agree at the join, matching Python. Within the table it is a bilinear
interpolation, and below Re = 10 it extrapolates.
"""
function sudden_contraction_factor(aratio, re)
    return _sudden_area_factor(
        _IDELCHIK_410_RE[end], _IDELCHIK_410_RE[1], _IDELCHIK_410_F[1, 1],
        _IDELCHIK_ARATIOS[end], _IDELCHIK_ARATIOS[1], 0.5,
        _contraction_asymptote,
        (ar, r) -> _table_interp(_IDELCHIK_410_RE, _IDELCHIK_ARATIOS, _IDELCHIK_410_F, ar, r),
        aratio, re,
    )
end

"""
    factor(ṁ, A1, A2, mu) -> K

Dimensionless loss coefficient `K` for a sudden area change `A1 -> A2`, at mass flow `ṁ` and
dynamic viscosity `mu`. Feed it to [`dp`](@ref) to get a pressure.

Forward flow (`ṁ >= 0`) goes `1 -> 2`, so it sees an expansion when `A2 >= A1` and a
contraction otherwise. Reverse flow swaps the roles, which is what keeps the loss correct through
a flow reversal.

`K` comes from the Idelchik tables, indexed by area ratio and Reynolds number: table 4.2 for
expansion, table 4.10 for contraction. Above the tabulated Reynolds range the analytic closed
forms apply (Borda-Carnot for expansion, Idelchik's for contraction); below it the value is
extrapolated by velocity decay. Ported from Python STREAM's
`stream/physical_models/pressure_drop/local.py`.

`@register_symbolic`, so MTK carries the table lookup as one opaque node and it can sit inside a
pressure-drop equation.

# Arguments
- `ṁ`: mass flow rate [kg/s]; its sign selects expansion or contraction
- `A1`: upstream flow area [m^2]
- `A2`: downstream flow area [m^2]
- `mu`: dynamic viscosity [Pa·s]

# Returns
The dimensionless loss coefficient `K`.
"""
function factor(ṁ::Real, A1::Real, A2::Real, mu::Real)
    A = min(A1, A2)
    aratio = min(A1 / A2, A2 / A1)
    Dh = sqrt(A / pi)
    re = abs(ṁ) * Dh / (A * mu)
    pos, neg = A2 >= A1 ?
               (sudden_expansion_factor, sudden_contraction_factor) :
               (sudden_contraction_factor, sudden_expansion_factor)
    return ṁ >= 0 ? pos(aratio, re) : neg(aratio, re)
end

@register_symbolic factor(ṁ::Real, A1::Real, A2::Real, mu::Real)

"""
    dp(ṁ, rho, f, A) -> Pa

Local (minor) loss pressure drop:

    dP = f * ṁ|ṁ| / (2*rho*A^2)

The same quadratic form as [`darcy_weisbach_dp`](@ref) without the `L/Dh` factor, because a
local loss is tied to a fitting rather than to a length of duct. Positive `ṁ` gives a
positive drop.

# Arguments
- `ṁ`: mass flow rate [kg/s]
- `rho`: density [kg/m^3]
- `f`: local loss coefficient
- `A`: reference flow area [m^2]

# Returns
Pressure drop [Pa].
"""
dp(ṁ, rho, f, A) = f * (ṁ * abs(ṁ) / (2 * rho * A^2))

"""
    DISCHARGE_CD

Fully turbulent discharge coefficients `C_d = C_c·C_v` by hole geometry, the values
[`discharge_cd`](@ref) looks up. They hold above a throat Reynolds number of about 1e4; below
that use [`lichtarowicz_cd`](@ref).

| Key | `C_d` | Geometry |
|:---|:---|:---|
| `:sharp` | 0.61 | Sharp-edged thin plate, set by the vena contracta |
| `:rounded` | 0.98 | Rounded, bellmouth or nozzle inlet: no contraction, friction only |
| `:short_tube` | 0.81 | Thick hole with `L/d` of 2 to 4, where the jet reattaches |
| `:borda` | 0.51 | Re-entrant tube protruding into the vessel |
| `:pipe_stub` | 0.6 | Clean severed pipe end, a sharp entrance into the stub |
"""
const DISCHARGE_CD = Dict(
    :sharp => 0.61,
    :rounded => 0.98,
    :short_tube => 0.81,
    :borda => 0.51,
    :pipe_stub => 0.6,
)

"""
    discharge_cd(geometry::Symbol) -> Float64

The fully turbulent discharge coefficient of a hole of the given geometry, one of the keys of
[`DISCHARGE_CD`](@ref).

# Arguments
- `geometry`: `:sharp`, `:rounded`, `:short_tube`, `:borda` or `:pipe_stub`

# Returns
The discharge coefficient.

# Throws
`ArgumentError` for a geometry not in [`DISCHARGE_CD`](@ref).
"""
function discharge_cd(geometry::Symbol)
    haskey(DISCHARGE_CD, geometry) || throw(ArgumentError(
        "no discharge coefficient for :$geometry; known geometries are " *
        join(sort!(collect(keys(DISCHARGE_CD))), ", "),
    ))
    return DISCHARGE_CD[geometry]
end

"""
    lichtarowicz_cd(Re, L_over_d) -> Float64

The discharge coefficient of a parallel-bore orifice at finite Reynolds number, after
Lichtarowicz, Duggins and Markland (1965):

    C_du = 0.827 − 0.0085·L/d
    1/C_d = 1/C_du + (20/Re)·(1 + 2.25·L/d) − 0.005·(L/d) / (1 + 7.5·log10(1.5e-4·Re)²)

`C_du` is the high Reynolds limit, which `C_d` approaches from below as the viscous term dies
out. Fitted for `10 ≤ Re ≤ 2e4` and `L/d ≤ 10`; outside that it extrapolates. For a thin
plate rather than a bore, use `discharge_cd(:sharp)`.

# Arguments
- `Re`: Reynolds number at the throat, on the bore diameter
- `L_over_d`: bore length over bore diameter

# Returns
The discharge coefficient.
"""
function lichtarowicz_cd(Re, L_over_d)
    cdu = 0.827 - 0.0085 * L_over_d
    inverse = 1 / cdu + (20 / Re) * (1 + 2.25 * L_over_d) -
        0.005 * L_over_d / (1 + 7.5 * log10(0.00015 * Re)^2)
    return 1 / inverse
end

"""
    stub_discharge_mdot(dp, rho, area, k_total) -> kg/s

Mass flow discharged through a sum of losses, such as a broken pipe stub:

    ṁ = area·sqrt(2·rho·dp / k_total)

`k_total` collects every loss between the intact system and the break: entrance, the stub's
own friction `f·L/d`, and exit. For a bare hole `k_total = 1/C_d²` gives the Torricelli form.
Undefined for `dp < 0`; a model that hands it to a solver needs [`smooth_signed_sqrt`](@ref).

# Arguments
- `dp`: driving pressure difference, upstream minus back pressure [Pa]
- `rho`: liquid density [kg/m³]
- `area`: break flow area [m²]
- `k_total`: sum of the loss coefficients along the discharge path

# Returns
The discharged mass flow rate [kg/s].
"""
stub_discharge_mdot(dp, rho, area, k_total) = area * sqrt(2 * rho * dp / k_total)

"""
    drain_time(h0, h1, area_tank, area_hole, cd) -> s

Time for a tank of constant cross-section to drain by gravity from `h0` to `h1`, both
measured above the hole:

    t = (area_tank / (cd·area_hole))·sqrt(2/g)·(sqrt(h0) − sqrt(h1))

The discharge is quasi-steady and not submerged. A tank whose cross-section changes with
level needs `A(h)·dh/dt = −cd·area_hole·sqrt(2gh)` integrated instead.

# Arguments
- `h0`, `h1`: initial and final level above the hole [m]
- `area_tank`: tank free-surface area [m²]
- `area_hole`: hole area [m²]
- `cd`: discharge coefficient

# Returns
The draining time [s]. [`drain_level`](@ref) is its inverse.
"""
function drain_time(h0, h1, area_tank, area_hole, cd)
    return (area_tank / (cd * area_hole)) * sqrt(2 / G_EARTH) * (sqrt(h0) - sqrt(h1))
end

"""
    drain_level(t, h0, area_tank, area_hole, cd) -> m

Level above the hole after a tank has drained by gravity for `t` seconds from `h0`, the
inverse of [`drain_time`](@ref):

    h(t) = (sqrt(h0) − (cd·area_hole/area_tank)·sqrt(g/2)·t)²

The root is floored at zero, so an emptied tank stays empty instead of following the parabola
back up.

# Arguments
- `t`: time since the level was `h0` [s]
- `h0`: initial level above the hole [m]
- `area_tank`: tank free-surface area [m²]
- `area_hole`: hole area [m²]
- `cd`: discharge coefficient

# Returns
The level above the hole [m].
"""
function drain_level(t, h0, area_tank, area_hole, cd)
    root = sqrt(h0) - (cd * area_hole / area_tank) * sqrt(G_EARTH / 2) * t
    return max(root, 0.0)^2
end

"""
    smooth_signed_sqrt(x, eps) -> Float64

`sign(x)·sqrt(|x|)` with the corner at zero rounded off:

    x / (x² + eps²)^(1/4)

The exact form has an infinite slope at `x = 0`, which a flow driven by a pressure difference
crosses whenever a break seals or its flow reverses. Here the slope stays finite, about
`1/sqrt(eps)`, and for `|x| ≫ eps` the result matches the exact form to a relative error of
`eps²/(4x²)`. Odd in `x`, and defined for negative `x`.

# Arguments
- `x`: the signed quantity, usually a pressure difference [Pa]
- `eps`: half-width of the rounded band, in the units of `x`

# Returns
The regularised signed square root.
"""
smooth_signed_sqrt(x, eps) = x / (x^2 + eps^2)^(1 / 4)
