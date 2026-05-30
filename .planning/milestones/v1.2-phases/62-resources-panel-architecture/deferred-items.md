# Phase 62 — Deferred Items

Items discovered during plan execution that are out of scope per the
SCOPE BOUNDARY rule (pre-existing or unrelated to the current task).
Each entry should record the plan that surfaced it, the file/location, a
short description, and an action plan owner.


## From plan 62-01 (Wave 1 — Julia source helpers)

- **Pre-existing failure in `test/test_channels.jl:413`** —
  `CAC htc_correlation=dittus_boelter — closed loop solves` errors with
  `ArgumentError: Symbol (cac₊h_tc(t))[1] is not present in the system.`
  Reproduced on the base commit `e7d4212` BEFORE any plan-62-01 change
  (verified via a fresh `git clone` of the worktree at that commit and a
  cold `julia --project=. test/test_channels.jl` run — same 2-passed /
  1-errored signature). The failure is in
  `ChannelAndContacts` symbol-lookup logic; touched files in this plan
  are `src/utilities.jl` (new), `src/STREAM.jl` (export-only diff),
  `test/test_utilities.jl` (new), `test/runtests.jl` (one include line)
  — none of which interact with `cac.h_tc`. Out of scope for 62-01;
  flagged for a future phase 55-style channels follow-up.

