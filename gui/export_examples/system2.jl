using ModelingToolkit, STREAM
using ModelingToolkit: t_nounits as t

@named channelandcontacts_1 = ChannelAndContacts(; n=10, geometry=PipeGeometry_circular(123.0, 123.0))
@named pump_1 = Pump(123.0)

eqs = [
    connect(pump_1.port_out, channelandcontacts_1.port_in),
    connect(channelandcontacts_1.port_out, pump_1.port_in),
    pump_1.port_in.P ~ 100000.0,
]

@named sys = ODESystem(eqs, t; systems=[channelandcontacts_1, pump_1])
ssys = mtkcompile(sys)

# Solve (uncomment to run)
# sol = solve(SteadyStateProblem(ssys, []), DynamicSS(Rodas5P()))