// codeGenerator.ts -- Pure code generation function: canvas state -> STREAM.jl Julia code
//
// Zero React dependencies. Transforms nodes, edges, and boundary conditions
// into valid Julia code that uses ModelingToolkit and STREAM.jl.
//
// Phase 62 (D-21, D-22, D-25, D-26 — INV-CG-01..04):
// - Resource declarations (Geometries + Power Shapes) are emitted at the top of
//   the generated script BEFORE the first @named component constructor.
// - Component constructors reference resources by their declared variable name
//   via _ref UUID lookups (never inline values).
// - Four Power Shape forms emit per kind: uniform / z_cosine / file_loaded /
//   unset (sentinel). The file_loaded form uses rebin_extensive(readdlm(...))
//   from STREAM.jl + DelimitedFiles (conditionally imported).
// - Pitfall 4: resource names that collide with default component instance
//   names get a WARNING comment (full validation framework owns Phase 71).

import type { Node, Edge } from "@xyflow/react";
import type {
  ComponentDefinition,
  Parameter,
  FunctionOption,
  FactoryCorrelationValue,
} from "../registry/types";
import { validateJuliaIdentifier } from "./validation";
import { bcModeKey, type BCModeEntry } from "@/lib/bcMode";

// SENTINEL_UNSET_POWER_SHAPE is duplicated here as a literal (rather than
// imported from useStore.ts) because the store module pulls in zustand and
// React-Flow types that we deliberately keep out of this pure-codegen module
// per the "zero React dependencies" rule above. The value MUST match
// useStore.ts SENTINEL_UNSET_POWER_SHAPE — both sides assert this string
// shape in their respective tests.
const SENTINEL_UNSET_POWER_SHAPE_UUID = "00000000-0000-0000-0000-000000000000";

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

export interface BCEntry {
  nodeId: string;
  portField: "port_in.P" | "port_out.P";
  value: number;
}

// Re-export StreamNodeData shape inline (avoid importing zustand store)
interface StreamNodeData {
  componentId: string;
  instanceName: string;
  parameters: Record<string, unknown>;
  constructorMode?: string;
}

// Phase 62 Resource shapes (local mirror; avoid importing useStore).
// MUST match the shapes declared in gui/src/store/useStore.ts.
export interface CodegenGeometryResource {
  uuid: string;
  name: string;
  kind: "rectangular" | "circular";
  params: { L: number; W?: number; H?: number; D?: number };
}

export interface CodegenPowerShapeResource {
  uuid: string;
  name: string;
  kind: "uniform" | "z_cosine" | "file_loaded" | "unset";
  params: { amplitude?: number; path?: string };
}

export interface CodegenFluidResource {
  uuid: string;
  name: string;
}

export interface CodegenResources {
  geometries: Record<string, CodegenGeometryResource>;
  powerShapes: Record<string, CodegenPowerShapeResource>;
  fluids: Record<string, CodegenFluidResource>;
}

// Phase 63 BC state passed into generateCode. Mirrors the useStore BC slices
// (bcMode / bcSymmetric) without importing the store — keeps the pure-codegen
// purity rule intact.
export interface CodegenBCsState {
  bcMode: Record<string, BCModeEntry>;
  bcSymmetric: Record<string, boolean>;
}

// ---------------------------------------------------------------------------
// Value formatting helpers (not exported)
// ---------------------------------------------------------------------------

/** Format a number as a Julia Real literal (always has a decimal point). */
function formatReal(n: number): string {
  const s = String(n);
  // Already has decimal or scientific notation -> keep as-is
  if (s.includes(".") || s.includes("e") || s.includes("E")) {
    return s;
  }
  return s + ".0";
}

/** Format a number as a Julia Int literal (no decimal). */
function formatInt(n: number): string {
  return String(Math.round(n));
}

/** Format a PipeGeometry value object into a Julia constructor call. */
function formatPipeGeometry(value: unknown): string {
  if (typeof value !== "object" || value === null) {
    return "# TODO: set geometry dimensions";
  }
  const geo = value as Record<string, unknown>;
  if (geo.type === "circular") {
    const L = geo.L;
    const D = geo.D;
    if (L == null || D == null) return "# TODO: set geometry dimensions";
    return `PipeGeometry_circular(${formatReal(L as number)}, ${formatReal(D as number)})`;
  }
  if (geo.type === "rectangular") {
    // PipeGeometry_rectangular(L, edge1, edge2, heated_edge) — see Resources-block
    // emission above for the L/W/H → 4-arg mapping rationale.
    const L = geo.L;
    const W = geo.W;
    const H = geo.H;
    if (L == null || W == null || H == null) return "# TODO: set geometry dimensions";
    return `PipeGeometry_rectangular(${formatReal(L as number)}, ${formatReal(W as number)}, ${formatReal(H as number)}, ${formatReal(W as number)})`;
  }
  return "# TODO: set geometry dimensions";
}

/**
 * Format a Function-type parameter value.
 *
 * - Simple string -> bare identifier (e.g., "dittus_boelter" -> dittus_boelter)
 * - Factory object { kind: "factory", value, subParams } -> value(key1=val1, ...)
 *   Sub-params that match their default (from FunctionOption.sub_parameters) are omitted.
 */
function formatFunctionParam(
  value: unknown,
  options?: FunctionOption[],
): string {
  // Simple string -> bare identifier
  if (typeof value === "string") {
    return value;
  }

  // Factory object
  if (
    typeof value === "object" &&
    value !== null &&
    (value as FactoryCorrelationValue).kind === "factory"
  ) {
    const fv = value as FactoryCorrelationValue;
    const factoryName = fv.value;

    // Look up sub_parameter definitions from the matching FunctionOption
    const optionDef = options?.find((o) => o.value === factoryName);
    const subParamDefs = optionDef?.sub_parameters ?? [];

    // Build sub-param strings, omitting defaults
    const subParts: string[] = [];
    for (const sp of subParamDefs) {
      const subVal = fv.subParams[sp.name];
      if (subVal === undefined) continue;

      // Check against default -- skip if matches
      if (sp.default !== undefined && sp.default !== null) {
        // Compare with type coercion for numbers
        if (typeof sp.default === "number" && typeof subVal === "number") {
          if (sp.default === subVal) continue;
        } else if (sp.default === subVal) {
          continue;
        }
      }

      // Format sub-param value based on type
      let formattedSubVal: string;
      if (sp.type === "Function") {
        formattedSubVal = formatFunctionParam(subVal, sp.options);
      } else if (sp.type === "Real") {
        formattedSubVal = formatReal(subVal as number);
      } else if (sp.type === "Int") {
        formattedSubVal = formatInt(subVal as number);
      } else if (sp.type === "Bool") {
        formattedSubVal = String(subVal);
      } else {
        formattedSubVal = String(subVal);
      }

      subParts.push(`${sp.name}=${formattedSubVal}`);
    }

    // Also handle sub-params not in the definition (shouldn't happen, but be safe)
    // -- skip, rely on registry definitions

    return `${factoryName}(${subParts.join(", ")})`;
  }

  // Fallback
  return String(value);
}

/**
 * Resource-FK resolver result. Used by emitComponentDeclaration for
 * PipeGeometry / Matrix(power_shape) params per Phase 62 INV-CG-02.
 */
interface ResolvedRef {
  /** Emitted Julia expression for the param value (e.g., `geom_mtr` or `missing`). */
  expr: string;
  /** Optional warning comment line to emit BEFORE the @named declaration. */
  warning?: string;
}

/**
 * Format a parameter value based on its type definition.
 *
 * Phase 62 (INV-CG-02): if `resolveRef` is provided and the param is a
 * Resource-FK type (PipeGeometry or Matrix-named-power_shape), the value
 * is treated as a UUID string and resolved to the resource's declared
 * variable name. Inline pre-Phase-62 geometry-object values still flow
 * through formatPipeGeometry as a defensive fallback.
 */
function formatParamValue(
  param: Parameter,
  value: unknown,
  resolveRef?: (param: Parameter, value: unknown) => ResolvedRef | undefined,
): string {
  switch (param.type) {
    case "Real":
      return formatReal(value as number);
    case "Int":
      return formatInt(value as number);
    case "Bool":
      return String(value);
    case "PipeGeometry": {
      if (resolveRef) {
        const ref = resolveRef(param, value);
        if (ref) return ref.expr;
      }
      // Defensive fallback for pre-Phase-62 inline values.
      return formatPipeGeometry(value);
    }
    case "Function":
      return formatFunctionParam(value, param.options);
    case "Matrix": {
      if (resolveRef) {
        const ref = resolveRef(param, value);
        if (ref) return ref.expr;
      }
      // Matrix params are complex; emit as-is for now
      return String(value);
    }
    default:
      return String(value);
  }
}

/**
 * Emit a single component @named declaration line.
 * Returns one or two lines (warning comment + @named).
 *
 * TODO: Phase 66 — wire external_inputs[] into MTK equations.
 * v1.1 Channel and ChannelHeatFlux carry an `external_inputs[]` array (T_wall_left /
 * T_wall_right for Channel; q_left / q_right for ChannelHeatFlux) that this codegen
 * currently ignores. The full BC-to-MTK wiring path (bc_modes "Value" / "Profile" /
 * "Function" / "Mark" / "Source", plus the Source-mode dashed-edge resolution to a
 * WallTemperature or HeatFluxSource block on the canvas) is owned by Phase 66. For
 * Phase 61, the registry only locks in the shape — the emitted Julia for these
 * components is the constructor call without any BC wiring.
 */
function emitComponentDeclaration(
  nodeData: StreamNodeData,
  component: ComponentDefinition,
  resolveRef?: (param: Parameter, value: unknown) => ResolvedRef | undefined,
): string {
  const lines: string[] = [];

  // TODO: Phase 66 — when the active component has external_inputs[], emit a per-BC
  // `# TODO: bind <name>` placeholder block before the @named line. For now the
  // shape is locked in the registry but not yet honored by the generator.

  // Identifier validation warning
  const idResult = validateJuliaIdentifier(nodeData.instanceName);
  if (!idResult.valid) {
    lines.push(
      `# WARNING: Invalid identifier "${nodeData.instanceName}" -- rename before exporting`,
    );
  }

  // Find active constructor mode
  const activeMode =
    component.constructorModes.find(
      (m) => m.mode === nodeData.constructorMode,
    ) ?? component.constructorModes[0];

  const activeParamNames = activeMode.parameters;

  // Partition into positional and keyword, preserving order
  const positionalParts: string[] = [];
  const kwParts: string[] = [];

  for (const paramName of activeParamNames) {
    const paramDef = component.parameters.find((p) => p.name === paramName);
    if (!paramDef) continue;

    // Phase 62: Resource-FK params live under `<name>_ref` in node.data.parameters
    // (e.g. `geometry_ref`, `power_shape_ref`). Plain inline params stay under
    // `<name>` (e.g., `n`, `nz`). Look up FK first, fall back to the plain key.
    const isResourceFK =
      paramDef.type === "PipeGeometry" ||
      (paramDef.type === "Matrix" && paramDef.name === "power_shape");
    const refKey = `${paramName}_ref`;
    const value = isResourceFK
      ? (nodeData.parameters[refKey] !== undefined
          ? nodeData.parameters[refKey]
          : nodeData.parameters[paramName])
      : nodeData.parameters[paramName];

    // Skip if value matches default (default elision)
    if (paramDef.default !== undefined && paramDef.default !== null) {
      if (isValueEqualToDefault(paramDef, value)) continue;
    }

    // Skip if value is undefined and param is not required
    if (value === undefined && !paramDef.required) continue;

    // Required param with no value -- still emit (will produce invalid code, but user sees it)
    if (value === undefined) continue;

    // Resource-FK warning emission BEFORE the @named line (Pitfall 4 + missing ref)
    let formatted: string;
    if (resolveRef && isResourceFK) {
      const ref = resolveRef(paramDef, value);
      if (ref?.warning) {
        lines.push(ref.warning);
      }
      formatted = ref ? ref.expr : formatParamValue(paramDef, value, resolveRef);
    } else {
      formatted = formatParamValue(paramDef, value, resolveRef);
    }

    if (paramDef.positional) {
      positionalParts.push(formatted);
    } else {
      kwParts.push(`${paramName}=${formatted}`);
    }
  }

  // Build arg string
  let argStr: string;
  if (positionalParts.length > 0 && kwParts.length > 0) {
    argStr = `${positionalParts.join(", ")}; ${kwParts.join(", ")}`;
  } else if (positionalParts.length > 0) {
    argStr = positionalParts.join(", ");
  } else if (kwParts.length > 0) {
    argStr = `; ${kwParts.join(", ")}`;
  } else {
    argStr = "";
  }

  lines.push(
    `@named ${nodeData.instanceName} = ${component.id}(${argStr})`,
  );

  return lines.join("\n");
}

/**
 * Compare a parameter value against its default for elision.
 */
function isValueEqualToDefault(param: Parameter, value: unknown): boolean {
  const def = param.default;
  if (def === undefined || def === null) return false;
  if (value === undefined || value === null) return false;

  // For Function type, compare string value or factory object
  if (param.type === "Function") {
    if (typeof value === "string" && typeof def === "string") {
      return value === def;
    }
    // Factory objects are never equal to a string default
    return false;
  }

  // For Real/Int/Bool -- direct comparison
  if (typeof def === "number" && typeof value === "number") {
    return def === value;
  }
  return def === value;
}

// ---------------------------------------------------------------------------
// Thermal topology detection (Phase 40 -- D-07 through D-10)
// ---------------------------------------------------------------------------

interface ThermalAssembly {
  type: "symmetric_plate" | "plate" | "one_sided_connection" | "unknown";
  hdNodeId: string;
  hdInstanceName: string;
  /** For symmetric_plate / one_sided_connection: one CAC. For plate: two CACs (left, right). */
  cacEntries: Array<{
    nodeId: string;
    instanceName: string;
    /** Which CAC thermal port connects to this HD */
    cacSide: "thermal_left" | "thermal_right" | "both";
    /** Which HD side the CAC connects to */
    hdSide: "thermal_left" | "thermal_right" | "both";
  }>;
  ctEntries: Array<{
    nodeId: string;
    instanceName: string;
    /** Which side of the HD the CT connects to */
    hdSide: "thermal_left" | "thermal_right";
  }>;
  assemblyName: string;
}

/**
 * Look up port type from a component definition and handle name.
 */
function getPortTypeFromDef(
  comp: ComponentDefinition | undefined,
  handleName: string,
): "FlowPort" | "ThermalPort" | "BCPort" | undefined {
  if (!comp) return undefined;
  const port = comp.ports.find((p) => p.name === handleName);
  return port?.type;
}

/**
 * Detect thermal wiring topologies from canvas edges.
 *
 * Groups thermal edges by HeatDiffusion node and classifies each group
 * as symmetric_plate, plate, one_sided_connection, or unknown.
 *
 * @returns Array of ThermalAssembly descriptors
 */
export function detectThermalTopology(
  _nodes: Node[],
  edges: Edge[],
  nodeDataMap: Map<string, StreamNodeData>,
  getComponent: (id: string) => ComponentDefinition | undefined,
): ThermalAssembly[] {
  // Partition edges into flow and thermal
  const thermalEdges: Edge[] = [];

  for (const edge of edges) {
    const sourceData = nodeDataMap.get(edge.source);
    const targetData = nodeDataMap.get(edge.target);
    if (!sourceData || !targetData) continue;

    const sourceComp = getComponent(sourceData.componentId);
    const targetComp = getComponent(targetData.componentId);
    const sourcePortType = getPortTypeFromDef(sourceComp, edge.sourceHandle ?? "");
    const targetPortType = getPortTypeFromDef(targetComp, edge.targetHandle ?? "");

    if (sourcePortType === "ThermalPort" && targetPortType === "ThermalPort") {
      thermalEdges.push(edge);
    }
  }

  if (thermalEdges.length === 0) return [];

  // Group thermal edges by HeatDiffusion node
  const hdGroups = new Map<string, Edge[]>();

  for (const edge of thermalEdges) {
    const sourceData = nodeDataMap.get(edge.source);
    const targetData = nodeDataMap.get(edge.target);
    if (!sourceData || !targetData) continue;

    // Find which end is HeatDiffusion
    if (sourceData.componentId === "HeatDiffusion") {
      const existing = hdGroups.get(edge.source) ?? [];
      existing.push(edge);
      hdGroups.set(edge.source, existing);
    } else if (targetData.componentId === "HeatDiffusion") {
      const existing = hdGroups.get(edge.target) ?? [];
      existing.push(edge);
      hdGroups.set(edge.target, existing);
    }
    // Edges with no HD endpoint will be handled as unknown below
  }

  // Check for thermal edges not involving any HD (e.g., HD-to-HD or CT-to-CAC without HD)
  const hdEdgeSet = new Set<string>();
  for (const edges of hdGroups.values()) {
    for (const e of edges) hdEdgeSet.add(e.id);
  }
  const orphanThermalEdges = thermalEdges.filter((e) => !hdEdgeSet.has(e.id));

  const assemblies: ThermalAssembly[] = [];
  let assemblyCounter = 1;

  // Classify each HD group
  for (const [hdNodeId, hdEdges] of hdGroups) {
    const hdData = nodeDataMap.get(hdNodeId)!;

    // Collect CAC connections: which CAC connects via which ports
    const cacConnections = new Map<
      string,
      { nodeId: string; instanceName: string; connections: Array<{ cacPort: string; hdPort: string }> }
    >();
    const ctConnections: ThermalAssembly["ctEntries"] = [];

    for (const edge of hdEdges) {
      const sourceData = nodeDataMap.get(edge.source)!;
      const targetData = nodeDataMap.get(edge.target)!;

      // Determine which end is HD and which is the other component
      let otherNodeId: string;
      let otherData: StreamNodeData;
      let hdPort: string;
      let otherPort: string;

      if (edge.source === hdNodeId) {
        otherNodeId = edge.target;
        otherData = targetData;
        hdPort = edge.sourceHandle ?? "";
        otherPort = edge.targetHandle ?? "";
      } else {
        otherNodeId = edge.source;
        otherData = sourceData;
        hdPort = edge.targetHandle ?? "";
        otherPort = edge.sourceHandle ?? "";
      }

      if (otherData.componentId === "ChannelAndContacts") {
        const existing = cacConnections.get(otherNodeId) ?? {
          nodeId: otherNodeId,
          instanceName: otherData.instanceName,
          connections: [],
        };
        existing.connections.push({ cacPort: otherPort, hdPort });
        cacConnections.set(otherNodeId, existing);
      } else if (otherData.componentId === "ConstantTemperature") {
        ctConnections.push({
          nodeId: otherNodeId,
          instanceName: otherData.instanceName,
          hdSide: hdPort as "thermal_left" | "thermal_right",
        });
      }
      // Other component types connected to HD are unrecognized
    }

    const cacList = Array.from(cacConnections.values());

    let assemblyType: ThermalAssembly["type"];
    const cacEntries: ThermalAssembly["cacEntries"] = [];

    if (cacList.length === 1) {
      const cac = cacList[0];
      const hdSides = new Set(cac.connections.map((c) => c.hdPort));
      const cacSides = new Set(cac.connections.map((c) => c.cacPort));

      if (hdSides.has("thermal_left") && hdSides.has("thermal_right")) {
        // One CAC connected to both sides of HD -> symmetric_plate
        assemblyType = "symmetric_plate";
        cacEntries.push({
          nodeId: cac.nodeId,
          instanceName: cac.instanceName,
          cacSide: "both",
          hdSide: "both",
        });
      } else if (hdSides.size === 1) {
        // One CAC connected to one side of HD -> one_sided_connection
        assemblyType = "one_sided_connection";
        const hdSide = [...hdSides][0] as "thermal_left" | "thermal_right";
        const cacSide = [...cacSides][0] as "thermal_left" | "thermal_right";
        cacEntries.push({
          nodeId: cac.nodeId,
          instanceName: cac.instanceName,
          cacSide,
          hdSide,
        });
      } else {
        assemblyType = "unknown";
      }
    } else if (cacList.length === 2) {
      // Two CACs -> plate
      // Determine which is ch_left and which is ch_right
      // ch_left connects via thermal_right -> HD.thermal_left
      // ch_right connects via thermal_left -> HD.thermal_right
      let chLeft: typeof cacList[0] | undefined;
      let chRight: typeof cacList[0] | undefined;

      for (const cac of cacList) {
        for (const conn of cac.connections) {
          if (conn.hdPort === "thermal_left" && conn.cacPort === "thermal_right") {
            chLeft = cac;
          } else if (conn.hdPort === "thermal_right" && conn.cacPort === "thermal_left") {
            chRight = cac;
          }
        }
      }

      if (chLeft && chRight && chLeft !== chRight) {
        assemblyType = "plate";
        cacEntries.push({
          nodeId: chLeft.nodeId,
          instanceName: chLeft.instanceName,
          cacSide: "thermal_right",
          hdSide: "thermal_left",
        });
        cacEntries.push({
          nodeId: chRight.nodeId,
          instanceName: chRight.instanceName,
          cacSide: "thermal_left",
          hdSide: "thermal_right",
        });
      } else {
        assemblyType = "unknown";
      }
    } else if (cacList.length === 0 && ctConnections.length > 0) {
      // Only CT connections, no assemblies to generate
      // This is handled separately in code gen
      continue;
    } else {
      assemblyType = "unknown";
    }

    assemblies.push({
      type: assemblyType,
      hdNodeId,
      hdInstanceName: hdData.instanceName,
      cacEntries,
      ctEntries: ctConnections,
      assemblyName: `assembly_${assemblyCounter}`,
    });
    assemblyCounter++;
  }

  // Handle orphan thermal edges (no HD involved) -> unknown
  if (orphanThermalEdges.length > 0) {
    // Check if these are CT-to-CAC edges (not involving HD)
    // These don't form assemblies but we still need to handle them in code gen
    // For now, thermal edges without HD are left for the main code gen to handle as-is
  }

  return assemblies;
}

// ---------------------------------------------------------------------------
// Instance path resolution
// ---------------------------------------------------------------------------

/**
 * Resolve the instance path for a node's port, prefixing with assembly name
 * if the node is consumed by a thermal assembly.
 */
function resolveInstancePath(
  nodeId: string,
  data: StreamNodeData,
  handle: string,
  nodeToAssembly: Map<string, ThermalAssembly>,
): string {
  const asm = nodeToAssembly.get(nodeId);
  if (asm) {
    return `${asm.assemblyName}.${data.instanceName}.${handle}`;
  }
  return `${data.instanceName}.${handle}`;
}

// ---------------------------------------------------------------------------
// Main export
// ---------------------------------------------------------------------------

/**
 * Generate valid STREAM.jl Julia code from canvas state.
 *
 * @param nodes - React Flow nodes (insertion order)
 * @param edges - React Flow edges (connections)
 * @param bcs - Boundary condition entries
 * @param getComponent - Registry lookup function
 * @param resources - Phase 62 Resources slice (geometries / power shapes / fluids).
 *   When provided, FK-typed params (PipeGeometry, Matrix-named-power_shape) emit
 *   resource-variable references instead of inline values, and a Resources block
 *   is emitted at the top before the first @named declaration (INV-CG-01).
 * @returns Julia code string
 */
export function generateCode(
  nodes: Node[],
  edges: Edge[],
  bcs: BCEntry[],
  getComponent: (id: string) => ComponentDefinition | undefined,
  resources?: CodegenResources,
  bcsState?: CodegenBCsState,
): string {
  // Empty canvas
  if (nodes.length === 0) {
    return "# Add components to the canvas to generate Julia code.";
  }

  const lines: string[] = [];

  // --- Smoke header comment ---
  lines.push(
    "# =============================================================================",
  );
  lines.push("# Generated by STREAM Composer");
  lines.push(
    "# =============================================================================",
  );

  // --- Header ---
  lines.push("using ModelingToolkit, STREAM");
  lines.push("using ModelingToolkit: t_nounits as t");

  // Phase 62 / 63: conditional DelimitedFiles import. Fires when any
  // file_loaded power shape is present (Phase 62) OR any Profile-file BC mode
  // entry exists (Phase 63 D-07 — readdlm() call in the emitted rebin_intensive
  // line). Keeps the generated script free of unused-package warnings.
  const hasFileLoadedShape =
    resources != null &&
    Object.values(resources.powerShapes).some((p) => p.kind === "file_loaded");
  const hasFileBCMode =
    bcsState != null &&
    Object.values(bcsState.bcMode).some(
      (e) => e.mode === "profile" && e.preset === "file",
    );
  if (hasFileLoadedShape || hasFileBCMode) {
    lines.push("using DelimitedFiles  # for file_loaded power shapes / file BC profiles");
  }
  lines.push("");

  // --- Build nodeDataMap ---
  const nodeDataMap = new Map<string, StreamNodeData>();
  const instanceNames: string[] = [];

  for (const node of nodes) {
    const data = node.data as unknown as StreamNodeData;
    nodeDataMap.set(node.id, data);
    instanceNames.push(data.instanceName);
  }

  // --- Phase 62: Resources block (INV-CG-01..04) ---
  // The variable names declared here are referenced from component constructors
  // via the resolveRef closure below. Per RESEARCH Pitfall 4 (Conservative
  // option), resource names colliding with default component instance names
  // get a WARNING comment, but the codegen still emits them.
  //
  // Per-consumer Power Shape variable naming (RESEARCH Open Question Q2 — pick
  // "separate statement per HD consumer"): each HeatDiffusion that references
  // a Power Shape gets its own assignment line keyed by the HD instance name,
  // so different (nz, nx) consumers don't trample each other.
  //
  // psVarFor: Map<HD nodeId, emitted variable name> — built during the
  // Resources block emission, consumed inside resolveRef.
  const psVarFor = new Map<string, string>();
  const geomNameByUuid = new Map<string, string>();

  // Detect resource-name collisions with default component instance names.
  // Default instance names follow `<componentId.toLowerCase()>_<n>` (see
  // useStore.getNextInstanceName). For each node, record both the actual
  // declared instance name and the default-shape — both forms can collide.
  const componentInstanceNames = new Set<string>();
  for (const node of nodes) {
    const data = node.data as unknown as StreamNodeData;
    componentInstanceNames.add(data.instanceName);
  }

  if (resources) {
    const geometries = Object.values(resources.geometries);
    const powerShapes = Object.values(resources.powerShapes);

    // Need at least one resource line OR HD consumer to render the header.
    const hdNodes = nodes.filter((n) => {
      const data = n.data as unknown as StreamNodeData;
      return data.componentId === "HeatDiffusion";
    });

    if (geometries.length > 0 || hdNodes.length > 0) {
      lines.push(
        "# ---------------------------------------------------------------------------",
      );
      lines.push("# Resources");
      lines.push(
        "# ---------------------------------------------------------------------------",
      );
    }

    // --- Geometries ---
    for (const g of geometries) {
      geomNameByUuid.set(g.uuid, g.name);
      // Pitfall 4: collision warning
      if (componentInstanceNames.has(g.name)) {
        lines.push(
          `# WARNING: Resource name "${g.name}" collides with component instance name "${g.name}" — generated code will not compile; rename the Resource.`,
        );
      }
      if (g.kind === "rectangular") {
        // Julia signature is PipeGeometry_rectangular(L, edge1, edge2, heated_edge)
        // (src/geometry.jl line 60). The GUI's L/W/H map as: L=length,
        // W=edge1 (plate-width cross-section), H=edge2 (channel-gap cross-section),
        // heated_edge=W (the plate's heated face equals the plate width). This
        // matches the MTR plate-fuel convention used throughout STREAM.jl examples
        // (src/examples.jl build_cube). INV-CG-05 (62-11) surfaced the missing
        // fourth argument — the Resources-block emit previously dropped it,
        // producing a MethodError at script runtime.
        const L = g.params.L;
        const W = g.params.W ?? 0;
        const H = g.params.H ?? 0;
        lines.push(
          `${g.name} = PipeGeometry_rectangular(${formatReal(L)}, ${formatReal(W)}, ${formatReal(H)}, ${formatReal(W)})`,
        );
      } else if (g.kind === "circular") {
        const L = g.params.L;
        const D = g.params.D ?? 0;
        lines.push(
          `${g.name} = PipeGeometry_circular(${formatReal(L)}, ${formatReal(D)})`,
        );
      }
    }

    // --- Power Shapes — per-consumer emission ---
    for (const node of hdNodes) {
      const data = node.data as unknown as StreamNodeData;
      const hdName = data.instanceName;
      const psRefRaw =
        data.parameters["power_shape_ref"] ?? data.parameters["power_shape"];
      const psRef = typeof psRefRaw === "string" ? psRefRaw : undefined;
      const nzRaw = data.parameters["nz"];
      const nxRaw = data.parameters["nx"];
      const nz = typeof nzRaw === "number" ? formatInt(nzRaw) : "nz";
      const nx = typeof nxRaw === "number" ? formatInt(nxRaw) : "nx";

      // No ref at all -> emit a missing-ref warning + skip the variable
      if (psRef === undefined) {
        lines.push(`# WARNING: power_shape_ref missing on ${hdName}`);
        continue;
      }

      // Sentinel "unset" -> the verbatim unset emit form per D-26
      if (psRef === SENTINEL_UNSET_POWER_SHAPE_UUID) {
        const varName = `power_shape_unset_for_${hdName}`;
        psVarFor.set(node.id, varName);
        lines.push(
          `${varName} = ones(${nz}, ${nx})  # TODO: fill in your power shape`,
        );
        continue;
      }

      const psResource = powerShapes.find((p) => p.uuid === psRef);
      if (!psResource) {
        lines.push(`# WARNING: power_shape_ref missing on ${hdName}`);
        continue;
      }

      // Skip emission for any reference to the unset sentinel that slipped
      // through the kind-based check (defensive).
      if (psResource.kind === "unset") {
        const varName = `power_shape_unset_for_${hdName}`;
        psVarFor.set(node.id, varName);
        lines.push(
          `${varName} = ones(${nz}, ${nx})  # TODO: fill in your power shape`,
        );
        continue;
      }

      const varName = `power_shape_${psResource.name}_for_${hdName}`;
      psVarFor.set(node.id, varName);

      // Pitfall 4: collision with component instance names
      if (componentInstanceNames.has(psResource.name)) {
        lines.push(
          `# WARNING: Resource name "${psResource.name}" collides with component instance name "${psResource.name}" — generated code will not compile; rename the Resource.`,
        );
      }

      switch (psResource.kind) {
        case "uniform":
          lines.push(`${varName} = ones(${nz}, ${nx})`);
          break;
        case "z_cosine": {
          const amp = psResource.params.amplitude ?? 1.0;
          lines.push(
            `${varName} = cosine_power_shape(${nz}, ${nx}; amplitude=${formatReal(amp)})`,
          );
          break;
        }
        case "file_loaded": {
          const path = psResource.params.path ?? "TODO_set_path.csv";
          lines.push(
            `${varName} = rebin_extensive(readdlm(joinpath(@__DIR__, ${JSON.stringify(path)}), ','), (${nz}, ${nx}))`,
          );
          break;
        }
      }
    }

    if (geometries.length > 0 || hdNodes.length > 0) {
      lines.push("");
    }
  }

  // --- Detect thermal topology ---
  const assemblies = detectThermalTopology(nodes, edges, nodeDataMap, getComponent);
  const hasThermalAssemblies = assemblies.length > 0;

  // Build set of consumed node IDs (CAC + HD nodes in assemblies)
  const consumedNodeIds = new Set<string>();
  for (const asm of assemblies) {
    consumedNodeIds.add(asm.hdNodeId);
    for (const cac of asm.cacEntries) {
      consumedNodeIds.add(cac.nodeId);
    }
  }

  // Build nodeId -> assembly mapping for path resolution
  const nodeToAssembly = new Map<string, ThermalAssembly>();
  for (const asm of assemblies) {
    for (const cac of asm.cacEntries) {
      nodeToAssembly.set(cac.nodeId, asm);
    }
    nodeToAssembly.set(asm.hdNodeId, asm);
  }

  // --- Components section ---
  for (const node of nodes) {
    const data = nodeDataMap.get(node.id)!;
    const component = getComponent(data.componentId);
    if (!component) {
      lines.push(`# Unknown component: ${data.componentId}`);
      continue;
    }

    // resolveRef closure: maps Resource-FK params to the variable name declared
    // in the Resources block. Returns undefined if `resources` was not passed
    // (legacy 4-arg call path keeps inline emission).
    const resolveRef = resources
      ? (param: Parameter, value: unknown): ResolvedRef | undefined => {
          if (param.type === "PipeGeometry") {
            if (typeof value !== "string") return undefined;
            const name = geomNameByUuid.get(value);
            if (!name) {
              return {
                expr: "missing",
                warning: `# WARNING: geometry_ref missing on ${data.instanceName}`,
              };
            }
            return { expr: name };
          }
          if (param.type === "Matrix" && param.name === "power_shape") {
            const varName = psVarFor.get(node.id);
            if (!varName) {
              return {
                expr: "missing",
                warning: `# WARNING: power_shape_ref missing on ${data.instanceName}`,
              };
            }
            return { expr: varName };
          }
          return undefined;
        }
      : undefined;

    lines.push(emitComponentDeclaration(data, component, resolveRef));
  }

  lines.push("");

  // --- Thermal assembly declarations ---
  if (hasThermalAssemblies) {
    for (const asm of assemblies) {
      // Check nz/n mismatch
      const hdData = nodeDataMap.get(asm.hdNodeId);
      if (hdData) {
        const nzVal = hdData.parameters["nz"];
        for (const cac of asm.cacEntries) {
          const cacData = nodeDataMap.get(cac.nodeId);
          if (cacData) {
            const nVal = cacData.parameters["n"];
            if (nzVal !== undefined && nVal !== undefined && nzVal !== nVal) {
              lines.push(
                `# NOTE: HeatDiffusion nz (${nzVal}) must equal ChannelAndContacts n (${nVal}) for this helper to work correctly`,
              );
            }
          }
        }
      }

      if (asm.type === "symmetric_plate") {
        const cac = asm.cacEntries[0];
        lines.push(
          `# Thermal assembly (auto-detected: symmetric_plate)`,
        );
        lines.push(
          `@named ${asm.assemblyName} = symmetric_plate(${cac.instanceName}, ${asm.hdInstanceName})`,
        );
      } else if (asm.type === "plate") {
        const chLeft = asm.cacEntries[0]; // connected to HD.thermal_left
        const chRight = asm.cacEntries[1]; // connected to HD.thermal_right
        lines.push(
          `# Thermal assembly (auto-detected: plate)`,
        );
        lines.push(
          `@named ${asm.assemblyName} = plate(${chLeft.instanceName}, ${chRight.instanceName}, ${asm.hdInstanceName})`,
        );
      } else if (asm.type === "one_sided_connection") {
        const cac = asm.cacEntries[0];
        // Determine side: per helpers.jl:
        // side=:left  => channel.thermal_left  <-> fuel.thermal_right
        // side=:right => channel.thermal_right <-> fuel.thermal_left
        const side = cac.cacSide === "thermal_left" ? ":left" : ":right";
        lines.push(
          `# Thermal assembly (auto-detected: one_sided_connection)`,
        );
        lines.push(
          `@named ${asm.assemblyName} = one_sided_connection(${cac.instanceName}, ${asm.hdInstanceName}; side=${side})`,
        );
      } else {
        // unknown
        lines.push(`# TODO: verify thermal wiring`);
      }
    }
    lines.push("");
  }

  // --- Partition edges into flow and thermal ---
  const flowEdges: Edge[] = [];
  const thermalEdgesNonAssembly: Edge[] = [];

  for (const edge of edges) {
    const sourceData = nodeDataMap.get(edge.source);
    const targetData = nodeDataMap.get(edge.target);
    if (!sourceData || !targetData) continue;

    const sourceComp = getComponent(sourceData.componentId);
    const targetComp = getComponent(targetData.componentId);
    const sourcePortType = getPortTypeFromDef(sourceComp, edge.sourceHandle ?? "");
    const targetPortType = getPortTypeFromDef(targetComp, edge.targetHandle ?? "");

    if (sourcePortType === "ThermalPort" && targetPortType === "ThermalPort") {
      // Thermal edges consumed by assemblies are not emitted as connect() calls
      // Check if NEITHER endpoint involves a recognized assembly
      const sourceInAsm = consumedNodeIds.has(edge.source);
      const targetInAsm = consumedNodeIds.has(edge.target);
      if (!sourceInAsm && !targetInAsm) {
        thermalEdgesNonAssembly.push(edge);
      }
      // Otherwise the assembly helper handles the thermal wiring
    } else {
      flowEdges.push(edge);
    }
  }

  // --- Phase 63: BC pre-eqs emission (profile-vars + function stubs) ---
  // For each consumer node with at least one Profile-cosine / Profile-file /
  // Function BC mode entry, emit the profile-var assignment or function stub
  // BEFORE the `eqs = [` block. Binding equations are emitted INSIDE the eqs
  // block (below) per CONTEXT D-06..D-09 + CD-01..CD-02.
  //
  // bcEmitPlan: per (nodeId, externalInputName) record of the resolved entry
  // and what to emit. Built once here so the pre-eqs and in-eqs passes share
  // the same view. Walks consumer nodes in registry order and partitions by
  // (left, right) for symmetric-expansion handling (D-05).
  interface BCEmitItem {
    consumerNode: Node;
    consumerData: StreamNodeData;
    externalInputName: string;
    entry: BCModeEntry | undefined;
    nValue: string | number;
    // Variable / function name used by the binding equation. Stable per
    // (instanceName, externalInputName) — collisions are extremely unlikely
    // because Julia identifiers + instanceNames are validated.
    profileVarName?: string;
    functionStubName?: string;
    // For symmetric ON, the L emission writes a flag so the R sibling is
    // skipped (the L for-comprehension covers both sides via the sibling
    // binding equation appended).
    isSymmetricLeftPrimary?: boolean;
    siblingExternalInputName?: string;
  }
  const bcEmitPlan: BCEmitItem[] = [];
  if (bcsState !== undefined) {
    for (const node of nodes) {
      const data = nodeDataMap.get(node.id);
      if (!data) continue;
      const comp = getComponent(data.componentId);
      if (!comp?.external_inputs) continue;
      for (const ext of comp.external_inputs) {
        const key = bcModeKey(node.id, ext.name);
        const entry = bcsState.bcMode[key];
        // baseField for symmetric handling (T_wall_left → T_wall).
        const isLeft = ext.name.endsWith("_left");
        const isRight = ext.name.endsWith("_right");
        const baseField = isLeft
          ? ext.name.slice(0, -"_left".length)
          : isRight
            ? ext.name.slice(0, -"_right".length)
            : ext.name;
        const symKey = `${node.id}::${baseField}`;
        const symmetric = bcsState.bcSymmetric[symKey] ?? true;
        // If symmetric ON and this is the RIGHT sibling AND the LEFT sibling
        // has an entry, skip — the LEFT emission will write both sides.
        let isSymmetricLeftPrimary = false;
        let siblingExt: string | undefined;
        if (symmetric && isRight) {
          const leftKey = bcModeKey(node.id, `${baseField}_left`);
          if (bcsState.bcMode[leftKey] !== undefined) {
            continue; // skip — left emission covers both
          }
        }
        if (symmetric && isLeft) {
          const rightKey = bcModeKey(node.id, `${baseField}_right`);
          if (bcsState.bcMode[rightKey] !== undefined || entry !== undefined) {
            isSymmetricLeftPrimary = true;
            siblingExt = `${baseField}_right`;
          }
        }
        const nRaw = data.parameters["n"];
        const nValue: string | number = typeof nRaw === "number" ? nRaw : "n";
        const item: BCEmitItem = {
          consumerNode: node,
          consumerData: data,
          externalInputName: ext.name,
          entry,
          nValue,
          isSymmetricLeftPrimary,
          siblingExternalInputName: siblingExt,
        };
        if (entry?.mode === "profile") {
          item.profileVarName = `${data.instanceName}_${ext.name}_profile`;
        }
        if (entry?.mode === "function") {
          item.functionStubName = entry.functionName;
        }
        bcEmitPlan.push(item);
      }
    }
  }

  // Pre-eqs pass: emit profile-vars and function stubs.
  let bcHeaderEmitted = false;
  const ensureBCHeader = () => {
    if (bcHeaderEmitted) return;
    lines.push("# ---------------------------------------------------------------------------");
    lines.push("# Boundary conditions (Phase 63)");
    lines.push("# ---------------------------------------------------------------------------");
    bcHeaderEmitted = true;
  };
  for (const item of bcEmitPlan) {
    const entry = item.entry;
    if (entry === undefined) continue;
    if (entry.mode === "profile" && entry.preset === "cosine") {
      ensureBCHeader();
      const amp = entry.amplitude;
      const pf = entry.peakingFactor;
      lines.push(
        `${item.profileVarName} = cosine_T_wall_profile(${item.nValue}; amplitude=${formatReal(amp)}, peaking_factor=${formatReal(pf)})`,
      );
    } else if (entry.mode === "profile" && entry.preset === "file") {
      ensureBCHeader();
      const path = entry.path;
      lines.push(
        `${item.profileVarName} = rebin_intensive(readdlm(joinpath(@__DIR__, ${JSON.stringify(path)}), ','), ${item.nValue})`,
      );
    }
  }
  for (const item of bcEmitPlan) {
    const entry = item.entry;
    if (entry?.mode !== "function") continue;
    ensureBCHeader();
    const argList = entry.signature === "fn(t, i)" ? "t, i" : "t";
    lines.push(
      `${entry.functionName}(${argList}) = 0.0  # TODO: define your time-varying boundary condition`,
    );
  }
  if (bcHeaderEmitted) lines.push("");

  // --- Equations section ---
  lines.push("eqs = [");

  // Flow connections (using assembly paths for consumed nodes)
  for (const edge of flowEdges) {
    const sourceData = nodeDataMap.get(edge.source)!;
    const targetData = nodeDataMap.get(edge.target)!;

    const sourceHandle = edge.sourceHandle ?? "port_out";
    const targetHandle = edge.targetHandle ?? "port_in";

    // Resolve instance path: if consumed by assembly, prefix with assembly name
    const sourcePath = resolveInstancePath(edge.source, sourceData, sourceHandle, nodeToAssembly);
    const targetPath = resolveInstancePath(edge.target, targetData, targetHandle, nodeToAssembly);

    lines.push(`    connect(${sourcePath}, ${targetPath}),`);
  }

  // Non-assembly thermal edges (CT-to-CAC without HD, or unrecognized patterns)
  for (const edge of thermalEdgesNonAssembly) {
    const sourceData = nodeDataMap.get(edge.source)!;
    const targetData = nodeDataMap.get(edge.target)!;

    const sourceHandle = edge.sourceHandle ?? "";
    const targetHandle = edge.targetHandle ?? "";

    // Check if this involves a ConstantTemperature connected to an array ThermalPort
    const sourceComp = getComponent(sourceData.componentId);
    const targetComp = getComponent(targetData.componentId);
    const sourcePort = sourceComp?.ports.find((p) => p.name === sourceHandle);
    const targetPort = targetComp?.ports.find((p) => p.name === targetHandle);

    // v1.1 (D-16): array-shaped logical ports now declare `array_size: "<param>"` instead
    // of the legacy `array: true` + `arrayParam: "<param>"` pair. Recognise either form.
    const sourceIsArray = sourcePort?.array === true || typeof sourcePort?.array_size === "string";
    const targetIsArray = targetPort?.array === true || typeof targetPort?.array_size === "string";
    if (sourceIsArray || targetIsArray) {
      // Emit per-cell connect with port() helper
      const arrayPort = sourceIsArray ? sourcePort! : targetPort!;
      const arraySide = sourceIsArray ? sourceData : targetData;
      const singleSide = sourceIsArray ? targetData : sourceData;
      const arrayHandle = sourceIsArray ? sourceHandle : targetHandle;
      const singleHandle = sourceIsArray ? targetHandle : sourceHandle;
      const nParam = arrayPort.array_size ?? arrayPort.arrayParam ?? "n";
      const nVal = arraySide.parameters[nParam] ?? "n";

      lines.push(`    # ConstantTemperature per-cell connections`);
      lines.push(
        `    [connect(${singleSide.instanceName}.${singleHandle}, port(${arraySide.instanceName}, :${arrayHandle}, i)) for i in 1:${nVal}]...,`,
      );
    } else {
      lines.push(
        `    connect(${sourceData.instanceName}.${sourceHandle}, ${targetData.instanceName}.${targetHandle}),`,
      );
    }
  }

  // Boundary conditions
  for (const bc of bcs) {
    const data = nodeDataMap.get(bc.nodeId);
    if (!data) continue;

    // Resolve BC path with assembly prefix if needed
    const asm = nodeToAssembly.get(bc.nodeId);
    const prefix = asm ? `${asm.assemblyName}.` : "";

    lines.push(
      `    ${prefix}${data.instanceName}.${bc.portField} ~ ${formatReal(bc.value)},`,
    );
  }

  // --- Phase 63: BC binding equations (D-06..D-09, CD-01, CD-02) ---
  // Per-mode binding emission. The bcEmitPlan was built before `eqs = [`.
  // For each plan item:
  //   - undefined entry → emit TODO comment only (no equation; D-09 required-unset)
  //   - mode: "value"     → scalar binding for-comprehension
  //   - mode: "profile"   → binding against profile-var declared pre-eqs
  //   - mode: "function"  → binding against function stub declared pre-eqs
  //   - mode: "mark"      → TODO comment only (same shape as undefined; user
  //                          intent differs but codegen output is the same)
  //   - mode: "source"    → binding against source-node array variable
  //
  // Symmetric expansion (D-05): when an item is `isSymmetricLeftPrimary`, the
  // L emission writes a SECOND binding line for the sibling R side (the R
  // sibling itself was filtered out in the plan-building pass).
  let bcEqHeaderEmitted = false;
  const emitBCEqHeaderIfNeeded = (instanceName: string) => {
    if (bcEqHeaderEmitted) return;
    lines.push(`    # BCs for ${instanceName}:`);
    bcEqHeaderEmitted = true;
  };
  for (const item of bcEmitPlan) {
    const { consumerData, externalInputName, entry, nValue, isSymmetricLeftPrimary, siblingExternalInputName } = item;
    const targets: string[] = [externalInputName];
    if (isSymmetricLeftPrimary && siblingExternalInputName) {
      targets.push(siblingExternalInputName);
    }

    if (entry === undefined || entry.mode === "mark") {
      // D-09 / CD-01: emit TODO comment per (consumer.externalInputName), no equation.
      for (const tgt of targets) {
        lines.push(
          `    # TODO: set ${consumerData.instanceName}.${tgt}[i] here`,
        );
      }
      continue;
    }

    if (entry.mode === "value") {
      emitBCEqHeaderIfNeeded(consumerData.instanceName);
      for (const tgt of targets) {
        lines.push(
          `    [${consumerData.instanceName}.${tgt}[i] ~ ${formatReal(entry.value)} for i in 1:${nValue}]...,`,
        );
      }
      continue;
    }

    if (entry.mode === "profile") {
      emitBCEqHeaderIfNeeded(consumerData.instanceName);
      const profVar = item.profileVarName!;
      for (const tgt of targets) {
        lines.push(
          `    [${consumerData.instanceName}.${tgt}[i] ~ ${profVar}[i] for i in 1:${nValue}]...,`,
        );
      }
      continue;
    }

    if (entry.mode === "function") {
      emitBCEqHeaderIfNeeded(consumerData.instanceName);
      const fnName = entry.functionName;
      const argList = entry.signature === "fn(t, i)" ? "t, i" : "t";
      for (const tgt of targets) {
        lines.push(
          `    [${consumerData.instanceName}.${tgt}[i] ~ ${fnName}(${argList}) for i in 1:${nValue}]...,`,
        );
      }
      continue;
    }

    if (entry.mode === "source") {
      // Resolve the source-node instanceName + its BCPort name from the registry.
      const sourceData = nodeDataMap.get(entry.sourceNodeId);
      if (!sourceData) {
        lines.push(
          `    # WARNING: BC source node ${entry.sourceNodeId} not found for ${consumerData.instanceName}.${externalInputName}`,
        );
        continue;
      }
      const sourceComp = getComponent(sourceData.componentId);
      const sourcePort = sourceComp?.ports.find((p) => p.type === "BCPort");
      if (!sourcePort) {
        lines.push(
          `    # WARNING: source node ${sourceData.instanceName} has no BCPort`,
        );
        continue;
      }
      emitBCEqHeaderIfNeeded(consumerData.instanceName);
      for (const tgt of targets) {
        lines.push(
          `    [${consumerData.instanceName}.${tgt}[i] ~ ${sourceData.instanceName}.${sourcePort.name}[i] for i in 1:${nValue}]...,`,
        );
      }
      continue;
    }
  }

  lines.push("]");
  lines.push("");

  // --- System section ---
  if (hasThermalAssemblies) {
    // Use compose_systems: assemblies first, then non-consumed nodes
    const systemParts: string[] = [];
    for (const asm of assemblies) {
      if (asm.type !== "unknown") {
        systemParts.push(asm.assemblyName);
      }
    }
    for (const node of nodes) {
      if (!consumedNodeIds.has(node.id)) {
        const data = nodeDataMap.get(node.id)!;
        systemParts.push(data.instanceName);
      }
    }
    lines.push(
      `@named sys = compose_systems(${systemParts.join(", ")}; connections=eqs, name=:sys)`,
    );
  } else {
    const systemsList = instanceNames.join(", ");
    lines.push(
      `@named sys = ODESystem(eqs, t; systems=[${systemsList}])`,
    );
  }
  lines.push("ssys = mtkcompile(sys)");
  lines.push("");

  // --- Solve stub ---
  lines.push("# Solve (uncomment to run)");
  lines.push(
    "# sol = solve(SteadyStateProblem(ssys, []), DynamicSS(Rodas5P()))",
  );

  return lines.join("\n");
}
