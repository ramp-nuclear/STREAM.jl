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
4. **Persona usability/gap study runs after feature build-out, not before** *(revised
   2026-06-05)*. Originally W9 was slotted before W6/W7 so findings could reprioritize the
   tracker. But WA already locked and spike-validated the two features, so W9 cannot steer
   them; running it early would make personas evaluate an authoring surface that W7 is about
   to replace, with no W8 guide to assess, and would mostly rediscover the gaps W6/W7/W8
   already fill. The full study now runs **after W8**, on the finished, documented product.
   Caveat: if W7's user-facing authoring API has open UX questions, fold a small targeted
   usability check into W7's design step rather than relying on the early study.
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

**DECIDED 2026-06-04 (spike-validated; see issue #19).**
- **Uncertainty (W6):** Float64 sampling. An opt-in registry of uncertain inputs feeds a
  `remake`/`EnsembleProblem` ensemble; attribution via finite-difference local sensitivity
  (cheap per-input budget) plus GlobalSensitivity Sobol (nonlinear, variance-based %).
  Number-type packages (Measurements/Particles) are rejected: they StackOverflow through
  STREAM's stiff DAE in every configuration tried.
- **Model-authoring (W7):** derived geometry as expression-valued default parameters of
  base "knob" parameters; rebuild-free scans via `remake`/`setp`. Validated end-to-end
  through the steady-state solve with a guess. Requires reworking the Float64-only
  `PipeGeometry` so components take base parameters and derive `Dh`/`A`/perimeter.
- Both halves share one substrate: a named parameter interface varied at solve time via
  `remake`. W6 and W7 should be co-designed at implementation time.

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

### W9 — Multi-persona usability / gap study (#5)  *(DEFERRED — runs LAST, after W8)*
On the finished, documented product (post-W8). Multi-agent study spanning the trait axes (Julia proficiency ×
physics proficiency × familiarity with peer codes × learning ability × internet access ×
learning goal). Not the full outer product — a chosen spread. Each persona files an
individual report; then an adversarial cross-examination round to filter biased
directions. Goal: "what's missing" — tutorials/guides, usability features, missing physics
(two-phase/drift-flux, volumes for LOCA), helper/analysis/debug/reporting tooling. Output
feeds + reprioritizes the tracker. Good fit for a Workflow when we reach it.

### WV — Python-parity validation  *(CURRENT FOCUS; gates everything after it)*

**Added 2026-06-05 (Itay + Aviv + Eshed). The team is not yet confident STREAM.jl
reproduces Python STREAM, so this runs next, before the deferred W6/W8/W9.** Goal: all
three agree 100% that Julia solves the same systems and gives the same numbers as Python.

North star: **`test/test_integration.jl` is a 1:1 port of Python
`tests/test_general/test_integrations.py`** — same systems, same numbers, same methods,
both passing, and *strictly* 1:1 (no Julia-only tests in that file; they move to the file
that mirrors their source, or are removed). Python's integration tests assert against
closed-form analytic solutions, so the port validates physics, not just code-to-code
agreement. The living map is `VALIDATION.md`.

Decisions taken: implement the missing components (`VolumetricFlowResistor`,
`LocalPressureDrop`, the closure-resistor / `Transistor` pattern, network `signify`) and a
mock-fluid path so all 21 Python tests can port with the same numbers; split
`one_sided_connection` into the truthful one-sided helper (kept) plus a Python-matching
both-faces helper (so `mtr_one_sided` parity goes clean). Sign-off is a human-reviewed
`VALIDATION.md` matrix.

### W6 — Implement uncertainty (#1)  *(DEFERRED — after WV)*
Per the WA design, on the validated base. Deferred 2026-06-05: UQ amplifies the nominal
solve, so it waits until WV establishes trust in nominal. The WA design + W7 knobs are kept.

### W7 — Implement model-authoring paradigm (#7/#9)  — DONE (2026-06-05)
Design knobs + symbolic geometry, 5 stages, parity held 434/20/72 throughout. Tagged
`w7-complete`.

### W8 — Model-writing guide/manual (#8)  *(DEFERRED — after WV, then W6)*
Step-by-step manual. Deferred: documents a tool the team does not yet trust; content also
depends on W6.

---

## Dependency summary

```
W0 ──┬──────────────────────────────► (governs everything)
     │
     ├─ WA (design 1 & 7/9) ─┐
     ├─ W2 (GUI split)       ─┤
     │                        ▼  [GATE]
     │            W4 (audit) ─► W5 (cleanup) ─► W7 (model-authoring, DONE) ─┐
     │                                                                      ▼
     │                                              WV (Python-parity validation)  ◄── CURRENT
     │                                                                      │  [TRUST GATE]
     │                                                                      ▼
     │                                                          W6 (uncertainty)
     │                                                                      ▼
     │                                              W8 (model guide) ─► W9 (persona study)
```
*Pivot 2026-06-05: WV (validation) inserted as the trust gate before W6/W8/W9, which are
deferred. W7 landed before W6 (it is W6's substrate). See the WV section.*

## Open items still to resolve
- Tracker mechanism: confirm **Project board + issues** vs a pinned meta-issue.
- #12/#13 fluids decision (open PR vs deferral memory).
- WA: the two framework/architecture choices (UQ library; model-authoring return shape).
