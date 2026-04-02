// Stub - replaced in Task 2
import type { ConstructorMode } from "@/registry/types";

interface ModeToggleProps {
  modes: ConstructorMode[];
  activeMode: string;
  onChange: (mode: string) => void;
}

export default function ModeToggle({ modes: _modes, activeMode: _activeMode, onChange: _onChange }: ModeToggleProps) {
  return <div>ModeToggle placeholder</div>;
}
