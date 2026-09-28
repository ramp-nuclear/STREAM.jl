function assembly(connections, components...; name, t=ModelingToolkit.t_nounits)
    eqs = Equation[]
    for c in connections
        append!(eqs, normalize_eqs(c))
    end
    sys = System(eqs, t, name=name)
    compose(sys, components...)
end

normalize_eqs(x::Equation) = [x] 
normalize_eqs(x::Vector{Equation}) = x
normalize_eqs(x::Symbolics.Arr{Any, 1}) = collect(x)