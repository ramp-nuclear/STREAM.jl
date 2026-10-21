"""
    AbstractArrangement

How the two streams of a heat exchanger run past each other. A subtype has an
[`effectiveness`](@ref) method. [`Counterflow`](@ref) and [`ParallelFlow`](@ref) are provided.
"""
abstract type AbstractArrangement end

"""
    Counterflow()

The two streams enter at opposite ends and run in opposite directions. For the same UA and flows
it transfers more heat than [`ParallelFlow`](@ref).
"""
struct Counterflow <: AbstractArrangement end

"""
    ParallelFlow()

The two streams enter at the same end and run in the same direction (co-current flow).
"""
struct ParallelFlow <: AbstractArrangement end

# An arrangement is a scalar to broadcasting, so `effectiveness.(arr, NTUs, Cr)` works.
Base.broadcastable(arr::AbstractArrangement) = Ref(arr)

"""
    _reversed(arrangement) -> AbstractArrangement

The arrangement a heat exchanger runs in when exactly one of its streams flows backwards:
counterflow becomes parallel flow and the reverse.
"""
_reversed(::Counterflow) = ParallelFlow()
_reversed(::ParallelFlow) = Counterflow()

@doc raw"""
    effectiveness(arrangement, NTU, Cr) -> ε

Heat exchanger effectiveness, the heat transferred as a fraction of the most the two inlet
temperatures allow, ``Q = ε C_{min} (T_{h,in} - T_{c,in})`` [Incropera2007](@cite)
[KaysLondon1984](@cite).

For [`Counterflow`](@ref),

```math
ε = (1 - e^{-N (1 - C_r)}) / (1 - C_r e^{-N (1 - C_r)}), \qquad ε = N / (1 + N) \quad \mathrm{at}\ C_r = 1
```

and for [`ParallelFlow`](@ref),

```math
ε = (1 - e^{-N (1 + C_r)}) / (1 + C_r)
```

At ``C_r = 0``, one stream with an unbounded capacity rate, both reduce to ``1 - e^{-N}``.
The functions trace symbolically, and the counterflow form switches to its ``C_r = 1`` limit
with `ifelse`.

# Arguments
- `arrangement`: [`Counterflow`](@ref) or [`ParallelFlow`](@ref)
- `NTU`: number of transfer units, ``UA / C_{min}``
- `Cr`: capacity rate ratio ``C_{min} / C_{max}``, between 0 and 1

# Returns
The effectiveness ε, between 0 and 1.

# Examples
```jldoctest
julia> HTC.effectiveness(HTC.Counterflow(), 2.0, 0.5)
0.7746003264394359

julia> HTC.effectiveness(HTC.ParallelFlow(), 2.0, 0.5)
0.6334752877547574

julia> HTC.effectiveness(HTC.Counterflow(), 2.0, 1.0)
0.6666666666666666
```
"""
function effectiveness(::Counterflow, NTU, Cr)
    near_one = abs(1 - Cr) < 1e-6
    # The general form is 0/0 at Cr = 1. Both ifelse branches are evaluated, so the one not
    # taken still has to be finite.
    Cr_safe = ifelse(near_one, zero(Cr), Cr)
    x = exp(-NTU * (1 - Cr_safe))
    return ifelse(near_one, NTU / (1 + NTU), (1 - x) / (1 - Cr_safe * x))
end

effectiveness(::ParallelFlow, NTU, Cr) = (1 - exp(-NTU * (1 + Cr))) / (1 + Cr)

@doc raw"""
    flow_scaled_UA(UA0, ṁp0, ṁs0; n=0.8, primary_share=0.5) -> (ṁp, ṁs) -> UA

A UA that follows the flows on both sides, for the two-stream
[`HeatExchanger`](@ref STREAM.Components.HeatExchanger). The two film resistances add in series,
and each film conductance scales with its flow as in turbulent forced convection
[DittusBoelter1930](@cite):

```math
1 / UA = 1 / (hA)_p + 1 / (hA)_s, \qquad (hA)_i = (hA)_{i,0} (|\dot m_i| / \dot m_{i,0})^n
```

The design conductances are set so the result is `UA0` at the design flows, with
`primary_share` of the design resistance ``1 / UA_0`` on the primary side. Near zero flow
``|\dot m|`` is smoothed over 0.1% of the design flow, so the derivative stays finite and a
stagnant side keeps about 0.4% of its design film conductance instead of none.

# Arguments
- `UA0`: overall conductance at the design flows [W/K]
- `ṁp0`, `ṁs0`: primary and secondary design mass flow rates [kg/s]
- `n`: flow exponent of a film conductance (default 0.8)
- `primary_share`: fraction of the design resistance on the primary side, between 0 and 1
  (default 0.5)

# Returns
A closure `(ṁp, ṁs) -> UA` [W/K].

# Examples
```jldoctest
julia> ua = HTC.flow_scaled_UA(1.0e5, 50.0, 80.0);

julia> ua(50.0, 80.0)
100000.0

julia> ua(50.0, 40.0)
72963.43447650553
```
"""
function flow_scaled_UA(UA0, ṁp0, ṁs0; n=0.8, primary_share=0.5)
    0 < primary_share < 1 ||
        throw(ArgumentError("primary_share must be between 0 and 1, got $primary_share"))
    hA_p0 = UA0 / primary_share
    hA_s0 = UA0 / (1 - primary_share)
    # sqrt(ṁ² + δ²) in place of |ṁ|: |ṁ|^n has an infinite slope at zero flow.
    scale(ṁ, ṁ0) = ((ṁ^2 + (1e-3 * ṁ0)^2) / (ṁ0^2 + (1e-3 * ṁ0)^2))^(n / 2)
    return function (ṁp, ṁs)
        hA_p = hA_p0 * scale(ṁp, ṁp0)
        hA_s = hA_s0 * scale(ṁs, ṁs0)
        return hA_p * hA_s / (hA_p + hA_s)
    end
end
