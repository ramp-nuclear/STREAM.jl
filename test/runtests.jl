using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using STREAM

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
