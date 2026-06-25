# twoports.jl -- Shared helpers for hydraulic two-port components

function HydraulicTwoPort(; name, inlet, outlet, eqs, vars=[], pars=[])
    full_eqs = Equation[
        inlet.ṁ + outlet.ṁ ~ 0,
        eqs...,
        outlet.T ~ instream(inlet.T),
        inlet.T ~ instream(outlet.T),
    ]
    return compose(System(full_eqs, t, vars, pars; name=name), inlet, outlet)
end
