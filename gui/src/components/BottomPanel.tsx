import { Tabs, TabsContent, TabsList, TabsTrigger } from "./ui/tabs";
import useStore from "../store/useStore";
import CodePreview from "./CodePreview";
import BCPanel from "./BCPanel";

export default function BottomPanel() {
  const bottomPanelOpen = useStore((s) => s.bottomPanelOpen);

  if (!bottomPanelOpen) return null;

  return (
    <div className="h-[240px] border-t">
      <Tabs defaultValue="code" className="h-full flex flex-col">
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
