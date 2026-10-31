"""
    _check_parameters(ssys, parameters)

Check that every entry of `parameters` is a parameter of `ssys`, naming every one that is not.

# Throws
- `ArgumentError`: listing the entries of `parameters` that are not parameters of `ssys`
"""
function _check_parameters(ssys, parameters)
    strangers = filter(p -> !is_parameter(ssys, p), parameters)
    isempty(strangers) || throw(ArgumentError(
        "not parameters of $(nameof(ssys)): $(join(strangers, ", "))"
    ))
end

"""
    _readout(output) -> Function

`output` as a function of a solution: a function as it is, and a vector of variables as the
function reading each of them.
"""
_readout(output::AbstractVector) = sol -> reduce(vcat, [sol[v] for v in output])
_readout(output) = output

"""
    _outputs(y) -> AbstractVector

A model's result as the flat vector of outputs ForwardDiff differentiates, the entries of a
`NamedTuple` one after the other.

# Throws
- `ArgumentError`: for anything but a number, an array or a `NamedTuple` of these
"""
_outputs(y::Number) = [y]
_outputs(y::AbstractArray) = vec(y)
_outputs(y::NamedTuple) = mapreduce(_outputs, vcat, values(y))
_outputs(y) = throw(ArgumentError(
    "a model returns a number, an array or a NamedTuple of these, not a $(typeof(y))"
))

"""
    _mirror(r::NamedTuple, output) -> NamedTuple

The results `r` over the flat outputs, in the shape of a model's `output`. A `NamedTuple`
output gives its keys and nesting, with `r`'s fields at each leaf holding that leaf's part in
its shape. Any other output keeps `r` flat.
"""
_mirror(r, output) = r
function _mirror(r, output::NamedTuple)
    slices = NamedTuple{keys(output)}(_slices(_outputs.(Tuple(output))))
    return map((y, s) -> _leaf(map(x -> _take(x, s), r), y), output, slices)
end

"""
    _leaf(r, y) -> NamedTuple

The part `r` of the results at the entry `y` of a named output: shaped like `y`, or mirrored
further when `y` is a `NamedTuple` itself.
"""
_leaf(r, y) = map(x -> _shape(x, y), r)
_leaf(r, y::NamedTuple) = _mirror(r, y)

"""
    _take(x, slice)

The outputs at `slice` of one field of a result: entries of a vector, rows of a matrix. A
field that is not per output, such as a count, stays as it is.
"""
_take(x, _) = x
_take(x::AbstractVector, slice) = x[slice]
_take(x::AbstractMatrix, slice) = x[slice, :]

"""
    _shape(x, y)

One field of a result in the shape of the output `y`: a number for a number, and an array of
`y`'s size otherwise, with the columns of a matrix field as a last dimension.
"""
_shape(x, _) = x
_shape(x::AbstractVector, ::Number) = only(x)
_shape(x::AbstractVector, y) = reshape(x, size(y))
_shape(x::AbstractMatrix, y) = reshape(x, size(y)..., :)

"""
    _position(parameters, parameter) -> Int

Where `parameter` sits in the list of inputs `parameters`.

# Throws
- `ArgumentError`: when it is not one of them
"""
function _position(parameters, parameter)
    i = findfirst(p -> isequal(p, parameter), parameters)
    i === nothing && throw(ArgumentError(
        "$parameter is not one of the inputs, which are $(join(parameters, ", "))"
    ))
    return i
end

"""
    _slices(values) -> Vector{UnitRange{Int}}

The positions each input takes in the flat vector ForwardDiff differentiates over, one entry
for a number and one per element for an array.
"""
function _slices(values)
    lengths = length.(values)
    stops = cumsum(lengths)
    return range.(stops .- lengths .+ 1, stops)
end

"""
    _flat(values) -> Vector{Float64}

The inputs' values as the one flat vector ForwardDiff differentiates over.
"""
_flat(values) = collect(Float64, Iterators.flatten(values))

"""
    _unflatten(x, values, slices) -> Vector

The inputs held in the flat vector `x`, each shaped like its nominal value in `values`.
"""
function _unflatten(x, values, slices)
    return [v isa Number ? x[only(s)] : reshape(x[s], size(v)) for (v, s) in zip(values, slices)]
end

"""
    _values(vals) -> Vector

The plain values of parameter values that may carry ForwardDiff duals.
"""
_values(vals) = [ForwardDiff.value.(v) for v in vals]

"""
    _partials(x) -> Matrix

The partials of the ForwardDiff duals `x`, a row per entry and a column per direction.
"""
_partials(x) = stack(ForwardDiff.partials.(x); dims=1)

"""
    _with_partials(x, du, D) -> Vector{D}

The values `x` as duals of type `D`, entry `i` carrying the partials in row `i` of `du`.
"""
_with_partials(x, du, ::Type{D}) where {D} =
    map((xi, row) -> D(xi, ForwardDiff.Partials(Tuple(row))), x, eachrow(du))
