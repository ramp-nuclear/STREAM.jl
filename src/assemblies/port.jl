# port.jl -- reaching one element of an indexed connector array.
#
# A plain getter rather than a wiring verb, so it sits above Connect instead of
# inside it. Connect's own helpers use it, which is why it is defined first.

"""
    port(sys, face, i)

Access an indexed thermal port array element from a compiled subsystem.

# Arguments
- `sys`: MTK system instance
- `face`: port array name (Symbol), e.g. `:thermal_left`
- `i`: 1-based cell index (Int)

# Returns
The namespaced connector subsystem (e.g. `sys.thermal_left3`), suitable for `connect()`.
"""
port(sys, face::Symbol, i::Int) = getproperty(sys, Symbol(face, i))
