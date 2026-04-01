# Stack Research

**Domain:** Desktop GUI (Tauri 2 + React + ReactFlow node editor) for STREAM.jl visual composition
**Researched:** 2026-04-01
**Confidence:** HIGH

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Tauri 2 | 2.10.x (`@tauri-apps/cli` 2.10.1, `tauri` crate 2.10.3) | Desktop shell: system webview, native file dialogs, OS integration | Proven Claude Code territory (Claudia, opcode). <10 MB bundle, <0.5s startup. Minimal Rust needed -- file I/O only for v0.8. Cross-platform Win/Linux via WebView2/WebKitGTK. |
| React | 19.2.x (19.2.4 current) | UI framework | Industry standard. Required by ReactFlow. React 19 is stable since Dec 2024; 19.2.4 is latest patch (Jan 2026). |
| @xyflow/react (React Flow 12) | 12.10.x (12.10.2 current) | Node-based canvas editor | 800K+ weekly npm downloads, 26K+ GitHub stars. Built-in zoom/pan/minimap/controls. Custom nodes with typed handles map directly to STREAM.jl FlowPort/ThermalPort. The `reactflow` package name is DEPRECATED -- use `@xyflow/react` (named imports, not default). |
| Vite | 8.0.x (8.0.3 current) | Build tool, dev server, HMR | Vite 8 ships Rolldown (Rust bundler) for 10-30x faster builds. Official Tauri 2 template uses Vite. Sub-second HMR. |
| TypeScript | 5.8.x | Type safety | Non-negotiable for a project with complex component metadata, graph state, and code generation. |
| Tailwind CSS | 4.2.x (4.2.2 current) | Utility-first CSS | v4 has zero-config setup, automatic content detection, 5x faster builds. Required by shadcn/ui. No `tailwind.config.js` needed in v4 -- single CSS import line. |
| shadcn/ui | CLI v4 (March 2026) | UI component library | Copy-paste components (not npm dependency). Uses Radix UI primitives (unified `radix-ui` package since Feb 2026). Prevents hand-rolled CSS. Every button, input, dropdown, dialog, tooltip comes pre-built and accessible. |

### Tauri Plugins (Rust + npm pairs)

| Plugin | npm Package | Cargo Crate | Purpose |
|--------|-------------|-------------|---------|
| Dialog | `@tauri-apps/plugin-dialog` ~2.6.0 | `tauri-plugin-dialog` | Native file open/save dialogs for .streamgui and .jl export |
| Fs | `@tauri-apps/plugin-fs` | `tauri-plugin-fs` | Read/write project files (.streamgui JSON) |
| Store | `@tauri-apps/plugin-store` | `tauri-plugin-store` | Persist recent files list, window state |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| zustand | 5.0.x (5.0.12 current) | Global state management (graph state, undo/redo history, UI panels) | Use for all app state outside ReactFlow's internal state. zustand 5.x is required for React 19 compatibility. ReactFlow 12.6+ bundles zustand 5 internally. |
| @tauri-apps/api | 2.x | Tauri JS API (invoke Rust commands, events) | File system access, window management, app lifecycle |
| lucide-react | latest | Icons for toolbox component categories and node decorations | Use for all icons; consistent with shadcn/ui defaults |
| clsx + tailwind-merge | latest | Conditional class merging | Installed automatically by shadcn/ui init (`cn()` utility) |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Node.js 20 LTS or 22 LTS | JS runtime for dev/build | Tauri 2 requires Node 18+; use LTS for stability |
| Rust stable (1.77.2+) | Tauri backend compilation | Tauri plugins require Rust 1.77.2+. Install via `rustup`. |
| `@tauri-apps/cli` 2.10.x | Tauri CLI (`npm run tauri dev`, `npm run tauri build`) | Install as devDependency |
| ESLint + Prettier | Linting and formatting | Standard React/TS config |

## Installation

### Scaffold (one-time)

```bash
# Create Tauri 2 + React + TypeScript + Vite project
npm create tauri-app@latest stream-composer -- --template react-ts

cd stream-composer

# Install React Flow (use @xyflow/react, NOT reactflow)
npm install @xyflow/react

# Install Tailwind CSS v4 (Vite plugin)
npm install tailwindcss @tailwindcss/vite

# Install zustand for state management
npm install zustand

# Install Tauri plugins (npm side)
npm install @tauri-apps/plugin-dialog @tauri-apps/plugin-fs @tauri-apps/plugin-store

# Initialize shadcn/ui
npx shadcn@latest init

# Add commonly needed shadcn/ui components
npx shadcn@latest add button input label select tabs dialog tooltip scroll-area separator sheet
```

### Cargo.toml (src-tauri/Cargo.toml)

```toml
[dependencies]
tauri = { version = "2", features = [] }
tauri-plugin-dialog = "2"
tauri-plugin-fs = "2"
tauri-plugin-store = "2"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
```

### Dev dependencies (package.json)

```bash
npm install -D @tauri-apps/cli typescript @types/react @types/react-dom eslint prettier
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Tauri 2 | Electron | When you need Chrome DevTools protocol access, or when WebKitGTK rendering issues on Linux are a dealbreaker. Electron bundles Chromium (100+ MB) but guarantees identical rendering everywhere. |
| @xyflow/react | Rete.js | When you need framework-agnostic (Vue/Svelte/Angular) support. Rete has typed ports but smaller ecosystem (26K weekly downloads vs 800K). |
| @xyflow/react | Litegraph.js | When building ComfyUI-style Canvas2D pipelines. Not React-native; poor TypeScript support. |
| zustand | Redux Toolkit | When the team already uses Redux. zustand is simpler (no actions/reducers boilerplate), and ReactFlow uses it internally, so sharing the dependency is natural. |
| zustand | Jotai | When you prefer atomic state. zustand's single-store model is better for undo/redo (snapshot entire state). |
| shadcn/ui | Radix UI directly | When you want full control over styling without any pre-built component patterns. shadcn/ui IS Radix under the hood but with sensible defaults. |
| Vite 8 | Vite 6 | Only if Vite 8's Rolldown integration causes plugin compatibility issues (unlikely -- stable since March 2026). |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `reactflow` (old npm package) | Deprecated since React Flow 12. Named `@xyflow/react` now. Old package stuck at 11.11.4 (2+ years stale). | `@xyflow/react` |
| zustand 4.x | Does not support React 19. Peer dependency conflict. | zustand 5.x |
| Tailwind CSS 3.x | v4 is a complete rewrite with zero-config. v3 requires `tailwind.config.js` and PostCSS plugin. shadcn/ui CLI v4 targets Tailwind v4. | Tailwind CSS 4.x |
| Material UI / Ant Design / Chakra UI | Heavy npm dependencies, opinionated styling that fights Tailwind, larger bundle. shadcn/ui gives you ownership of the code (copy-paste, not dependency). | shadcn/ui |
| Redux | Unnecessary complexity for this app's state. Actions/reducers/middleware overkill. | zustand |
| Tauri 1.x | EOL trajectory. Tauri 2 has been stable since Oct 2024 with active development (2.10.x). Plugin ecosystem is Tauri 2-only now. | Tauri 2.x |
| `@tauri-apps/api` v1 | Incompatible with Tauri 2. The v2 API is a complete rewrite. | `@tauri-apps/api` v2 |
| Monaco Editor (for v0.8) | Overkill for read-only code preview. A `<pre>` block with syntax highlighting (e.g., Prism.js or highlight.js) is sufficient. Monaco adds ~2 MB. Defer to v0.9+ if user code editing is needed. | `<pre>` + basic syntax highlighting |

## Cross-Platform Notes (Windows + Linux)

### WebView Differences

| Platform | WebView Engine | Version | Notes |
|----------|---------------|---------|-------|
| Windows | WebView2 (Chromium-based) | Auto-updates with Edge | Reliable, consistent rendering. Pre-installed on Windows 10/11. |
| Linux | WebKitGTK | Varies by distro | **Primary risk area.** Rendering may differ from Chromium. Font rendering, CSS flexbox edge cases, and animation timing can vary. |

### Mitigation Strategy

1. **Test on both platforms early** (Phase 33 scaffold must run on both before proceeding).
2. **Avoid bleeding-edge CSS** -- stick to Tailwind utilities which abstract browser differences.
3. **shadcn/ui components are tested cross-browser** -- this is a major advantage over hand-rolled CSS.
4. **ReactFlow handles its own canvas rendering** -- the node editor itself is well-tested cross-platform.
5. **File paths**: Use Tauri's path APIs (not hardcoded `/` or `\`). `@tauri-apps/api/path` normalizes paths.

### Linux Prerequisites

```bash
# Ubuntu/Debian
sudo apt install libwebkit2gtk-4.1-dev build-essential curl wget file \
  libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev

# Fedora
sudo dnf install webkit2gtk4.1-devel openssl-devel curl wget file \
  libxdo-devel libappindicator-gtk3-devel librsvg2-devel
```

### Windows Prerequisites

- WebView2 runtime (pre-installed on Windows 10 21H2+ and Windows 11)
- Visual Studio Build Tools 2022 with C++ workload (for Rust compilation)
- Rust via `rustup`

## Version Compatibility Matrix

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| @xyflow/react 12.6+ | React 19.x, zustand 5.x | React 19 support confirmed since 12.6.0 (zustand 5 peer dep) |
| @xyflow/react 12.10.x | Vite 8.x | No known issues; standard ESM package |
| shadcn/ui CLI v4 | Tailwind CSS 4.x, React 19.x | Feb 2026 update switched to unified `radix-ui` package |
| Tailwind CSS 4.x | Vite 8.x | Uses `@tailwindcss/vite` plugin (not PostCSS) |
| Tauri 2.10.x | Node 18+, Rust 1.77.2+ | npm + Cargo versions must stay in sync (same minor) |
| `@tauri-apps/plugin-dialog` 2.6.x | Tauri 2.10.x | Plugin versions track Tauri 2.x major; minor versions may lag |
| zustand 5.0.x | React 19.x | Full React 19 support; no peer dependency issues |

## Project Structure (gui/ directory)

```
gui/
  package.json
  vite.config.ts
  tsconfig.json
  tsconfig.app.json
  src/
    App.tsx                    # Main layout (3-panel: toolbox | canvas | sidebar)
    main.tsx                   # Entry point
    components/
      ui/                      # shadcn/ui components (auto-generated)
      canvas/                  # ReactFlow canvas, custom nodes, edges
      toolbox/                 # Component palette (drag source)
      sidebar/                 # Parameter editing forms
      codegen/                 # Code preview panel
    registry/
      components.json          # STREAM.jl component metadata
    stores/
      graph-store.ts           # zustand: nodes, edges, undo/redo
      project-store.ts         # zustand: file path, dirty flag, recent files
    lib/
      codegen.ts               # Graph-to-Julia code generator
      validation.ts            # Topology validation (unconnected ports, missing BC)
      utils.ts                 # shadcn/ui cn() utility
    styles/
      globals.css              # Tailwind CSS v4 import + ReactFlow styles
  src-tauri/
    Cargo.toml
    src/
      main.rs                  # Tauri entry point, plugin registration
      lib.rs                   # Tauri commands (if any custom Rust commands needed)
    tauri.conf.json            # App config: window size, title, permissions
    capabilities/
      default.json             # Tauri 2 capability permissions for plugins
```

## Sources

- [Tauri 2 Official Docs](https://v2.tauri.app/) -- version 2.10.x, create-project guide, plugin docs (HIGH confidence)
- [Tauri 2 Releases (GitHub)](https://github.com/tauri-apps/tauri/releases) -- crate version 2.10.3 confirmed (HIGH confidence)
- [@tauri-apps/cli npm](https://www.npmjs.com/package/@tauri-apps/cli) -- v2.10.1 confirmed (HIGH confidence)
- [@xyflow/react npm](https://www.npmjs.com/package/@xyflow/react) -- v12.10.2 confirmed (HIGH confidence)
- [React Flow 12 Migration Guide](https://reactflow.dev/learn/troubleshooting/migrate-to-v12) -- package rename, named imports (HIGH confidence)
- [React Flow + React 19 compatibility](https://x.com/xyflowdev/status/1877044785485087175) -- confirmed compatible since @xyflow/react 12.6.0 (HIGH confidence)
- [React npm](https://www.npmjs.com/package/react) -- v19.2.4 confirmed (HIGH confidence)
- [Vite 8 Announcement](https://vite.dev/blog/announcing-vite8) -- Rolldown integration, March 2026 (HIGH confidence)
- [shadcn/ui Changelog](https://ui.shadcn.com/docs/changelog) -- CLI v4 March 2026, unified radix-ui Feb 2026 (HIGH confidence)
- [shadcn/ui Vite Installation](https://ui.shadcn.com/docs/installation/vite) -- setup steps verified (HIGH confidence)
- [Tailwind CSS npm](https://www.npmjs.com/package/tailwindcss) -- v4.2.2 confirmed (HIGH confidence)
- [zustand npm](https://www.npmjs.com/package/zustand) -- v5.0.12, React 19 support (HIGH confidence)
- [Tauri WebView Versions](https://v2.tauri.app/reference/webview-versions/) -- WebView2 vs WebKitGTK platform matrix (HIGH confidence)
- [Tauri Cross-Platform Discussion](https://github.com/tauri-apps/tauri/discussions/12311) -- rendering differences Win vs Linux (MEDIUM confidence)
- [@tauri-apps/plugin-dialog npm](https://www.npmjs.com/package/@tauri-apps/plugin-dialog) -- v2.6.0 confirmed (HIGH confidence)
- [kitlib/tauri-app-template](https://github.com/kitlib/tauri-app-template) -- community template: Tauri v2 + React 19 + shadcn/ui (MEDIUM confidence)

---
*Stack research for: STREAM Composer GUI (v0.8) -- Tauri 2 + React + ReactFlow desktop node editor*
*Researched: 2026-04-01*
