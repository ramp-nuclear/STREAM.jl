import { ReactFlowProvider } from "@xyflow/react";
import ToolboxPanel from "./components/ToolboxPanel";
import CanvasPanel from "./components/CanvasPanel";
import SidebarPanel from "./components/SidebarPanel";

function App() {
  return (
    <ReactFlowProvider>
      <div className="flex h-screen w-screen overflow-hidden">
        <ToolboxPanel />
        <CanvasPanel />
        <SidebarPanel />
      </div>
    </ReactFlowProvider>
  );
}

export default App;
