# sources.jl — WallTemperature and HeatFluxSource value-source components for STREAM.jl
#

"""
    WallTemperature(; name, n, T_wall) -> ODESystem

Portless "value source" subsystem exposing per-cell wall temperature outputs
`T_wall_out(t)[1:n]`. Used to drive `Channel.T_wall_left[i]` / `Channel.T_wall_right[i]`
external-input variables (Phase 55 D-04 / D-05 Style 2).

# Arguments
- `name`: system name (Symbol; keyword-only, supplied by `@named`)
- `n`: number of output cells (Int)
- `T_wall`: wall temperature value [K]; one of:
  - `Real`: broadcast — `T_wall_out[i] ~ T_wall` for all `i ∈ 1:n`
  - `AbstractVector{<:Real}` of length `n`: per-cell static profile —
    `T_wall_out[i] ~ T_wall[i]`
  - `Function` (callable `(t) -> K`): time-varying — uses MTK callable-parameter
    pattern; user must supply `wt.T_wall_fn => fn` in solve `op` dict

# Returns
Uncompiled `System` exposing `T_wall_out(t)[1:n]` as the only unknowns. Has
no port subsystems and no Flow / Stream variables. Compose into the parent
system and bind to a consumer's external-input variable via direct binding
equations.

# Example
```julia
@named wt = WallTemperature(; n=10, T_wall=373.15)
connections = [..., [ch.T_wall_left[i] ~ wt.T_wall_out[i] for i in 1:10]...]
```
"""
function WallTemperature(;
    name, n::Int, T_wall::Union{Real,AbstractVector{<:Real},Function}
)
    @variables (T_wall_out(t))[1:n]

    if T_wall isa Real
        pars = @parameters T_wall_const = T_wall
        eqs = Equation[T_wall_out[i] ~ T_wall_const for i in 1:n]
        return System(eqs, t, [collect(T_wall_out)...], pars; name=name)

    elseif T_wall isa AbstractVector
        length(T_wall) == n ||
            throw(DimensionMismatch("T_wall has length $(length(T_wall)), expected n=$n"))
        # Vector-of-Real branch: bake the values into the equations directly
        # (matches Channel.h_left's Vector branch — no @parameters needed).
        eqs = Equation[T_wall_out[i] ~ T_wall[i] for i in 1:n]
        return System(eqs, t, [collect(T_wall_out)...], Num[]; name=name)

    else  # Function / callable — MTK callable-parameter pattern (RESEARCH.md §1)
        FType = typeof(T_wall)
        pT = @parameters (T_wall_fn::FType)(..)
        eqs = Equation[T_wall_out[i] ~ pT[1](t) for i in 1:n]
        pars = Any[collect(pT)...]
        return System(eqs, t, [collect(T_wall_out)...], pars; name=name)
    end
end

"""
    HeatFluxSource(; name, n, q) -> ODESystem

Portless "value source" subsystem exposing per-cell heat flux density outputs
`q_out(t)[1:n]` [W/m^2]. Used to drive `ChannelHeatFlux.q_left[i]` /
`ChannelHeatFlux.q_right[i]` external-input variables (Phase 55 D-04 / D-05 Style 2).

# Arguments
- `name`: system name (Symbol; keyword-only, supplied by `@named`)
- `n`: number of output cells (Int)
- `q`: heat flux density value [W/m^2]; one of:
  - `Real`: broadcast — `q_out[i] ~ q` for all `i ∈ 1:n`
  - `AbstractVector{<:Real}` of length `n`: per-cell static profile —
    `q_out[i] ~ q[i]`
  - `Function` (callable `(t) -> W/m^2`): time-varying — uses MTK callable-parameter
    pattern; user must supply `hfs.q_fn => fn` in solve `op` dict

# Returns
Uncompiled `System` exposing `q_out(t)[1:n]` as the only unknowns. Has no port
subsystems and no Flow / Stream variables.

# Example
```julia
@named hfs = HeatFluxSource(; n=10, q=1.0e5)
connections = [..., [chf.q_left[i] ~ hfs.q_out[i] for i in 1:10]...]
```
"""
function HeatFluxSource(; name, n::Int, q::Union{Real,AbstractVector{<:Real},Function})
    @variables (q_out(t))[1:n]

    if q isa Real
        pars = @parameters q_const = q
        eqs = Equation[q_out[i] ~ q_const for i in 1:n]
        return System(eqs, t, [collect(q_out)...], pars; name=name)

    elseif q isa AbstractVector
        length(q) == n ||
            throw(DimensionMismatch("q has length $(length(q)), expected n=$n"))
        eqs = Equation[q_out[i] ~ q[i] for i in 1:n]
        return System(eqs, t, [collect(q_out)...], Num[]; name=name)

    else  # Function / callable — MTK callable-parameter pattern
        FType = typeof(q)
        pq = @parameters (q_fn::FType)(..)
        eqs = Equation[q_out[i] ~ pq[1](t) for i in 1:n]
        pars = Any[collect(pq)...]
        return System(eqs, t, [collect(q_out)...], pars; name=name)
    end
end
