@doc raw"""
    _dual_solution(steady, vals, D) -> NonlinearSolution

The steady state of [`_steady_state`](@ref) with its derivatives attached, for parameter
values `vals` holding ForwardDiff duals of type `D`.

With `p` the parameters set to `vals`, the partials of the residual ``F(u, p)`` are
``∂F/∂p`` along the seeded directions, and ``du/dp = -(∂F/∂u)^{-1} ∂F/∂p``. The solution holds
`u` as duals carrying ``du/dp``, and `p` as given, so anything read off it (an unknown, an
observed variable, a parameter) carries its derivative.
"""
function _dual_solution(steady, vals, ::Type{D}) where {D<:ForwardDiff.Dual}
    (; sol, ∂F∂u) = steady
    prob = sol.prob
    p = steady.setter(prob, vals)
    du = -(∂F∂u \ _partials(_residual(prob, sol.u, p, D)))
    u_dual = _with_partials(sol.u, du, D)
    dual_prob = remake(prob; u0=u_dual, p=p)
    resid = _residual(dual_prob, u_dual, p, D)
    return SciMLBase.build_solution(dual_prob, nothing, u_dual, resid; retcode=ReturnCode.Success)
end

@doc raw"""
    _consistent_start(prob, u0, p, u0_plain, p_plain, solver, abstol, reltol) -> Vector

`u0` with its algebraic states solved for, holding its differential states, and with the
derivatives of both.

The values come from `BrownFullBasicInit` on the plain problem. With ``g`` the algebraic rows
at the first time, ``u_d`` the differential states and ``u_a`` the algebraic ones, the
derivatives of the algebraic states follow from ``g = 0`` as

```math
du_a = -(∂g/∂u_a)^{-1} (∂g/∂u_d \, du_d + ∂g/∂p \, dp)
```

the bracket being the partials of ``g`` at the new values, with ``du_a`` set to zero.
"""
function _consistent_start(prob, u0, p, u0_plain, p_plain, solver, abstol, reltol)
    M = prob.f.mass_matrix
    algebraic = M isa AbstractMatrix ? findall(iszero, diag(M)) : Int[]
    isempty(algebraic) && return u0
    integrator = SciMLBase.init(remake(prob; u0=u0_plain, p=p_plain), solver;
                                initializealg=OrdinaryDiffEq.BrownFullBasicInit(), abstol, reltol)
    plain = integrator.u
    t0 = first(prob.tspan)
    u = copy(u0)
    u[algebraic] .= plain[algebraic]
    r = similar(u)
    prob.f(r, u, p, t0)
    function g(u_a)
        v = convert(Vector{eltype(u_a)}, plain)
        v[algebraic] = u_a
        out = similar(v)
        prob.f(out, v, p_plain, t0)
        return out[algebraic]
    end
    du = -(ForwardDiff.jacobian(g, plain[algebraic]) \ _partials(r[algebraic]))
    u[algebraic] = _with_partials(plain[algebraic], du, eltype(u0))
    return u
end

"""
    _steady_state(ssys, op, parameters; solver=nothing, abstol=1e-10, reltol=1e-10) -> NamedTuple

Solve the steady state of `ssys` at `op` and prepare it for differentiation in `parameters`:
the solution, ``∂F/∂u`` factorized there, the out-of-place parameter setter, the solver
settings, and each parameter's value.

# Throws
- `ErrorException`: when the solve fails, or when ``∂F/∂u`` is singular at its root
"""
function _steady_state(ssys, op, parameters; solver=nothing, abstol=1e-10, reltol=1e-10)
    sol = solve_steady(ssys, op; solver, abstol, reltol)
    SciMLBase.successful_retcode(sol) ||
        error("the steady solve failed with retcode $(sol.retcode), so there is nothing to " *
              "differentiate")
    prob = sol.prob
    ∂F∂u = lu(ForwardDiff.jacobian(u -> _residual(prob, u, prob.p), sol.u); check=false)
    issuccess(∂F∂u) ||
        error("∂F/∂u is singular at the steady state, so the state does not depend smoothly " *
              "on the parameters")
    values = Any[prob.ps[p] for p in parameters]
    return (; sol, ∂F∂u, setter=setp_oop(prob, parameters), solver, abstol, reltol, values)
end

"""
    _residual(prob, u, p, T=eltype(u)) -> Vector{T}

The steady residual ``F(u, p)`` of `prob`, in element type `T`. A `SteadyStateProblem`'s
function takes a time, and root finders call it at `t = Inf`; a root finder hands back its
solution on the `NonlinearProblem` it converted that to, whose function takes none.
"""
function _residual(prob::SciMLBase.SteadyStateProblem, u, p, T=eltype(u))
    du = similar(u, T)
    prob.f(du, u, p, Inf)
    return du
end

function _residual(prob::SciMLBase.NonlinearProblem, u, p, T=eltype(u))
    du = similar(u, T)
    prob.f(du, u, p)
    return du
end

"""
    _resolve(steady, vals) -> Union{SciMLSolution,Nothing}

The steady state at the parameter values `vals`, solved again from the nominal one with the
same solver and tolerances, or `nothing` when that solve fails.
"""
function _resolve(steady, vals)
    (; sol, setter) = steady
    prob = remake(sol.prob; p=setter(sol.prob, vals), u0=sol.u)
    inner = steady.solver isa DynamicSS ? (; odesolve_kwargs=(; dense=false)) : (;)
    sol = solve(prob, steady.solver; steady.abstol, steady.reltol, inner...)
    return SciMLBase.successful_retcode(sol) ? sol : nothing
end

"""
    _integrate(prob, u0, p, t, solver, initializealg, abstol, reltol, callbacks=nothing)

`prob` from `u0` with parameters `p`, stepping onto every saved time as
[`solve_transient`](@ref) does.
"""
function _integrate(prob, u0, p, t, solver, initializealg, abstol, reltol, callbacks=nothing)
    prob = remake(prob; u0, p)
    return solve(prob, solver; saveat=t, initializealg, abstol, reltol, callback=callbacks,
                 _saved_steps(prob, t, (;))...)
end
