import { useState } from "react";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "./ui/select";
import { Input } from "./ui/input";
import { Button } from "./ui/button";
import useStore, { type StreamNodeData } from "../store/useStore";
import { validateReal } from "../lib/validation";
import BCRow from "./BCRow";

export default function BCPanel() {
  const nodes = useStore((s) => s.nodes);
  const bcs = useStore((s) => s.bcs);
  const addBC = useStore((s) => s.addBC);
  const removeBC = useStore((s) => s.removeBC);

  const [selectedNodeId, setSelectedNodeId] = useState("");
  const [selectedPort, setSelectedPort] = useState("");
  const [valueStr, setValueStr] = useState("");

  const canAdd =
    selectedNodeId !== "" && selectedPort !== "" && valueStr.trim() !== "";

  function handleAdd() {
    const result = validateReal(valueStr);
    if (!result.valid) return;

    addBC({
      nodeId: selectedNodeId,
      portField: selectedPort as "port_in.P" | "port_out.P",
      value: result.value,
    });

    setSelectedNodeId("");
    setSelectedPort("");
    setValueStr("");
  }

  // Resolve nodeId to instanceName
  function getInstanceName(nodeId: string): string | undefined {
    const node = nodes.find((n) => n.id === nodeId);
    if (!node) return undefined;
    return (node.data as unknown as StreamNodeData).instanceName;
  }

  return (
    <div className="p-4 space-y-4 h-full overflow-y-auto">
      {/* Add form */}
      <div className="flex items-center gap-2">
        <Select value={selectedNodeId} onValueChange={setSelectedNodeId}>
          <SelectTrigger className="w-[140px]">
            <SelectValue placeholder="Component" />
          </SelectTrigger>
          <SelectContent>
            {nodes.map((n) => {
              const data = n.data as unknown as StreamNodeData;
              return (
                <SelectItem key={n.id} value={n.id}>
                  {data.instanceName}
                </SelectItem>
              );
            })}
          </SelectContent>
        </Select>

        <span className="text-muted-foreground">.</span>

        <Select value={selectedPort} onValueChange={setSelectedPort}>
          <SelectTrigger className="w-[120px]">
            <SelectValue placeholder="Port" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="port_in.P">port_in.P</SelectItem>
            <SelectItem value="port_out.P">port_out.P</SelectItem>
          </SelectContent>
        </Select>

        <span className="text-muted-foreground font-mono">~</span>

        <Input
          className="w-[120px]"
          placeholder="1.0e5"
          inputMode="decimal"
          value={valueStr}
          onChange={(e) => setValueStr(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && canAdd) handleAdd();
          }}
        />

        <Button
          variant="outline"
          size="sm"
          disabled={!canAdd}
          onClick={handleAdd}
        >
          Add
        </Button>
      </div>

      {/* BC list */}
      {bcs.length === 0 ? (
        <div className="text-muted-foreground text-sm space-y-1">
          <p className="font-medium">No boundary conditions added.</p>
          <p>Add a pressure anchor (e.g., pump.port_in.P ~ 1.0e5).</p>
        </div>
      ) : (
        <div className="space-y-2">
          {bcs.map((bc, index) => {
            const name = getInstanceName(bc.nodeId);
            if (!name) return null;
            return (
              <BCRow
                key={`${bc.nodeId}-${bc.portField}-${index}`}
                expression={`${name}.${bc.portField} ~ ${bc.value}`}
                onDelete={() => removeBC(index)}
              />
            );
          })}
        </div>
      )}
    </div>
  );
}
