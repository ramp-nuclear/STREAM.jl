// Stub - replaced in Task 2
import type { Parameter } from "@/registry/types";

interface FunctionSelectProps {
  param: Parameter;
  value: unknown;
  onChange: (value: string) => void;
}

export default function FunctionSelect({ param: _param, value: _value, onChange: _onChange }: FunctionSelectProps) {
  return <div>FunctionSelect placeholder</div>;
}
