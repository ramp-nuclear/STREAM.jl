"""
    _design_knob(name, default) -> Num

Build a single design knob: a `GlobalScope` MTK parameter named `name` with `default`
stored on the symbol. Runs inside the STREAM module so it does not depend on the caller
having `ModelingToolkit` in scope. Use the `@design_knob` macro rather than calling this
directly.
"""
function _design_knob(name::Symbol, default)
    p = ModelingToolkit.toparam(Symbolics.unwrap(Symbolics.variable(name)))
    p = ModelingToolkit.setdefault(p, default)
    return ModelingToolkit.GlobalScope(p)
end

"""
    @design_knob name = default

Declare a design knob, a parameter that can change between solves without recompiling.

A knob is a named scalar input that drives geometry, or any other parameter, across one or
more components, and is varied at solve time through the operating point or `remake`.

The knob is a `GlobalScope` parameter, so the same knob passed into several composed
components stays one un-namespaced parameter at the root system. `remake(name => x)` sets
it once and the change reaches every component that uses it. The default is stored on the
knob; `knob_defaults` gathers it into the operating point so a model runs without the
caller supplying a value.

# Example
```julia
gap = @design_knob gap = 0.0024
geometry = PipeGeometry_rectangular(0.6, 0.067, gap, 0.063)   # build with it, then:
solve_steady(sys, [gap => 0.0027, ...])                       # a new gap, no rebuild
```
See [Scan a design parameter](@ref).

# Returns
Binds `name` in the caller's scope to the knob and returns it.
"""
macro design_knob(ex)
    Meta.isexpr(ex, :(=)) ||
        throw(ArgumentError("@design_knob expects `name = default`, got $(ex)"))
    name, default = ex.args
    name isa Symbol ||
        throw(ArgumentError("@design_knob name must be a symbol, got $(name)"))
    return quote
        $(esc(name)) = $(_design_knob)($(QuoteNode(name)), $(esc(default)))
    end
end

"""
    knob_defaults(knobs) -> Vector{Pair}

Collect each knob's stored default into operating-point pairs. `GlobalScope` parameters
are not auto-applied from symbol metadata at problem build, so a model assembles its
baseline operating point as `[knob_defaults(knobs); state_guesses...]` to run on the
declared defaults with no caller input.

# Arguments
- `knobs`: iterable of design knobs (from `@design_knob`)

# Returns
`Vector{Pair}` mapping each knob to its default value.
"""
knob_defaults(knobs) = Pair[k => ModelingToolkit.getdefault(k) for k in knobs]
