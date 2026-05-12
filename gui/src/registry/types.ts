// types.ts — TypeScript interfaces for STREAM.jl component registry schema (v1.1 / schema 2.0)
//
// Phase 61 extends the v0.7 schema with the vocabulary needed by the v1.2 GUI redesign.
// All previous fields remain so the 12 existing component entries continue to parse and the
// pre-rewrite consumers (`gui/src/lib/codeGenerator.ts`, `gui/src/lib/validation.ts`) keep
// compiling. New v1.1 fields are added as optional. Plans 02/03/04 rewrite component
// bodies to populate them; Plan 05 sunsets the legacy `array` / `arrayParam` pair.
//
// Decision references (see .planning/phases/61-registry-audit-rewrite-for-v1-1/61-CONTEXT.md):
//   D-01 / D-02   version + schema bumps
//   D-03 / D-05   top-level external_inputs[] block + per-entry shape
//   D-04          no scope field — structural separation suffices
//   D-06 / D-07   per-factory kind/geom_source
//   D-08          per-factory leaf kwargs (no_default, required_if)
//   D-09          regime_dependent produces ["htc","friction"]
//   D-10 / D-11   type_union + input_modes (kwargs) vs bc_modes (external inputs)
//   D-12 / D-13   PointKinetics + ReactivityController (Reactor Physics / Resources)
//   D-14 / D-15   BCPort GUI-only port type
//   D-16 / D-17   array_size, default_axis, pair_with
//   D-18..D-21    concrete channel-family port deltas

/**
 * GUI-only port-type tag for value-source outputs (WallTemperature, HeatFluxSource).
 *
 * `BCPort` has no `src/` counterpart and no MTK connector type — the underlying binding
 * is a plain `@variable` equality (`ch.T_wall_left[i] ~ wt.T_wall_out[i]`). The tag is
 * what enables the dashed-edge rendering style and the connection-time hard-blocks
 * (e.g., `BCPort(T_wall) → CHF.q_*` rejected). See CONTEXT D-14.
 */
export type PortType = "FlowPort" | "ThermalPort" | "BCPort";

export interface Port {
  name: string;
  type: PortType;
  /**
   * Static port side on the icon.
   *
   * Optional in v1.1: array-shaped logical ports that use `default_axis` to autoflip
   * may leave `side` undefined; non-autoflip components (Pump, Resistor, etc.) keep
   * it set as before.
   */
  side?: "left" | "right" | "top" | "bottom";

  /**
   * Legacy v0.7 array flag — kept for backwards compatibility with the 12 not-yet-rewritten
   * entries and with `gui/src/lib/codeGenerator.ts` array-port handling. Plan 05 sunsets it.
   */
  array?: boolean;
  /**
   * Legacy v0.7 sibling of `array`: name of the size parameter (e.g., `"n"` or `"nz"`).
   * Plan 05 sunsets it in favor of `array_size`.
   */
  arrayParam?: string;

  /**
   * v1.1: size of an array-shaped logical port. String-valued; references a sibling
   * `parameters[]` entry (e.g., `"n"` or `"nz"`). Replaces `array` + `arrayParam`. See D-16.
   */
  array_size?: string;

  /**
   * v1.1: which axis the port pair defaults to when the icon autoflips (§3.4). See D-16.
   *   - CAC `thermal_left`/`thermal_right`     → `"vertical"`
   *   - HeatDiffusion `thermal_left`/`thermal_right` → `"horizontal"`
   *   - Value-source `T_wall_out` / `q_out`    → `"horizontal"` with static `side: "right"`
   */
  default_axis?: "horizontal" | "vertical";

  /**
   * v1.1: name of the opposing port in a thermal pair. Locks the autoflip code to put
   * the two ports on opposite faces of the icon. See D-17.
   */
  pair_with?: string;
}

export interface FunctionOption {
  value: string;
  /**
   * Display label. Optional in v1.1 — some Phase 61 factory entries omit it (the rewrite
   * plans will keep `label` where it already exists). See D-06.
   */
  label?: string;
  /**
   * Factory kind discriminator.
   *   - `"simple"`    legacy v0.7 value (still emitted by the 12 unrewritten entries).
   *   - `"stateless"` v1.1 replacement for stateless options (`dittus_boelter`, etc.). See D-07.
   *   - `"factory"`   factory option that returns a closure built from `sub_parameters[]`.
   */
  kind: "simple" | "stateless" | "factory";
  /**
   * Only present when `kind === "factory"`. Recursive — `regime_dependent` nests
   * htc/friction sub-pickers inside its sub_parameters. See D-06.
   */
  sub_parameters?: Parameter[];

  /**
   * v1.1: where the factory gets its geometry from. `"parent"` means the factory derives
   * geometry from the enclosing channel's `geometry` Resource — no `Dh` / `L` / `b` /
   * `aspect_ratio` leaves. Stateless options omit this field. See D-07.
   */
  geom_source?: "parent";

  /**
   * v1.1: which correlation-field consumer slots the factory's return value occupies.
   * `regime_dependent` returns a NamedTuple `(htc=fn, friction=fn)` and carries
   * `produces: ["htc", "friction"]`. The registry stays simple — Phase 66 owns the
   * dedupe codegen rule. See D-09.
   */
  produces?: ReadonlyArray<"htc" | "friction">;
}

// Represents a selected factory correlation value with its configured sub-parameters
export interface FactoryCorrelationValue {
  kind: "factory";
  value: string;
  subParams: Record<string, unknown>;
}

export interface Parameter {
  name: string;
  /**
   * Single-type kwarg type. Mutually exclusive with `type_union` — when `type_union` is
   * set, `type` is omitted. `"Vector"` and `"Symbol"` are v1.1 additions (D-12, D-13).
   */
  type?: "Real" | "Int" | "Bool" | "PipeGeometry" | "Function" | "Matrix" | "Vector" | "Symbol";

  /**
   * v1.1: polymorphic kwarg type list — used together with `input_modes`. See D-10, D-12.
   *   - Channel `h_left` / `h_right`, WallTemperature `T_wall`, HeatFluxSource `q`:
   *     `["Real", "Vector", "Function"]`
   *   - PointKinetics `rho`:
   *     `["Real", "Function", "ReactivityController"]`
   *   - PointKinetics `temp_worth` / `ref_temp`:
   *     `["Mark"]`  (rendered as "mark in code" — user fills the dict in generated .jl)
   *   - ReactivityController `input_reactivity` / `state_machine` / `abort_states`:
   *     `["Mark"]`
   */
  type_union?: ReadonlyArray<"Real" | "Vector" | "Function" | "ReactivityController" | "Mark" | "Symbol">;

  /**
   * v1.1: GUI mode-picker labels paired 1:1 with `type_union[]`. See D-10, D-12.
   * Constructor kwargs use this list; external-input fields use `bc_modes` instead (D-11).
   */
  input_modes?: ReadonlyArray<"scalar" | "vector" | "callable" | "controller">;

  unit?: string;
  default?: number | string | boolean | null;
  description?: string;
  required: boolean;
  positional: boolean;
  options?: FunctionOption[];

  /**
   * v1.1: when true, the parameter is required but the GUI MUST NOT silently substitute
   * a default. `developing_laminar_h_spl.develop_length` uses this (Phase 59 D-04 forbids
   * silent substitution with `geom.L`). See D-08.
   */
  no_default?: boolean;

  /**
   * v1.1: parameter is required only when another (named) parameter is set.
   * `regime_dependent.g` uses `required_if: "htc_natural"`. See D-08.
   */
  required_if?: string;

  /**
   * v1.1: GUI visibility predicate evaluated against sibling parameter modes.
   * `temp_worth` / `ref_temp` use `"rho.input_mode in ['callable','controller']"`. See D-12.
   */
  visible_when?: string;
}

export interface ConstructorMode {
  mode: string;
  signature: string;
  parameters: string[];
}

/**
 * v1.1: top-level array per component entry declaring external `@variable` inputs (the
 * BCs tab of the property panel). Distinct from `parameters[]`, which stays a pure
 * constructor-kwarg list. Components with no external inputs (CAC, Pump, value-sources
 * themselves) simply omit the block. See D-03, D-05.
 */
export interface ExternalInput {
  name: string;
  /** Shape literal as it appears in `@variables`, e.g. `"[1:n]"`. */
  shape: string;
  unit?: string;
  description: string;
  /**
   * BCs-tab mode list — deliberately distinct from constructor `input_modes`. `"Mark"`
   * emits a `# TODO:` comment in generated Julia; `"Source"` creates a bidirectional
   * sync to a `WallTemperature` / `HeatFluxSource` block on the canvas (the dashed
   * BC edge). See D-11.
   */
  bc_modes: ReadonlyArray<"Value" | "Profile" | "Function" | "Mark" | "Source">;
  /** Allowed value-source component id (e.g., `"WallTemperature"`). See D-15. */
  source_component: string;
  /** Allowed output port name on the source component (e.g., `"T_wall_out"`). See D-15. */
  source_port: string;
}

export interface ComponentDefinition {
  id: string;
  label: string;
  /**
   * Component category. `"Hydraulic"` and `"Thermal"` are the v0.7 values; v1.1 adds
   * `"Sources"` (value-source blocks), `"Resources"` (non-canvas resources like
   * `ReactivityController`), and `"Reactor Physics"` (`PointKinetics`). See D-03, D-12,
   * D-13.
   */
  category: "Hydraulic" | "Thermal" | "Sources" | "Resources" | "Reactor Physics";
  description: string;
  /**
   * Canvas ports. Required on every entry that exists in v1.1 components.json today.
   * Plan 04 introduces the first Resource entry (`ReactivityController`, no ports per
   * D-13) and will widen this to optional then; doing it now would force a cascade of
   * non-null assertions across `StreamNode`, `CanvasPanel`, `useStore`, `codeGenerator`,
   * `layers`, `validation`, all of which legitimately assume canvas components have
   * ports. Plan 01 stays additive — keep required for now.
   */
  ports: Port[];
  parameters: Parameter[];
  /**
   * Constructor modes. Required on every entry that exists in v1.1 components.json today.
   * Plan 04 widens this to optional when `ReactivityController` (a plain Julia struct
   * with no MTK constructor mode, D-13) lands. Plan 01 stays additive.
   */
  constructorModes: ConstructorMode[];

  /**
   * v1.1: external `@variable` inputs (the BCs tab). Absent on components with no
   * external inputs. See D-03.
   */
  external_inputs?: ReadonlyArray<ExternalInput>;

  /**
   * v1.1: machine-readable resource kind for Resource entries. `ReactivityController`
   * carries `"reactivity_controller"`. See D-13.
   */
  resource_kind?: string;

  _note?: string;
}

export interface ComponentRegistry {
  stream_version: string;
  schema_version: string;
  components: ComponentDefinition[];
}
