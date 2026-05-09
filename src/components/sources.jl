# sources.jl — WallTemperature and HeatFluxSource value-source components for STREAM.jl
#
# Phase 55 D-04 deliverables. Both are portless "value source" subsystems —
# their job is to expose a vector of plain output variables that other
# systems (typically Channel.T_wall_left[i] / ChannelHeatFlux.q_left[i])
# can bind to via either:
#
#   # Style 1 — direct binding eqns at compose time (args.funcs idiom):
#   connections = [..., [ch.T_wall_left[i] ~ T_wall_value for i in 1:n]...]
#
#   # Style 2 — value-source component:
#   @named wt = WallTemperature(; n=n, T_wall=T_wall_value)
#   connections = [..., [ch.T_wall_left[i] ~ wt.T_wall_out[i] for i in 1:n]...]
#
# The two styles produce identical post-mtkcompile systems; Style 2 is
# preferred for GUI / boxes-and-wires use cases (each "value source" is a
# named subsystem in the compose tree).
#
# Difference from src/components/misc.jl:ConstantTemperature: ConstantTemperature
# is FlowPort-side (single scalar T tied to a stream connector); WallTemperature /
# HeatFluxSource are portless (a vector of plain @variables — no connector).

# Three-branch construction pattern shared by both components, mirroring
# Channel.h_left/h_right resolution at src/components/channels.jl (Phase 54
# D-02) and PointKinetics rho_c_fn pattern at src/components/point_kinetics.jl:225,241
# (RESEARCH.md §1 — verified MTK callable-parameter pattern).

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
function WallTemperature(; name, n::Int, T_wall::Union{Real, AbstractVector{<:Real}, Function})
    @variables (T_wall_out(t))[1:n]

    if T_wall isa Real
        pars = @parameters T_wall_const = T_wall
        eqs = Equation[T_wall_out[i] ~ T_wall_const for i in 1:n]
        return System(eqs, t, [collect(T_wall_out)...], pars; name=name)

    elseif T_wall isa AbstractVector
        length(T_wall) == n ||
            error("WallTemperature: T_wall vector length $(length(T_wall)) ≠ n=$n")
        # Vector-of-Real branch: bake the values into the equations directly
        # (matches Channel.h_left's Vector branch — no @parameters needed).
        eqs = Equation[T_wall_out[i] ~ T_wall[i] for i in 1:n]
        return System(eqs, t, [collect(T_wall_out)...], Num[]; name=name)

    else  # Function / callable — MTK callable-parameter pattern (RESEARCH.md §1)
        FType = typeof(T_wall)
        pT = @parameters (T_wall_fn::FType)(..)
        eqs = Equation[T_wall_out[i] ~ pT[1](t) for i in 1:n]
        # `extra_pars` shape — Vector{Any} because callable-parameter @parameters
        # returns Vector{Symbolics.CallAndWrap{Num}}, not Vector{Num} (Pitfall in
        # RESEARCH.md §6: don't try Vector{Num} for the merged pars list — method error).
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
function HeatFluxSource(; name, n::Int, q::Union{Real, AbstractVector{<:Real}, Function})
    @variables (q_out(t))[1:n]

    if q isa Real
        pars = @parameters q_const = q
        eqs = Equation[q_out[i] ~ q_const for i in 1:n]
        return System(eqs, t, [collect(q_out)...], pars; name=name)

    elseif q isa AbstractVector
        length(q) == n ||
            error("HeatFluxSource: q vector length $(length(q)) ≠ n=$n")
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
