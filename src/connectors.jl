# FlowPort and ThermalPort acausal connectors. The @connector function form lets the
# across-variable initial values (P, ṁ, T) double as overridable keyword arguments.

"""
    FlowPort(; name, P=1.0e5, ṁ=0.0, T=26.85)

Acausal hydraulic connector. `P` is the across (potential) variable, `ṁ` is the flow
variable (sums to zero at a junction), and `T` is a stream variable carried with the flow.

# Arguments
- `name`: connector name (Symbol; supplied by `@named`).
- `p`: pressure [Pa].
- `ṁ`: mass flow rate [kg/s]; positive points into the port.
- `T`: temperature [°C].
"""
@connector function FlowPort(; name, p=1.0e5, ṁ=0.0, T=26.85)
    sts = @variables begin
        p(t) = p, [description = "Pressure (Pa), across variable"]
        ṁ(t) = ṁ,
        [connect = Flow, description = "Mass flow rate (kg/s), positive = into port"]
        T(t) = T, [connect = Stream, description = "Temperature (°C), stream variable"]
    end
    System(Equation[], t, sts, []; name=name)
end

"""
    ThermalPort(; name, T=26.85, Q=0.0)

Acausal thermal connector. `T` is the across (potential) variable and `Q` is the flow
variable (sums to zero at a junction); positive `Q` flows into the component.

# Arguments
- `name`: connector name (Symbol; supplied by `@named`).
- `T`: temperature [°C].
- `Q`: heat flow rate [W].
"""
@connector function ThermalPort(; name, T=26.85, Q=0.0)
    sts = @variables begin
        T(t) = T, [description = "Temperature (°C), across variable"]
        Q(t) = Q,
        [connect = Flow, description = "Heat flow rate (W), positive = into component"]
    end
    System(Equation[], t, sts, []; name=name)
end
