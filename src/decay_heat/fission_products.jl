"""
    Standard

A published fission product decay heat standard: `ANS14` (ANSI/ANS-5.1-2014), `ANS73`
(ANS-5.1-1973) or `JAERI91` (JAERI-M-91-034).

Names the table [`read_standard`](@ref) looks for, together with a [`Source`](@ref).
"""
@enum Standard ANS14 ANS73 JAERI91

"""
    Source

The fissioning nuclide a table covers, and which part of its decay: `U235`, `U235_beta`,
`U235_gamma`, `U238` or `U238_gamma`.

The ANS standards do not split beta from gamma. JAERI-91 does, which matters for non-fuel
components, where the beta contribution is deposited locally and the gamma contribution may
not be. Its tables cover thermal fission of U235 and fast fission of U238.

Member names carry the lower-case suffix rather than SCREAMING_SNAKE_CASE because they are
the literal file name token, the same way Python STREAM spells them.
"""
@enum Source U235 U235_beta U235_gamma U238 U238_gamma

"""
    STANDARDS_DIR

Where [`read_standard`](@ref) looks for tables. Empty until set, since the tables are not
distributed with this package. Read it through [`standards_dir`](@ref).
"""
const STANDARDS_DIR = Ref("")

"""
    standards_dir() -> String

The directory [`read_standard`](@ref) reads tables from.

# Returns
- `String`: the directory currently set

# Throws
- `ArgumentError`: if no directory has been set
"""
function standards_dir()
    if isempty(STANDARDS_DIR[])
        throw(ArgumentError("no decay heat standards directory set; call \
                             DecayHeat.standards_dir!(path), pass dir= explicitly, or set \
                             ENV[\"STREAM_DECAY_HEAT_STANDARDS\"] before loading STREAM"))
    end
    return STANDARDS_DIR[]
end

"""
    standards_dir!(path) -> String

Point [`read_standard`](@ref) at the directory holding the decay heat tables.

# Arguments
- `path`: directory holding files named `<source>_<standard>.csv`

# Returns
- `String`: the directory that was set
"""
standards_dir!(path) = (STANDARDS_DIR[] = String(path))

function __init__()
    haskey(ENV, "STREAM_DECAY_HEAT_STANDARDS") &&
        standards_dir!(ENV["STREAM_DECAY_HEAT_STANDARDS"])
    return nothing
end

_tag(standard::Standard) = lowercase(string(standard))

_table_path(dir, standard::Standard, source::Source) =
    joinpath(dir, "$(source)_$(_tag(standard)).csv")

"""
    read_standard(standard, source; dir=standards_dir()) -> (λ, α)

Read one decay heat table off disk.

The file is `<source>_<standard>.csv`, a headed CSV whose `lamda` column holds the group
decay constants λ in 1/s and whose `alpha` column holds the group strengths α in
MeV/(fission/s). Those two spellings are the literal headers the standards ship with, not a
typo to fix. Columns are found by name, so their order in the file does not matter, and row
order does not matter either since [`FissionProducts`](@ref) only sums over the groups.

Not every combination of [`Standard`](@ref) and [`Source`](@ref) has a published table.

# Arguments
- `standard`: which [`Standard`](@ref) to read
- `source`: which [`Source`](@ref) to read

# Keywords
- `dir`: directory to read from, defaulting to [`standards_dir`](@ref)

# Returns
- `Tuple{Vector{Float64},Vector{Float64}}`: the λ and α columns

# Throws
- `ArgumentError`: if the table is absent, empty, or missing either column
"""
function read_standard(standard::Standard, source::Source; dir=standards_dir())
    path = _table_path(dir, standard, source)
    # An empty file is how Python STREAM ships the combinations it has no table for, so it
    # gets the same answer here as a missing one.
    if !isfile(path) || iszero(filesize(path))
        throw(ArgumentError("no $source table for $standard in $dir"))
    end

    table, header = readdlm(path, ',', Float64; header=true)
    columns = strip.(string.(vec(header)))
    λ_col = findfirst(==("lamda"), columns)
    α_col = findfirst(==("alpha"), columns)
    if λ_col === nothing || α_col === nothing
        throw(ArgumentError("$path needs lamda and alpha columns, found $columns"))
    end

    return table[:, λ_col], table[:, α_col]
end

"""
    FissionProducts(λ, α) <: AbstractDecayHeat
    FissionProducts(standard, source; dir=standards_dir()) <: AbstractDecayHeat

Decay of fission products, the largest decay heat contribution, as the summed exponential
fit the standards publish,

    F(t, T) = Σᵢ (αᵢ/λᵢ)·e^(-λᵢt)·(1 - e^(-λᵢT))    [MeV/fission]

The second form reads the groups from a table with [`read_standard`](@ref); the first takes
them directly, for a fit the standards here do not cover.

Negative α values are expected in the JAERI-91 tables. They are least-squares fit
coefficients rather than physical group yields, so only the sum means anything, and nothing
here filters or clamps them.

Source: Python STREAM decay_heat/fission_products.py `contribution` and `fp_inner_`.

# Arguments
- `λ`: group decay constants [1/s]
- `α`: group strengths [MeV/(fission/s)], in the same group order as `λ`

# Returns
An [`AbstractDecayHeat`](@ref) whose value is in MeV/fission.

# Throws
- `DimensionMismatch`: if `λ` and `α` differ in length
"""
struct FissionProducts <: AbstractDecayHeat
    λ::Vector{Float64}
    α::Vector{Float64}

    function FissionProducts(λ::AbstractVector, α::AbstractVector)
        if length(λ) != length(α)
            throw(DimensionMismatch("λ has $(length(λ)) groups, α has $(length(α))"))
        end
        return new(collect(Float64, λ), collect(Float64, α))
    end
end

function FissionProducts(standard::Standard, source::Source; dir=standards_dir())
    return FissionProducts(read_standard(standard, source; dir)...)
end

function (model::FissionProducts)(t, T=Inf)
    return sum(α / λ * _saturated_decay(t, T, λ) for (λ, α) in zip(model.λ, model.α))
end
