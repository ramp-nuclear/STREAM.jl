# Acausal connector tests (FlowPort, ThermalPort).
# Connector unit tests: FlowPort + ThermalPort — the v1.1 connector roster.

using Test
using ModelingToolkit
using STREAM
using STREAM: Channel  # resolve Base.Channel ambiguity
const ModelingToolkitBase = ModelingToolkit.ModelingToolkitBase
using ModelingToolkit: t_nounits as t

@testset "ṁ is a Flow variable" begin
    @named fp = FlowPort()
    ṁ_var = only(filter(v -> ModelingToolkit.getname(v) == :ṁ, unknowns(fp)))
    connect_type = Symbolics.getmetadata(
        ṁ_var,
        ModelingToolkitBase.VariableConnectType,
        nothing,
    )
    @test connect_type == ModelingToolkit.Flow
end

@testset "T is a Stream variable" begin
    @named fp = FlowPort()
    T_var = only(filter(v -> ModelingToolkit.getname(v) == :T, unknowns(fp)))
    connect_type = Symbolics.getmetadata(
        T_var, ModelingToolkitBase.VariableConnectType, nothing
    )
    @test connect_type == ModelingToolkit.Stream
end

@testset "ThermalPort variable count" begin
    @named tp = ThermalPort()
    @test length(unknowns(tp)) == 2
end

@testset "T is an across variable (no connect metadata)" begin
    @named tp = ThermalPort()
    T_var = only(filter(v -> ModelingToolkit.getname(v) == :T, unknowns(tp)))
    connect_type = Symbolics.getmetadata(
        T_var, ModelingToolkitBase.VariableConnectType, nothing
    )
    @test connect_type === nothing
end
