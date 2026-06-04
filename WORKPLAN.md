# STREAM.jl — Work Program

The master plan for the post-v1.2 STREAM.jl overhaul. Source-of-truth for *what we
do and in what order*. The living, status-tracked version lives in the GitHub tracker
(see W0); this file is the durable narrative and the seed for it.

Written 2026-06-04 with Itay. Supersedes the sequencing in
`.planning/proposals/julia-idiom-mtk-pass.md` (that proposal's *content* still governs
the audit; its *ordering* — audit before GUI split — is overridden here).

---

## Locked decisions (2026-06-04)

1. **Split GUI to its own repo *before* the Julia/MTK audit.** The audit's surface is
   Julia-only; removing `gui/` first just deletes noise.
2. **Design the invasive architecture (uncertainty, model-authoring) *before* the audit;
   implement *after* the cleanup.** Avoids auditing/polishing code those features will
   overturn. The contested zone is the parameter / geometry / model-assembly layer.
3. **`JULIA.md` + MTK skill already exist** (Itay authors; drops them in). The audit
   blocks on them being present and wired.
4. **Persona usability/gap study runs after the cleanup, before feature build-out** — so
   personas evaluate clean code, and findings reprioritize the tracker before we commit
   to feature work beyond the two already chosen.
5. **Merge policy: squash only.** Repo ruleset enforces it; `config.json` reconciled.

---

## Cross-cutting policy overhaul ("how we save things")

Settled up front because it governs how every workstream below is executed and recorded.
Final wording lands in `CLAUDE.md` during W0/W5.

- **Lighter GSD footprint.** No GSD jargon in source (no "Phase NN" markers, no
  phase-derived test names). Conventions live in `CLAUDE.md` (+ `JULIA.md`), not scattered
  across `.planning/`.
- **No archived-`.md` hoarding.** Delete `.md` for completed milestones/phases instead of
  archiving them. Keep only currently-in-work planning docs. (Policy committed in W0.)
- **Comment discipline.** No bloat / AI-slop comments. Keep only comments that earn their
  place. Docstrings get a `/humanizer` pass and exist with a purpose.
- **Single conventions home:** `CLAUDE.md` (works with or without GSD).

---

## Workstreams (execution order)

### W0 — Reset: process, tracker, rules drop-in  *(foundation; governs all)*
- Define + write the policies above into `CLAUDE.md`.
- Stand up the **GitHub master tracker** (point 6). Recommendation: a **Project board +
  issues** (status columns), seeded from: this WORKPLAN, existing open issues/PRs, and the
  not-yet-done Python-STREAM parity gaps. This is where everything below is tracked/updated.
- **Drop in `JULIA.md`** (repo root, referenced from `CLAUDE.md` by a plain line — not an
  `@`-include) and the **MTK skill** (`.claude/skills/mtk/`). Precedence: MTK skill wins for
  MTK-specific code; `JULIA.md` governs elsewhere.
- **Triage existing issues/PRs** into the tracker:
  - #7 "Testing homework", #8 "Code rewrite homework" → folded into / closed by W4.
  - #10 PR "formatter workflow" → W4 CI lock-in (JuliaFormatter).
  - #12 "Fluids generic + MTK" + PR #13 (H2O/D2O) → **decision needed**: open PR vs the
    `defer multi-fluid to v0.6+` memory. Resolve, don't leave dangling.
  - #16 "HTC(t) inflates IC/guess params" (bug) → backlog (adjacent to W6 parameters).
  - #4 "Junction mixing unit vs graph", #5 "Loading code into GUI" → #4 to physics backlog
    (relevant to volumes/LOCA); #5 migrates to the GUI repo (W2).

### WA — Architecture design sprint *(design only; runs in parallel with W2)*
Two design docs + spikes, no production code. Decided before the audit so the audit knows
the target shape.
- **Uncertainty (#1).** Opt-in uncertainty *registry layered over MTK parameters* (no
  construct-time fork; you don't pre-declare which inputs are uncertain). Decide
  `Measurements.jl` (Gaussian, derivative-based, native per-source contribution
  decomposition — closest to the "% from where" ask) vs `MonteCarloMeasurements.jl`
  (sampling, survives stiff DAE solves, full distributions). Decide the attribution method
  (local derivative contributions vs variance/Sobol) and the "collect all uncertain inputs
  in one place" surface. Spike through a real solve.
- **Model-authoring (#7/#9).** Solve the propagation problem (one annulus diameter that
  drives the whole system can't currently be scanned without re-pulling the model into
  `construct`). Likely answer: **symbolic dependent-parameter graph** (base params drive
  derived ones) + a **model generator** + `remake`/`EnsembleProblem` for rebuild-free
  parametric scans. Decide what replaces today's `(system, steady_guess)` return. Spike on
  the annulus-diameter case end-to-end.

### W2 — GUI → separate repo (#2)  *(runs in parallel with WA)*
- Extract `gui/` (source only — drop `node_modules/` and `src-tauri/target/`; the 9.9 GB is
  build junk) with history into a new GitHub repo. Strip GSD. Carry the GUI's own design
  stack (`PRODUCT.md`, `DESIGN.md`, `.impeccable/`).
- Preserve the **cross-repo contract**: the code generator + component registry mirror the
  `src/` STREAM API — pin/track a STREAM.jl version. This coupling is the thing to get right.
- Remove `gui/` from this repo. Migrate issue #5.

> **GATE:** GUI gone · `JULIA.md` + MTK skill present & wired · WA architecture decided.

### W4 — Julia idiom + MTK audit + fixes (#3)
Per `.planning/proposals/julia-idiom-mtk-pass.md` (audit-then-fix, leaves-first, with
`channels.jl`/`heat_diffusion.jl` last as load-bearing physics). Informed by WA: do **not**
polish the parameter/geometry/assembly code the features will overturn — flag it instead.
Hard rules from the proposal hold: tests stay green, parity report stays 424/78/34, no
silent API changes, atomic commits, no new features. Closes #7/#8.

### W5 — Honesty/cleanup pass (#4 + cleanup bullets)
- `/humanizer` pass on all docstrings; strip GSD mentions + AI-slop comments codebase-wide.
- Delete stale/archived `.md`, stale code, stale docs; de-bloat planning/context.
- Macro-consistency sweep (proposal Phase I) folds in here.
- Encode the comment/docstring/archival policies into `CLAUDE.md` as standing rules.

### W9 — Multi-persona usability / gap study (#5)
On the cleaned codebase. Multi-agent study spanning the trait axes (Julia proficiency ×
physics proficiency × familiarity with peer codes × learning ability × internet access ×
learning goal). Not the full outer product — a chosen spread. Each persona files an
individual report; then an adversarial cross-examination round to filter biased
directions. Goal: "what's missing" — tutorials/guides, usability features, missing physics
(two-phase/drift-flux, volumes for LOCA), helper/analysis/debug/reporting tooling. Output
feeds + reprioritizes the tracker. Good fit for a Workflow when we reach it.

### W6 — Implement uncertainty (#1)  *(feature build-out; ∥ W7)*
Per the WA design, on the clean base.

### W7 — Implement model-authoring paradigm (#7/#9)  *(∥ W6)*
Per the WA design, on the clean base.

### W8 — Model-writing guide/manual (#8)  *(after W7)*
Step-by-step manual for writing full dynamic, modular, parametrically-scannable models —
down to file-system organization. Content is only knowable once W7 lands.

---

## Dependency summary

```
W0 ──┬──────────────────────────────► (governs everything)
     │
     ├─ WA (design 1 & 7/9) ─┐
     ├─ W2 (GUI split)       ─┤
     │                        ▼  [GATE]
     │                       W4 (audit) ─► W5 (cleanup) ─► W9 (persona study)
     │                                                          │
     │                                          ┌───────────────┴───────────────┐
     │                                          ▼                               ▼
     │                                    W6 (uncertainty)            W7 (model-authoring)
     │                                                                          ▼
     │                                                                  W8 (model guide)
```

## Open items still to resolve
- Tracker mechanism: confirm **Project board + issues** vs a pinned meta-issue.
- #12/#13 fluids decision (open PR vs deferral memory).
- WA: the two framework/architecture choices (UQ library; model-authoring return shape).
