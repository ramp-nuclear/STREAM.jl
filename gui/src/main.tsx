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
// JetBrains Mono — locked project mono per DESIGN.md §3 (2026-05-28). The
// variable-font asset registers `JetBrains Mono Variable` family, consumed
// via the `--font-mono` token in index.css. Imported here at the entry so
// font-display=swap rendering doesn't FOUT-flash in the production build.
import "@fontsource-variable/jetbrains-mono";
import App from "./App";
import "./index.css";

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
