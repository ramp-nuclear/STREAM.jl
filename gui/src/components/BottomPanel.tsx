import { Tabs, TabsContent, TabsList, TabsTrigger } from "./ui/tabs";
import useStore from "../store/useStore";
import { useBottomPanelResize } from "../hooks/useBottomPanelResize";
import CodePreview from "./CodePreview";
import BCPanel from "./BCPanel";

export default function BottomPanel() {
  const bottomPanelOpen = useStore((s) => s.bottomPanelOpen);
  const bottomPanelHeight = useStore((s) => s.bottomPanelHeight);
  const { onMouseDown } = useBottomPanelResize();

  if (!bottomPanelOpen) return null;

  return (
    <div style={{ height: bottomPanelHeight }} className="border-t flex flex-col">
      {/* Drag handle */}
      <div
        className="h-2 w-full cursor-row-resize hover:bg-ring/30 transition-colors flex-shrink-0"
        onMouseDown={onMouseDown}
      />
      <Tabs defaultValue="code" className="flex-1 min-h-0 flex flex-col">
        <TabsList className="mx-2 mt-1">
          <TabsTrigger value="code" className="text-[13px] font-medium">
            Code
          </TabsTrigger>
          <TabsTrigger value="bcs" className="text-[13px] font-medium">
            BCs
          </TabsTrigger>
        </TabsList>
        <TabsContent value="code" className="flex-1 min-h-0">
          <CodePreview />
        </TabsContent>
        <TabsContent value="bcs" className="flex-1 min-h-0">
          <BCPanel />
        </TabsContent>
      </Tabs>
    </div>
  );
}
