# local.jl -- Idelchik sudden expansion / contraction local-loss factors.
#
# Faithful port of Python STREAM's stream/physical_models/pressure_drop/local.py. The
# loss coefficient K depends on the area ratio and the Reynolds number through Idelchik
# tables 4.2 (expansion) and 4.10 (contraction), with analytic closed forms above the
# table's Reynolds range and a documented extrapolation below it. `factor`
# bundles the whole lookup into one `@register_symbolic` function so it can sit inside an
# MTK pressure-drop equation.

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

function sudden_expansion_factor(aratio, re)
    return _sudden_area_factor(
        _IDELCHIK_42_RE[end], _IDELCHIK_42_RE[1], _IDELCHIK_42_F[1, 1],
        _IDELCHIK_ARATIOS[end], _IDELCHIK_ARATIOS[1], 1.0,
        _expansion_asymptote,
        (ar, r) -> _table_interp(_IDELCHIK_42_RE, _IDELCHIK_ARATIOS, _IDELCHIK_42_F, ar, r),
        aratio, re,
    )
end

function sudden_contraction_factor(aratio, re)
    return _sudden_area_factor(
        _IDELCHIK_410_RE[end], _IDELCHIK_410_RE[1], _IDELCHIK_410_F[1, 1],
        _IDELCHIK_ARATIOS[end], _IDELCHIK_ARATIOS[1], 0.5,
        _contraction_asymptote,
        (ar, r) -> _table_interp(_IDELCHIK_410_RE, _IDELCHIK_ARATIOS, _IDELCHIK_410_F, ar, r),
        aratio, re,
    )
end

# Loss coefficient K for a sudden area change A1 -> A2 at mass flow `ṁ`, viscosity `mu`.
# Forward flow (ṁ >= 0) goes 1 -> 2: an expansion if A2 >= A1, a contraction otherwise.
# Reverse flow swaps the role. Returns the dimensionless K used in dp = K*ṁ|ṁ|/(2 rho A^2).
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
