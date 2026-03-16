using Test
using ModelingToolkit
using Symbolics
using STREAM
import STREAM: Channel  # resolve Base.Channel ambiguity
const ModelingToolkitBase = ModelingToolkit.ModelingToolkitBase

# ─────────────────────────────────────────────────────────────────
# FOUND-01: Package loads (implicitly tested by reaching this line)
# ─────────────────────────────────────────────────────────────────
@testset "FOUND-01: Package loads" begin
    @test true  # reaching here means `using STREAM` succeeded
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
