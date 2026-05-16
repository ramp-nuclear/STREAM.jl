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
const TOKEN_CLASS: Record<TokKind, string> = {
  plain: "",
  comment: "text-zinc-500 italic",
  string: "text-emerald-300",
  macro: "text-amber-300",
  kw: "text-purple-300",
  type: "text-sky-300",
  num: "text-orange-300",
};
function tokenize(line: string): { kind: TokKind; text: string }[] {
  const out: { kind: TokKind; text: string }[] = [];
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

export default function CodePreview() {
  // Listen for stream:show-code-for at this level too, so the consumer effect
  // below sees `pendingShowCodeFor` even when CodePreview is mounted without
  // App (tests). In production, App's hook also installs a listener; both
  // call setPendingShowCodeFor with the same ids — idempotent.
  useShowCodeFor();

  const nodes = useStore((s) => s.nodes);
  const edges = useStore((s) => s.edges);
  const anchors = useStore((s) => s.anchors);
  const resources = useStore((s) => s.resources);
  const bcMode = useStore((s) => s.bcMode);
  const bcSymmetric = useStore((s) => s.bcSymmetric);
  const pendingShowCodeFor = useStore((s) => s.pendingShowCodeFor);
  // Subscribe to pinnedSourceIds so the code panel itself shows pinned state
  // (canvas already shows the ring via StreamNode subscription — this is the
  // matching code-side affordance for bidirectional visual link).
  const pinnedSourceIds = useStore((s) => s.pinnedSourceIds);

  const sections = useMemo<CodeSection[]>(
    () =>
      generateCode(nodes, edges, { anchors }, getComponent, resources, {
        bcMode,
        bcSymmetric,
      }),
    [nodes, edges, anchors, resources, bcMode, bcSymmetric],
  );

  // Ref map keyed by stable sub-block id, for scrollIntoView lookup.
  const subBlockRefs = useRef<Map<string, HTMLElement>>(new Map());

  // Flash state: set of ids (multi-node payload can flash multiple sub-blocks).
  const [flashedIds, setFlashedIds] = useState<Set<string>>(new Set());

  // Build a stable id for a sub-block.
  const subBlockId = (section: CodeSection, i: number): string =>
    `code-sb-${section.name.toLowerCase()}-${i}`;

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
          matched.push({ id: subBlockId(section, i), sub });
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

  // Sub-block event handlers.
  const handleSubBlockMouseEnter = useCallback((sourceIds: string[]) => {
    useStore.getState().setHoveredSourceIds(sourceIds);
  }, []);

  const handleSubBlockMouseLeave = useCallback(() => {
    useStore.getState().clearHoveredSourceIds();
  }, []);

  const handleSubBlockClick = useCallback((sourceIds: string[]) => {
    useStore.getState().togglePinnedForSubBlock(sourceIds);
  }, []);

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

  const setSubBlockRef = (id: string) => (el: HTMLElement | null) => {
    if (el) subBlockRefs.current.set(id, el);
    else subBlockRefs.current.delete(id);
  };

  return (
    <ScrollArea className="h-full bg-[#0d1117]">
      <div
        className="p-4 font-mono text-[13px] leading-[1.55] text-zinc-200"
        onClick={handlePanelBodyClick}
      >
        {sections.length === 0 ? (
          <div className="text-zinc-500 italic text-xs">
            (empty — add components on the canvas to see generated Julia code)
          </div>
        ) : (
          sections.map((section) => (
            <div
              key={section.name}
              className="mb-5 last:mb-0"
              onClick={handlePanelBodyClick}
            >
              <h4 className="flex items-center gap-2 text-[11px] font-semibold uppercase tracking-[0.12em] text-sky-300/90 mb-2 select-text">
                <span
                  aria-hidden
                  className="inline-block h-3 w-[3px] rounded-sm bg-sky-400/80"
                />
                {section.name}
              </h4>
              <div className="flex flex-col gap-1.5">
                {section.subBlocks.map((sub, i) => {
                  const id = subBlockId(section, i);
                  const flashed = flashedIds.has(id);
                  const pinned = sub.sourceIds.some((sid) =>
                    pinnedSourceIds.has(sid),
                  );
                  return (
                    <pre
                      key={id}
                      id={id}
                      ref={setSubBlockRef(id)}
                      data-sub-block=""
                      data-source-ids={sub.sourceIds.join(",")}
                      data-flash={flashed ? "true" : undefined}
                      data-pinned={pinned ? "true" : undefined}
                      onMouseEnter={() =>
                        handleSubBlockMouseEnter(sub.sourceIds)
                      }
                      onMouseLeave={handleSubBlockMouseLeave}
                      onClick={(e) => {
                        // Prevent bubbling to panel-body so the empty-space
                        // clear-pins handler doesn't fire after this toggle.
                        e.stopPropagation();
                        handleSubBlockClick(sub.sourceIds);
                      }}
                      className={[
                        "whitespace-pre overflow-x-auto rounded-md cursor-pointer transition-colors duration-150",
                        "px-3 py-1.5 border-l-2",
                        flashed
                          ? "bg-amber-500/30 border-amber-400 ring-1 ring-amber-400/70"
                          : pinned
                            ? "bg-sky-500/[0.14] border-sky-400 ring-1 ring-sky-400/40"
                            : "border-transparent hover:bg-sky-500/[0.09] hover:border-sky-400/60",
                      ]
                        .filter(Boolean)
                        .join(" ")}
                    >
                      <code>
                        {sub.lines.map((line, li) => (
                          <Fragment key={li}>
                            {tokenize(line).map((tok, ti) =>
                              tok.kind === "plain" ? (
                                <Fragment key={ti}>{tok.text}</Fragment>
                              ) : (
                                <span
                                  key={ti}
                                  className={TOKEN_CLASS[tok.kind]}
                                >
                                  {tok.text}
                                </span>
                              ),
                            )}
                            {li < sub.lines.length - 1 ? "\n" : ""}
                          </Fragment>
                        ))}
                      </code>
                    </pre>
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
