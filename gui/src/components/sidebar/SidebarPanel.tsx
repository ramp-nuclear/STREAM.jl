import useStore from "@/store/useStore";
import type { StreamNodeData } from "@/store/useStore";
import { getComponent } from "@/registry";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import InstanceNameField from "./InstanceNameField";
import ParameterForm from "./ParameterForm";
import ModeToggle from "./ModeToggle";

interface SidebarPanelProps {
  width: number;
}

export default function SidebarPanel({ width }: SidebarPanelProps) {
  const selectedNodeId = useStore((s) => s.selectedNodeId);
  const nodes = useStore((s) => s.nodes);
  const updateNodeParams = useStore((s) => s.updateNodeParams);

  if (selectedNodeId === null) {
    return (
      <div className="h-full border-l shrink-0" style={{ width }}>
        <div className="p-[16px] pt-[32px]">
          <h2 className="text-[16px] font-semibold leading-[1.3]">
            Properties
          </h2>
          <div className="mt-[32px]">
            <p className="text-[14px] font-semibold text-muted-foreground">
              No selection
            </p>
            <p className="text-[14px] text-muted-foreground mt-[8px]">
              Select a component on the canvas to view its properties.
            </p>
          </div>
        </div>
      </div>
    );
  }

  const node = nodes.find((n) => n.id === selectedNodeId);
  if (!node) return null;

  const data = node.data as unknown as StreamNodeData;
  const component = getComponent(data.componentId);

  if (!component) {
    return (
      <div className="h-full border-l shrink-0" style={{ width }}>
        <div className="p-[16px] pt-[32px]">
          <h2 className="text-[16px] font-semibold leading-[1.3]">
            Properties
          </h2>
          <p className="text-destructive text-sm mt-[16px]">
            Unknown component: {data.componentId}
          </p>
        </div>
      </div>
    );
  }

  const activeMode =
    data.constructorMode ?? component.constructorModes[0]?.mode ?? "default";

  return (
    <div className="h-full border-l shrink-0" style={{ width }}>
      <ScrollArea className="h-full">
        <div className="p-[16px] pt-[32px]" key={selectedNodeId}>
          <h2 className="text-[16px] font-semibold leading-[1.3]">
            Properties
          </h2>

          <div className="mt-[24px] flex flex-col gap-[8px]">
            <InstanceNameField
              value={data.instanceName}
              onChange={(name) =>
                updateNodeParams(selectedNodeId, { instanceName: name })
              }
            />
            <Badge variant="secondary">{component.label}</Badge>
          </div>

          <Separator className="my-[24px]" />

          {component.constructorModes.length > 1 && (
            <>
              <ModeToggle
                modes={component.constructorModes}
                activeMode={activeMode}
                onChange={(mode) =>
                  updateNodeParams(selectedNodeId, { constructorMode: mode })
                }
              />
              <Separator className="my-[24px]" />
            </>
          )}

          <ParameterForm
            component={component}
            activeMode={activeMode}
            values={data.parameters}
            onParamChange={(name, value) =>
              updateNodeParams(selectedNodeId, {
                parameters: { [name]: value },
              })
            }
          />
        </div>
      </ScrollArea>
    </div>
  );
}
