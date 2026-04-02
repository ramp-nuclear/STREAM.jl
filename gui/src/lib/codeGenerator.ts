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
 */
function emitComponentDeclaration(
  nodeData: StreamNodeData,
  component: ComponentDefinition,
): string {
  const lines: string[] = [];

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

  // --- Components section ---
  const nodeDataMap = new Map<string, StreamNodeData>();
  const instanceNames: string[] = [];

  for (const node of nodes) {
    const data = node.data as unknown as StreamNodeData;
    nodeDataMap.set(node.id, data);
    instanceNames.push(data.instanceName);

    const component = getComponent(data.componentId);
    if (!component) {
      lines.push(`# Unknown component: ${data.componentId}`);
      continue;
    }

    lines.push(emitComponentDeclaration(data, component));
  }

  lines.push("");

  // --- Equations section ---
  lines.push("eqs = [");

  // Connections from edges
  for (const edge of edges) {
    const sourceData = nodeDataMap.get(edge.source);
    const targetData = nodeDataMap.get(edge.target);
    if (!sourceData || !targetData) continue;

    const sourceHandle = edge.sourceHandle ?? "port_out";
    const targetHandle = edge.targetHandle ?? "port_in";

    lines.push(
      `    connect(${sourceData.instanceName}.${sourceHandle}, ${targetData.instanceName}.${targetHandle}),`,
    );
  }

  // Boundary conditions
  for (const bc of bcs) {
    const data = nodeDataMap.get(bc.nodeId);
    if (!data) continue; // Skip BC for deleted node

    lines.push(
      `    ${data.instanceName}.${bc.portField} ~ ${formatReal(bc.value)},`,
    );
  }

  lines.push("]");
  lines.push("");

  // --- System section ---
  const systemsList = instanceNames.join(", ");
  lines.push(
    `@named sys = ODESystem(eqs, t; systems=[${systemsList}])`,
  );
  lines.push("ssys = mtkcompile(sys)");
  lines.push("");

  // --- Solve stub ---
  lines.push("# Solve (uncomment to run)");
  lines.push(
    "# sol = solve(SteadyStateProblem(ssys, []), DynamicSS(Rodas5P()))",
  );

  return lines.join("\n");
}
