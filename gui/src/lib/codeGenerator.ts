// codeGenerator.ts -- Pure code generation function: canvas state -> STREAM.jl Julia code
//
// Zero React dependencies. Transforms nodes, edges, and boundary conditions
// into valid Julia code that uses ModelingToolkit and STREAM.jl.

import type { Node, Edge } from "@xyflow/react";
import type {
  ComponentDefinition,
  Parameter,
  FunctionOption,
  FactoryCorrelationValue,
} from "../registry/types";
import { validateJuliaIdentifier } from "./validation";

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
    const L = geo.L;
    const W = geo.W;
    const H = geo.H;
    if (L == null || W == null || H == null) return "# TODO: set geometry dimensions";
    return `PipeGeometry_rectangular(${formatReal(L as number)}, ${formatReal(W as number)}, ${formatReal(H as number)})`;
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
 * Format a parameter value based on its type definition.
 */
function formatParamValue(param: Parameter, value: unknown): string {
  switch (param.type) {
    case "Real":
      return formatReal(value as number);
    case "Int":
      return formatInt(value as number);
    case "Bool":
      return String(value);
    case "PipeGeometry":
      return formatPipeGeometry(value);
    case "Function":
      return formatFunctionParam(value, param.options);
    case "Matrix":
      // Matrix params are complex; emit as-is for now
      return String(value);
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

    const value = nodeData.parameters[paramName];

    // Skip if value matches default (default elision)
    if (paramDef.default !== undefined && paramDef.default !== null) {
      if (isValueEqualToDefault(paramDef, value)) continue;
    }

    // Skip if value is undefined and param is not required
    if (value === undefined && !paramDef.required) continue;

    // Required param with no value -- still emit (will produce invalid code, but user sees it)
    if (value === undefined) continue;

    const formatted = formatParamValue(paramDef, value);

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
  nodes: Node[],
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
 * @returns Julia code string
 */
export function generateCode(
  nodes: Node[],
  edges: Edge[],
  bcs: BCEntry[],
  getComponent: (id: string) => ComponentDefinition | undefined,
): string {
  // Empty canvas
  if (nodes.length === 0) {
    return "# Add components to the canvas to generate Julia code.";
  }

  const lines: string[] = [];

  // --- Header ---
  lines.push("using ModelingToolkit, STREAM");
  lines.push("using ModelingToolkit: t_nounits as t");
  lines.push("");

  // --- Build nodeDataMap ---
  const nodeDataMap = new Map<string, StreamNodeData>();
  const instanceNames: string[] = [];

  for (const node of nodes) {
    const data = node.data as unknown as StreamNodeData;
    nodeDataMap.set(node.id, data);
    instanceNames.push(data.instanceName);
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
    lines.push(emitComponentDeclaration(data, component));
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
      const singlePort = sourceIsArray ? targetPort! : sourcePort!;
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
