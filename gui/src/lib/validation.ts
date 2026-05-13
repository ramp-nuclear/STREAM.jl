// validation.ts — Field validation functions for parameter editing sidebar

export type ValidationResult =
  | { valid: true; value: number }
  | { valid: false; message: string };

export type StringValidationResult =
  | { valid: true; value: string }
  | { valid: false; message: string };

export function validateInt(value: string): ValidationResult {
  if (value.trim() === "") return { valid: false, message: "Required" };
  const n = Number(value);
  if (!Number.isInteger(n)) return { valid: false, message: "Must be a positive integer" };
  if (n <= 0) return { valid: false, message: "Must be a positive integer" };
  return { valid: true, value: n };
}

export function validateReal(value: string): ValidationResult {
  if (value.trim() === "") return { valid: false, message: "Required" };
  const n = Number(value);
  if (isNaN(n) || !isFinite(n)) return { valid: false, message: "Must be a finite number" };
  return { valid: true, value: n };
}

export function validatePositiveReal(value: string): ValidationResult {
  const result = validateReal(value);
  if (!result.valid) return result;
  if (result.value <= 0) return { valid: false, message: "Must be positive" };
  return result;
}

export function validateJuliaIdentifier(value: string): StringValidationResult {
  if (value.trim() === "") return { valid: false, message: "Required" };
  if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(value)) {
    return {
      valid: false,
      message:
        "Must be a valid Julia identifier (letters, digits, underscores; start with letter or underscore)",
    };
  }
  return { valid: true, value };
}

// ---------------------------------------------------------------------------
// Topology validation (Phase 39)
// ---------------------------------------------------------------------------

import type { Node, Edge } from "@xyflow/react";
import type { AnchorEntry } from "./anchors";
import type { ComponentDefinition } from "../registry/types";

export interface NodeError {
  nodeId: string;
  instanceName: string;
  portName: string;
}

export interface SystemError {
  message: string;
}

export interface TopologyResult {
  valid: boolean;
  nodeErrors: NodeError[];
  systemErrors: SystemError[];
}

/**
 * Validate the topology of a STREAM.jl canvas graph.
 *
 * Checks:
 * - VALD-01: Every FlowPort on every node must be connected by an edge.
 * - VALD-02: At least one pressure boundary condition must exist.
 * - VALD-03: At least one driving element (Pump or Gravity) must exist.
 *
 * Pure function — no side effects, no store dependency.
 */
export function validateTopology(
  nodes: Node[],
  edges: Edge[],
  anchors: Record<string, AnchorEntry>,
  getComponentDef: (id: string) => ComponentDefinition | undefined,
): TopologyResult {
  const nodeErrors: NodeError[] = [];

  for (const node of nodes) {
    const data = node.data as { componentId: string; instanceName: string };
    const def = getComponentDef(data.componentId);
    if (!def) continue;
    const flowPorts = def.ports.filter((p) => p.type === "FlowPort");
    for (const port of flowPorts) {
      const isInput = port.name.includes("in");
      const connected = edges.some((e) =>
        isInput
          ? e.target === node.id && e.targetHandle === port.name
          : e.source === node.id && e.sourceHandle === port.name,
      );
      if (!connected) {
        nodeErrors.push({
          nodeId: node.id,
          instanceName: data.instanceName,
          portName: port.name,
        });
      }
    }
  }

  const systemErrors: SystemError[] = [];
  if (Object.keys(anchors).length === 0) {
    systemErrors.push({ message: "No pressure boundary condition" });
  }
  const hasDriving = nodes.some((n) => {
    const cid = (n.data as { componentId: string }).componentId;
    return cid === "Pump" || cid === "Gravity";
  });
  if (!hasDriving) {
    systemErrors.push({
      message: "No driving element (add a Pump or Gravity component)",
    });
  }

  return {
    valid: nodeErrors.length === 0 && systemErrors.length === 0,
    nodeErrors,
    systemErrors,
  };
}
