import { ReactFlowProvider } from "@xyflow/react";
import ToolboxPanel from "./components/ToolboxPanel";
import CanvasPanel from "./components/CanvasPanel";
import SidebarPanel from "./components/SidebarPanel";
import Toolbar from "./components/Toolbar";
import BottomPanel from "./components/BottomPanel";

function App() {
  return (
    <ReactFlowProvider>
      <div className="flex flex-col h-screen w-screen overflow-hidden">
        <div className="flex flex-1 min-h-0">
          <ToolboxPanel />
          <div className="flex flex-col flex-1">
            <Toolbar />
            <CanvasPanel />
          </div>
          <SidebarPanel />
        </div>
        <BottomPanel />
      </div>
    </ReactFlowProvider>
  );
}

export default App;
