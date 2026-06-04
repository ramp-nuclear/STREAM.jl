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
  // Phase 72 (post-Preferences) — honor the user `appearance.reduceMotion`
  // override in addition to the OS preference. Inline check (no pref-lib
  // import) keeps this helper dependency-free; the data-motion attribute
  // on <html> is the source of truth (set by App.tsx).
  const root = typeof document !== "undefined" ? document.documentElement : null;
  const userPref = root?.getAttribute("data-motion");
  // "full" → user forces motion on regardless of OS pref
  // "reduced" → user forces reduced regardless of OS pref
  // anything else → follow the OS
  const reduceMotion =
    userPref === "reduced" ||
    (userPref !== "full" &&
      typeof window !== "undefined" &&
      typeof window.matchMedia === "function" &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches);

  el.scrollIntoView({
    ...opts,
    behavior: reduceMotion ? "auto" : (opts.behavior ?? "smooth"),
  });
}
