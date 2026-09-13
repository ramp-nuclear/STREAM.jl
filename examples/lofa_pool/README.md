# Pool LOFA

A loss of flow in a pool-type MTR with two assembly types in parallel: the pump trips, a
low-flow signal scrams the reactor, the flywheel carries the flow down, the flapper above the
core opens, and both types turn around into natural circulation with the pool as the sink.
Every number in the input block of `run.jl` is a placeholder.

The model lives here rather than in the package. Nothing in `src/` or `test/` refers to it.

| File | What it is |
|:---|:---|
| `model.jl` | `build_pool_lofa` and `solve_pool_lofa_steady` |
| `case.jl` | The placeholder case, and `controls()` for the scram and the decay heat source |
| `run.jl` | The transient, margins, plots, timings, and the files `compare.py` reads |
| `timings.jl` | Cold and warm timings: first pass, the same model re-solved, a rebuilt model |
| `test.jl` | Checks on a small case, run by hand |
| `test_case.jl` | That small case, with a data-free decay heat stand-in |
| `compare.py` | The same case in Python STREAM, compared with the Julia run |

Run from the repository root:

```bash
STREAM_DECAY_HEAT_STANDARDS=/path/to/STANDARDS julia --project=. examples/lofa_pool/run.jl
```

```bash
julia --project=. examples/lofa_pool/test.jl
```

```bash
STREAM_DECAY_HEAT_STANDARDS=/path/to/STANDARDS python examples/lofa_pool/compare.py
```

`compare.py` needs a Python environment with STREAM installed, and reads the case and the
Julia results that `run.jl` writes to `examples/output/lofa_pool/`. Its low-flow trip comes
from Python's own state machine, which reads the primary flow. Its output goes to the same
folder: the tables in `comparison.md`, and the figures in `lofa_pool_comparison.pdf`, one
quantity per page. `compare.py --plot` redraws the figures from the last run without solving
again.
