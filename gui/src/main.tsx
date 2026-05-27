import React from "react";
import ReactDOM from "react-dom/client";
// Phase 73 — xyflow's stylesheet MUST be imported before `./index.css` so
// our overrides on `.react-flow` (e.g. `--xy-edge-stroke-default`) land
// later in the cascade and win at equal specificity. Previously this was
// imported deep inside CanvasPanel.tsx, which made it load AFTER index.css
// and silently shadowed every edge-color override. The duplicate import
// in CanvasPanel.tsx stays — both resolve to the same module so Vite
// deduplicates them.
import "@xyflow/react/dist/style.css";
import App from "./App";
import "./index.css";

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
