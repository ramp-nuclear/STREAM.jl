"""
The two loops several test files solve. A file that needs them includes this one behind
`@isdefined(build_loop)`, so it runs on its own as well as from `runtests.jl`.
"""

using ModelingToolkit
using ModelingToolkit: t_nounits as t
using STREAM
using STREAM.Assemblies
using STREAM.Components
using STREAM.Components: Channel  # explicit: Base.Channel also exists

"""
    build_loop(; n=10, dP_pump=3.0e4, T_inlet=40.0, T_wall=100.0, g_acc=0.0) -> System

A pump, a heat exchanger (`bc`) and a 0.6 m by 1 cm pipe (`ch`) heated through its left face
at 5000 W/(m²K), compiled. A callable `T_wall` becomes the callable parameter
`T_wall_callable`. A non-zero `g_acc` runs the pipe upward and closes the loop through a
return leg (`ret`) that falls the same height.
"""
function build_loop(; n=10, dP_pump=3.0e4, T_inlet=40.0, T_wall=100.0, g_acc=0.0)
    L = 0.6
    @named pump = Pump(dP_pump)
    @named bc = HeatExchanger(T_inlet)
    @named ch = Channel(; n, geometry=Duct(L, Circular(0.01)), g=g_acc, h=5000.0)
    parts = Any[pump, bc, ch]
    iszero(g_acc) || push!(parts, Gravity(-L, g_acc; name=:ret))
    pars, wall = [], T_wall
    if T_wall isa Function
        FType = typeof(T_wall)
        pars = @parameters (T_wall_callable::FType)(..)
        wall = pars[1](t)
    end
    connections = [
        inseries(parts..., pump),
        pump.inlet.p ~ 1.0e5,
        ch.T_wall_outer .~ wall,
    ]
    @named sys = assembly(connections, parts...; parameters=pars)
    return mtkcompile(sys)
end

"""
    build_loop_pk(ctrl; n=7, nz=7, nx=2, T_inlet=20.0, P0=1.0, feedback=nothing,
                  power_input=nothing) -> (System, Vector{Pair})

A fuel plate between two channels (`rods.cac`, `rods.fuel`, joined by `symmetric_plate`) in
a pumped loop, its power `1e4 * pk.P` from a `PointKinetics` (`pk`) driven by `ctrl` and
starting critical at `P0`. `feedback = :cac => α` or `:fuel => α` gives every cell of that
part the worth `α`, referred to `T_inlet`. Returns the compiled system and an operating point
with the flow and every temperature at `T_inlet`.
"""
function build_loop_pk(ctrl; n=7, nz=7, nx=2, T_inlet=20.0, P0=1.0, feedback=nothing,
                       power_input=nothing)
    geom = Duct(0.6, Rectangular(0.070, 0.0025))
    @named cac = ChannelAndContacts(; n, geometry=geom, htc=HTC.ConstantNusselt(; Nu=8.235),
                                    darcy=Friction.RectangularLaminar())
    slab = Slab(; x=range(0, 0.005, nx + 1), z=range(0, 0.6, nz + 1), y=0.07,
                material=Solid(19300.0, 116.0, 174.0))
    @named fuel = HeatDiffusion(slab)
    rods = symmetric_plate(cac, fuel; name=:rods)

    felt, worth, ref = System[], nothing, nothing
    if feedback !== nothing
        part, α = getproperty(rods, first(feedback)), last(feedback)
        shape = first(feedback) === :cac ? (n,) : (nz, nx)
        felt, worth, ref = [part], Dict(part => fill(α, shape)), Dict(part => fill(T_inlet, shape))
    end
    @named pk = PointKinetics(ctrl; temp_worth=worth, ref_temp=ref, power_input, P0)
    @named pump = Pump(3.0e4)
    @named bc = HeatExchanger(T_inlet)

    connections = [
        inseries(pump, bc, rods.cac, pump),
        pump.inlet.p ~ 1.0e5,
        Connect.temperature_feedback(pk, felt),
        rods.fuel.power ~ pk.P * 1e4,   # the total, so a power_input reaches the plate
    ]
    @named sys = assembly(connections, rods, pk, pump, bc)
    ssys = mtkcompile(sys)

    ic = Pair{Any,Any}[
        ssys.rods.cac.inlet.ṁ => 0.2,
        ssys.rods.cac.T => fill(T_inlet, n),
        ssys.rods.fuel.T => fill(T_inlet, nz, nx),
    ]
    # Which member of each port and contact alias set survives mtkcompile changes between
    # runs and MTK versions, so all of them start at T_inlet. Left at the connector default
    # of 26.85 °C, a loop with feedback would start off critical.
    for part in (ssys.rods.cac, ssys.pump, ssys.bc), p in (part.inlet, part.outlet)
        push!(ic, p.T => T_inlet)
    end
    for part in (ssys.rods.cac, ssys.rods.fuel), face in (:thermal_left, :thermal_right)
        append!(ic, port(part, face, :T) .=> T_inlet)
    end
    return ssys, ic
end
