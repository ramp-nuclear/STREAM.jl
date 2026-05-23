/**
 * Phase 72 harden — motion-aware scrollIntoView wrapper.
 *
 * `Element.scrollIntoView({ behavior: "smooth" })` is a JS option, NOT a CSS
 * property. The global `@media (prefers-reduced-motion: reduce)` rule in
 * index.css (which sets `scroll-behavior: auto !important`) only affects
 * CSS-side smooth scrolling; the JS option ignores it entirely.
 *
 * Every site that opts into smooth scrolling must therefore consult
 * matchMedia at call time. This helper is that chokepoint: pass the desired
 * options, and the behavior collapses to `"auto"` under reduced motion.
 *
 * Defaulting to `"smooth"` matches the call-site idiom across the codebase
 * (every prior call passed it explicitly).
 */
export function scrollIntoViewSafe(
  el: Element,
  opts: ScrollIntoViewOptions = {},
): void {
  const reduceMotion =
    typeof window !== "undefined" &&
    typeof window.matchMedia === "function" &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  el.scrollIntoView({
    ...opts,
    behavior: reduceMotion ? "auto" : (opts.behavior ?? "smooth"),
  });
}
