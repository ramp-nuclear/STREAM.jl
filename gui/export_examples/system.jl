using ModelingToolkit, STREAM
using ModelingToolkit: t_nounits as t

@named channel_1 = Channel()
@named pump_1 = Pump()

eqs = [
    connect(channel_1.port_out, pump_1.port_in),
    connect(pump_1.port_out, channel_1.port_in),
]

@named sys = ODESystem(eqs, t; systems=[channel_1, pump_1])
ssys = mtkcompile(sys)

# Solve (uncomment to run)
# sol = solve(SteadyStateProblem(ssys, []), DynamicSS(Rodas5P()))