/**
 * CodePreview — Phase 66 Plan 04
 *
 * Section-by-section renderer over the structured `CodeSection[]` produced by
 * `generateCode` (Plan 02). Each `CodeSubBlock` is a wrapper carrying:
 *   - `data-sub-block` attribute (Plan 01 selector contract)
 *   - `data-source-ids` (canvas-node UUIDs the lines came from)
 *   - stable `id="code-sb-{section_lowercase}-{index}"` (scroll/flash anchor)
 *
 * Interactions (Phase 66 D-05..D-11, D-14):
 *   - Hover a sub-block  → writes `sourceIds` into `hoveredSourceIds`.
 *   - Leave a sub-block  → clears `hoveredSourceIds`.
 *   - Click a sub-block  → `togglePinnedForSubBlock(sourceIds)` (additive
 *                         per D-09/D-10; second click on same sub-block
 *                         removes its ids).
 *   - Click empty space inside the panel → `clearPinnedSourceIds()`.
 *   - Triple-click       → fires three click events on the same sub-block →
 *                         pin toggles ON → OFF → ON; net result is ON. This
 *                         is an accepted side effect of preserving native
 *                         text-selection (D-14): no preventDefault on
 *                         mousedown, no select-none.
 *
 * `stream:show-code-for` consumer (D-07, D-08):
 *   The hook `useShowCodeFor` is installed at App.tsx root (Plan 03). It is
 *   ALSO mounted here so the consumer works when CodePreview is rendered
 *   without App (tests). The hook writes `pendingShowCodeFor`; the
 *   `useEffect` below consumes it: find first matching sub-block, pin
 *   additively, scrollIntoView({behavior:'smooth', block:'center'}), flash
 *   for 1.5s via `data-flash="true"`, then `consumePendingShowCodeFor()` to
 *   clear the pending state.
 */

import {
  Fragment,
  memo,
  useEffect,
  useMemo,
  useRef,
  useState,
  useCallback,
} from "react";
import { ScrollArea } from "./ui/scroll-area";
import useStore from "../store/useStore";
import { useShowCodeFor } from "../hooks/useShowCodeFor";
import { getComponent } from "../registry";
import {
  generateCode,
  type CodeSection,
  type CodeSubBlock,
} from "../lib/codeGenerator";

// Lightweight Julia tokenizer for in-panel syntax tinting. Operates on one
// line at a time; comment-from-# wins over everything else on that line
// (Julia has no multi-line strings in our generated output, so this is safe).
type TokKind = "plain" | "comment" | "string" | "macro" | "kw" | "type" | "num";
const JULIA_KEYWORDS = new Set([
  "using", "import", "export", "module", "const", "let", "global", "local",
  "function", "return", "end", "begin", "do",
  "if", "else", "elseif", "while", "for", "in", "break", "continue",
  "try", "catch", "finally", "struct", "mutable",
  "true", "false", "nothing", "missing",
]);
// Phase 72 — syntax classes consume the --syntax-* tokens (One Dark Pro
// anchored, code-editor-lane carve-out per DESIGN.md §2). Comment reuses
// --muted-foreground (no separate token). Theme-aware: light + dark
// resolve via the OKLCH values declared in index.css :root + .dark.
const TOKEN_CLASS: Record<TokKind, string> = {
  plain: "",
  comment: "text-muted-foreground italic",
  string: "text-[var(--syntax-string)]",
  macro: "text-[var(--syntax-macro)]",
  kw: "text-[var(--syntax-keyword)]",
  type: "text-[var(--syntax-type)]",
  num: "text-[var(--syntax-number)]",
};
type Token = { kind: TokKind; text: string };

function tokenizeRaw(line: string): Token[] {
  const out: Token[] = [];
  let i = 0;
  const n = line.length;
  let buf = "";
  const flush = () => {
    if (buf) {
      out.push({ kind: "plain", text: buf });
      buf = "";
    }
  };
  while (i < n) {
    const ch = line[i];
    if (ch === "#") {
      flush();
      out.push({ kind: "comment", text: line.slice(i) });
      return out;
    }
    if (ch === '"') {
      flush();
      let j = i + 1;
      while (j < n && line[j] !== '"') {
        if (line[j] === "\\" && j + 1 < n) j += 2;
        else j++;
      }
      out.push({ kind: "string", text: line.slice(i, Math.min(j + 1, n)) });
      i = j + 1;
      continue;
    }
    if (ch === "@" && i + 1 < n && /[A-Za-z_]/.test(line[i + 1])) {
      flush();
      let j = i + 1;
      while (j < n && /[A-Za-z0-9_]/.test(line[j])) j++;
      out.push({ kind: "macro", text: line.slice(i, j) });
      i = j;
      continue;
    }
    if (/[0-9]/.test(ch)) {
      flush();
      let j = i;
      while (j < n && /[0-9._]/.test(line[j])) j++;
      if (j < n && (line[j] === "e" || line[j] === "E")) {
        j++;
        if (j < n && (line[j] === "+" || line[j] === "-")) j++;
        while (j < n && /[0-9]/.test(line[j])) j++;
      }
      out.push({ kind: "num", text: line.slice(i, j) });
      i = j;
      continue;
    }
    if (/[A-Za-z_]/.test(ch)) {
      flush();
      let j = i;
      while (j < n && /[A-Za-z0-9_!]/.test(line[j])) j++;
      const word = line.slice(i, j);
      if (JULIA_KEYWORDS.has(word)) out.push({ kind: "kw", text: word });
      else if (/^[A-Z]/.test(word)) out.push({ kind: "type", text: word });
      else out.push({ kind: "plain", text: word });
      i = j;
      continue;
    }
    buf += ch;
    i++;
  }
  flush();
  return out;
}

// Module-level cache: most generated lines (boilerplate `using …`, comment
// dividers, repeated `connect(...)` shapes) recur across renders. A Map
// lookup short-circuits the per-character regex walk and — more importantly —
// returns the SAME Token[] reference, which keeps downstream React subtree
// reconciliation cheap. Cap size to avoid leaks if the user pastes huge code.
const tokenizeCache = new Map<string, readonly Token[]>();
const TOKENIZE_CACHE_LIMIT = 4000;
function tokenize(line: string): readonly Token[] {
  const hit = tokenizeCache.get(line);
  if (hit) return hit;
  const fresh = tokenizeRaw(line);
  if (tokenizeCache.size >= TOKENIZE_CACHE_LIMIT) tokenizeCache.clear();
  tokenizeCache.set(line, fresh);
  return fresh;
}

// Build a stable id for a sub-block (module-level so it doesn't allocate
// on every render).
function makeSubBlockId(sectionName: string, i: number): string {
  return `code-sb-${sectionName.toLowerCase()}-${i}`;
}

// One sub-block, memoized — only re-renders when its own content / state
// changes. Without this, every ReactFlow node-drag tick re-creates every
// sub-block's hundreds of token <span>s and React reconciles the whole tree.
interface CodeSubBlockProps {
  id: string;
  lines: readonly string[];
  sourceIds: readonly string[];
  flashed: boolean;
  pinned: boolean;
  interactive: boolean;
  onHover: (sourceIds: readonly string[]) => void;
  onLeave: () => void;
  onPick: (sourceIds: readonly string[]) => void;
  setRef: (el: HTMLElement | null) => void;
}
const CodeSubBlockView = memo(
  function CodeSubBlockView(props: CodeSubBlockProps) {
    const {
      id,
      lines,
      sourceIds,
      flashed,
      pinned,
      interactive,
      onHover,
      onLeave,
      onPick,
      setRef,
    } = props;
    return (
      <pre
        id={id}
        ref={setRef}
        data-sub-block=""
        data-source-ids={sourceIds.join(",")}
        data-flash={flashed ? "true" : undefined}
        data-pinned={pinned ? "true" : undefined}
        data-interactive={interactive ? "true" : undefined}
        onMouseEnter={
          interactive ? () => onHover(sourceIds) : undefined
        }
        onMouseLeave={interactive ? onLeave : undefined}
        onClick={
          interactive
            ? (e) => {
                e.stopPropagation();
                onPick(sourceIds);
              }
            : undefined
        }
        className={[
          // select-text re-enables selection inside this pre (the panel root
          // is select-none so visual selection bands don't bleed across
          // section headers and inter-block gaps; see CodePreview body).
          "whitespace-pre overflow-x-auto transition-colors duration-[80ms] select-text",
          // Phase 72 — border-l-2 colored stripe removed (absolute-ban in
          // PRODUCT.md; ring on pinned + bg-tint already provide the
          // affordance). Interactive sub-blocks get rounded bg + cursor;
          // non-interactive scaffolding (Imports header, `eqs = [`, `]`,
          // Main) renders as plain code so the panel doesn't read as a list
          // of clickable cells.
          interactive
            ? "px-3 py-1.5 rounded-sm cursor-pointer"
            : "px-3 cursor-text",
          // Phase 72 — flash/pinned/hover retokenized. Flash = warning amber
          // (same semantic as canvas validation-flash). Pinned/hover = neutral
          // --foreground (Option A: link state is "foregrounded", no new hue).
          // motion-reduce respected via transition-colors above (duration-0
          // collapses under prefers-reduced-motion via global rule in index.css).
          flashed
            ? "bg-[color-mix(in_oklch,var(--color-warning)_22%,transparent)] ring-2 ring-[var(--color-warning)]"
            : pinned
              ? "bg-[color-mix(in_oklch,var(--foreground)_8%,transparent)] ring-2 ring-[var(--foreground)]"
              : interactive
                ? "hover:bg-[color-mix(in_oklch,var(--foreground)_5%,transparent)]"
                : "",
        ].join(" ")}
      >
        <code>
          {lines.map((line, li) => {
            const toks = tokenize(line);
            return (
              <Fragment key={li}>
                {toks.map((tok, ti) =>
                  tok.kind === "plain" ? (
                    <Fragment key={ti}>{tok.text}</Fragment>
                  ) : (
                    <span key={ti} className={TOKEN_CLASS[tok.kind]}>
                      {tok.text}
                    </span>
                  ),
                )}
                {li < lines.length - 1 ? "\n" : ""}
              </Fragment>
            );
          })}
        </code>
      </pre>
    );
  },
  (prev, next) => {
    // Content equality — skip re-render when nothing the user can see has
    // changed. Reference of `lines` and `sourceIds` is fresh every codegen
    // run, so we MUST compare by content, not by reference.
    if (prev.id !== next.id) return false;
    if (prev.flashed !== next.flashed) return false;
    if (prev.pinned !== next.pinned) return false;
    if (prev.interactive !== next.interactive) return false;
    if (prev.lines.length !== next.lines.length) return false;
    for (let i = 0; i < prev.lines.length; i++) {
      if (prev.lines[i] !== next.lines[i]) return false;
    }
    if (prev.sourceIds.length !== next.sourceIds.length) return false;
    for (let i = 0; i < prev.sourceIds.length; i++) {
      if (prev.sourceIds[i] !== next.sourceIds[i]) return false;
    }
    // Handler refs (onHover/onLeave/onPick/setRef) are intentionally
    // excluded — the parent passes useCallback-stable references, so they
    // never change in practice.
    return true;
  },
);

export default function CodePreview() {
  // Listen for stream:show-code-for at this level too, so the consumer effect
  // below sees `pendingShowCodeFor` even when CodePreview is mounted without
  // App (tests). In production, App's hook also installs a listener; both
  // call setPendingShowCodeFor with the same ids — idempotent.
  useShowCodeFor();

  // PERF — subscribe to a STRING fingerprint of codegen-relevant state, not
  // to the live nodes/edges arrays. ReactFlow replaces the `nodes` array on
  // EVERY position update (60 Hz during drag); a direct subscription
  // re-renders CodePreview, re-runs generateCode, re-tokenizes every line and
  // re-creates hundreds of token <span>s per tick — that was the lag source.
  // Positions never affect generated code, so excluding them from the
  // fingerprint makes drag a no-op for the panel. The selector still runs on
  // every store update, but it's a few hundred microseconds of string-build
  // per tick, vs ms of React reconciliation. The fingerprint key gates a
  // useMemo that grabs the latest data via getState() — no closure capture,
  // no stale-data risk.
  const codegenKey = useStore(
    useCallback((s: ReturnType<typeof useStore.getState>) => {
      let nodesKey = "";
      for (const n of s.nodes) {
        nodesKey += n.id + "|" + (n.type ?? "") + "|" + JSON.stringify(n.data) + ";";
      }
      let edgesKey = "";
      for (const e of s.edges) {
        edgesKey +=
          e.id +
          "|" +
          e.source +
          "|" +
          e.target +
          "|" +
          (e.sourceHandle ?? "") +
          "|" +
          (e.targetHandle ?? "") +
          ";";
      }
      return (
        nodesKey +
        "#" +
        edgesKey +
        "#" +
        JSON.stringify(s.anchors) +
        "#" +
        JSON.stringify(s.resources) +
        "#" +
        s.bcMode +
        "#" +
        JSON.stringify(s.bcSymmetric)
      );
    }, []),
  );
  const pendingShowCodeFor = useStore((s) => s.pendingShowCodeFor);
  // Subscribe to pinnedSourceIds so the code panel itself shows pinned state
  // (canvas already shows the ring via StreamNode subscription — this is the
  // matching code-side affordance for bidirectional visual link).
  const pinnedSourceIds = useStore((s) => s.pinnedSourceIds);

  const sections = useMemo<CodeSection[]>(() => {
    const s = useStore.getState();
    return generateCode(
      s.nodes,
      s.edges,
      { anchors: s.anchors },
      getComponent,
      s.resources,
      { bcMode: s.bcMode, bcSymmetric: s.bcSymmetric },
    );
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [codegenKey]);

  // Ref map keyed by stable sub-block id, for scrollIntoView lookup.
  const subBlockRefs = useRef<Map<string, HTMLElement>>(new Map());

  // Flash state: set of ids (multi-node payload can flash multiple sub-blocks).
  const [flashedIds, setFlashedIds] = useState<Set<string>>(new Set());

  // 1.5s flash auto-clear. Reset whenever the flashed set changes to a
  // non-empty value; a single shared timer is fine because all flashes are
  // triggered together from a single show-code-for event.
  useEffect(() => {
    if (flashedIds.size === 0) return;
    const t = setTimeout(() => setFlashedIds(new Set()), 1500);
    return () => clearTimeout(t);
  }, [flashedIds]);

  // Consumer effect for pendingShowCodeFor.
  useEffect(() => {
    if (!pendingShowCodeFor || pendingShowCodeFor.length === 0) return;

    const targetIds = pendingShowCodeFor;

    // Find ALL matching sub-blocks (one or more, depending on payload). The
    // FIRST match in document order is the scroll target; ALL matches get
    // flashed (D-08 multi-node fan-out).
    const matched: { id: string; sub: CodeSubBlock }[] = [];
    for (const section of sections) {
      for (let i = 0; i < section.subBlocks.length; i++) {
        const sub = section.subBlocks[i];
        if (sub.sourceIds.some((sid) => targetIds.includes(sid))) {
          matched.push({ id: makeSubBlockId(section.name, i), sub });
        }
      }
    }

    if (matched.length > 0) {
      const first = matched[0];
      // Pin (additively) the first match — Plan 04 spec step 2. We deliberately
      // do NOT pin every match: D-09 says pin is sticky and additive; multi-
      // flash is fine, but multi-pin from a single user gesture would be
      // surprising. Hover state is intentionally untouched (D-09 footnote).
      useStore.getState().togglePinnedForSubBlock(first.sub.sourceIds);

      // Scroll first match into view.
      const el = subBlockRefs.current.get(first.id);
      if (el) {
        el.scrollIntoView({ behavior: "smooth", block: "center" });
      }

      // Flash all matches.
      setFlashedIds(new Set(matched.map((m) => m.id)));
    }

    // Always consume the pending state — even on no-match — so the effect
    // doesn't re-fire on the next render.
    useStore.getState().consumePendingShowCodeFor();
  }, [pendingShowCodeFor, sections]);

  // Sub-block event handlers — useCallback-stable so the memoized SubBlockView
  // skips re-render via reference equality.
  const handleSubBlockHover = useCallback(
    (sourceIds: readonly string[]) => {
      useStore.getState().setHoveredSourceIds(sourceIds as string[]);
    },
    [],
  );
  const handleSubBlockLeave = useCallback(() => {
    useStore.getState().clearHoveredSourceIds();
  }, []);
  const handleSubBlockPick = useCallback(
    (sourceIds: readonly string[]) => {
      useStore.getState().togglePinnedForSubBlock(sourceIds as string[]);
    },
    [],
  );

  // Empty-space click on the panel body clears pinned source ids. The handler
  // attaches to the panel-body wrapper and uses `e.target === e.currentTarget`
  // so clicks on sub-blocks (which bubble) do NOT trigger this path.
  const handlePanelBodyClick = useCallback(
    (e: React.MouseEvent<HTMLDivElement>) => {
      if (e.target === e.currentTarget) {
        useStore.getState().clearPinnedSourceIds();
      }
    },
    [],
  );

  // Ref-setter factory — memoized PER id so the function identity is stable
  // across renders (matches the SubBlockView memo equality contract).
  const setSubBlockRefForId = useRef(
    new Map<string, (el: HTMLElement | null) => void>(),
  );
  const getSubBlockRefSetter = useCallback(
    (id: string) => {
      let fn = setSubBlockRefForId.current.get(id);
      if (!fn) {
        fn = (el: HTMLElement | null) => {
          if (el) subBlockRefs.current.set(id, el);
          else subBlockRefs.current.delete(id);
        };
        setSubBlockRefForId.current.set(id, fn);
      }
      return fn;
    },
    [],
  );

  return (
    <ScrollArea className="h-full">
      {/* Phase 72 — body bg removed (was bg-[#0d1117] GitHub-dark borrow,
          a PRODUCT.md anti-reference). CodePreview now inherits --panel
          from BottomPanel — the depth hierarchy (chrome → panel → canvas)
          already gives the code surface its tonal step; no separate
          --code-surface token earned.

          select-none on the root suppresses the browser's visual selection
          band on inter-block gaps, section header rows, and padding. Each
          <pre> sub-block re-enables select-text on itself, so drag-selecting
          across code blocks copies only the code text (no section labels,
          no gap whitespace). */}
      <div
        className="p-4 font-mono text-[13px] leading-[1.55] text-foreground select-none"
        onClick={handlePanelBodyClick}
      >
        {sections.length === 0 ? (
          <div className="text-muted-foreground italic text-xs">
            (empty — add components on the canvas to see generated Julia code)
          </div>
        ) : (
          sections.map((section) => (
            <div
              key={section.name}
              className="mb-5 last:mb-0"
              onClick={handlePanelBodyClick}
            >
              {/* Phase 72 — section header retoken. Dropped the bg-sky-400/80
                  dot slab (SaaS-leading-indicator pattern + raw Tailwind sky)
                  and the text-sky-300/90 heading color. Header is now the
                  ValidationPanel column-label idiom: muted foreground +
                  uppercase + tracking, no marker. The mb-5 rhythm + typography
                  contrast carry the divider. */}
              <h4 className="text-[11px] font-semibold uppercase tracking-[0.12em] text-muted-foreground mb-2 select-none">
                {section.name}
              </h4>
              <div className="flex flex-col gap-1.5">
                {section.subBlocks.map((sub, i) => {
                  const id = makeSubBlockId(section.name, i);
                  const flashed = flashedIds.has(id);
                  // Sub-blocks with no sourceIds (Imports header, Composition
                  // scaffolding `eqs = [` / `]`, Main `@named sys = ...` block)
                  // have no canvas counterpart — hovering/clicking them has no
                  // useful effect. Mark them non-interactive.
                  const interactive = sub.sourceIds.length > 0;
                  const pinned =
                    interactive &&
                    sub.sourceIds.some((sid) => pinnedSourceIds.has(sid));
                  return (
                    <CodeSubBlockView
                      key={id}
                      id={id}
                      lines={sub.lines}
                      sourceIds={sub.sourceIds}
                      flashed={flashed}
                      pinned={pinned}
                      interactive={interactive}
                      onHover={handleSubBlockHover}
                      onLeave={handleSubBlockLeave}
                      onPick={handleSubBlockPick}
                      setRef={getSubBlockRefSetter(id)}
                    />
                  );
                })}
              </div>
            </div>
          ))
        )}
      </div>
    </ScrollArea>
  );
}
