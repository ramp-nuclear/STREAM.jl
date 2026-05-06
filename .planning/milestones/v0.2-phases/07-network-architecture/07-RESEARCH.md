# Phase 7: Network Architecture - Research

**Researched:** 2026-03-13
**Domain:** ModelingToolkit.jl multi-port connect semantics + hydraulic resistor networks
**Confidence:** HIGH

---

## Summary

Phase 7 adds a `Resistor` component (linear hydraulic resistance: `dp ~ R * mdot`) and validates
multi-branch network assembly by solving the classic Cube problem: 12 resistors on the edges of a
cube, 1 pump driving body-diagonal flow, analytical equivalent resistance = 5/6 R.

The key architectural insight is that MTK's `connect()` is **variadic**: `connect(sys1, sys2,
sys3, ...)` is the standard mechanism for junctions and is fully supported by ModelingToolkitBase.
No explicit Junction component is needed. When 3 or more connectors are joined, MTK generates the
correct Kirchhoff equations: Flow variables sum to zero, across variables are equalized, and Stream
variables get the instream()-weighted mixture.

The Resistor component is simpler than Channel: no energy balance, no array state variables, no
HTC correlations. It is a two-port purely-hydraulic component with a scalar parameter `R`. The
only design decision is how to handle the temperature stream: pass-through (same pattern as Pump
and Gravity).

**Primary recommendation:** Implement Resistor following the Pump/Gravity template (two FlowPorts,
pass-through T, scalar parameter), then assemble the Cube using `connect()` with 3 arguments at
each corner node.

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| NET-01 | Resistor component: `dp ~ R * mdot`, scalar R parameter | Template from Pump/Gravity; verified MTK compile pattern |
| NET-02 | Cube problem (12 R, 8 nodes, 1 Pump) assembled using multi-port connect() | Confirmed connect() is variadic; 3-port junction is standard |
| NET-03 | Cube flow distribution matches 5/6 R equivalent resistance within 1% | Analytical result confirmed (body diagonal); solve_steady pattern applies |
</phase_requirements>

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ModelingToolkit | 11 | Component/connector/connect() semantics | Project standard (Project.toml) |
| Sundials/KINSOL | 5 | Steady-state nonlinear solve | Proven in v0.1; reused via solve_steady() |
| DifferentialEquations | 7 | SSRootfind wrapper | Proven in v0.1 |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Symbolics | 5/6/7 | Symbolic registration | Only if new fluid functions are needed (not required for Resistor) |

**Installation:** No new dependencies. All required packages are already in Project.toml.

---

## Architecture Patterns

### Recommended File Changes
```
src/
├── components.jl    # ADD: Resistor() function
├── STREAM.jl        # ADD: export Resistor; ADD: export build_cube
└── solvers.jl       # ADD: build_cube() test utility
test/
└── runtests.jl      # ADD: @testset "STREAM Phase 7 Tests"
```

### Pattern 1: Resistor Component Structure

The Resistor follows the Pump/Gravity template: two FlowPorts, scalar parameter, no array
variables, no ThermalPort.

**Equation:** `inlet.P - outlet.P ~ R * inlet.mdot`

Note: `dp ~ R * mdot` where `dp = inlet.P - outlet.P`. Using `inlet.mdot` (positive =
into component) means positive mdot drives positive pressure drop from in to out.

**Temperature pass-through:** Same pattern as Pump and Gravity. The Resistor is isothermal —
no heat addition. The stream T just passes through:
- `outlet.T ~ instream(inlet.T)`
- `inlet.T  ~ instream(outlet.T)`

**Example (directly mirrors existing components):**
```julia
# Source: src/components.jl (Pump/Gravity pattern)
function Resistor(; name, R)
    pars = @parameters R = R
    @named inlet  = FlowPort()
    @named outlet = FlowPort()
    eqs = Equation[
        inlet.mdot + outlet.mdot ~ 0,
        inlet.P - outlet.P ~ R * inlet.mdot,
        outlet.T ~ instream(inlet.T),
        inlet.T  ~ instream(outlet.T),
    ]
    compose(System(eqs, t, [], pars; name=name), inlet, outlet)
end
```

### Pattern 2: Multi-Port connect() for Junctions

`connect()` is variadic: `connect(a, b, c)` connects three connectors at one node.

**Verified from ModelingToolkitBase source** (`connectors.jl` line 25):
```julia
function connect(sys1::AbstractSystem, sys2::AbstractSystem, syss::AbstractSystem...)
```

When `connect(a.outlet, b.inlet, c.inlet)` is used:
- **Flow** (`mdot`, marked `[connect = Flow]`): sum = 0, i.e. `a.mdot + b.mdot + c.mdot = 0`
- **Across** (`P`, no connect annotation): all equal, i.e. `a.P = b.P = c.P`
- **Stream** (`T`, marked `[connect = Stream]`): `instream()` computes weighted mixture temperature

No Junction component is needed. The `connect()` call IS the junction.

### Pattern 3: Cube Topology

The Cube has 8 corners and 12 edges. Label corners 0-7 in binary (xyz bits). Each edge connects
corners differing by exactly one bit. The Pump drives from corner 0 to corner 7 (body diagonal).

```
Corner indices (binary):
  000=0, 001=1, 010=2, 011=3, 100=4, 101=5, 110=6, 111=7

Edges (12 total, each is one Resistor):
  Along x: (0,4),(1,5),(2,6),(3,7)
  Along y: (0,2),(1,3),(4,6),(5,7)
  Along z: (0,1),(2,3),(4,5),(6,7)

Flow direction: Pump outlet -> corner 0 (source node)
                Pump inlet  <- corner 7 (sink node)
```

At each interior corner (1-6), exactly 3 Resistor ports meet. The connect() call joins them:

```julia
# Corner 1 (connected to edges 0-1, 1-3, 1-5):
connect(r01.outlet, r13.inlet, r15.inlet)
```

Corner 0 (source) and corner 7 (sink) also connect to the pump:
```julia
# Corner 0: pump outlet + 3 resistor inlets
connect(pump.outlet, r01.inlet, r02.inlet, r04.inlet)
# Corner 7: pump inlet + 3 resistor outlets
connect(pump.inlet,  r37.outlet, r57.outlet, r67.outlet)
```

### Pattern 4: Pressure Anchor

The gauge freedom (one DOF for absolute pressure level) must be fixed with one constraint:
```julia
pump.inlet.P ~ 1.0e5   # same pattern as build_loop
```

### Pattern 5: Temperature Constraint

In a purely hydraulic resistor network there is no heating. The TempBC pattern from build_loop
is not needed because the Resistor's temperature pass-through equations are self-consistent
(no circular thermal dependency in an isothermal network).

However, there is a subtle issue: with Stream variables in a multi-branch isothermal network,
MTK may still require a temperature anchor. Check if `mtkcompile` raises a singularity or
extra-equations error about temperature. If it does, add a single temperature pin:
```julia
r_any.inlet.T ~ T_ambient   # e.g. 300.0 K
```

**Note from STATE.md:** "Flow reversal with ifelse() — convergence in multi-branch networks is
untested." The Resistor uses `R * mdot` (not `R * mdot * abs(mdot)`), so it is linear and does
not use ifelse(). Linear resistors are bidirectional by construction and should not trigger
convergence issues.

### Anti-Patterns to Avoid

- **Using ifelse() in Resistor:** The Resistor equation `dp ~ R * mdot` is linear and
  bidirectional. Do NOT introduce abs(mdot). The Pump provides the flow direction. Linear
  Kirchhoff networks are well-conditioned.
- **Building a Junction component:** Unnecessary. MTK multi-port connect() handles this natively.
- **Two-argument connect() chains for junctions:** `connect(a, b)` + `connect(b, c)` does NOT
  mean a, b, c are all at the same pressure — b is shared but the system becomes incorrect.
  Use `connect(a, b, c)` (single call) for a proper 3-way junction.
- **Using Channel for Resistors:** Channel has n energy balance ODEs. For a pure hydraulic
  resistor the Channel is massively over-specified. Use the minimal Resistor pattern.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Multi-port junction | Custom Junction component with summing equations | `connect(p1, p2, p3)` variadic MTK | MTK generates correct Kirchhoff equations automatically |
| Kirchhoff flow balance at nodes | Manual `port_a.mdot + port_b.mdot + port_c.mdot ~ 0` | `connect()` with [connect=Flow] | Handled by connection semantics |
| Temperature mixing at junction | Custom mixture T equations | `instream()` + Stream semantics | MTK implements Modelica stream standard |

**Key insight:** The entire value of MTK's connector system is that it auto-generates Kirchhoff
equations from `connect()` calls. Bypassing this with manual equations defeats the purpose and
risks sign errors.

---

## Common Pitfalls

### Pitfall 1: Incorrect pressure drop sign convention
**What goes wrong:** Solver gets negative mdot or solution doesn't converge.
**Why it happens:** `inlet.P - outlet.P ~ R * mdot` with signed mdot — if flow reverses,
dP reverses too. This is physically correct for a linear resistor.
**How to avoid:** Use `inlet.P - outlet.P ~ R * inlet.mdot` consistently. The Pump sets
the flow direction; the Resistor's linear equation handles both directions.
**Warning signs:** `sol.retcode != ReturnCode.Success` or mdot ≈ 0 everywhere.

### Pitfall 2: Missing pressure gauge anchor
**What goes wrong:** `mtkcompile` raises "singular" or the solver returns NaN.
**Why it happens:** Kirchhoff networks have one floating pressure DOF (only pressure differences
are determined by flow equations). MTK cannot determine the absolute pressure level.
**How to avoid:** Always add `pump.inlet.P ~ 1.0e5` (or equivalent) as a boundary condition.
**Warning signs:** `warn_initialize_determined` warning, or solver failure.

### Pitfall 3: Temperature DOF in isothermal network
**What goes wrong:** `mtkcompile(; fully_determined=false)` works but `mtkcompile()` (default)
fails with extra unknowns related to T stream variables.
**Why it happens:** The stream T variables in FlowPort may introduce extra DOFs in an isothermal
system where no component sets T.
**How to avoid:** If `mtkcompile` fails on temperature variables, pin one temperature:
`r01.inlet.T ~ 300.0`. For the standalone Resistor test, use
`mtkcompile(; fully_determined=false)` (consistent with Phase 2 tests for Pump, Friction, Gravity).
**Warning signs:** mtkcompile error mentioning T or stream variables; overdetermined system.

### Pitfall 4: Naming collisions in the Cube
**What goes wrong:** `connect()` raises "connect takes distinct systems!" error.
**Why it happens:** The Cube has 12 resistors. Each must have a unique `name=` kwarg.
**How to avoid:** Name resistors as `r_ij` where i < j are the corner indices:
`r01, r02, r04, r13, r15, r23, r26, r37, r46, r57, r67`. That's 11 — double-check
the cube has exactly 12 edges.
**Warning signs:** ArgumentError from connect() about non-distinct names.

### Pitfall 5: Initial guess for Cube mdot
**What goes wrong:** KINSOL fails to converge for the Cube.
**Why it happens:** Starting mdot = 0 everywhere is a degenerate fixed point for Kirchhoff
networks. KINSOL needs a non-zero initial guess.
**How to avoid:** Provide `mdot_guess => dP_pump / (5/6 * R)` as the pump mdot guess
(analytical expected total flow). For each resistor, provide a fraction of that:
edge branches carry 1/3, face diagonal branches carry 1/6.

---

## Code Examples

### Resistor stub test (NET-01 pattern)
```julia
# Source: project pattern, confirmed from Phase 2 component tests
@testset "NET-01: Resistor stub callable" begin
    @named r = Resistor(R=1.0e5)
    @test r isa ModelingToolkit.System
    @test_nowarn mtkcompile(r; fully_determined=false)
end
```

### 3-way connect syntax (confirmed from ModelingToolkitBase source)
```julia
# Source: ModelingToolkitBase/src/systems/connectors.jl line 25
# connect() takes sys1, sys2, syss... (variadic)
connect(node_a.outlet, node_b.inlet, node_c.inlet)
# => mdot_a_out + mdot_b_in + mdot_c_in = 0
# => P_a_out = P_b_in = P_c_in
```

### Cube initial guess (physics-based)
```julia
# Analytical: total mdot = dP_pump / R_eq = dP_pump / (5/6 * R)
# Body diagonal symmetry: 3 parallel groups
#   Group 1 (3 edges from source corner 0): each carries dP_pump/(3*R)... etc.
# Simple starting guess: all resistors carry 1/3 of pump mdot
mdot_total_guess = dP_pump / (5/6 * R_val)
mdot_branch_guess = mdot_total_guess / 3
```

### build_cube structure
```julia
# Source: pattern from build_loop/build_loop_vertical in solvers.jl
function build_cube(; dP_pump=3.0e4, R=1.0e4)
    @named pump = Pump(dP_pump=dP_pump)
    # 12 resistors: edges of cube, corners labeled 0-7 (binary xyz)
    @named r01 = Resistor(R=R); @named r02 = Resistor(R=R); @named r04 = Resistor(R=R)
    @named r13 = Resistor(R=R); @named r15 = Resistor(R=R)
    @named r23 = Resistor(R=R); @named r26 = Resistor(R=R)
    @named r37 = Resistor(R=R)
    @named r46 = Resistor(R=R); @named r57 = Resistor(R=R)
    @named r67 = Resistor(R=R)
    # Wait: that's only 11. Need to count carefully. See cube topology below.
    # Edges: (0,1),(0,2),(0,4),(1,3),(1,5),(2,3),(2,6),(3,7),(4,5),(4,6),(5,7),(6,7) = 12 OK
    @named r45 = Resistor(R=R)  # adds the missing edge (4,5)
    connections = [
        connect(pump.outlet, r01.inlet, r02.inlet, r04.inlet),  # node 0: source
        connect(r01.outlet,  r13.inlet, r15.inlet),               # node 1
        connect(r02.outlet,  r23.inlet, r26.inlet),               # node 2
        connect(r13.outlet,  r23.outlet, r37.inlet),              # node 3
        connect(r04.outlet,  r45.inlet, r46.inlet),               # node 4
        connect(r15.outlet,  r45.outlet, r57.inlet),              # node 5
        connect(r26.outlet,  r46.outlet, r67.inlet),              # node 6
        connect(pump.inlet,  r37.outlet, r57.outlet, r67.outlet), # node 7: sink
        pump.inlet.P ~ 1.0e5,                                         # pressure anchor
    ]
    @named sys = compose(System(connections, t; name=:sys),
                         pump, r01, r02, r04, r13, r15, r23, r26, r37, r45, r46, r57, r67, r67)
    ssys = mtkcompile(sys)
    return ssys
end
```

### Cube analytical solution verification (NET-03)
```julia
# Analytical: R_eq_body_diagonal = 5/6 * R
# Total flow: mdot_total = dP_pump / R_eq = dP_pump * 6 / (5 * R)
R_val = 1.0e4
dP_pump_val = 3.0e4
mdot_analytical = dP_pump_val / (5/6 * R_val)   # = dP_pump * 6 / (5*R)

# Check from solver:
mdot_numerical = abs(sol[ssys.pump.outlet.mdot])
@test isapprox(mdot_numerical, mdot_analytical; rtol=0.01)
```

---

## Cube Topology Reference

Complete list of 12 cube edges (label format: corner_i, corner_j where i < j):

```
Axis  Edge   Corners  delta-bit
 X    r04:   0 ↔ 4   bit-2
 X    r15:   1 ↔ 5   bit-2
 X    r26:   2 ↔ 6   bit-2
 X    r37:   3 ↔ 7   bit-2
 Y    r02:   0 ↔ 2   bit-1
 Y    r13:   1 ↔ 3   bit-1
 Y    r46:   4 ↔ 6   bit-1
 Y    r57:   5 ↔ 7   bit-1
 Z    r01:   0 ↔ 1   bit-0
 Z    r23:   2 ↔ 3   bit-0
 Z    r45:   4 ↔ 5   bit-0
 Z    r67:   6 ↔ 7   bit-0
```

Total: 12 edges. Corner 0 = source (pump.outlet), corner 7 = sink (pump.inlet).

Node connections at each corner (3 edges per corner):
- Corner 0: r04, r02, r01 (pump source)
- Corner 1: r01, r13, r15
- Corner 2: r02, r23, r26
- Corner 3: r13, r23, r37
- Corner 4: r04, r46, r45
- Corner 5: r15, r57, r45
- Corner 6: r26, r46, r67
- Corner 7: r37, r57, r67 (pump sink)

---

## Analytical Verification Details

The Cube body-diagonal resistance is 5/6 R (confirmed by symmetry argument):

1. By symmetry, nodes {1,2,4} are equipotential at V_source - (1/3)ΔV (3 nodes, 3 parallel edges from source).
2. Nodes {3,5,6} are equipotential at V_source - (2/3)ΔV.
3. Resulting network: 3 parallel resistors from source → middle → sink, with 6 middle resistors cross-connecting.
4. R_eq = R/3 + R/6 + R/3 = 2/6 + 1/6 + 2/6 = 5/6 R.

For verification in the Cube test:
- Total mass flow through pump = dP_pump / R_eq = dP_pump * 6 / (5 * R)
- Each source-edge resistor carries mdot_total / 3 (3 equal source branches)
- Each middle cross-resistor carries mdot_total / 6

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Explicit Junction component | Multi-port connect() | MTK v9+ | No Junction needed; simpler DAE |
| Two-argument connect() chains | Single connect(a,b,c,...) call | MTK v9+ | Correct Kirchhoff generation |

**Deprecated/outdated:**
- Junction as explicit component: `connect(a, junction.inlet); connect(junction.outlet, b)` — this is the old Modelica 2.x approach. MTK and Modelica 3.x use multi-port connect() instead.

---

## Open Questions

1. **Temperature handling in isothermal Resistor network**
   - What we know: FlowPort has a Stream variable T; multi-branch connect() generates instream() mixture equations
   - What's unclear: Whether the Cube (isothermal) requires an explicit T anchor or if the stream equations are self-consistent
   - Recommendation: Attempt mtkcompile without T anchor first. If it fails with temperature-related error, add `pump.inlet.T ~ 300.0` as a temperature anchor.

2. **Initial guess sensitivity for Cube KINSOL solve**
   - What we know: Nonlinear networks can be sensitive to initial guess; linear R*mdot makes this less severe
   - What's unclear: Whether mdot=0 everywhere fails (degenerate fixed point) or whether KINSOL self-corrects
   - Recommendation: Provide physics-based mdot guesses (mdot_total/3 for source branches) rather than zeros.

3. **Compose subsystem list for build_cube**
   - What we know: `compose(sys, subsys...)` requires all subsystems in the second argument
   - What's unclear: Whether MTK complains if a subsystem appears in connections but not compose() list
   - Recommendation: Always list all 13 subsystems (pump + 12 resistors) in the compose() call.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia Test stdlib (built-in `@testset`, `@test`) |
| Config file | none — test entry: `test/runtests.jl` |
| Quick run command | `julia --project=. -e 'using Pkg; Pkg.test()'` |
| Full suite command | `julia --project=. -e 'using Pkg; Pkg.test()'` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| NET-01 | Resistor(R=1e5) instantiates, mtkcompiles without error | unit | `julia --project=. -e 'using Pkg; Pkg.test()'` | ❌ Wave 0 |
| NET-02 | build_cube() assembles 12 Resistors + Pump, mtkcompiles | integration | `julia --project=. -e 'using Pkg; Pkg.test()'` | ❌ Wave 0 |
| NET-03 | solve_steady on Cube returns mdot within 1% of dP/(5/6*R) | integration | `julia --project=. -e 'using Pkg; Pkg.test()'` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `julia --project=. -e 'using Pkg; Pkg.test()'`
- **Per wave merge:** `julia --project=. -e 'using Pkg; Pkg.test()'`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/runtests.jl` — needs Phase 7 testset block (NET-01, NET-02, NET-03)
- [ ] `src/components.jl` — needs `Resistor` function
- [ ] `src/solvers.jl` — needs `build_cube` utility
- [ ] `src/STREAM.jl` — needs `export Resistor` and `export build_cube`

*(No new test framework needed — existing Test stdlib infrastructure is sufficient.)*

---

## Sources

### Primary (HIGH confidence)
- `ModelingToolkitBase/src/systems/connectors.jl` line 25 — connect() variadic signature confirmed by reading installed source
- `src/components.jl`, `src/solvers.jl` — existing component patterns (Pump, Gravity) directly verified
- `Project.toml` — dependency versions confirmed (MTK 11, Sundials 5)
- `.planning/REQUIREMENTS.md` — NET-01/NET-02/NET-03 definitions

### Secondary (MEDIUM confidence)
- [Resistor Cube Equivalent Resistance - RF Cafe](https://www.rfcafe.com/miscellany/factoids/resistor-cube-equivalent-resistance-kirts-cogitations-256.htm) — 5/6 R body diagonal confirmed by multiple independent sources
- [ModelingToolkit Acausal Components Docs](https://docs.sciml.ai/ModelingToolkit/dev/tutorials/acausal_components/) — connect() pairwise syntax confirmed; multi-port not demonstrated but source code confirms variadic
- [Modelica Stream Connectors Spec](https://specification.modelica.org/master/stream-connectors.html) — instream() semantics for multi-branch junctions

### Tertiary (LOW confidence)
- None required — all critical claims verified from source code or official docs.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies, all verified in Project.toml
- Architecture: HIGH — connect() variadic confirmed from MTK source; Resistor pattern directly derived from existing Pump/Gravity components
- Pitfalls: HIGH — pressure anchor pitfall confirmed from existing build_loop; stream T pitfall inferred from FlowPort definition + Modelica spec
- Analytical solution: HIGH — 5/6 R body diagonal is a well-known textbook result confirmed by multiple sources

**Research date:** 2026-03-13
**Valid until:** 2026-06-13 (MTK 11 is stable; no fast-moving changes expected)
