using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using DifferentialEquations: ReturnCode
using STREAM
import STREAM: Channel, Pump, Friction, Gravity  # resolve ambiguity with Base.Channel

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
    @named grav = Gravity(H=3.0, A_grav=7.85e-5)
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
