// types.ts — TypeScript interfaces for STREAM.jl component registry schema

export interface Port {
  name: string;
  type: "FlowPort" | "ThermalPort";
  side: "left" | "right" | "top" | "bottom";
  array?: boolean;
  arrayParam?: string;
}

export interface FunctionOption {
  value: string;
  label: string;
  kind: "simple" | "factory";
  sub_parameters?: Parameter[];  // only present when kind === "factory"
}

// Represents a selected factory correlation value with its configured sub-parameters
export interface FactoryCorrelationValue {
  kind: "factory";
  value: string;
  subParams: Record<string, unknown>;
}

export interface Parameter {
  name: string;
  type: "Real" | "Int" | "Bool" | "PipeGeometry" | "Function" | "Matrix";
  unit?: string;
  default?: number | string | boolean | null;
  description: string;
  required: boolean;
  positional: boolean;
  options?: FunctionOption[];
}

export interface ConstructorMode {
  mode: string;
  signature: string;
  parameters: string[];
}

export interface ComponentDefinition {
  id: string;
  label: string;
  category: "Hydraulic" | "Thermal";
  description: string;
  ports: Port[];
  parameters: Parameter[];
  constructorModes: ConstructorMode[];
  _note?: string;
}

export interface ComponentRegistry {
  stream_version: string;
  schema_version: string;
  components: ComponentDefinition[];
}
