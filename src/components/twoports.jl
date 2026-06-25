# twoports.jl -- Shared helpers for hydraulic two-port components

function HydraulicTwoPort(; name, port_in, port_out, eqs, vars=[], pars=[])
    full_eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        eqs...,
        port_out.T ~ instream(port_in.T),
        port_in.T ~ instream(port_out.T),
    ]
    return compose(System(full_eqs, t, vars, pars; name=name), port_in, port_out)
end
