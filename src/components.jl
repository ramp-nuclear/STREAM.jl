# components.jl — Thermal-hydraulic components for STREAM.jl
#
# Design note (q_wall indirection):
# Channel uses a single ThermalPort carrying total Q_wall (W), then splits
# internally: q_wall[i] = thermal.Q_flow / n per cell. This indirection
# exists so that a future refactor to per-cell ThermalPorts only changes
# the port declaration and q_wall binding — the energy balance loop
# D(T[i]) ~ ... is untouched.
#
# Note: `Channel` is declared as a new generic function here to avoid
# conflict with Base.Channel (Julia's built-in concurrency channel type).

# Declare as new generic functions independent of Base
function Channel end
function Channel(; name, n::Int, L, D, A)
    # Rename plain-Julia D to Dh so it doesn't shadow Differential(t) operator
    Dh = D
    Dt = Differential(t)  # explicit Differential operator (avoids shadowing by D kwarg)

    pars = @parameters begin
        L_ch = L
        D_h  = Dh
        A_ch = A
    end

    vars = @variables begin
        (T(t))[1:n]      = fill(600.0, n)
        (Re(t))[1:n]
        (Nu(t))[1:n]
        (h_tc(t))[1:n]
        (v(t))[1:n]
        (q_wall(t))[1:n]
        T_out(t) = 600.0
        dP(t)
    end

    @named port_in  = FlowPort()
    @named port_out = FlowPort()
    @named thermal  = ThermalPort()

    dz = L / n

    eqs = Equation[]
    T_inlet = instream(port_in.T)

    for i in 1:n
        T_up = (i == 1) ? T_inlet : T[i-1]
        # Energy balance (first-order upwind FV)
        push!(eqs,
            Dt(T[i]) ~ (port_in.mdot * cp_water(T[i]) * (T_up - T[i])
                       + h_tc[i] * (π * Dh) * dz * (thermal.T - T[i]))
                      / (rho_water(T[i]) * cp_water(T[i]) * A * dz)
        )
        # Observables
        push!(eqs, q_wall[i] ~ thermal.Q_flow / n)
        push!(eqs, v[i]      ~ port_in.mdot / (rho_water(T[i]) * A))
        push!(eqs, Re[i]     ~ abs(port_in.mdot) * Dh / (A * mu_water(T[i])))
        push!(eqs, Nu[i]     ~ 0.023 * Re[i]^0.8 *
                                (cp_water(T[i]) * mu_water(T[i]) / k_water(T[i]))^0.4)
        push!(eqs, h_tc[i]  ~ Nu[i] * k_water(T[i]) / Dh)
    end

    # Scalar observables
    i_mid = max(1, n ÷ 2)   # middle cell for mean-property dP
    Re_mean = abs(port_in.mdot) * Dh / (A * mu_water(T[i_mid]))
    f_ch    = 0.3164 * Re_mean^(-0.25)
    push!(eqs, T_out ~ T[n])
    push!(eqs, dP    ~ f_ch * (port_in.mdot * abs(port_in.mdot) /
                                (2 * rho_water(T[i_mid]) * A^2)) * (L / Dh))

    # Port wiring
    push!(eqs, port_in.mdot + port_out.mdot ~ 0)
    push!(eqs, port_out.P - port_in.P ~ -dP)
    push!(eqs, port_out.T ~ T[n])
    push!(eqs, port_in.T  ~ instream(port_out.T))

    all_vars = [collect(T); collect(Re); collect(Nu);
                collect(h_tc); collect(v); collect(q_wall);
                T_out; dP]

    compose(System(eqs, t, all_vars, pars; name=name), port_in, port_out, thermal)
end

function Pump(; name, dP_pump)
    pars = @parameters begin
        dP_pump = dP_pump
    end
    @named port_in  = FlowPort()
    @named port_out = FlowPort()
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        port_out.P - port_in.P ~ dP_pump,
        port_out.T ~ instream(port_in.T),
        port_in.T  ~ instream(port_out.T),
    ]
    compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end

function Friction(; name, L, D, A)
    pars = @parameters begin
        L_f = L
        D_h = D
        A_f = A
    end
    vars = @variables begin
        Re(t)
        f(t)
    end
    @named port_in  = FlowPort()
    @named port_out = FlowPort()
    T_in = instream(port_in.T)
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        Re ~ abs(port_in.mdot) * D / (A * mu_water(T_in)),
        f  ~ 0.3164 * Re^(-0.25),
        port_in.P - port_out.P ~ f * (port_in.mdot * abs(port_in.mdot) /
                                       (2 * rho_water(T_in) * A^2)) * (L / D),
        port_out.T ~ instream(port_in.T),
        port_in.T  ~ instream(port_out.T),
    ]
    compose(System(eqs, t, vars, pars; name=name), port_in, port_out)
end

function Gravity(; name, H, A_grav)
    pars = @parameters begin
        H_grav = H
        A_grav = A_grav
    end
    @named port_in  = FlowPort()
    @named port_out = FlowPort()
    T_in = instream(port_in.T)
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        port_in.P - port_out.P ~ rho_water(T_in) * 9.80665 * H,
        port_out.T ~ instream(port_in.T),
        port_in.T  ~ instream(port_out.T),
    ]
    compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end
