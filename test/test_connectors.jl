using Test
using ModelingToolkit
using STREAM
using STREAM.Components
const ModelingToolkitBase = ModelingToolkit.ModelingToolkitBase

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

@testset "a port's flow starts in its usual direction" begin
    @named fp = FlowPort()
    @named out = FlowPort(; ṁ=-Components.FLOW_START)
    flow(p) = only(filter(v -> ModelingToolkit.getname(v) == :ṁ, unknowns(p)))
    @test ModelingToolkit.getdefault(flow(fp)) == Components.FLOW_START > 0
    @test ModelingToolkit.getdefault(flow(out)) == -Components.FLOW_START
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
