# test/test_connectors.jl — Phase 55 D-06 trim.
# Connector unit tests: FlowPort + ThermalPort — the v1.1 connector roster.

using Test
using ModelingToolkit
using STREAM
import STREAM: Channel  # resolve Base.Channel ambiguity
const ModelingToolkitBase = ModelingToolkit.ModelingToolkitBase
using ModelingToolkit: t_nounits as t

@testset "CONN-01: mdot is a Flow variable" begin
    @named fp = FlowPort()
    mdot_var = only(filter(v -> ModelingToolkit.getname(v) == :mdot, unknowns(fp)))
    connect_type = Symbolics.getmetadata(
        mdot_var, ModelingToolkitBase.VariableConnectType, nothing
    )
    @test connect_type == ModelingToolkit.Flow
end

@testset "CONN-01: T is a Stream variable" begin
    @named fp = FlowPort()
    T_var = only(filter(v -> ModelingToolkit.getname(v) == :T, unknowns(fp)))
    connect_type = Symbolics.getmetadata(
        T_var, ModelingToolkitBase.VariableConnectType, nothing
    )
    @test connect_type == ModelingToolkit.Stream
end

@testset "CONN-02: ThermalPort variable count" begin
    @named tp = ThermalPort()
    @test length(unknowns(tp)) == 2
end

@testset "CONN-02: T is an across variable (no connect metadata)" begin
    @named tp = ThermalPort()
    T_var = only(filter(v -> ModelingToolkit.getname(v) == :T, unknowns(tp)))
    connect_type = Symbolics.getmetadata(
        T_var, ModelingToolkitBase.VariableConnectType, nothing
    )
    @test connect_type === nothing
end
