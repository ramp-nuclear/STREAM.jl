# The Sudo-Kaminaga CHF correlation is a maximum over three branch expressions; these are the
# branches. Kept private because only q_CHF_sudo_kaminaga has any use for them.

function _SKq1(G_star)
    return 0.005 * abs(G_star)^0.611
end

function _SKq2(A_ratio, G_star, dT_inlet)
    return A_ratio * abs(G_star) * dT_inlet
end

function _SKq3(A_ratio, w, lamda, dT_inlet, rho_v, rho_l)
    return 0.7 * A_ratio * sqrt(w / lamda) * (1 + dT_inlet) / (1 + (rho_v / rho_l)^0.25)^2
end

function _SKq4(G_star, dT_outlet)
    return iszero(G_star) ? Inf : _SKq1(G_star) * (1 + 5000 * dT_outlet / abs(G_star))
end

# #### Public API

@doc raw"""
    bergles_rohsenow_t_onb(pressure, q_wall, T_sat) -> T_ONB [°C]

Wall temperature at the onset of nucleate boiling, from Bergles and Rohsenow
[BerglesRohsenow1964](@cite):

```math
T_{ONB} = T_{sat} + 0.556 \, (q_{wall} / (1082 \, p^{1.156}))^{0.463 \, p^{0.0234}}
```

with `p` in bar and `q_wall` in W/m². See [Onset of nucleate boiling](@ref) for the physics.

# Arguments
- `pressure`: absolute system pressure [Pa]
- `q_wall`: wall heat flux [W/m^2]
- `T_sat`: saturation temperature [°C]

# Returns
Wall temperature at onset of nucleate boiling `T_ONB` [°C].

# Examples
```jldoctest
julia> Thresholds.bergles_rohsenow_t_onb(1e5, 1e5, 100.0)
104.52092778452801
```
"""
function bergles_rohsenow_t_onb(pressure, q_wall, T_sat)
    return T_sat + _bergles_rohsenow_dT_ONB(pressure, q_wall)
end

@doc raw"""
    q_boiling_onset(ṁ, T_sat, T_inlet, cp) -> Q [W]

The boiling power: the channel power that brings the outlet to saturation,

```math
Q = |\dot{m}| \, c_p \, (T_{sat} - T_{inlet})
```

Python STREAM calls it `boiling_power`, and TERMIC and CONVEC the boiling power limit.

# Arguments
- `ṁ`: mass flow rate [kg/s] (sign-insensitive; uses `abs(ṁ)`)
- `T_sat`: saturation temperature [°C]
- `T_inlet`: coolant inlet temperature [°C]
- `cp`: specific heat at inlet temperature [J/(kg·K)]

# Returns
Channel power limit for boiling onset `Q` [W].

# Examples
```jldoctest
julia> Thresholds.q_boiling_onset(0.5, 100.0, 40.0, 4180.0)
125400.0
```
"""
function q_boiling_onset(ṁ, T_sat, T_inlet, cp)
    return abs(ṁ) * cp * (T_sat - T_inlet)
end

@doc raw"""
    q_OFI_whittle_forgan(ṁ, T_sat, T_inlet, pipe) -> Q [W]

Channel power at the onset of flow instability, from the Whittle-Forgan correlation
[WhittleForgan1967](@cite) with Fabrèga's flow-dependent `η` [Fabrega1971](@cite):

```math
Q_{OFI} = |\dot{m}| \int c_p \, dT / (1 + η D_h / L), \qquad η = 3.15 \, (1.08 \, G)^{0.29}
```

with the integral from `T_inlet` to `T_sat` and the mass flux `G` in g/(cm²·s), as the
correlation was fitted. See [Onset of flow instability](@ref) for the physics.

# Arguments
- `ṁ`: mass flow rate [kg/s] (sign-insensitive; uses `abs(ṁ)`)
- `T_sat`: saturation temperature [°C]
- `T_inlet`: coolant inlet temperature [°C]
- `pipe`: channel geometry [`PipeGeometry`]

- `liquid`: the coolant whose `cₚ` is integrated (default [`H2O`](@ref))

# Returns
OFI limit power `Q_OFI` [W].

# Examples
```jldoctest
julia> pipe = PipeGeometry_rectangular(0.6, 0.0671, 0.0024, 0.0671);  # 2.4 mm MTR gap

julia> round(Thresholds.q_OFI_whittle_forgan(0.5, 100.0, 26.85, pipe); sigdigits=7)
135474.3
```
"""
function q_OFI_whittle_forgan(ṁ, T_sat, T_inlet, pipe; liquid::AbstractLiquid=H2O)
    G = abs(ṁ) / pipe.A
    G_cgs = G / 10  # SI to CGS conversion (G must be in CGS per Whittle-Forgan)
    integral_cp, _ = quadgk(T -> cₚ(liquid, T), T_inlet, T_sat)
    return abs(ṁ) * integral_cp / (1.0 + 3.15 * (pipe.Dh / pipe.L) * (1.08 * G_cgs)^0.29)
end

@doc raw"""
    q_OSV_saha_zuber(T_inlet, ṁ, pipe, coolant; flux_shape=nothing, dz=nothing) -> q_OSV [W/m^2]

Onset of significant void (OSV) heat flux per cell, from Saha and Zuber
[SahaZuber1974](@cite), with the bulk temperature computed as though the channel ran at the
OSV flux. See [Onset of significant void](@ref) for the physics.

Saha and Zuber give `T_sat - T_bulk = q_OSV / X`, with `X = κ/Dh · Nu_c` (`Nu_c = 455`) for
`Pe ≤ 70000` and `X = St_c · G · cₚ` (`St_c = 0.0065`) above. Scaling the flux shape until
the bulk temperature the energy balance gives meets that condition yields

```math
q_{OSV} = X (T_{sat} - T_{inlet}) / (1 + (X H_p / (|\dot{m}| c_p)) \int q \, dz / q)
```

which does not depend on how `flux_shape` is normalized. The integral runs from the upstream
end, so under reversed flow it starts at the last cell. This is Python STREAM's
`Saha_Zuber_OSV_computed_bulk`.

# Arguments
- `T_inlet`: temperature of the coolant entering the channel [°C]
- `ṁ`: mass flow rate [kg/s]; its sign says which end is upstream
- `pipe`: channel geometry [`PipeGeometry`]
- `coolant`: coolant properties per cell as a [`Liquid`](@ref), at the bulk temperature and
  pressure, e.g. `H2O(T_bulk, P)`. Supplies cₚ, κ and Tsat.
- `flux_shape`: axial heat flux per cell, in any normalization; default uniform
- `dz`: axial cell lengths [m]; default `pipe.L / n`

# Returns
OSV heat flux per cell [W/m²].

# Examples
```jldoctest
julia> pipe = PipeGeometry_rectangular(0.6, 0.0671, 0.0024, 0.0671);  # 2.4 mm MTR gap

julia> coolant = H2O(fill(26.85, 10), fill(1e5, 10));  # 10 cells at 26.85 °C and 1 bar

julia> round(last(Thresholds.q_OSV_saha_zuber(26.85, 0.5, pipe, coolant)); sigdigits=9)
1.44385224e6
```
"""
function q_OSV_saha_zuber(
    T_inlet, ṁ, pipe, coolant::Liquid; flux_shape=nothing, dz=nothing
)
    n = flux_shape === nothing ? length(coolant.ρ) : length(flux_shape)
    cells(x) = x isa AbstractArray ? collect(x) : fill(x, n)
    shape = flux_shape === nothing ? ones(n) : collect(float.(flux_shape))
    dz_c = dz === nothing ? fill(pipe.L / n, n) : cells(dz)
    cp_c, κ_c, T_sat = cells(coolant.cₚ), cells(coolant.κ), cells(coolant.Tsat)

    G = abs(ṁ) / pipe.A
    Pe_c = G * pipe.Dh .* cp_c ./ κ_c
    X = ifelse.(Pe_c .<= 7e4, κ_c ./ pipe.Dh .* 455.0, 0.0065 .* G .* cp_c)

    # The coolant reaching a cell has been heated by every cell before it in the flow, so
    # the running sum starts at whichever end the flow enters. Reversing twice does that
    # under reversed flow and hands the result back in cell order.
    upstream(a) = ṁ >= 0 ? a : reverse(a)
    heated = upstream(cumsum(upstream(shape .* dz_c)))
    power_factor = pipe.heated_perimeter ./ (abs(ṁ) .* cp_c)
    denominator = 1 .+ X .* power_factor .* heated ./ shape
    return X .* (T_sat .- T_inlet) ./ denominator
end

"""
    q_CHF_sudo_kaminaga(T_bulk, ṁ, pipe, gravity, sat_coolant) -> q_CHF [W/m^2]

Critical heat flux from the Sudo-Kaminaga correlation for plate-type fuel
[SudoKaminaga1993, Kaminaga1998](@cite). See [Critical heat flux](@ref) for the physics and
the ranges it was fitted over.

Four sub-correlations (`_SKq1..4`) with direction-dependent selection:
- `G_star >= 0` (downward/horizontal flow): `q_star = max(min(q2, q4), q3)`
- `G_star < 0` (upward flow): the same, then also maxed against `q1`

Final result: `q_CHF = q_star * hfg * sqrt(lamda * drho * rho_v * gravity)` where
`lamda = sqrt(sigma / drho / |gravity|)` is the capillary length.

Everything is elementwise, so passing per-cell `T_bulk` and a per-cell `sat_coolant` gives a
per-cell CHF, and passing scalars gives a scalar.

The subcooling is the exception, and it is what makes this a channel correlation rather than
a per-cell one. It was fitted to experiments that characterised a whole test section, so q2
and q3 are driven by the temperature difference at the **inlet** and q4 by the one at the
**outlet**. Only those two differences come from the channel ends; the `cp/hfg` factor
multiplying them stays per cell, as in Python STREAM.

`q3` reads the channel width `pipe.width`, not half the heated perimeter, following the
experiments it was fitted to. This is Python STREAM's `Sudo_Kaminaga_CHF`.

# Arguments
- `T_bulk`: bulk coolant temperature, per cell [°C]
- `ṁ`: mass flow rate [kg/s]
- `pipe`: channel geometry [`PipeGeometry`]
- `gravity`: gravitational acceleration [m/s^2]. Only its size is used. The branch
  follows the sign of the flow, positive taken as downward, as in Python STREAM
- `sat_coolant`: saturated-coolant properties as a [`Liquid`](@ref), supplying ρ, ρᵥ, cₚ,
  hfg, σ and Tsat. Build it by calling a coolant at the channel's saturation state, e.g.
  `H2O(T_sat, P)`. There is no default: which coolant, and at which state, is the caller's
  to state.

# Returns
CHF heat flux `q_CHF` [W/m²], shaped like the inputs.

# Examples
Downward flow at 0.5 kg/s with the bulk at 46.85 °C, against book values for water at 1 atm:
```jldoctest
julia> pipe = PipeGeometry_rectangular(0.6, 0.0671, 0.0024, 0.0671);  # 2.4 mm MTR gap

julia> sat = Substances.Liquid(; ρ=958.4, ρᵥ=0.598, cₚ=4217.0, hfg=2257e3, σ=0.059, Tsat=100.0);

julia> round(Thresholds.q_CHF_sudo_kaminaga(46.85, 0.5, pipe, 9.81, sat); sigdigits=9)
1.39178807e6
```
"""
function q_CHF_sudo_kaminaga(T_bulk, ṁ, pipe, gravity, sat_coolant::Liquid)
    g_abs = abs(gravity)
    rho_l, rho_v = sat_coolant.ρ, sat_coolant.ρᵥ
    hfg, cp, T_sat = sat_coolant.hfg, sat_coolant.cₚ, sat_coolant.Tsat

    drho = rho_l .- rho_v
    lamda = sqrt.(sat_coolant.σ ./ drho ./ g_abs)
    G_star = ṁ ./ pipe.A ./ sqrt.(lamda .* drho .* rho_v .* g_abs)
    A_ratio = pipe.A / (sum(pipe.heated_parts) * pipe.L)

    # The driving temperature differences are the channel's, taken at its two ends. The
    # cp/hfg factor in front of them is local.
    dT_inlet = (cp ./ hfg) .* (first(T_sat) - first(T_bulk))
    dT_outlet = (cp ./ hfg) .* (last(T_sat) - last(T_bulk))

    q1 = _SKq1.(G_star)
    q2 = _SKq2.(A_ratio, G_star, dT_inlet)
    q3 = _SKq3.(A_ratio, pipe.width, lamda, dT_inlet, rho_v, rho_l)
    q4 = _SKq4.(G_star, dT_outlet)

    # Downward or horizontal flow takes the forced selection; upward flow also admits q1.
    forced = max.(min.(q2, q4), q3)
    q_star = ifelse.(G_star .>= 0, forced, max.(forced, q1))

    return q_star .* hfg .* sqrt.(lamda .* drho .* rho_v .* g_abs)
end

@doc raw"""
    q_CHF_mirshak(T_bulk, T_sat, pressure, v) -> q_CHF [W/m^2]

Critical heat flux from the Mirshak correlation [Mirshak1959](@cite), for fast flows
(`v > 1.5` m/s):

```math
q_{CHF} = 1.51 \cdot 10^6 \, (1 + 0.1198 \, v)(1 + 0.00914 \, (T_{sat} - T_{bulk}))(1 + 1.9 \cdot 10^{-6} p)
```

in W/m², with `v` in m/s and `p` in Pa. See [Critical heat flux](@ref).

# Arguments
- `T_bulk`: bulk coolant temperature [°C]
- `T_sat`: saturation temperature [°C]
- `pressure`: system pressure [Pa]
- `v`: coolant flow velocity [m/s]

# Returns
CHF heat flux `q_CHF` [W/m²].

# Examples
```jldoctest
julia> Thresholds.q_CHF_mirshak(46.85, 100.0, 1e5, 2.0)
3.30950620425684e6
```
"""
function q_CHF_mirshak(T_bulk, T_sat, pressure, v)
    return 1.51e6 *
           (1 + 0.1198 * v) *
           (1 + 0.00914 * (T_sat - T_bulk)) *
           (1 + 1.9e-6 * pressure)
end

@doc raw"""
    q_CHF_fabrega(T_inlet, T_sat, pipe) -> q_CHF [W/m^2]

Critical heat flux from Fabrèga's low-flow correlation [Fabrega1971](@cite), for slow flows
(`v < 0.5` m/s):

```math
q_{CHF} = 10^7 \, D_h \, (0.023 \, (T_{sat} - T_{inlet}) + 4.56)
```

in W/m², with `Dh` in m. See [Critical heat flux](@ref).

# Arguments
- `T_inlet`: coolant bulk temperature at inlet [°C]
- `T_sat`: saturation temperature [°C]
- `pipe`: channel geometry [`PipeGeometry`] (uses `pipe.Dh`)

# Returns
CHF heat flux `q_CHF` [W/m²].

# Examples
```jldoctest
julia> pipe = PipeGeometry_rectangular(0.6, 0.0671, 0.0024, 0.0671);  # 2.4 mm MTR gap

julia> Thresholds.q_CHF_fabrega(26.85, 100.0, pipe)
289290.40230215824
```
"""
function q_CHF_fabrega(T_inlet, T_sat, pipe)
    return 1e7 * pipe.Dh * (0.023 * (T_sat - T_inlet) + 4.56)
end

@doc raw"""
    twall_limit(T_bulk, T_wall, inhomogeneity_factor=1.0) -> T_limit [°C]

Wall temperature the face would reach if the local heat flux were worse by
`inhomogeneity_factor`.

```math
T_{limit} = T_{bulk} + f \, (T_{wall} - T_{bulk})
```

The solution carries no fuel inhomogeneity, so the wall temperature it reports understates the
hot spot. Scaling the flux by `f` and reading the wall temperature back off Newton's law gives
the temperature to check against. Python STREAM writes the same thing as `T_bulk + q f / h`,
since `q = h (T_wall - T_bulk)`. See [Wall temperature limit](@ref).

Needs a channel carrying a wall temperature, so `Channel` or `ChannelAndContacts`. See
[`ChannelState`](@ref) for `ChannelHeatFlux`.

# Arguments
- `T_bulk`: bulk coolant temperature [°C]
- `T_wall`: wall temperature on the face being checked [°C]
- `inhomogeneity_factor`: dimensionless flux multiplier (default 1.0, no correction)

# Returns
Effective wall temperature limit `T_limit` [°C].

# Examples
A 100 K rise worsened by 20%:
```jldoctest
julia> Thresholds.twall_limit(26.85, 126.85, 1.2)
146.85
```
"""
function twall_limit(T_bulk, T_wall, inhomogeneity_factor=1.0)
    return T_bulk + inhomogeneity_factor * (T_wall - T_bulk)
end
