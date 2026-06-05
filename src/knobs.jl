# knobs.jl -- design knobs for parametric model authoring

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

Declare a design knob: a named scalar input that drives geometry (or any other parameter)
across one or more components and can be varied at solve time with `remake`, without
rebuilding or recompiling the model.

The knob is a `GlobalScope` parameter, so the same knob passed into several composed
components stays one un-namespaced parameter at the root system. `remake(name => x)` sets
it once and the change reaches every component that uses it. The default is stored on the
knob; `knob_defaults` gathers it into the operating point so a model runs without the
caller supplying a value.

# Example
```julia
outer_d = @design_knob outer_d = 0.02      # annulus outer / channel inner [m]
@named ch = CoolantChannel(outer_d)         # same knob into both components
@named hd = FuelAnnulus(outer_d)
# ... compose, mtkcompile, build a SteadyStateProblem ...
remake(prob; p = [outer_d => 0.025])        # scan one knob, no rebuild
```

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
