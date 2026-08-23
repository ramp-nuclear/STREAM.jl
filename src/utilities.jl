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

Resample an **extensive** quantity (an amount per cell — power, mass, ...) onto a
new grid, preserving the total: `sum(out) == sum(v)`.

Extensive means the value scales with cell size, so splitting one cell into two
halves the value and merging two cells adds them. `rebin_extensive([10.0], 2)`
gives `[5.0, 5.0]`.

The `(v, n_out)` and `(M, target_shape)` forms assume source and target cells
uniformly tile the same domain. The `(v, src_edges, tgt_edges)` form takes
explicit cell boundaries (`length(v)+1` and `n_out+1` increasing values), which
may be non-uniform. The 2D form is separable (rebin along z, then x).

Inputs are trusted: no checks on sign, finiteness, normalization, or shape.
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

Resample an **intensive** quantity (a per-cell value — temperature, heat flux,
...) onto a new grid, preserving the value rather than the total.

Intensive means the value does not depend on cell size, so splitting one cell
into two copies the value and merging two cells averages them.
`rebin_intensive([10.0], 2)` gives `[10.0, 10.0]`; `rebin_intensive([3.0, 7.0], 1)`
gives `[5.0]`. A constant field stays constant under any regrid. Each target cell
ends up holding the area-weighted average of the source values it covers.

Forms and trust posture mirror [`rebin_extensive`](@ref): `(v, n_target)` /
`(M, target_shape)` are uniform; `(v, src_edges, tgt_edges)` takes explicit,
possibly non-uniform, boundaries; inputs are not validated.
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

Build an `(nz, nx)` matrix whose every column is the same cell-centered
cosine-squared profile along z — zero at the two axial ends, peaking at the
mid-plane — scaled by `amplitude` and repeated across the `nx` columns.

The axial profile is `sin(pi*(i-0.5)/nz)^2` at cell centers (written as
`cos(pi*(i-0.5)/nz - pi/2)^2`). It is not normalized; scale it yourself if you
need a particular integral.
"""
function cosine_power_shape(nz::Integer, nx::Integer; amplitude::Real = 1.0)
    zaxis = [cos(pi * (i - 0.5) / nz - pi / 2)^2 for i in 1:nz]
    return repeat(amplitude .* zaxis, 1, nx)
end

"""
    cosine_T_wall_profile(n; amplitude=1.0) -> Vector{Float64}

Length-`n` cell-centered cosine-squared profile — the single-column form of
[`cosine_power_shape`](@ref), for axial wall-temperature / heat-flux profiles.
Not normalized.
"""
cosine_T_wall_profile(n::Integer; amplitude::Real = 1.0) =
    cosine_power_shape(n, 1; amplitude = amplitude)[:, 1]
