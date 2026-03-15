# helpers.jl — QoL and composition helpers for STREAM.jl
#
# QoL helpers (Phase 15 Plan 01): port, check_gravity_mismatch
# Composition helpers (Phase 15 Plan 02): symmetric_plate, plate,
#                                          one_sided_connection, compose_systems

# ----------------------------------------------------------------
# port — QOL-03
# Wraps getproperty(sys, Symbol(face, i)) — the only correct MTK
# syntax for indexed port array access in connect() calls.
#
# Example:
#   connect(port(cac, :thermal_left, 2), port(fuel, :thermal_right, 2))
# ----------------------------------------------------------------
port(sys, face::Symbol, i::Int) = getproperty(sys, Symbol(face, i))

# ----------------------------------------------------------------
# check_gravity_mismatch — QOL-02
# Checks whether gravity pressure contributions in a hydraulic loop are
# consistent (balanced). Returns :ok if balanced, :mismatch otherwise.
#
# Strategy:
#   1. Collect all parameters from the system (via ModelingToolkit.parameters).
#   2. Find channel gravity terms: parameters whose string ends with "g_acc".
#   3. Find Gravity component heights: parameters whose string ends with "H".
#   4. A balanced vertical loop has active g_acc (> 0) AND a Gravity component
#      with H > 0 (return leg). build_loop_vertical creates this by default.
#   5. If g_acc > 0 but no H parameter found, the loop is unbalanced (:mismatch).
#   6. If g_acc == 0 everywhere, gravity is disabled — trivially :ok.
#
# Parameter names in compiled systems have subsystem prefixes (e.g., ch₊g_acc,
# grav₊H) — we match by the suffix after the last ₊ separator.
# ----------------------------------------------------------------
function check_gravity_mismatch(sys::ModelingToolkit.AbstractSystem)
    # Collect all parameters from the system
    all_pars = try
        ModelingToolkit.parameters(sys)
    catch
        return :ok  # cannot inspect — assume ok
    end

    # Helper: get the local parameter name (last segment after ₊)
    local_name(p) = begin
        s = string(p)
        idx = findlast('₊', s)
        idx === nothing ? s : s[nextind(s, idx):end]
    end

    # Find g_acc parameters (channel gravity terms) by local name
    g_params = filter(p -> local_name(p) == "g_acc", all_pars)

    # Find H parameters (Gravity component heights) by local name
    h_params = filter(p -> local_name(p) == "H", all_pars)

    # Extract numeric default values
    g_vals = Float64[]
    for p in g_params
        try
            val = ModelingToolkit.getdefault(p)
            if val isa Real
                push!(g_vals, Float64(val))
            end
        catch
        end
    end

    h_vals = Float64[]
    for p in h_params
        try
            val = ModelingToolkit.getdefault(p)
            if val isa Real
                push!(h_vals, Float64(val))
            end
        catch
        end
    end

    # No gravity active anywhere — trivially ok
    if isempty(g_vals) || all(iszero, g_vals)
        return :ok
    end

    # Gravity is active in channels (g_acc > 0) — check for Gravity return components
    active_g  = any(v -> v > 0.0, g_vals)
    has_return = !isempty(h_vals) && any(v -> v > 0.0, h_vals)

    if active_g && !has_return
        @warn "check_gravity_mismatch: channels have g_acc > 0 but no Gravity return component found — loop gravity terms may be unbalanced"
        return :mismatch
    end

    return :ok
end
