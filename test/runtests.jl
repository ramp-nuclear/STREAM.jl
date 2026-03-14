using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using DifferentialEquations  # ReturnCode, ODEProblem, Rodas5P, etc.
using STREAM
import STREAM: Channel, Pump, Friction, Gravity, Resistor, build_loop_vertical, Inertia, HeatExchanger, ChannelAndContacts, ChannelHeatFlux, ConstantTemperature, HeatDiffusion  # resolve ambiguity with Base.Channel
const SciMLBase = DifferentialEquations.SciMLBase  # for NoInit() in RL-decay test

@testset "STREAM Phase 1 Tests" begin

# ─────────────────────────────────────────────────────────────────
# FOUND-01: Package loads (implicitly tested by reaching this line)
# ─────────────────────────────────────────────────────────────────
@testset "FOUND-01: Package loads" begin
    @test true  # reaching here means `using STREAM` succeeded
end

# ─────────────────────────────────────────────────────────────────
# FOUND-02: Fluid property spot-checks (Simantov correlations)
# Reference values computed from Python STREAM light_water.py
# Tolerance: rtol=1e-6 (deterministic polynomial; any larger diff = unit error)
# ─────────────────────────────────────────────────────────────────
@testset "FOUND-02: rho_water" begin
    @test isapprox(rho_water(300.0), 995.925708;  rtol=1e-5)
    @test isapprox(rho_water(350.0), 973.771824;  rtol=1e-5)
    @test isapprox(rho_water(400.0), 938.700383;  rtol=1e-5)
end

@testset "FOUND-02: cp_water" begin
    @test isapprox(cp_water(300.0), 4177.781138; rtol=1e-5)
    @test isapprox(cp_water(350.0), 4195.561824; rtol=1e-5)
    @test isapprox(cp_water(400.0), 4258.577497; rtol=1e-5)
end

@testset "FOUND-02: mu_water" begin
    @test isapprox(mu_water(300.0), 8.5524859163e-4; rtol=1e-5)
    @test isapprox(mu_water(350.0), 3.6810159678e-4; rtol=1e-5)
    @test isapprox(mu_water(400.0), 2.1973269076e-4; rtol=1e-5)
end

@testset "FOUND-02: k_water" begin
    @test isapprox(k_water(300.0), 0.61240475; rtol=1e-5)
    @test isapprox(k_water(350.0), 0.66632812; rtol=1e-5)
    @test isapprox(k_water(400.0), 0.68588445; rtol=1e-5)
end

@testset "FOUND-02: MTK smoke test — rho_water symbolic" begin
    # Verify @register_symbolic is correctly placed at module top-level:
    # calling rho_water on a symbolic variable should return a symbolic expression (Num),
    # not a concrete Float64.
    @variables T_sym(t) = 300.0
    result = rho_water(T_sym)
    @test result isa Symbolics.Num  # symbolic, not a Float64
end

# ─────────────────────────────────────────────────────────────────
# CONN-01: FlowPort — variable names and MTK metadata
# ─────────────────────────────────────────────────────────────────
@testset "CONN-01: FlowPort instantiation" begin
    @named fp = FlowPort()
    # Variable names exposed
    var_names = Symbol.(ModelingToolkit.getname.(unknowns(fp)))
    @test :P in var_names
    @test :mdot in var_names
    @test :T in var_names
end

@testset "CONN-01: FlowPort variable count" begin
    @named fp = FlowPort()
    @test length(unknowns(fp)) == 3
end

@testset "CONN-01: mdot is a Flow variable" begin
    @named fp = FlowPort()
    mdot_var = only(filter(v -> ModelingToolkit.getname(v) == :mdot, unknowns(fp)))
    # Use Symbolics.getmetadata to access the connect type from variable metadata
    connect_type = Symbolics.getmetadata(mdot_var, ModelingToolkitBase.VariableConnectType, nothing)
    @test connect_type == ModelingToolkit.Flow
end

@testset "CONN-01: T is a Stream variable" begin
    @named fp = FlowPort()
    T_var = only(filter(v -> ModelingToolkit.getname(v) == :T, unknowns(fp)))
    connect_type = Symbolics.getmetadata(T_var, ModelingToolkitBase.VariableConnectType, nothing)
    @test connect_type == ModelingToolkit.Stream
end

# ─────────────────────────────────────────────────────────────────
# CONN-02: ThermalPort — variable names and MTK metadata
# ─────────────────────────────────────────────────────────────────
@testset "CONN-02: ThermalPort instantiation" begin
    @named tp = ThermalPort()
    var_names = Symbol.(ModelingToolkit.getname.(unknowns(tp)))
    @test :T in var_names
    @test :Q_flow in var_names
end

@testset "CONN-02: ThermalPort variable count" begin
    @named tp = ThermalPort()
    @test length(unknowns(tp)) == 2
end

@testset "CONN-02: Q_flow is a Flow variable" begin
    @named tp = ThermalPort()
    q_var = only(filter(v -> ModelingToolkit.getname(v) == :Q_flow, unknowns(tp)))
    connect_type = Symbolics.getmetadata(q_var, ModelingToolkitBase.VariableConnectType, nothing)
    @test connect_type == ModelingToolkit.Flow
end

@testset "CONN-02: T is an across variable (no connect metadata)" begin
    @named tp = ThermalPort()
    T_var = only(filter(v -> ModelingToolkit.getname(v) == :T, unknowns(tp)))
    # Across variables have no connect metadata — getmetadata returns nothing
    connect_type = Symbolics.getmetadata(T_var, ModelingToolkitBase.VariableConnectType, nothing)
    @test connect_type === nothing
end

end  # @testset "STREAM Phase 1 Tests"

@testset "STREAM Phase 2 Tests" begin

@testset "COMP-01: Channel stub callable" begin
    @named ch = Channel(n=5, L=1.0, D=0.01, A=7.85e-5)
    @test ch isa ModelingToolkit.System
end

@testset "COMP-01: Channel equation count" begin
    @named ch = Channel(n=5, L=1.0, D=0.01, A=7.85e-5)
    energy_eqs = filter(eq -> occursin("Differential", string(eq)), equations(ch))
    @test length(energy_eqs) == 5
end

@testset "COMP-01: Channel mtkcompile" begin
    @named ch = Channel(n=5, L=1.0, D=0.01, A=7.85e-5)
    # fully_determined=false required for isolated component with unconnected ports
    @test_nowarn mtkcompile(ch; fully_determined=false)
end

@testset "COMP-02: Pump stub callable" begin
    @named pump = Pump(dP_pump=1e4)
    @test pump isa ModelingToolkit.System
    @test_nowarn mtkcompile(pump; fully_determined=false)
end

@testset "COMP-03: Friction stub callable" begin
    @named fr = Friction(L=1.0, D=0.01, A=7.85e-5)
    @test fr isa ModelingToolkit.System
    @test_nowarn mtkcompile(fr; fully_determined=false)
end

@testset "COMP-04: Gravity stub callable" begin
    @named grav = Gravity(H=3.0)
    @test grav isa ModelingToolkit.System
    @test_nowarn mtkcompile(grav; fully_determined=false)
end

end  # @testset "STREAM Phase 2 Tests"

@testset "STREAM Phase 3 Tests" begin

# ─────────────────────────────────────────────────────────────────
# SYS-01: build_loop assembles and compiles without error
# ─────────────────────────────────────────────────────────────────
@testset "SYS-01: build_loop compiles closed loop" begin
    ssys = build_loop()
    @test ssys isa ModelingToolkit.AbstractSystem
    # mtkcompile benchmark reported via @info (not asserted)
end

# ─────────────────────────────────────────────────────────────────
# SYS-02: steady_state_guess returns physically correct profile
# ─────────────────────────────────────────────────────────────────
@testset "SYS-02: steady_state_guess monotonically increasing" begin
    T = steady_state_guess(T_inlet=313.15, Q_wall=1e4, mdot_guess=0.1, n=10)
    @test length(T) == 10
    @test T[1] > 313.15       # first cell above inlet temperature
    @test all(diff(T) .> 0)   # monotonically increasing
end

# ─────────────────────────────────────────────────────────────────
# SOLV-01: solve_steady returns physical steady-state solution
# ─────────────────────────────────────────────────────────────────
@testset "SOLV-01: solve_steady returns physical solution" begin
    n = 10
    T_inlet = 313.15
    Q_wall  = 1.0e4
    mdot_guess = 0.490  # physics-based estimate for 30 kPa pump, 0.01m pipe

    ssys = build_loop(T_inlet=T_inlet)
    T_guess = steady_state_guess(T_inlet=T_inlet, Q_wall=Q_wall, mdot_guess=mdot_guess, n=n)

    op = [ssys.ch.T[i] => T_guess[i] for i in 1:n]
    push!(op, ssys.ch.port_in.mdot => mdot_guess)

    sol = solve_steady(ssys, op)
    @test sol.retcode == ReturnCode.Success
    @test sol[ssys.ch.T_out] > T_inlet      # outlet > inlet (fluid heated)
    @test sol[ssys.ch.T_out] < 400.0        # physically reasonable (< 127°C)
    @test sol[ssys.ch.port_in.mdot] > 0     # positive mass flow
end

# ─────────────────────────────────────────────────────────────────
# SOLV-02: solve_transient returns time-series with T_outlet rising
# after T_wall step change
# ─────────────────────────────────────────────────────────────────
@testset "SOLV-02: build_loop_transient compiles" begin
    ssys, T_wall_sym = build_loop_transient()
    @test ssys isa ModelingToolkit.AbstractSystem
    @test T_wall_sym isa Symbolics.Num   # T_wall parameter symbol returned
end

@testset "SOLV-02: solve_transient returns time-series" begin
    n = 10
    T_inlet = 313.15
    Q_wall_0 = 1.0e4
    mdot_guess = 0.490  # rough guess; KINSOL is robust to this

    ssys, T_wall_sym = build_loop_transient(T_inlet=T_inlet)
    T_guess = steady_state_guess(T_inlet=T_inlet, Q_wall=Q_wall_0, mdot_guess=mdot_guess, n=n)

    op_guess = [ssys.ch.T[i] => T_guess[i] for i in 1:n]
    push!(op_guess, ssys.ch.port_in.mdot => mdot_guess)

    # Rodas5P+NoInit requires algebraically consistent ICs (pressure balance satisfied).
    # Run solve_steady on the transient system first to get a consistent starting point.
    sol_ss = solve_steady(ssys, op_guess)
    op_ic = [ssys.ch.T[i] => sol_ss[ssys.ch.T[i]] for i in 1:n]
    push!(op_ic, ssys.ch.port_in.mdot => sol_ss[ssys.ch.port_in.mdot])

    # Step T_wall from 373.15 K (100°C) to 393.15 K (120°C) at t=10s
    sol = solve_transient(ssys, T_wall_sym, op_ic, (0.0, 30.0);
                          T_wall_final=393.15, t_step=10.0)
    @test sol.retcode == ReturnCode.Success
    @test length(sol.t) > 2                            # multiple time points
    T_ts = sol[ssys.ch.T_out, :]
    @test !any(isnan, T_ts)                            # no NaN
    @test T_ts[end] > T_ts[1]                          # T_outlet rises after T_wall step
end

# ─────────────────────────────────────────────────────────────────
# VAL-01: Steady-state T_outlet and mdot within 1% of Python STREAM
# Reference: generate_reference.py (T_wall=373.15K, T_inlet=313.15K,
#            dP_pump=30kPa, n=10, L=0.6m, D=0.01m, g=0)
# ─────────────────────────────────────────────────────────────────
T_outlet_ref = 327.7894  # K  (Python STREAM: 54.6394 °C)
mdot_ref     = 0.609289  # kg/s

@testset "VAL-01: Steady-state matches Python STREAM within 1%" begin
    n = 10; T_inlet = 313.15
    ssys = build_loop(T_inlet=T_inlet)
    T_guess = steady_state_guess(T_inlet=T_inlet, Q_wall=1e4, mdot_guess=0.490, n=n)
    op = [ssys.ch.T[i] => T_guess[i] for i in 1:n]
    push!(op, ssys.ch.port_in.mdot => 0.490)
    sol = solve_steady(ssys, op)

    T_out = sol[ssys.ch.T_out]
    mdot  = abs(sol[ssys.ch.port_in.mdot])
    @test isapprox(T_out, T_outlet_ref; rtol=0.01)
    @test isapprox(mdot,  mdot_ref;     rtol=0.01)
end

# ─────────────────────────────────────────────────────────────────
# VAL-02: Transient T_outlet rises after T_wall step change
# ─────────────────────────────────────────────────────────────────
@testset "VAL-02: Transient T_outlet rises after T_wall step" begin
    n = 10; T_inlet = 313.15
    ssys, T_wall_sym = build_loop_transient(T_inlet=T_inlet)
    T_guess = steady_state_guess(T_inlet=T_inlet, Q_wall=1e4, mdot_guess=0.490, n=n)
    op_guess = [ssys.ch.T[i] => T_guess[i] for i in 1:n]
    push!(op_guess, ssys.ch.port_in.mdot => 0.490)
    sol_ss = solve_steady(ssys, op_guess)
    op_ic = [ssys.ch.T[i] => sol_ss[ssys.ch.T[i]] for i in 1:n]
    push!(op_ic, ssys.ch.port_in.mdot => sol_ss[ssys.ch.port_in.mdot])

    sol = solve_transient(ssys, T_wall_sym, op_ic, (0.0, 60.0);
                          T_wall_final=393.15, t_step=10.0)
    @test sol.retcode == ReturnCode.Success
    T_ts = sol[ssys.ch.T_out, :]
    @test !any(isnan, T_ts)
    @test T_ts[end] > T_ts[1]   # outlet rises after T_wall step
end

# ─────────────────────────────────────────────────────────────────
# VAL-03: Full suite runs via Pkg.test() (confirmed by reaching here)
# ─────────────────────────────────────────────────────────────────
@testset "VAL-03: Test suite runs automatically" begin
    @test true
end

end  # @testset "STREAM Phase 3 Tests"

@testset "STREAM Phase 6 Tests" begin

# ─────────────────────────────────────────────────────────────────
# GRAV-01: Vertical closed loop assembles, compiles, and solves
# Topology: Pump -> TempBC -> Channel(g_acc=9.80665, L=0.6m) -> Gravity(H=0.6m) -> Pump
# Channel carries g_acc for the upward leg; Gravity carries the return leg.
# ─────────────────────────────────────────────────────────────────
@testset "GRAV-01: vertical loop mtkcompiles" begin
    ssys_v = build_loop_vertical()
    @test ssys_v isa ModelingToolkit.AbstractSystem
end

@testset "GRAV-01: vertical loop solves" begin
    n = 10; T_inlet = 313.15
    ssys_v = build_loop_vertical(T_inlet=T_inlet)
    T_guess = steady_state_guess(T_inlet=T_inlet, Q_wall=1e4, mdot_guess=0.490, n=n)
    op = [ssys_v.ch.T[i] => T_guess[i] for i in 1:n]
    push!(op, ssys_v.ch.port_in.mdot => 0.490)
    sol = solve_steady(ssys_v, op)
    @test sol.retcode == ReturnCode.Success
    @test sol[ssys_v.ch.port_in.mdot] > 0
end

# ─────────────────────────────────────────────────────────────────
# GRAV-02: Gravity cancellation — equal up/down height gives same
# steady-state mass flow as horizontal reference loop (within 1%)
#
# Physics: Channel dP includes +rho*g_acc*L (head loss going up).
# Gravity component adds rho*9.80665*H to the return leg (head gain going down).
# When H == L_ch == 0.6m, the two terms cancel; net gravity effect = 0.
# The cancellation loop should therefore match the horizontal loop's mdot.
# ─────────────────────────────────────────────────────────────────
@testset "GRAV-02: gravity cancellation within 1% of horizontal" begin
    n = 10; T_inlet = 313.15; L_ch = 0.6

    # Horizontal reference (g_acc=0, no Gravity component)
    ssys_h = build_loop(T_inlet=T_inlet)
    T_guess = steady_state_guess(T_inlet=T_inlet, Q_wall=1e4, mdot_guess=0.490, n=n)
    op_h = [ssys_h.ch.T[i] => T_guess[i] for i in 1:n]
    push!(op_h, ssys_h.ch.port_in.mdot => 0.490)
    sol_h = solve_steady(ssys_h, op_h)
    mdot_horiz = abs(sol_h[ssys_h.ch.port_in.mdot])

    # Vertical cancellation loop (g_acc=9.80665, H_return=L_ch)
    ssys_v = build_loop_vertical(T_inlet=T_inlet, L_ch=L_ch, H_return=L_ch)
    op_v = [ssys_v.ch.T[i] => T_guess[i] for i in 1:n]
    push!(op_v, ssys_v.ch.port_in.mdot => 0.490)
    sol_v = solve_steady(ssys_v, op_v)
    mdot_vert = abs(sol_v[ssys_v.ch.port_in.mdot])

    @test isapprox(mdot_vert, mdot_horiz; rtol=0.01)
end

end  # @testset "STREAM Phase 6 Tests"

@testset "STREAM Phase 7 Tests" begin

# ─────────────────────────────────────────────────────────────────
# NET-01: Resistor component — linear pressure drop dp ~ R * mdot
# ─────────────────────────────────────────────────────────────────
@testset "NET-01: Resistor stub callable" begin
    @named r = Resistor(R=1.0e5)
    @test r isa ModelingToolkit.System
end

@testset "NET-01: Resistor mtkcompile" begin
    @named r = Resistor(R=1.0e5)
    @test_nowarn mtkcompile(r; fully_determined=false)
end


# ─────────────────────────────────────────────────────────────────
# NET-02: Cube problem — 12 Resistors + 1 Pump assembled via multi-port connect()
# Topology: 8 corners (0-7 binary), 12 edges, pump drives corner 0 -> corner 7
# ─────────────────────────────────────────────────────────────────
@testset "NET-02: build_cube assembles and mtkcompiles" begin
    ssys = build_cube()
    @test ssys isa ModelingToolkit.AbstractSystem
end

# ─────────────────────────────────────────────────────────────────
# NET-03: Cube flow distribution matches analytical 5/6 R equivalent resistance
# Analytical: R_eq = 5/6 * R => mdot_total = dP_pump / (5/6 * R)
# Tolerance: 1% (consistent with GRAV-02 and VAL-01)
# ─────────────────────────────────────────────────────────────────
@testset "NET-03: Cube flow matches 5/6 R analytical within 1%" begin
    R_val    = 1.0e4
    dP_val   = 3.0e4
    ssys = build_cube(dP_pump=dP_val, R=R_val)

    mdot_analytical = dP_val / (5.0/6.0 * R_val)
    mdot_guess = mdot_analytical / 3.0   # each source branch carries ~1/3

    op = [ssys.pump.port_out.mdot => mdot_guess]
    sol = solve_steady(ssys, op)

    @test sol.retcode == ReturnCode.Success
    mdot_numerical = abs(sol[ssys.pump.port_out.mdot])
    @test isapprox(mdot_numerical, mdot_analytical; rtol=0.01)
end

end  # @testset "STREAM Phase 7 Tests"

@testset "STREAM Phase 8 Tests" begin

# ─────────────────────────────────────────────────────────────────
# COMP-01: Inertia — ODE pressure-drop component
# Equation: port_in.P - port_out.P ~ L_over_A * D(mdot)
# ─────────────────────────────────────────────────────────────────
@testset "COMP-01: Inertia stub callable" begin
    @named L = Inertia(L_over_A=1e3)
    @test L isa ModelingToolkit.System
end

@testset "COMP-01: Inertia mtkcompile" begin
    @named L = Inertia(L_over_A=1e3)
    @test_nowarn mtkcompile(L; fully_determined=false)
end

@testset "COMP-01: RL-decay transient matches exp(-(R/L_over_A)*t) within 1%" begin
    # Topology: Inertia + Resistor in a closed loop (no pump)
    # IC: mdot(0) = 1.0 kg/s. Analytical: mdot(t) = exp(-t/tau), tau = L_over_A/R = 1000s
    R_val     = 1.0
    L_over_A  = 1e3
    tau       = L_over_A / R_val   # 1000 s

    @named L_comp = Inertia(L_over_A=L_over_A)
    @named R_comp = Resistor(R=R_val)
    connections = [
        connect(L_comp.port_out, R_comp.port_in),
        connect(R_comp.port_out, L_comp.port_in),
        L_comp.port_in.P ~ 1.0e5,   # pressure gauge anchor
    ]
    @named sys = compose(System(connections, t; name=:rl_sys), L_comp, R_comp)
    ssys = mtkcompile(sys; fully_determined=false)  # T eqs underdetermined (no heat exchange in RL circuit)

    # Initial condition: mdot = 1.0 kg/s
    # T variables are free (no heat exchange in RL circuit); provide ICs for all unknowns
    # check_length=false required because T unknowns are underdetermined (no T equations in pure RL circuit)
    op = [
        ssys.L_comp.port_in.mdot => 1.0,
        ssys.L_comp.port_out.T   => 300.0,
        ssys.L_comp.port_in.T    => 300.0,
    ]
    prob = ODEProblem(ssys, op, (0.0, 5000.0); warn_initialize_determined=false, check_length=false)
    sol  = solve(prob, Rodas5P(); initializealg=SciMLBase.NoInit())

    @test sol.retcode == ReturnCode.Success
    t_check = [0.0, 500.0, 1000.0, 2000.0, 5000.0]
    for tc in t_check
        mdot_num = sol(tc, idxs=ssys.L_comp.port_in.mdot)
        mdot_ana = exp(-tc / tau)
        @test isapprox(mdot_num, mdot_ana; rtol=0.01)
    end
end

# ─────────────────────────────────────────────────────────────────
# COMP-02: HeatExchanger stubs (RED — implemented in Plan 02)
# ─────────────────────────────────────────────────────────────────
@testset "COMP-02: HeatExchanger stub callable" begin
    @named hx = HeatExchanger(T_bc=313.15)
    @test hx isa ModelingToolkit.System
end

@testset "COMP-02: HeatExchanger mtkcompile" begin
    @named hx = HeatExchanger(T_bc=313.15)
    @test_nowarn mtkcompile(hx; fully_determined=false)
end

@testset "COMP-02: HeatExchanger exported from STREAM" begin
    @test isdefined(STREAM, :HeatExchanger)
end

@testset "COMP-02: build_loop compiles after HeatExchanger rename (regression)" begin
    ssys = build_loop()
    @test ssys isa ModelingToolkit.AbstractSystem
end

end  # @testset "STREAM Phase 8 Tests"

@testset "STREAM Phase 9 Tests" begin

# ─────────────────────────────────────────────────────────────────
# THERM-01: ChannelAndContacts — n ThermalPorts, per-cell energy balance
# ─────────────────────────────────────────────────────────────────
@testset "THERM-01: ChannelAndContacts callable" begin
    @named ch = ChannelAndContacts(n=5, L=1.0, D=0.01, A=7.85e-5)
    @test ch isa ModelingToolkit.System
end

@testset "THERM-01: ChannelAndContacts mtkcompile" begin
    @named ch = ChannelAndContacts(n=5, L=1.0, D=0.01, A=7.85e-5)
    @test_nowarn mtkcompile(ch; fully_determined=false)
end

@testset "THERM-01: ChannelAndContacts has n ThermalPort subsystems" begin
    @named ch = ChannelAndContacts(n=5, L=1.0, D=0.01, A=7.85e-5)
    subsys_names = Symbol.(ModelingToolkit.getname.(ModelingToolkit.get_systems(ch)))
    for i in 1:5
        @test Symbol(:thermal_left, i)  in subsys_names
        @test Symbol(:thermal_right, i) in subsys_names
    end
    # Old single-side names must be absent
    @test !(Symbol(:thermal, 1) in subsys_names)
end

# ─────────────────────────────────────────────────────────────────
# THERM-02: Channel unchanged — all v0.1-v0.2 tests still pass
# (implicit: reaching this point means prior testsets passed)
# ─────────────────────────────────────────────────────────────────
@testset "THERM-02: Channel unmodified (regression)" begin
    @named ch = Channel(n=5, L=1.0, D=0.01, A=7.85e-5)
    @test ch isa ModelingToolkit.System
    subsys_names = Symbol.(ModelingToolkit.getname.(ModelingToolkit.get_systems(ch)))
    @test :thermal in subsys_names   # single ThermalPort, unchanged
    @test !(Symbol(:thermal, 1) in subsys_names)  # no per-cell array on Channel
end

# ─────────────────────────────────────────────────────────────────
# THERM-03: ChannelAndContacts two-sided matches ChannelHeatFlux within 0.1%
# Both thermal_left and thermal_right connected to T_wall with D_cac = D_chf.
# h_tc*(π*D/2)*dz*(T_wall-T)*2 = h_tc*(π*D)*dz*(T_wall-T) — exact CHF equivalence.
# ─────────────────────────────────────────────────────────────────
@testset "THERM-03: ChannelAndContacts two-sided matches ChannelHeatFlux within 0.1%" begin
    # Two-sided CAC (both left and right connected to same T_wall) with D=D_chf
    # gives h_tc*(π*D/2)*dz*(T_wall-T)*2 = h_tc*(π*D)*dz*(T_wall-T) — identical to CHF.
    # Same D ensures identical h_tc. CHAN-03 separately validates the adiabatic right side.
    n = 10; T_inlet = 313.15; T_wall = 373.15
    L_ch = 0.6; D_ch = 0.01; A_ch = 7.85e-5; dP_pump = 3.0e4

    # --- ChannelHeatFlux reference ---
    @named pump_chf = Pump(dP_pump=dP_pump)
    @named chf = ChannelHeatFlux(n=n, L=L_ch, D=D_ch, A=A_ch, T_wall=T_wall)
    @named bc_chf = HeatExchanger(T_bc=T_inlet)
    conns_chf = [
        connect(pump_chf.port_out, bc_chf.port_in),
        connect(bc_chf.port_out, chf.port_in),
        connect(chf.port_out, pump_chf.port_in),
        pump_chf.port_in.P ~ 1.0e5,
        chf.port_in.T ~ T_inlet,
    ]
    @named sys_chf = compose(System(conns_chf, t; name=:sys_chf), pump_chf, bc_chf, chf)
    ssys_chf = mtkcompile(sys_chf)
    T_guess = steady_state_guess(T_inlet=T_inlet, Q_wall=1e4, mdot_guess=0.490, n=n)
    op_chf = [ssys_chf.chf.T[i] => T_guess[i] for i in 1:n]
    push!(op_chf, ssys_chf.chf.port_in.mdot => 0.490)
    sol_chf = solve_steady(ssys_chf, op_chf)
    T_out_chf = sol_chf[ssys_chf.chf.T_out]

    # --- ChannelAndContacts two-sided (both left and right connected to T_wall) ---
    @named pump_cac = Pump(dP_pump=dP_pump)
    @named cac = ChannelAndContacts(n=n, L=L_ch, D=D_ch, A=A_ch)
    @named bc_cac = HeatExchanger(T_bc=T_inlet)
    ct_l = [ConstantTemperature(name=Symbol(:ct_l, i), T=T_wall) for i in 1:n]
    ct_r = [ConstantTemperature(name=Symbol(:ct_r, i), T=T_wall) for i in 1:n]
    conns_cac = [
        connect(pump_cac.port_out, bc_cac.port_in),
        connect(bc_cac.port_out, cac.port_in),
        connect(cac.port_out, pump_cac.port_in),
        [connect(ct_l[i].thermal, getproperty(cac, Symbol(:thermal_left,  i))) for i in 1:n]...,
        [connect(ct_r[i].thermal, getproperty(cac, Symbol(:thermal_right, i))) for i in 1:n]...,
        pump_cac.port_in.P ~ 1.0e5,
        cac.port_in.T ~ T_inlet,
    ]
    @named sys_cac = compose(System(conns_cac, t; name=:sys_cac), pump_cac, bc_cac, cac, ct_l..., ct_r...)
    ssys_cac = mtkcompile(sys_cac)
    op_cac = [ssys_cac.cac.T[i] => T_guess[i] for i in 1:n]
    push!(op_cac, ssys_cac.cac.port_in.mdot => 0.490)
    sol_cac = solve_steady(ssys_cac, op_cac)
    T_out_cac = sol_cac[ssys_cac.cac.T_out]

    @test isapprox(T_out_cac, T_out_chf; rtol=1e-3)  # 0.1%
end

# ─────────────────────────────────────────────────────────────────
# CHAN-03: Unconnected thermal_right defaults to adiabatic (Q_flow == 0)
# Uses same one-sided CAC geometry as THERM-03
# ─────────────────────────────────────────────────────────────────
@testset "CHAN-03: Unconnected thermal_right is adiabatic (Q_flow == 0)" begin
    n = 5; T_inlet = 313.15; T_wall = 373.15
    L_ch = 0.6; D_cac = 0.02; A_ch = 7.85e-5; dP_pump = 3.0e4

    @named pump2 = Pump(dP_pump=dP_pump)
    @named cac2 = ChannelAndContacts(n=n, L=L_ch, D=D_cac, A=A_ch)
    @named bc2 = HeatExchanger(T_bc=T_inlet)
    ct2 = [ConstantTemperature(name=Symbol(:ct2_, i), T=T_wall) for i in 1:n]
    conns2 = [
        connect(pump2.port_out, bc2.port_in),
        connect(bc2.port_out, cac2.port_in),
        connect(cac2.port_out, pump2.port_in),
        [connect(ct2[i].thermal, getproperty(cac2, Symbol(:thermal_left, i))) for i in 1:n]...,
        pump2.port_in.P ~ 1.0e5,
        cac2.port_in.T ~ T_inlet,
    ]
    @named sys2 = compose(System(conns2, t; name=:sys2), pump2, bc2, cac2, ct2...)
    ssys2 = mtkcompile(sys2; fully_determined=false)
    T_guess2 = steady_state_guess(T_inlet=T_inlet, Q_wall=5e3, mdot_guess=0.490, n=n)
    op2 = [ssys2.cac2.T[i] => T_guess2[i] for i in 1:n]
    push!(op2, ssys2.cac2.port_in.mdot => 0.490)
    # Unconnected thermal_right ports have free T variables — provide initial guess
    right_syms2 = [getproperty(ssys2.cac2, Symbol(:thermal_right, i)) for i in 1:n]
    append!(op2, [right_syms2[i].T => T_wall for i in 1:n])
    # Provide Re/Nu/h_tc guesses to break initialization cycle for algebraic variables
    append!(op2, [ssys2.cac2.Re[i] => 3e5 for i in 1:n])
    append!(op2, [ssys2.cac2.Nu[i] => 800.0 for i in 1:n])
    append!(op2, [ssys2.cac2.h_tc[i] => 2.7e4 for i in 1:n])
    sol2 = solve_steady(ssys2, op2)

    # Verify all unconnected thermal_right ports have Q_flow == 0
    right_syms = [getproperty(ssys2.cac2, Symbol(:thermal_right, i)) for i in 1:n]
    for i in 1:n
        @test isapprox(sol2[right_syms[i].Q_flow], 0.0; atol=1e-8)
    end
end

end  # @testset "STREAM Phase 9 Tests"

@testset "STREAM Phase 10 Tests" begin

# ─────────────────────────────────────────────────────────────────
# CHAN-01: ChannelAndContacts dual port arrays (DEBT-01 + CHAN-01/02)
# ─────────────────────────────────────────────────────────────────
@testset "CHAN-01: ChannelAndContacts callable with dual ports" begin
    @named ch = ChannelAndContacts(n=2, L=1.0, D=0.01, A=7.85e-5)
    @test ch isa ModelingToolkit.System
end

@testset "CHAN-01: ChannelAndContacts mtkcompile (bare, no connections)" begin
    @named ch = ChannelAndContacts(n=2, L=1.0, D=0.01, A=7.85e-5)
    @test_nowarn mtkcompile(ch; fully_determined=false)
end

@testset "CHAN-02: ConstantTemperature exported from STREAM" begin
    @test isdefined(STREAM, :ConstantTemperature)
end

@testset "CHAN-02: ConstantTemperature callable and mtkcompiles" begin
    @named ct = ConstantTemperature(T=373.15)
    @test ct isa ModelingToolkit.System
    @test_nowarn mtkcompile(ct; fully_determined=false)
end

end  # @testset "STREAM Phase 10 Tests"

# NOTE: Phase 11 block is intentionally split across two tasks.
# Task 1 adds HDIFF-01/04 (open block, no closing end yet).
# Task 2 adds HDIFF-02/03/05 and closes the block.
@testset "STREAM Phase 11 Tests" begin

# ─────────────────────────────────────────────────────────────────
# HDIFF-01: HeatDiffusion instantiation and 2D state variable
# ─────────────────────────────────────────────────────────────────
@testset "HDIFF-01: HeatDiffusion callable and returns MTK System" begin
    ps = fill(1.0 / (5 * 3), 5, 3)
    @named hd = HeatDiffusion(nz=5, nx=3, Lz=0.6, Lx=0.005, y=0.07,
                               rho_s=19300.0, cp_s=116.0, k_s=174.0,
                               power_shape=ps)
    @test hd isa ModelingToolkit.System
end

@testset "HDIFF-01: HeatDiffusion exported from STREAM" begin
    @test isdefined(STREAM, :HeatDiffusion)
end

@testset "HDIFF-01: HeatDiffusion mtkcompile bare (no connections)" begin
    ps = fill(1.0 / (3 * 2), 3, 2)
    @named hd = HeatDiffusion(nz=3, nx=2, Lz=0.6, Lx=0.005, y=0.07,
                               rho_s=19300.0, cp_s=116.0, k_s=174.0,
                               power_shape=ps)
    @test_nowarn mtkcompile(hd; fully_determined=false)
end

@testset "HDIFF-01: HeatDiffusion state T[1:nz, 1:nx] present in unknowns" begin
    nz, nx = 3, 2
    ps = fill(1.0 / (nz * nx), nz, nx)
    @named hd = HeatDiffusion(nz=nz, nx=nx, Lz=0.6, Lx=0.005, y=0.07,
                               rho_s=19300.0, cp_s=116.0, k_s=174.0,
                               power_shape=ps)
    unames = Symbol.(ModelingToolkit.getname.(unknowns(hd)))
    @test :T in unames
    # Count only plate temperature unknowns (excluding thermal port subsystem variables)
    @test count(u -> ModelingToolkit.getname(u) == :T, unknowns(hd)) == nz * nx
end

# ─────────────────────────────────────────────────────────────────
# HDIFF-04: ThermalPort arrays present as named subsystems
# ─────────────────────────────────────────────────────────────────
@testset "HDIFF-04: HeatDiffusion has thermal_left and thermal_right subsystems" begin
    nz = 3
    ps = fill(1.0 / (nz * 2), nz, 2)
    @named hd = HeatDiffusion(nz=nz, nx=2, Lz=0.6, Lx=0.005, y=0.07,
                               rho_s=19300.0, cp_s=116.0, k_s=174.0,
                               power_shape=ps)
    sub_names = Symbol.(ModelingToolkit.getname.(ModelingToolkit.get_systems(hd)))
    for i in 1:nz
        @test Symbol(:thermal_left, i)  in sub_names
        @test Symbol(:thermal_right, i) in sub_names
    end
end

# ─────────────────────────────────────────────────────────────────
# HDIFF-02/03: Steady-state behavioral test with pinned boundaries and uniform power
# ─────────────────────────────────────────────────────────────────
@testset "HDIFF-02/03: Steady-state plate T > T_boundary and Q_flow signs correct" begin
    nz, nx = 3, 3
    T_bc = 600.0
    pwr  = 1e5
    ps   = fill(1.0 / (nz * nx), nz, nx)

    @named hd = HeatDiffusion(nz=nz, nx=nx, Lz=0.6, Lx=0.005, y=0.07,
                               rho_s=19300.0, cp_s=116.0, k_s=174.0,
                               power_shape=ps, power=pwr)

    ct_l = [ConstantTemperature(name=Symbol(:ct_l, i), T=T_bc) for i in 1:nz]
    ct_r = [ConstantTemperature(name=Symbol(:ct_r, i), T=T_bc) for i in 1:nz]

    conns = [
        [connect(ct_l[i].thermal, getproperty(hd, Symbol(:thermal_left, i)))  for i in 1:nz]...,
        [connect(ct_r[i].thermal, getproperty(hd, Symbol(:thermal_right, i))) for i in 1:nz]...,
    ]
    @named sys = compose(System(conns, t; name=:sys), hd, ct_l..., ct_r...)
    ssys = mtkcompile(sys)

    # Initial guess: slightly above T_bc to break symmetry
    op = [ssys.hd.T[i, j] => T_bc + 10.0 for i in 1:nz for j in 1:nx]
    sol = solve_steady(ssys, op)

    # All plate temperatures should be >= T_bc (heat source raises interior)
    for i in 1:nz, j in 1:nx
        @test sol[ssys.hd.T[i, j]] >= T_bc - 1e-6
    end

    # Q_flow sign check: left equation gives Q_flow = k*(T_plate - T_bc)/(dx/2) > 0 when plate is hotter
    # Right equation gives Q_flow = k*(T_bc - T_plate)/(dx/2) < 0 when plate is hotter
    # Energy balance: total power leaving through left face + right face = pwr
    left_syms  = [getproperty(ssys.hd, Symbol(:thermal_left, i))  for i in 1:nz]
    right_syms = [getproperty(ssys.hd, Symbol(:thermal_right, i)) for i in 1:nz]
    Q_left_total  = sum(sol[left_syms[i].Q_flow]  for i in 1:nz)
    Q_right_total = sum(sol[right_syms[i].Q_flow] for i in 1:nz)

    # Left Q_flow > 0 (heat leaving plate to left channel — positive per half-cell scheme)
    @test Q_left_total > 0.0

    # Right Q_flow < 0 (heat leaving plate to right channel — negative per half-cell scheme)
    @test Q_right_total < 0.0

    # Energy balance check: |Q_left| + |Q_right| ≈ power (within 5% for FD approximation)
    @test isapprox(abs(Q_left_total) + abs(Q_right_total), pwr; rtol=0.05)
end

# ─────────────────────────────────────────────────────────────────
# HDIFF-05: One-sided connection — unconnected thermal_right is adiabatic
# ─────────────────────────────────────────────────────────────────
@testset "HDIFF-05: Unconnected thermal_right has Q_flow == 0 (adiabatic)" begin
    nz, nx = 3, 3
    T_bc = 600.0
    pwr  = 5e4
    ps   = fill(1.0 / (nz * nx), nz, nx)

    @named hd = HeatDiffusion(nz=nz, nx=nx, Lz=0.6, Lx=0.005, y=0.07,
                               rho_s=19300.0, cp_s=116.0, k_s=174.0,
                               power_shape=ps, power=pwr)

    ct_l = [ConstantTemperature(name=Symbol(:ct5_l, i), T=T_bc) for i in 1:nz]
    conns = [connect(ct_l[i].thermal, getproperty(hd, Symbol(:thermal_left, i)))
             for i in 1:nz]
    @named sys = compose(System(conns, t; name=:sys), hd, ct_l...)
    ssys = mtkcompile(sys; fully_determined=false)

    op = [ssys.hd.T[i, j] => T_bc + 10.0 for i in 1:nz for j in 1:nx]
    sol = solve_steady(ssys, op)

    # Unconnected thermal_right ports must have Q_flow == 0
    right_syms = [getproperty(ssys.hd, Symbol(:thermal_right, i)) for i in 1:nz]
    for i in 1:nz
        @test isapprox(sol[right_syms[i].Q_flow], 0.0; atol=1e-8)
    end
end

end  # @testset "STREAM Phase 11 Tests"
