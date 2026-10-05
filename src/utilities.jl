"""
    _rebin_1d(v, src_edges, tgt_edges, conserve) -> Vector{Float64}

Rebin a piecewise-constant 1D field from `src_edges` (length `n_in+1`, increasing) onto
`tgt_edges` (length `n_out+1`).

The shared core behind both public rebin functions. `conserve=:sum` keeps the integral over each
target cell (extensive); `conserve=:mean` keeps the area-weighted value (intensive). They differ
only in whether each overlap is divided by the source-cell or the target-cell width.
"""
function _rebin_1d(
    v::AbstractVector{<:Real},
    src_edges::AbstractVector{<:Real},
    tgt_edges::AbstractVector{<:Real},
    conserve::Symbol,
)
    # Identical grids are the identity; return the values unchanged (also avoids
    # a 1-ULP drift from overlap/width not being bit-exactly 1).
    src_edges == tgt_edges && return Float64.(v)
    n_out = length(tgt_edges) - 1
    out = zeros(Float64, n_out)
    for i in eachindex(v)
        src_lo, src_hi = src_edges[i], src_edges[i + 1]
        for j in 1:n_out
            tgt_lo, tgt_hi = tgt_edges[j], tgt_edges[j + 1]
            overlap = min(src_hi, tgt_hi) - max(src_lo, tgt_lo)
            overlap > 0.0 || continue
            width = conserve === :sum ? (src_hi - src_lo) : (tgt_hi - tgt_lo)
            out[j] += v[i] * overlap / width
        end
    end
    return out
end

# Uniform cell edges 0, 1/n, ..., 1.
_uniform_edges(n::Integer) = collect(range(0.0, 1.0; length = n + 1))

# Separable 2D rebin: pass over z (columns) then x (rows), reusing the 1D core.
function _rebin_2d(M::AbstractMatrix{<:Real}, target_shape::Tuple{Integer,Integer}, conserve::Symbol)
    nz_out, nx_out = target_shape
    nz_in, nx_in = size(M)
    z_src, z_tgt = _uniform_edges(nz_in), _uniform_edges(nz_out)
    x_src, x_tgt = _uniform_edges(nx_in), _uniform_edges(nx_out)
    intermediate = Matrix{Float64}(undef, nz_out, nx_in)
    for j in 1:nx_in
        intermediate[:, j] = _rebin_1d(view(M, :, j), z_src, z_tgt, conserve)
    end
    out = Matrix{Float64}(undef, nz_out, nx_out)
    for i in 1:nz_out
        out[i, :] = _rebin_1d(view(intermediate, i, :), x_src, x_tgt, conserve)
    end
    return out
end

"""
    rebin_extensive(v, n_out) -> Vector{Float64}
    rebin_extensive(v, src_edges, tgt_edges) -> Vector{Float64}
    rebin_extensive(M, (nz_out, nx_out)) -> Matrix{Float64}

Resample an **extensive** quantity (an amount per cell, such as power or mass) onto a new
grid, preserving the total: `sum(out) == sum(v)`.

Extensive means the value scales with cell size, so splitting one cell into two halves the
value and merging two cells adds them.

The `(v, n_out)` and `(M, target_shape)` forms assume source and target cells uniformly tile
the same domain. The `(v, src_edges, tgt_edges)` form takes explicit cell boundaries
(`length(v)+1` and `n_out+1` increasing values), which may be non-uniform. The 2D form is
separable: it rebins along z, then x.

Inputs are trusted: nothing checks their sign, finiteness, normalization or shape.

# Arguments
- `v`, `M`: the per-cell amounts
- `n_out`, `(nz_out, nx_out)`: the target cell counts
- `src_edges`, `tgt_edges`: source and target cell boundaries

# Returns
The amounts on the target grid.

# Examples
```jldoctest
julia> Utilities.rebin_extensive([10.0], 2)
2-element Vector{Float64}:
 5.0
 5.0
```
"""
rebin_extensive(v::AbstractVector{<:Real}, n_out::Integer) =
    _rebin_1d(v, _uniform_edges(length(v)), _uniform_edges(n_out), :sum)

rebin_extensive(
    v::AbstractVector{<:Real},
    src_edges::AbstractVector{<:Real},
    tgt_edges::AbstractVector{<:Real},
) = _rebin_1d(v, src_edges, tgt_edges, :sum)

rebin_extensive(M::AbstractMatrix{<:Real}, target_shape::Tuple{Integer,Integer}) =
    _rebin_2d(M, target_shape, :sum)

"""
    rebin_intensive(v, n_target) -> Vector{Float64}
    rebin_intensive(v, src_edges, tgt_edges) -> Vector{Float64}
    rebin_intensive(M, (nz_out, nx_out)) -> Matrix{Float64}

Resample an **intensive** quantity (a per-cell value, such as temperature or heat flux) onto
a new grid, preserving the value rather than the total.

Intensive means the value does not depend on cell size, so splitting one cell into two copies
the value and merging two cells averages them. A constant field stays constant under any
regrid. Each target cell ends up holding the area-weighted average of the source values it
covers.

The forms are those of [`rebin_extensive`](@ref), and inputs are not validated either.

# Arguments
- `v`, `M`: the per-cell values
- `n_target`, `(nz_out, nx_out)`: the target cell counts
- `src_edges`, `tgt_edges`: source and target cell boundaries

# Returns
The values on the target grid.

# Examples
```jldoctest
julia> Utilities.rebin_intensive([3.0, 7.0], 1)
1-element Vector{Float64}:
 5.0
```
"""
rebin_intensive(v::AbstractVector{<:Real}, n_target::Integer) =
    _rebin_1d(v, _uniform_edges(length(v)), _uniform_edges(n_target), :mean)

rebin_intensive(
    v::AbstractVector{<:Real},
    src_edges::AbstractVector{<:Real},
    tgt_edges::AbstractVector{<:Real},
) = _rebin_1d(v, src_edges, tgt_edges, :mean)

rebin_intensive(M::AbstractMatrix{<:Real}, target_shape::Tuple{Integer,Integer}) =
    _rebin_2d(M, target_shape, :mean)

"""
    cosine_power_shape(nz, nx; amplitude=1.0) -> Matrix{Float64}

Build an `(nz, nx)` matrix whose every column is the same cell-centred cosine-squared
profile along z, zero at the two axial ends and peaking at the mid-plane, scaled by
`amplitude`.

The axial profile is `sin(π(i - 1/2)/nz)²` at cell centres. It is not normalized; scale it
yourself if you need a particular integral.

# Arguments
- `nz`, `nx`: axial and lateral cell counts
- `amplitude`: the peak value

# Returns
An `nz × nx` `Matrix{Float64}`.
"""
function cosine_power_shape(nz::Integer, nx::Integer; amplitude::Real = 1.0)
    zaxis = [cos(pi * (i - 0.5) / nz - pi / 2)^2 for i in 1:nz]
    return repeat(amplitude .* zaxis, 1, nx)
end

"""
    cosine_T_wall_profile(n; amplitude=1.0) -> Vector{Float64}

Length-`n` cell-centred cosine-squared profile, the single-column form of
[`cosine_power_shape`](@ref), for axial wall-temperature or heat-flux profiles. Not
normalized.

# Arguments
- `n`: number of cells
- `amplitude`: the peak value

# Returns
A `Vector{Float64}` of length `n`.
"""
cosine_T_wall_profile(n::Integer; amplitude::Real = 1.0) =
    cosine_power_shape(n, 1; amplitude = amplitude)[:, 1]

"""
    _peaking_angle(ppf) -> Float64

The angle `h` with `h/sin(h) = ppf`, found by bisection on `[0, π/2]`.

`sin(h)/h` falls monotonically from 1 to `2/π` over that interval, so any `ppf` the caller is
allowed to pass is bracketed by construction and bisection cannot miss it. It is solved once
per profile, which does not pay for a root-finding dependency.
"""
function _peaking_angle(ppf)
    ppf == 1 && return 0.0
    lo, hi = 0.0, π / 2
    while hi - lo > eps(hi)
        mid = (lo + hi) / 2
        sin(mid) / mid > 1 / ppf ? (lo = mid) : (hi = mid)
    end
    return (lo + hi) / 2
end

"""
    cosine_shape(x, ppf=π/2; xmax=nothing) -> Vector{Float64}

A cosine power profile over cells with boundaries `x`, integrated over each cell and
normalised so the shares sum to 1.

The profile is `cos(π(x - xmax)/L)`. The extrapolated length `L` is set by the power peaking
factor `ppf`, the ratio of the profile's peak to its mean over `x`: with `ℓ` the span of `x`
and `h = πℓ/(2L)`, that ratio is `h/sin(h)`, solved here for `h`. The peak sits in the
middle of `x` unless `xmax` moves it, as for a partially inserted control rod.

Integrating each cell rather than sampling its centre keeps the total right on a coarse or
graded mesh. [`cosine_power_shape`](@ref) samples instead, and its peak is always twice its
mean.

# Arguments
- `x`: increasing cell boundaries, `length(x) = ncells + 1` [m]
- `ppf`: power peaking factor in `[1, π/2]`. `1` is flat, and `π/2` is a cosine reaching
  zero exactly at the ends.

# Keywords
- `xmax`: where the cosine peaks, the middle of `x` by default

# Returns
`Vector{Float64}` of length `length(x) - 1`, one share per cell.

# Throws
- `ArgumentError`: if `ppf` is outside `[1, π/2]`

# Examples
Four equal cells with a peaking factor of 1.4: the middle cells take the larger shares, and
the shares sum to 1.
```jldoctest
julia> s = Utilities.cosine_shape(range(0.0, 0.6; length=5), 1.4);

julia> round.(s; digits=4), sum(s) ≈ 1
([0.1768, 0.3232, 0.3232, 0.1768], true)
```
"""
function cosine_shape(x, ppf=π / 2; xmax=nothing)
    1 <= ppf <= π / 2 || throw(ArgumentError("ppf must be in [1, π/2], got $ppf"))
    span = last(x) - first(x)
    mid = xmax === nothing ? (first(x) + last(x)) / 2 : xmax
    h = _peaking_angle(ppf)
    # Flat is the h -> 0 limit of the expression below, which divides by zero there.
    iszero(h) && return diff(collect(Float64, x)) ./ span
    a = 2h / span
    b = ppf / span
    return (b / a) .* diff(sin.(a .* (x .- mid)))
end
