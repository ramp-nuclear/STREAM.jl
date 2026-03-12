# MTK connectors for thermal-hydraulic system
# Uses the @connector function syntax required by ModelingToolkit v11

using ModelingToolkit
using ModelingToolkit: t_nounits as t

@connector function FlowPort(; name, P = 1.0e5, mdot = 0.0, T = 300.0)
    sts = @variables begin
        P(t) = P, [description = "Pressure (Pa), across variable"]
        mdot(t) = mdot, [connect = Flow, description = "Mass flow rate (kg/s), positive = into port"]
        T(t) = T, [connect = Stream, description = "Temperature (K), stream variable"]
    end
    System(Equation[], t, sts, []; name = name)
end

@connector function ThermalPort(; name, T = 300.0, Q_flow = 0.0)
    sts = @variables begin
        T(t) = T, [description = "Temperature (K), across variable"]
        Q_flow(t) = Q_flow, [connect = Flow, description = "Heat flow rate (W), positive = into component"]
    end
    System(Equation[], t, sts, []; name = name)
end
