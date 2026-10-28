"""
    assembly(connections, components...; name, parameters=[], t=t_nounits) -> System

Compose `components` into one system joined by `connections`.

`connections` may nest freely: a list can hold single equations next to the vectors
[`inseries`](@ref STREAM.Assemblies.Connect.inseries),
[`inparallel`](@ref STREAM.Assemblies.Connect.inparallel),
[`face`](@ref STREAM.Assemblies.Connect.face) and
[`faces`](@ref STREAM.Assemblies.Connect.faces) return, and broadcast equations such as
`ch.T_wall_left .~ T_wall`, with no splatting.

# Arguments
- `connections`: an `Equation`, or any vector or tuple of equations and nested collections
  of them
- `components`: the uncompiled systems to compose

# Keywords
- `name`: required, the system name. `@named sys = assembly(...)` supplies it.
- `parameters`: parameters the connections do not mention but the model needs, such as one
  a callback reads
- `t`: the independent variable

# Returns
Uncompiled `System`, ready for `mtkcompile`.

# Example
```julia
conns = [
    inseries(pump, hx, ch, pump),
    pump.inlet.p ~ 1.0e5,
    ch.T_wall_left .~ 100.0,
]
@named sys = assembly(conns, pump, hx, ch)
```
"""
function assembly(connections, components...; name, parameters=[],
                  t=ModelingToolkit.t_nounits)
    eqs = _flatten_eqs!(Equation[], connections)
    sys = isempty(parameters) ? System(eqs, t; name=name) :
          System(eqs, t, [], parameters; name=name)
    return compose(sys, components...)
end

"""
    @assembly name begin ... end [keyword=value ...]

Build the components and connections in the block, compose them with [`assembly`](@ref),
compile the result and assign it to `name`, a system named `name`.

Each line of the block is one of:

- an assignment, `pump = Pump(3.0e4)`. When the function called takes a `name` keyword it
  gets `name=:pump`, as `@named` gives it; otherwise, as in `geom = Duct(...)`, the line
  runs as written. The variable is set in the scope around the block, so `pump` can be used
  after it.
- a connection: an equation, a broadcast equation, or a call that returns equations, such as
  `inseries(...)` or `pump.inlet.p ~ 1.0e5`.
- a system, or a vector or tuple of systems, on its own, to compose one no connection
  mentions.

The components are the systems the connections mention and the ones listed on their own,
whether built in the block or before it. A system used only to build another one, such as a
channel handed to [`symmetric_plate`](@ref STREAM.Assemblies.symmetric_plate), is part of
that one and is not composed again.

# Keywords
- `parameters`, `t`: passed to [`assembly`](@ref)
- any other, such as `fully_determined=false`: passed to `mtkcompile`

# Returns
The compiled `System`, also assigned to `name`.

# Example
```julia
@assembly loop begin
    pump = Pump(3.0e4)
    hx = HeatExchanger(40.0)
    ch = Channel(; n=10, geometry=Duct(0.6, Circular(0.01)), h=5000.0)
    inseries(pump, hx, ch, pump)
    pump.inlet.p ~ 1.0e5
    ch.T_wall_outer .~ 100.0
end
solve_steady(loop)[loop.ch.inlet.ṁ]
```
"""
macro assembly(name::Symbol, block::Expr, kwargs...)
    Meta.isexpr(block, :block) ||
        throw(ArgumentError("@assembly takes a name and a begin ... end block"))
    body, parts, lines, mentioned = Any[], Symbol[], String[], Symbol[]
    for ex in block.args
        if ex isa LineNumberNode || Meta.isexpr(ex, :macrocall)
            push!(body, ex)
        elseif Meta.isexpr(ex, :(=)) && first(ex.args) isa Symbol
            push!(body, _auto_named(ex))
        else
            part = gensym(:part)
            push!(body, :($part = $ex))
            push!(parts, part)
            push!(lines, string(ex))
            _mentions!(mentioned, ex)
        end
    end
    # A name a comprehension binds is not defined outside it, and contributes nothing.
    found = [:($(Expr(:isdefined, s)) ? $s : nothing) for s in unique(mentioned)]
    all(ex -> Meta.isexpr(ex, :(=)), kwargs) ||
        throw(ArgumentError("@assembly takes keywords after the block as `key=value`"))
    keywords = [Expr(:kw, ex.args...) for ex in kwargs]
    call = :($_assemble($(QuoteNode(name)), Any[$(parts...)], $lines, Any[$(found...)];
                        $(keywords...)))
    return esc(Expr(:block, body..., :($name = $call)))
end

"""
    _auto_named(ex) -> Expr

The assignment `x = f(args...)` rewritten to call `f` through [`_named_call`](@ref), which
passes `name=:x` when `f` takes it. Any other assignment, and a call already given a `name`,
is returned as is.
"""
function _auto_named(ex)
    lhs, rhs = ex.args
    Meta.isexpr(rhs, :call) || return ex
    f, args = first(rhs.args), rhs.args[2:end]
    params = filter(a -> Meta.isexpr(a, :parameters), args)
    rest = filter(a -> !Meta.isexpr(a, :parameters), args)
    names(a) = a === :name || (Meta.isexpr(a, :kw) && first(a.args) === :name)
    any(names, [rest; (p.args for p in params)...]) && return ex
    return :($lhs = $(Expr(:call, _named_call, params..., f, QuoteNode(lhs), rest...)))
end

"""
    _named_call(f, name, args...; kwargs...)

`f(args...; kwargs..., name)` when `f` has a method for `args` that takes a `name` keyword,
and `f(args...; kwargs...)` otherwise.
"""
function _named_call(f, name, args...; kwargs...)
    hasmethod(f, typeof(args), (:name,)) || return f(args...; kwargs...)
    return f(args...; kwargs..., name)
end

"""
    _mentions!(names, ex) -> Vector{Symbol}

Append to `names` every variable `ex` reads: the root of a property access `a.b.c`, and
every symbol outside keyword names and quoted ones. `begin`, `end` and `_` are left out:
they are not variables.
"""
function _mentions!(names, ex::Symbol)
    (ex in (:begin, :end) || all(==('_'), string(ex))) && return names
    return push!(names, ex)
end
function _mentions!(names, ex::Expr)
    if Meta.isexpr(ex, :.) && last(ex.args) isa QuoteNode
        _mentions!(names, first(ex.args))
    elseif Meta.isexpr(ex, :kw)
        _mentions!(names, last(ex.args))
    else
        foreach(a -> _mentions!(names, a), ex.args)
    end
    return names
end
_mentions!(names, _) = names

"""
    _assemble(name, parts, lines, mentioned; parameters=[], t, kwargs...) -> System

The system [`@assembly`](@ref) builds. `parts` are the values of the block's lines that are
not assignments, `lines` their source, and `mentioned` the values of the variables those
lines read. Systems among `parts` and `mentioned` are composed, except a subsystem reached
through its parent, and every other part is a connection. `kwargs` go to `mtkcompile`.
"""
function _assemble(name, parts, lines, mentioned; parameters=[],
                   t=ModelingToolkit.t_nounits, kwargs...)
    connections = Any[]
    for (part, line) in zip(parts, lines)
        (isnothing(part) || _holds_systems(part)) && continue
        _holds_equations(part) || throw(ArgumentError(
            "the line `$line` gives a $(typeof(part)), not equations or systems; " *
            "put it before the @assembly block"))
        push!(connections, part)
    end
    found = filter(_holds_systems, [parts; mentioned])
    systems = unique(objectid, mapreduce(_systems, vcat, found; init=Any[]))
    # A subsystem reached through its parent, `rods.cac`, carries the parent's namespace.
    nested(s) = occursin(ModelingToolkit.NAMESPACE_SEPARATOR, string(nameof(s)))
    top = filter(!nested, systems)
    return mtkcompile(assembly(connections, top...; name, parameters, t); kwargs...)
end

"""
    _systems(x) -> Vector

The systems in `x`, a system or an array or tuple of them.
"""
_systems(x::ModelingToolkit.AbstractSystem) = Any[x]
_systems(xs) = collect(Any, xs)

"""
    _holds_systems(x) -> Bool

Whether `x` is a system or a non-empty array or tuple of systems.
"""
_holds_systems(x) = x isa ModelingToolkit.AbstractSystem ||
    (x isa Union{AbstractArray,Tuple} && !isempty(x) && all(_holds_systems, x))

"""
    _holds_equations(x) -> Bool

Whether `x` is an equation, a symbolic array of them, or a collection holding only those.
"""
_holds_equations(::Equation) = true
_holds_equations(::ModelingToolkit.Symbolics.Arr) = true
_holds_equations(x::Union{AbstractArray,Tuple}) = all(_holds_equations, x)
_holds_equations(_) = false

"""
    _flat(xs...) -> Vector{Equation}

Every equation in `xs`, in order, however they nest: single equations, vectors and tuples of
them, and the symbolic arrays a broadcast `.~` over a symbolic array gives.
"""
_flat(xs...) = _flatten_eqs!(Equation[], xs)

"""
    _flatten_eqs!(eqs, x) -> Vector{Equation}

Append every equation in `x` to `eqs`, descending into vectors, tuples and symbolic arrays.
"""
_flatten_eqs!(eqs, x::Equation) = push!(eqs, x)
# Iterating a symbolic array yields bare symbolic terms; scalarize materialises the equations.
_flatten_eqs!(eqs, x::ModelingToolkit.Symbolics.Arr) = _flatten_eqs!(eqs, scalarize(x))
function _flatten_eqs!(eqs, x::Union{AbstractArray,Tuple})
    foreach(e -> _flatten_eqs!(eqs, e), x)
    return eqs
end
_flatten_eqs!(eqs, x) = throw(ArgumentError("expected an equation or a collection of them, got $(typeof(x))"))
