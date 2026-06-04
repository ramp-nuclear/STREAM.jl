# FlowPort and ThermalPort acausal connectors. The @connector function form lets the
# across-variable initial values (P, mdot, T) double as overridable keyword arguments.

"""
    FlowPort(; name, P=1.0e5, mdot=0.0, T=300.0)

Acausal hydraulic connector. `P` is the across (potential) variable, `mdot` is the flow
variable (sums to zero at a junction), and `T` is a stream variable carried with the flow.

# Arguments
- `name`: connector name (Symbol; supplied by `@named`).
- `P`: initial pressure [Pa].
- `mdot`: initial mass flow rate [kg/s]; positive points into the port.
- `T`: initial temperature [K].
"""
@connector function FlowPort(; name, P=1.0e5, mdot=0.0, T=300.0)
    sts = @variables begin
        P(t) = P, [description = "Pressure (Pa), across variable"]
        mdot(t) = mdot,
        [connect = Flow, description = "Mass flow rate (kg/s), positive = into port"]
        T(t) = T, [connect = Stream, description = "Temperature (K), stream variable"]
    end
    System(Equation[], t, sts, []; name=name)
end

"""
    ThermalPort(; name, T=300.0, Q_flow=0.0)

Acausal thermal connector. `T` is the across (potential) variable and `Q_flow` is the flow
variable (sums to zero at a junction); positive `Q_flow` flows into the component.

# Arguments
- `name`: connector name (Symbol; supplied by `@named`).
- `T`: initial temperature [K].
- `Q_flow`: initial heat flow rate [W].
"""
@connector function ThermalPort(; name, T=300.0, Q_flow=0.0)
    sts = @variables begin
        T(t) = T, [description = "Temperature (K), across variable"]
        Q_flow(t) = Q_flow,
        [connect = Flow, description = "Heat flow rate (W), positive = into component"]
    end
    System(Equation[], t, sts, []; name=name)
end
