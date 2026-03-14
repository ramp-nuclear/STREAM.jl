# Phase 12 VAL gap: ChannelAndContacts missing heated-perimeter parameter

## Root cause

Julia's `ChannelAndContacts` hardcodes `π*Dh/2` as the heated perimeter per face.
This is correct for a **circular pipe** but wrong for a **rectangular MTR channel**.

Python STREAM's `EffectivePipe` separates:
- Hydraulic diameter `Dh` → Re, Nu, h [W/m²K], pressure drop
- Heated perimeter per face (`heated_parts[i]`) → area for heat transfer [W]

Julia conflates these. `HeatDiffusion` already uses `y * dz` area for its thermal
port equations. The mismatch:
- `HeatDiffusion.thermal_left[i].Q_flow = k_s * (y * dz) * (T_port - T[i,1]) / (dx/2)` uses plate area
- `ChannelAndContacts.thermal_left[i].Q_flow = h_tc * (π*Dh/2) * dz * (T_port - T[i])` uses circular area
- For y=0.07 m, D=0.01 m: ratio = 0.07 / 0.01571 = 4.46× mismatch

Kirchhoff at the junction still enforces energy conservation in Julia, but the
temperature results diverge significantly from Python (Julia gives physically
correct energy balance for the channel; Python's model is self-consistent but
with different effective geometry).

## Fix required

Add `Pw` (heated perimeter per face, [m]) parameter to `ChannelAndContacts`:

```julia
function ChannelAndContacts(; name, n, L, D, A, g=0.0, Pw=π*D/2)
```

Replace all `π * Dh / 2` in the heat transfer equations with `Pw`:
```julia
# energy balance per cell:
h_tc[i] * Pw * dz * (thermal_left[i].T  - T[i])
+ h_tc[i] * Pw * dz * (thermal_right[i].T - T[i])

# port equations:
thermal_left[i].Q_flow  ~ h_tc[i] * Pw * dz * (thermal_left[i].T  - T[i])
thermal_right[i].Q_flow ~ h_tc[i] * Pw * dz * (thermal_right[i].T - T[i])
```

Default `Pw=π*D/2` preserves all existing tests (backward-compatible).

## VAL test update

In VAL-01/02/03 tests, create channels with `Pw = 0.07` (plate width y):
```julia
@named cac_l = ChannelAndContacts(n=nz, L=0.6, D=0.01, A=7.85e-5, Pw=0.07)
```

## Python reference update

Change `heated_parts` in `generate_mtr_reference.py` to rectangular geometry:
```python
pipe_ch = EffectivePipe(
    length=LZ,
    heated_perimeter=2 * Y_LEN,    # both faces: 2 * 0.07
    wet_perimeter=np.pi * D_H,     # hydraulic: circular equiv
    area=np.pi * D_H**2 / 4,       # same as Julia A=7.85e-5
    heated_parts=(Y_LEN, Y_LEN),   # 0.07 m per face
    width=D_H,
)
```

## Expected outcome

With matching heated perimeter (0.07 m) in both models:
- Both use same h [W/m²K] (Dittus-Boelter with Dh=0.01)
- Both use same area 0.07 * dz per face
- VAL-01/02/03 results should match within 1%
- Validates that Julia-STREAM can model the same MTR system as Python STREAM
