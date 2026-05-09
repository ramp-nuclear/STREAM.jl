# Phase 54: Variant Rewrites & File Consolidation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-07
**Phase:** 54-Variant Rewrites & File Consolidation
**Areas discussed:** Channel ↔ HeatDiffusion bridge, Drive-aware kwarg shape, Smoke test location & CHF flux source, ChannelHeatFlux signature minimization

---

## Channel ↔ HeatDiffusion bridge

### Initial framing — what real-component bridge for Channel?

| Option | Description | Selected |
|--------|-------------|----------|
| WallPort facade on HeatDiffusion | Add an alternate WallPort exposure to HeatDiffusion alongside (or replacing) ThermalPort. Risk: REQUIREMENTS marks HD stable. | |
| Small WallPort↔ThermalPort adapter component | New `WallToThermal` mini-component bridging the two connector shapes. HD untouched. | |
| Test-only inline adapter (drive-aware stub style) | Non-exported `_HDtoChannelBridge` inside the smoke test file. Mirrors Phase 52 stub pattern. | |
| Defer to Phase 55 / use a different real component | Read criterion 6(a) loosely: 'real external component' need not be HD. | |

**User's response (decisive correction):** "No no no. Channel and ChannelHeatFlux are never meant to connect to Heatdiffusion. ONLY CHANNELANDCONTACTS EVER CONNECTS TO HEATDIFFUSION. you need to save this and remember this forever."

**Outcome:** Architectural rule locked and saved to memory (`feedback_channel_hd_connection_rule.md`). All bridge options invalidated. Question reframed: what real driver supplies Channel's T_wall + h?

### Reframed — what supplies Channel's T_wall + h?

| Option | Description | Selected |
|--------|-------------|----------|
| New `WallTemperatureHTC` BC component | Small new exported component pinning T_wall and h. | |
| Promote Phase 52's `_StubWallDriver` to exported component | Reuse existing pattern. | |
| Keep WallDriver as a test-only helper | Non-exported helper in test file. | |
| ConstantTemperature reused as WallPort source | Adapt existing pattern. | |

**User's response:** "The same as it is done in python STREAM. … providing values for Channel and CHF for what they need (T_wall and h, or q) is meant to be through the external funcs. The method you can manually add custom equations and stuff like that. … we should have a way of adding custom equations that are just meant for giving a variable of some component whatever values you want."

**Outcome:** No new component. User wants the standard MTK acausal idiom — binding equations at compose time (e.g., `ch.thermal_left[i].T_wall ~ value` listed alongside `connect()` calls in the parent `connections` vector). Already used in `src/examples.jl` (`pump.port_in.P ~ 1.0e5`, `ch.thermal.T ~ T_wall`).

### Implication question — does automatic-adiabatic-by-default work for 2-across-1-flow WallPort?

| Option | Description | Selected |
|--------|-------------|----------|
| Confirm: user anchors all cells; no built-in adiabatic | Channel always emits Q_flow eqn; user MUST anchor or no compile. | |
| Built-in default: Channel self-anchors when no equation present | drive_left/right BitVector kwargs. | |
| Hybrid: side-level enum default + per-side override | wall_drive::Symbol with :adiabatic / :left / :right / :both. | |

**User pushed back asking to clarify, then asked the deeper question:** "Hold on I think we are running away from the simple solutions. … I want it to be automatic in the sense that the user does not need to flag if this channel will receive T_wall and h. If he provides it, it works and heats, if not, it just doesn't. no extra work. Is that doable?"

### Deep-dive — MTK structural-determinism analysis presented

Key insight: WallPort is 2-across-1-flow (T_wall + h + Q_flow). When unconnected, MTK Flow rule auto-zeros Q_flow only; the across vars (T_wall, h) remain free. Channel's natural eqn `Q_flow ~ h*A*(T_wall - T)` plus the Flow rule gives 2 equations for 3 unknowns — underdetermined. IC defaults are solver guesses, not equations. ThermalPort is 1-across-1-flow and works automatically because the structure naturally closes.

| Option | Description | Selected |
|--------|-------------|----------|
| Reshape WallPort to 1-across-1-flow (drop h); h moves to a Channel kwarg | Default h=0 ⇒ adiabatic via ThermalPort-like structure. Mirrors Python STREAM. | |
| Drop WallPort entirely; Channel reuses ThermalPort with h as a Channel kwarg | No WallPort at all. Cleanest result; biggest Phase 52 walk-back. | |
| Keep WallPort 2-across-1-flow; user must always anchor | Not automatic. | |
| Keep WallPort but mark T_wall/h as `[input = true]` with defaults | Needs verification spike. | |

**User's response:** "First, Check the [input = true] marking as you said. We don't know if it works but it might work and solve for the exact thing we are trying to do here. If it works perfectly and we confirmed 100% it does exactly what we want it to do in all cases - great, go with that. If it does not work like we want, scarp the input = true and then I would be torn between option 1 and option 2. At that point there would be no difference between WallPort and ThermalPort, no? they both carry the same variables in the same across or through thing. If that is true and they would be the same, we might as well drop WallPort and just use ThermalPort."

### Spike result — `[input = true]` verification

`/tmp/spike_input_true.jl` exercised four configurations:

| Test | Setup | Result |
|------|-------|--------|
| A | unconnected, `[input=true]` | ✗ `ExtraVariablesSystemException` — unset inputs `port1.h`, `port2.T_wall` |
| B | both ports connected, `[input=true]` | ✓ compiles, heats to 400 K correctly |
| C | one connected + one dangling | ✗ same error on the dangling side |
| D | unconnected, no `[input=true]` (sanity) | ✗ fails as expected |

`[input = true]` does NOT auto-close 2-across-1-flow. MTK detects unset inputs but does NOT structurally bind them to default values.

### Lock — h kwarg shape

| Option | Description | Selected |
|--------|-------------|----------|
| `h` accepts Real/AbstractVector/Callable, default 0.0 | Single h kwarg; same per-side or split? | |
| Per-side `h_left`, `h_right` kwargs, each Real/Vector/Callable, default 0.0 | Two-sided like Python STREAM `h_left, h_right` calculate kwargs. | ✓ |
| Single `h` kwarg, two-sided geometry handled inside via heated_parts | Less flexible. | |

**User's choice:** Per-side `h_left`, `h_right` kwargs.

**Outcome:** Drop WallPort. New `Channel(; n, geometry, g, h_left=0.0, h_right=0.0, friction_correlation)`. Mirrors Python STREAM `Channel.calculate(h_left=0.0, h_right=0.0, T_left=None, T_right=None, ...)` defaults exactly.

---

## Drive-aware kwarg shape

**Status:** Made moot by the WallPort-removal pivot. Channel uses ThermalPort (1+1) and CHF uses HeatFluxPort (1+1) — both close structurally without any drive flag.

**Outcome:** No drive-aware kwarg on either Channel or CHF. Adiabatic-by-default is automatic via IC + Flow rule.

---

## Smoke test location & CHF flux source

### CHF q_flux supply mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Keep HeatFluxPort; user binds q_flux per cell via connect() or equations (default 0.0 IC) | HeatFluxPort 1-across-1-flow already adiabatic-by-default. Asymmetric to Channel (which drops its connector for kwargs). | ✓ |
| Drop HeatFluxPort too; q_flux_left/right become Channel-style kwargs | Symmetric with new Channel; walks back HeatFluxPort entirely. | |
| Keep HeatFluxPort but add convenience kwargs (q_flux_left/right) that bind to ports internally | Maximizes flexibility. | |

**User's choice:** Keep HeatFluxPort.

### Smoke test file location

| Option | Description | Selected |
|--------|-------------|----------|
| New `test/test_channels.jl` matching new src filename | Matches CLAUDE.md test-mirrors-src rule. Phase 55 (TEST-01) ports the rest of test/test_channel.jl into test_channels.jl and deletes the old. | ✓ |
| Append to existing `test/test_channel.jl`; Phase 55 renames | Avoids interim file. | |
| Inline in `test/test_connectors.jl` next to Phase 52 stubs | Stretches test-mirrors-src rule. | |

**User's choice:** New `test/test_channels.jl`.

---

## ChannelHeatFlux signature minimization

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal: `(; n, geometry, g, friction_correlation)` | Remove both T_wall and htc_correlation. q purely external via HeatFluxPort. | ✓ |
| Keep htc_correlation for an h_tc[i] diagnostic observable, drop T_wall | Bloat. | |
| Keep both for backward-compat | Causes scope creep against VAR-02. | |

**User's choice:** Minimal.

---

## Wrap-up — additional doc fixes during this discuss

| Option | Description | Selected |
|--------|-------------|----------|
| I'm ready for context | Write CONTEXT.md and DISCUSSION-LOG.md as-is. | |
| Explore more gray areas | Continue discussing further. | |
| Update ROADMAP success criterion 6(a) now before writing CONTEXT.md | Fix the 'Channel ↔ HeatDiffusion' wording bug inline. | ✓ |

**User's choice:** Update ROADMAP. Done — Phase 54 success criterion 6 rewritten to align with the architectural rule (Channel/CHF never wire to HeatDiffusion; replaced with kwarg-driven Channel and binding-equation-driven CHF smoke specs).

| Option | Description | Selected |
|--------|-------------|----------|
| Update VAR-01 wording in REQUIREMENTS.md now | Edit VAR-01 to drop the WallPort/CONN-01 reference and reflect the new architecture. | ✓ |
| Leave VAR-01 as-is; capture inconsistency in CONTEXT.md | Pragmatic; intent still holds. | |
| Update both VAR-01 and add an explicit walk-back note for CONN-01 | Most thorough. | |

**User's choice:** Update VAR-01. Done — REQUIREMENTS.md VAR-01 rewritten to describe the ThermalPort + h-kwarg mechanism and reference the architectural rule + the `[input=true]` spike.

---

## Claude's Discretion

- Smoke topology specifics (exact n, L_ch, D_ch, h values for the smoke loops) — Phase 54 planner picks based on what produces stable transient solves.
- Commit-granularity strategy for the file consolidation (single big commit vs. extract→consolidate→delete sequence) — planner picks per CONTEXT.md D-12.
- Order of variants inside the new `channels.jl` file — planner picks (alphabetical or `_channel_core` first then variants).

## Deferred Ideas

- Phase 55 (TEST-01..03, TEST-05): rewrite `test/test_channel.jl`, fix all shipped builders that pass `T_wall` (`build_loop`, `build_loop_vertical`, `build_loop_transient`, `build_loop_lof_bypass`, `build_loop_pk`), assess whether `composition/helpers.jl` needs any change.
- Phase 56 (TEST-04): cross-validation against Python STREAM under the new energy balance + the new connector architecture.
- MTK upstream issue: file a feature request for "treat unbound inputs with default values as default-valued constants at mtkcompile time" (out of v1.1 scope; spike `/tmp/spike_input_true.jl` is reference).
- STATE.md Key Decisions update: append the v1.1 Phase 54 entries (WallPort removal, h-kwarg architecture, architectural rule) — happens at `/gsd:execute-phase` finalization or via `/gsd:extract-learnings`.
- CONN-01 status in REQUIREMENTS.md: whether to retroactively mark "Superseded by Phase 54 D-01" or leave the audit trail in the VAR-01 footnote — documentation-hygiene decision for Phase 54 planning or Phase 56 milestone close.
