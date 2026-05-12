# src/utilities.jl
#
# General-purpose 2D data-shape helpers used by Phase 62 codegen for
# Power Shape Resources:
#
#   - `rebin_extensive` : conservative area-weighted regrid from any source
#                         shape to any target shape (sum-preserving). Emitted
#                         by codegen for `file_loaded` Power Shapes.
#   - `cosine_power_shape` : closed-form axial cosine-squared profile uniform
#                            along x. Emitted by codegen for `z_cosine`
#                            Power Shapes (D-22).
#
# Caller-trust posture (D-25 + project memory `feedback_power_shape_trust_caller.md`):
# these functions do NOT validate, normalize, or guard positivity / shape /
# NaN. Whatever you put in is what gets resampled.
#
# ASCII-only Julia identifiers (project memory `feedback_ascii_variable_names.md`).

"""
    _rebin_1d(v::AbstractVector{<:Real}, n_out::Integer) -> Vector{Float64}

Internal helper. Conservatively rebin a 1D vector `v` of length `n_in` to
length `n_out`, preserving `sum(out) == sum(v)` to floating-point precision.

Treats each source cell `i` as occupying the interval
`[(i-1)/n_in, i/n_in]` and each target cell `j` as occupying
`[(j-1)/n_out, j/n_out]`. The fraction of `v[i]` assigned to `out[j]` is the
overlap length scaled by `n_in` (i.e. divided by the source-cell width
`1/n_in`). When `n_in == n_out` the input is copied through unchanged.

Not exported; underscore prefix marks it internal.
"""
function _rebin_1d(v::AbstractVector{<:Real}, n_out::Integer)
    n_in = length(v)
    out  = zeros(Float64, n_out)
    if n_in == n_out
        copyto!(out, v)
        return out
    end
    inv_n_in = 1.0 / n_in
    for i in 1:n_in
        src_lo = (i - 1) * inv_n_in
        src_hi = i * inv_n_in
        # First / last target cell that could overlap source cell i.
        j_lo = max(1, floor(Int, src_lo * n_out) + 1)
        j_hi = min(n_out, ceil(Int, src_hi * n_out))
        for j in j_lo:j_hi
            tgt_lo = (j - 1) / n_out
            tgt_hi = j / n_out
            overlap = max(0.0, min(src_hi, tgt_hi) - max(src_lo, tgt_lo))
            # Fraction of v[i] living in target cell j (overlap / source-width).
            out[j] += v[i] * overlap * n_in
        end
    end
    return out
end


"""
    rebin_extensive(M::AbstractMatrix{<:Real}, target_shape::Tuple{Int,Int}) -> Matrix{Float64}

Conservatively rebin a 2D extensive quantity `M` to `target_shape == (nz, nx)`,
preserving `sum(out) == sum(M)` to floating-point precision.

Designed for Phase 62 codegen of `file_loaded` Power Shape Resources: a user
hands in any CSV-shaped matrix and `rebin_extensive` redistributes the
integrated total onto the consumer's `(nz, nx)` grid at script runtime.

# Arguments
- `M`            : Source matrix of any size and any `Real` element type.
- `target_shape` : `(nz_out, nx_out)` target dimensions.

# Returns
A `Matrix{Float64}` of size `target_shape`. The element type is always
`Float64` regardless of the input element type.

# Algorithm
Separable 1D pass:

  1. Rebin each column along axis 1 (z), producing an intermediate matrix
     of shape `(nz_out, nx_in)`.
  2. Rebin each row of the intermediate along axis 2 (x), producing the
     final `(nz_out, nx_out)` output.

The z-then-x order is canonical (locked for reproducibility per the phase
RESEARCH document, Pitfall 6). Sum-conservation holds regardless of order,
but matrix entries may differ at ULP between orders.

# Caller trust
Per project policy `feedback_power_shape_trust_caller.md`, this function does
NOT validate the input. It does not check positivity, normalization, finite
values, or any shape constraint. Negative values, zeros, and NaNs flow
through; verification is the caller's responsibility.
"""
function rebin_extensive(M::AbstractMatrix{<:Real}, target_shape::Tuple{Int,Int})
    nz_out, nx_out = target_shape
    nz_in, nx_in   = size(M)
    # Pass 1: rebin each column along z.
    intermediate = Matrix{Float64}(undef, nz_out, nx_in)
    for j in 1:nx_in
        intermediate[:, j] = _rebin_1d(view(M, :, j), nz_out)
    end
    # Pass 2: rebin each row along x.
    out = Matrix{Float64}(undef, nz_out, nx_out)
    for i in 1:nz_out
        out[i, :] = _rebin_1d(view(intermediate, i, :), nx_out)
    end
    return out
end


"""
    cosine_power_shape(nz::Integer, nx::Integer; amplitude::Real=1.0) -> Matrix{Float64}

Build a `(nz, nx)` power-shape matrix with a cosine-squared profile along the
axial (z) direction and uniform distribution along the lateral (x) direction.

Emitted by Phase 62 codegen for `z_cosine` Power Shape Resources (D-22).

# Arguments
- `nz`        : Number of axial cells.
- `nx`        : Number of lateral cells.
- `amplitude` : Scalar multiplier on the axial profile. Default `1.0`.

# Returns
A `Matrix{Float64}` of size `(nz, nx)`. Every column is identical (uniform
along x); each column carries the axial cosine-squared profile evaluated at
cell centers.

# Formula
The axial profile is

    zaxis[i] = cos(pi * (i - 0.5) / nz - pi/2)^2     for i in 1:nz

which is the cell-centered form of `sin(pi * (i - 0.5) / nz)^2`, zero at the
axial boundaries and peaking at the channel midplane. The result is then
scaled by `amplitude` and broadcast uniformly across `nx` columns.

ASCII-only: `pi` (Julia constant), not the Unicode glyph for it.

# Python parity
The formula `[ASSUMED]` parity with Python STREAM
`uniform_x_power_shape` (lines 297-335 of
`stream/composition/mtr_geometry.py`), which uses the more general
`cosine_shape` integrated over cell boundaries with PPF-based extrapolation
length. The simpler cell-centered cos^2 form here matches the natural
discretization commitment in Phase 62 RESEARCH (Example 3). Caller is
responsible for any further normalization — this function does not normalize.
"""
function cosine_power_shape(nz::Integer, nx::Integer; amplitude::Real=1.0)
    # Cell-centered cosine-squared profile along z (ASCII-only: pi, not the Unicode glyph).
    zaxis = [cos(pi * (i - 0.5) / nz - pi/2)^2 for i in 1:nz]
    col   = amplitude .* zaxis
    return repeat(col, 1, nx)
end
