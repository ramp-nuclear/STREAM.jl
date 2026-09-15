"""Rebuild the pool LOFA case of run.jl in Python STREAM and compare the two codes.

run.jl writes julia_case.json and julia_series.csv to examples/output/lofa_pool. This script
reads the case from the first, builds the same loop in Python STREAM, runs the same
transient, and compares the result with the second:

    python examples/lofa_pool/compare.py            # steady state and transient
    python examples/lofa_pool/compare.py --steady   # steady state only
    python examples/lofa_pool/compare.py --plot     # redraw the figures from the last run

The scram comes from Python's own state machine, which reads the primary flow as the
kinetics' reference flow, so the trip time is calculated rather than taken from Julia. The
tables go to comparison.md and the figures to one multipage PDF, lofa_pool_comparison.pdf.
"""

import argparse
import json
import os
import textwrap
import time

_T_START = time.perf_counter()  # so the import of the STREAM stack is timed too
from functools import partial
from pathlib import Path
from types import SimpleNamespace

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.backends.backend_pdf import PdfPages
from matplotlib.lines import Line2D
from matplotlib.patches import Rectangle
from networkx import DiGraph
from scipy.constants import g

from stream.aggregator import Aggregator, CalculationGraph, vars_
from stream.aggregator.solution import Solution
from stream.calculations import (
    Channel,
    ChannelAndContacts,
    Flapper,
    Fuel,
    HeatExchanger,
    Inertia,
    Junction,
    KirchhoffWDerivatives,
    PointKineticsWInput,
    Pump,
    Solid,
)
from stream.calculations.flapper import continuously_differentiable_relaxation
from stream.calculations.point_kinetics import OneWayToSCRAM, ReactivityController
from stream.composition import ResistorFromKnownPoint, flow_edge, flow_graph
from stream.composition.cycle import flow_graph_to_aggregator, kirchhoffify
from stream.composition.mtr_geometry import symmetric_plate
from stream.composition.subsystems import (
    guess_hydraulic_steady_state,
    point_kinetics_steady_state,
    symmetric_plate_steady_state,
)
from stream.physical_models.decay_heat import actinides, fission_products
from stream.physical_models.heat_transfer_coefficient import wall_heat_transfer_coeff
from stream.physical_models.heat_transfer_coefficient.laminar import constant_Nusselt_h_spl
from stream.physical_models.heat_transfer_coefficient.natural_convection import Elenbaas_h_spl
from stream.physical_models.heat_transfer_coefficient.single_phase import regime_dependent_h_spl
from stream.physical_models.heat_transfer_coefficient.subcooled_boiling import regime_dependent_q_scb
from stream.physical_models.heat_transfer_coefficient.turbulent import Dittus_Boelter_h_spl
from stream.physical_models.pressure_drop import friction_factor, pressure_diff
from stream.physical_models.pressure_drop.friction import (
    Blasius_friction,
    Darcy_Weisbach_pressure_by_mdot,
    rectangular_laminar_correction,
)
from stream.pipe_geometry import EffectivePipe
from stream.solvers import TransientRuntimeError
from stream.state import State
from stream.substances import light_water
from stream.utilities import cosine_shape, identity, summed

OUT = Path(__file__).resolve().parent.parent / "output" / "lofa_pool"
RE_BOUNDS = (2000.0, 5000.0)
Q_FISSION = 200.0  # MeV recovered per fission, the default of Julia's DecayHeatSource
PUMP_RAMP = 0.05  # s over which Python's pump head falls to zero at the trip
MAX_STEP = 0.05  # s, the largest step IDA may take

# Where the two builds differ on purpose or by construction, and what each difference predicts.
KNOWN_DIFFERENCES = [
    ("Low-flow trip", "Callback finds the crossing of the primary flow",
     "State machine reads the primary flow, as the kinetics' reference flow, between solver "
     f"steps at most {MAX_STEP} s apart",
     f"Python trips up to {MAX_STEP} s after its flow crosses the setpoint, and the pump ramp "
     "makes that crossing a little later, so power and plate temperatures differ sharply while "
     "the rods go in"),
    ("Flapper opening", "Callback finds the exact crossing",
     f"Checked between solver steps at most {MAX_STEP} s apart",
     f"Python opens up to {MAX_STEP} s late, and flows differ sharply until both are open"),
    ("Equation handling", "ModelingToolkit reduces the index, then Rodas5P",
     "IDA on the unreduced system, which is above index 1, with the algebraic variables kept out "
     f"of its error test and its step capped at {MAX_STEP} s",
     "Without both, IDA fails within a second of the flapper opening"),
    ("Pump trip", "Head steps to zero at t = 0",
     f"Head ramps to zero over {PUMP_RAMP * 1000:.0f} ms, since IDA's initial-condition solver "
     "fails on the step",
     "The primary flow runs a fraction of a percent high just after the trip"),
    ("Saved points", "The solver steps onto every saved time",
     "IDA interpolates between its own steps", "None beyond interpolation"),
]


def channel_htc(heated_length):
    """Julia's HTC.RegimeDependent (constant-Nu laminar, Dittus-Boelter turbulent, Elenbaas
    natural convection) under Bergles-Rohsenow partial subcooled boiling, with the boiling flux
    blended across the same Re band, as Julia's regime_dependent_q_scb does."""
    single_phase = partial(
        regime_dependent_h_spl,
        re_bounds=RE_BOUNDS,
        laminar=partial(constant_Nusselt_h_spl, nu=8.235),
        turbulent=Dittus_Boelter_h_spl,
        natural=partial(Elenbaas_h_spl, Lh=heated_length),
    )
    return partial(
        wall_heat_transfer_coeff,
        h_spl=single_phase,
        q_scb=partial(regime_dependent_q_scb, re_bounds=RE_BOUNDS),
    )


def channel_friction(pipe):
    """Regime-dependent friction with the rectangular correction k_R on the Reynolds number
    both branches see: 64/(Re k_R) below the band and Blasius at Re k_R above it."""
    return friction_factor(
        "regime_dependent",
        re_bounds=RE_BOUNDS,
        k_R=rectangular_laminar_correction(pipe.depth / pipe.width),
        turbulent=Blasius_friction,
    )


def use_standards():
    """Python STREAM looks for its decay heat tables inside its own package. Point it at the
    directory run.jl reads, so both codes use the same tables."""
    path = os.environ.get("STREAM_DECAY_HEAT_STANDARDS")
    if not path:
        raise SystemExit("set STREAM_DECAY_HEAT_STANDARDS to the decay heat tables, as for run.jl")
    fission_products.STANDARDS = Path(path)


def decay_heat(inp, ctrl):
    """Julia's DecayHeatSource over FissionProducts(ANS14, U235) + U238CaptureChain(R), at
    P0 = 1, with its clock started when `ctrl` scrams."""
    fp = fission_products.contribution(fission_products.Standard.ANS14, fission_products.Source.U235)
    chain = actinides.contribution(inp["captures_per_fission"])

    def power(t):
        tripped = ctrl.state == OneWayToSCRAM.SCRAM
        tau = max(float(t) - ctrl.t_state, 0.0) if tripped else 0.0
        return float(np.sum(fp(tau, np.inf)) + np.sum(chain(tau, np.inf))) / Q_FISSION

    return power


def controller(inp, m_design):
    """The low-flow scram. The state machine reads the primary flow, which the kinetics get as
    their reference flow, and trips when it falls to the setpoint; the rods count from then."""
    setpoint = inp["case"]["trip_fraction"] * m_design
    worth, delay, insertion = inp["rod_worth"], inp["rod_delay"], inp["rod_insertion"]

    def rods(state, t_state, t):
        if state != OneWayToSCRAM.SCRAM:
            return 0.0
        return worth * float(np.clip((t - t_state - delay) / insertion, 0.0, 1.0))

    def low_flow(state, t, power, dPdt, ref_mdot=np.inf, **_):
        return OneWayToSCRAM.SCRAM if ref_mdot <= setpoint else state

    return ReactivityController(input_reactivity=rods, state_machine=low_flow)


def design_flow(case):
    return sum(ty["N"] * ty["design_ṁ"] for ty in case["types"].values())


def build(inp):
    case = inp["case"]
    L, n, nx, T_pool = case["L"], case["n"], case["nx"], case["T_pool"]
    z = np.linspace(0.0, L, n + 1)
    pool, plenum, top = Junction("pool"), Junction("plenum"), Junction("flapper node")
    m_design = design_flow(case)
    ctrl = controller(inp, m_design)
    pk = PointKineticsWInput(
        generation_time=case["Lambda"],
        delayed_neutron_fractions=np.asarray(case["beta_k"]),
        delayed_groups_decay_rates=np.asarray(case["lambda_k"]),
        controls=ctrl,
        name="pk",
    )
    decay = decay_heat(inp, ctrl)

    types, edges, plates, power_links = {}, [], [], []
    for key, ty in case["types"].items():
        pipe = EffectivePipe.rectangular(
            length=L, edge1=ty["width"], edge2=ty["gap"], heated_edge=ty["heated_width"]
        )
        ch = ChannelAndContacts(
            z_boundaries=z,
            fluid=light_water,
            pipe=pipe,
            h_wall_func=channel_htc(L),
            # Python counts downward flow as positive, so the downward core takes +g.
            pressure_func=partial(pressure_diff, f=channel_friction(pipe), g=g),
            name=f"ch_{key}",
        )
        plate_power = case["P_rated"] * ty["power_fraction"] / ty["N"]
        shares = np.repeat((cosine_shape(z, ty["ppf"]) / nx)[:, None], nx, axis=1)
        fuel = Fuel(
            z_boundaries=z,
            x_boundaries=np.linspace(0.0, ty["plate_thickness"], nx + 1),
            material=Solid(
                density=case["rho_s"], specific_heat=case["cp_s"], conductivity=case["k_s"]
            ),
            y_length=ty["heated_width"],
            # The kinetics run dimensionless, so each plate's watts ride in its shape.
            power_shape=plate_power * shares,
            name=f"fuel_{key}",
        )
        hx = HeatExchanger(outlet=T_pool, name=f"pool_{key}")
        orifice = ResistorFromKnownPoint(
            dp=-ty["orifice_dp"],
            mdot=ty["design_ṁ"],
            behavior="parabolic",
            Tin=T_pool,
            fluid=light_water,
            name=f"orifice_{key}",
        )
        edges.append(flow_edge((pool, plenum), hx, orifice, ch, signify=ty["N"]))
        plates.append(symmetric_plate(ch, fuel))
        power_links.append((pk, fuel, vars_("power")))
        types[key] = SimpleNamespace(
            ch=ch, fuel=fuel, hx=hx, orifice=orifice, pipe=pipe, N=ty["N"], design=ty["design_ṁ"]
        )

    pump = Pump(pressure=case["dP_pump"], name="pump")
    flywheel = Inertia(inertia=case["flywheel_L_over_A"], name="flywheel")
    primary = ResistorFromKnownPoint(
        dp=-case["primary_dp"],
        mdot=m_design,
        behavior="parabolic",
        Tin=T_pool,
        fluid=light_water,
        name="primary",
    )
    riser = Channel(
        z_boundaries=np.linspace(0.0, case["riser_L"], n + 1),
        fluid=light_water,
        pipe=EffectivePipe.circular(case["riser_L"], case["riser_D"]),
        pressure_func=partial(pressure_diff, f=friction_factor("Blasius"), g=-g),
        name="riser",
    )
    pool_flapper = HeatExchanger(outlet=T_pool, name="pool_flapper")
    flapper = Flapper(
        open_at_current=case["flapper_open_at"],
        f=case["flapper_f"],
        fluid=light_water,
        area=case["flapper_area"],
        open_rate=1.0 / case["flapper_open_time"],
        relaxation=continuously_differentiable_relaxation,
        name="flapper",
    )
    edges += [
        flow_edge((plenum, top), riser),
        flow_edge((pool, top), pool_flapper, flapper),
        # The flapper and the kinetics' state machine both watch the primary flow.
        flow_edge((top, pool), primary, pump, flywheel, ref_mdot_for=(flapper, pk)),
    ]
    fg = flow_graph(*edges)
    channels = [t.ch for t in types.values()]
    K = KirchhoffWDerivatives(fg, *channels, reference_node=(pool, case["p_pool"]))
    power = CalculationGraph(DiGraph(power_links), funcs={pk: dict(t=identity, power_input=decay, T={})})
    hydraulic = flow_graph_to_aggregator(fg, funcs={flapper: dict(t=identity)})
    graph = kirchhoffify(
        hydraulic + summed(plates) + power,
        K,
        inertial_comps=[flywheel, riser, *channels],
        ref_mdots=[flapper, pk],
        abs_pressure_comps=channels,
    )
    return SimpleNamespace(
        agr=Aggregator.from_CalculationGraph(graph),
        K=K,
        pk=pk,
        decay=decay,
        types=types,
        pump=pump,
        flywheel=flywheel,
        primary=primary,
        riser=riser,
        pool_flapper=pool_flapper,
        flapper=flapper,
        m_design=m_design,
    )


def solve_steady(m, inp):
    case = inp["case"]
    T_pool = case["T_pool"]
    flows = {
        m.pump: m.m_design,
        m.flywheel: m.m_design,
        m.primary: m.m_design,
        m.riser: m.m_design,
        m.pool_flapper: 0.0,
        m.flapper: 0.0,
    }
    for t in m.types.values():
        flows |= {t.hx: t.design, t.orifice: t.design, t.ch: t.design}
    T_mixed = T_pool + case["P_rated"] / (m.m_design * light_water.specific_heat(T_pool))
    guess = State.merge(
        guess_hydraulic_steady_state(m.K, flows, T_pool),
        *(
            symmetric_plate_steady_state(
                t.ch, t.fuel, mdot=t.design, p_abs=case["p_pool"], power=1.0, Tin=T_pool
            )
            for t in m.types.values()
        ),
        point_kinetics_steady_state(m.pk, power=1.0, power_input=m.decay(0.0)),
        {m.riser.name: dict(T_cool=np.full(case["n"], T_mixed))},
    )
    y = m.agr.solve_steady(guess)
    return y, m.agr.save(y)


def flows_at(m, sol, comp):
    return np.asarray(m.agr.at_times(sol, m.K, m.K.component_edge(comp)), dtype=float)


def python_series(m, sol, inp):
    """Python's run on its output times, in the columns run.jl writes for Julia."""
    at = partial(m.agr.at_times, sol)
    out = {
        "t": np.asarray(sol.time, dtype=float),
        "mdot_primary": flows_at(m, sol, m.pump),
        "mdot_flapper": flows_at(m, sol, m.flapper),
        "P": np.asarray(at(m.pk, "power"), dtype=float),
        "P_neutron": np.asarray(at(m.pk, "pk_power"), dtype=float),
    }
    for key, t in m.types.items():
        out[f"mdot_{key}"] = flows_at(m, sol, t.ch)
        out[f"Tcool_max_{key}"] = np.max(np.atleast_2d(at(t.ch, "T_cool")), axis=1)
        out[f"Tfuel_max_{key}"] = np.max(np.atleast_2d(at(t.fuel, "T")), axis=1)
        out[f"h_{key}"] = np.atleast_2d(at(t.ch, "h_left"))[:, inp["hot_cell"][key] - 1]

    # The wall temperature, the heat to the coolant and the pressures are not unknowns, so they
    # come from each channel's saved state.
    frictions = {key: channel_friction(t.pipe) for key, t in m.types.items()}
    extra = {f"{col}_{key}": [] for key in m.types for col in ("Twall_max", "Q", "dP", "dPfric")}
    for t_j, y in zip(sol.time, sol.data):
        state = m.agr.save(y, t=float(t_j))
        for key, t in m.types.items():
            s = state[t.ch.name]
            T, mdot = np.asarray(s["T_cool"]), float(s["mass_flow"])
            T_wall = (np.asarray(s["T_wall, left"]) + np.asarray(s["T_wall, right"])) / 2
            p_in = float(state[m.K.name][f"(p_abs of {t.ch.name})"])
            f = frictions[key](T, T_wall, mdot, light_water, t.pipe)
            friction = Darcy_Weisbach_pressure_by_mdot(
                mdot=mdot,
                rho=light_water.density(T),
                f=f,
                L=t.pipe.length / len(T),
                Dh=t.pipe.hydraulic_diameter,
                A=t.pipe.area,
            )
            extra[f"Twall_max_{key}"].append(float(np.max(s["T_wall, left"])))
            extra[f"Q_{key}"].append(float(s["power"]))
            extra[f"dP_{key}"].append(p_in - float(np.asarray(s["absolute_pressure"])[-1]))
            extra[f"dPfric_{key}"].append(float(np.sum(friction)))
    out |= {col: np.asarray(v, dtype=float) for col, v in extra.items()}
    return pd.DataFrame(out)


def first_negative(t, v):
    idx = np.flatnonzero(np.asarray(v) < 0)
    return float(t[idx[0]]) if idx.size else float("nan")


def rel(a, b):
    return (a - b) / abs(b) if b else float("nan")


def number(x):
    return float("nan") if x is None else float(x)


def fmt_diff(d, relative):
    return f"{100 * d:+.2f}%" if relative else f"{d:+.3g}"


def report_rows(inp, steady_py, jl, py, run_py):
    """The comparison table as (quantity, Julia, Python, Python - Julia, relative) rows."""
    case, ev, st = inp["case"], inp["events"], inp["steady"]
    keys = list(case["types"])
    rows = []

    def row(q, a, b, relative):
        a, b = number(a), number(b)
        rows.append((q, a, b, rel(b, a) if relative else b - a, relative))

    row("steady primary flow [kg/s]", st["primary"], steady_py["primary"], True)
    for k in keys:
        row(f"steady {k} flow per channel [kg/s]", st[f"mdot_{k}"], steady_py[f"mdot_{k}"], True)
        row(f"steady {k} outlet temperature [°C]", st[f"T_out_{k}"], steady_py[f"T_out_{k}"], False)
    if py is None:
        return rows

    jd = jl.drop_duplicates("t", keep="last")
    for k in keys:
        for col, label, scale in (
            (f"h_{k}", "heat transfer coefficient, hottest cell [W/(m²·K)]", 1.0),
            (f"dP_{k}", "pressure drop, inlet to outlet [kPa]", 1e-3),
            (f"dPfric_{k}", "friction pressure drop [kPa]", 1e-3),
        ):
            row(f"steady {k} {label}", scale * jd[col].iloc[0], scale * py[col].iloc[0], True)

    t_py = py["t"].to_numpy()
    row("low-flow trip [s]", ev["t_trip"], run_py["t_trip"], False)
    primary_at_trip = np.interp(run_py["t_trip"], t_py, py["mdot_primary"]) / design_flow(case)
    row("primary flow at each code's trip, share of design", case["trip_fraction"], primary_at_trip, False)
    row("flapper opens [s]", ev["t_flapper"], run_py["t_flapper"], False)
    for k in keys:
        row(f"{k} turns around [s]", ev[f"t_reversal_{k}"], first_negative(t_py, py[f"mdot_{k}"]), False)

    # Over the time both codes covered, from the rods being fully in.
    t_last = float(t_py[-1])
    rods_in = ev["t_trip"] + inp["rod_delay"] + inp["rod_insertion"]
    j_win = (jl["t"] > rods_in) & (jl["t"] <= t_last)
    p_win = py["t"] > rods_in
    for k in keys:
        for col, label in (
            (f"Tcool_max_{k}", "peak coolant"),
            (f"Twall_max_{k}", "peak wall"),
            (f"Tfuel_max_{k}", "peak plate"),
        ):
            row(f"{k} {label}, rods in to t = {t_last:.0f} s [°C]", jl.loc[j_win, col].max(), py.loc[p_win, col].max(), False)
    ends = [("P", "total power [share]")] + [(f"mdot_{k}", f"{k} flow per channel [kg/s]") for k in keys]
    for col, label in ends:
        row(f"{label} at t = {t_last:.0f} s", np.interp(t_last, jd["t"], jd[col]), py[col].iloc[-1], True)

    # The largest error over the whole run, and when. Relative for flows and power, left out
    # where Julia's flow is within 2% of design of zero, absolute for temperatures.
    J = {c: np.interp(t_py, jd["t"], jd[c]) for c in jd.columns if c != "t"}
    floors = {"mdot_primary": 0.02 * design_flow(case), "P": 0.0}
    floors |= {f"mdot_{k}": 0.02 * case["types"][k]["design_ṁ"] for k in keys}
    for col, floor in floors.items():
        ok = np.abs(J[col]) > floor
        err = np.where(ok, (py[col].to_numpy() - J[col]) / np.abs(J[col]), 0.0)
        i = int(np.argmax(np.abs(err)))
        label = "total power [share]" if col == "P" else f"{col[5:]} flow [kg/s]"
        row(f"largest error, {label}, at t = {t_py[i]:.1f} s", J[col][i], py[col].iloc[i], True)
    for k in keys:
        for col, label in ((f"Tcool_max_{k}", "hottest coolant"), (f"Tfuel_max_{k}", "hottest plate")):
            err = py[col].to_numpy() - J[col]
            i = int(np.argmax(np.abs(err)))
            row(f"largest error, {k} {label} [°C], at t = {t_py[i]:.1f} s", J[col][i], py[col].iloc[i], False)
    return rows


def report_md(rows, stopped):
    lines = ["| quantity | Julia | Python | Python - Julia |", "|:---|---:|---:|---:|"]
    lines += [f"| {q} | {a:.5g} | {b:.5g} | {fmt_diff(d, r)} |" for q, a, b, d, r in rows]
    if stopped is not None:
        lines.insert(0, f"Python stopped at t = {stopped[0]:.3f} s: {stopped[1]}\n")
    lines += ["", "Known differences between the two builds:", "",
              "| | Julia | Python | Expected effect |", "|:---|:---|:---|:---|"]
    lines += [f"| {a} | {b} | {c} | {d} |" for a, b, c, d in KNOWN_DIFFERENCES]
    return "\n".join(lines)


# #### Figures

A4_LANDSCAPE = (11.69, 8.27)
PALETTE = ("#1f5f99", "#c8413b", "#2f8f5b", "#b7791f")
JULIA_EVENT, PYTHON_EVENT = "#555555", "#e07000"
STYLE = {
    "font.size": 8.5,
    "axes.titlesize": 9.5,
    "axes.labelsize": 8.5,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.grid": True,
    "axes.edgecolor": "#888888",
    "grid.color": "#e3e3e3",
    "grid.linewidth": 0.6,
    "legend.fontsize": 8,
    "xtick.labelsize": 7.5,
    "ytick.labelsize": 7.5,
    "xtick.color": "#444444",
    "ytick.color": "#444444",
    "pdf.fonttype": 42,
}


def windows(inp):
    """The three time windows of every page: the trip, the flapper and the reversals, and the
    whole run."""
    ev = inp["events"]
    reversals = [number(v) for k, v in ev.items() if k.startswith("t_reversal_")]
    t_rev = max((v for v in reversals if np.isfinite(v)), default=ev["t_flapper"] + 10.0)
    return (
        ("Pump trip and scram", (0.0, 10.0)),
        ("Flapper opening and flow reversal", (ev["t_flapper"] - 5.0, t_rev + 12.0)),
        ("Whole transient", (0.0, inp["t_end"])),
    )


def event_marks(inp, run_py):
    ev = inp["events"]
    julia = [(ev["t_trip"], "trip"), (ev["t_flapper"], "flapper")]
    python = [(number(run_py["t_trip"]), "trip"), (number(run_py["t_flapper"]), "flapper")]
    return julia, [(t, label) for t, label in python if np.isfinite(t)]


def draw_events(top, bottom, marks, t0, t1):
    julia, python = marks
    for (who, color), events in (((0, JULIA_EVENT), julia), ((1, PYTHON_EVENT), python)):
        for t, label in events:
            if not t0 <= t <= t1:
                continue
            for ax in (top, bottom):
                ax.axvline(t, color=color, ls=":", lw=0.9, zorder=1)
            # Julia's events are named; Python's sit beside them and the legend says which is which.
            if who == 0:
                top.text(t, 0.985, f" {label}", transform=top.get_xaxis_transform(), rotation=90,
                         va="top", ha="right", fontsize=6.5, color=color)


def page_header(fig, title, note):
    fig.text(0.06, 0.955, title, fontsize=13, fontweight="bold", va="top")
    if note:
        fig.text(0.06, 0.918, note, fontsize=8.5, color="#444444", va="top")


def comparison_page(pdf, inp, marks, title, series, ylabel, unit, *, note=None, log=False,
                    relative=False, scale=1.0, floor=0.0):
    """One quantity on one page. Each column is a time window, with the values above (Julia a
    wide pale line, Python a thin dashed one) and Python minus Julia below. Values under
    `floor` times the largest value are left off a log axis and out of a relative difference."""
    cutoff = floor * max(float(np.nanmax(np.abs(s[2]))) for s in series) * scale
    fig = plt.figure(figsize=A4_LANDSCAPE)
    page_header(fig, title, note)
    wins = windows(inp)
    grid = fig.add_gridspec(2, len(wins), height_ratios=(2.5, 1.0), hspace=0.06, wspace=0.22,
                            left=0.085, right=0.985, top=0.82, bottom=0.08)
    for col, (name, (t0, t1)) in enumerate(wins):
        top = fig.add_subplot(grid[0, col])
        bottom = fig.add_subplot(grid[1, col], sharex=top)
        for color, (label, tj, yj, tp, yp) in zip(PALETTE, series):
            yj, yp = scale * yj, scale * yp
            in_j, in_p = (tj >= t0) & (tj <= t1), (tp >= t0) & (tp <= t1)
            top.plot(tj[in_j], yj[in_j], color=color, lw=3.4, alpha=0.3, solid_capstyle="round", zorder=2)
            top.plot(tp[in_p], yp[in_p], color=color, lw=1.1, ls=(0, (3.5, 2.0)), zorder=3)
            ref = np.interp(tp, tj, yj)
            diff = yp - ref
            if relative:
                diff = np.where(np.abs(ref) > max(cutoff, 0.0), 100 * diff / np.abs(ref), np.nan)
            bottom.plot(tp[in_p], diff[in_p], color=color, lw=1.1, zorder=3)
        if log:
            top.set_yscale("log")
            if cutoff > 0:
                # Autoscaling would still span the decades cut off below, so set both ends.
                peak = max(float(np.nanmax(scale * s[2][(s[1] >= t0) & (s[1] <= t1)])) for s in series)
                top.set_ylim(cutoff, 2.0 * peak)
        top.set_xlim(t0, t1)
        top.set_title(name, loc="left", color="#333333")
        top.tick_params(labelbottom=False)
        bottom.axhline(0.0, color="#999999", lw=0.7, zorder=1)
        bottom.set_xlabel("t [s]")
        if col == 0:
            top.set_ylabel(ylabel)
            bottom.set_ylabel(f"Python − Julia\n[{'%' if relative else unit}]")
        draw_events(top, bottom, marks, t0, t1)
    handles = [Line2D([], [], color=c, lw=2.5, label=s[0]) for c, s in zip(PALETTE, series)]
    handles += [
        Line2D([], [], color="#666666", lw=3.4, alpha=0.3, label="Julia"),
        Line2D([], [], color="#333333", lw=1.1, ls=(0, (3.5, 2.0)), label="Python"),
        Line2D([], [], color=JULIA_EVENT, lw=0.9, ls=":", label="event in Julia"),
        Line2D([], [], color=PYTHON_EVENT, lw=0.9, ls=":", label="event in Python"),
    ]
    fig.legend(handles=handles, loc="upper left", bbox_to_anchor=(0.06, 0.895), ncol=len(handles),
               frameon=False, handlelength=2.6, columnspacing=1.6)
    pdf.savefig(fig)
    plt.close(fig)


def summary_page(pdf, inp, run_py):
    """The comparison table and the known differences, as the first page."""
    case = inp["case"]
    fig = plt.figure(figsize=A4_LANDSCAPE)
    types = ", ".join(f"{ty['N']} {k} channels" for k, ty in case["types"].items())
    page_header(
        fig,
        "Pool loss of flow: STREAM.jl against Python STREAM",
        f"{case['P_rated'] / 1e6:.1f} MW, {types}, pump trip at t = 0, run to "
        f"{inp['t_end']:.0f} s. Every input is a placeholder and describes no plant.",
    )
    rows = run_py["rows"]
    y, dy = 0.86, min(0.028, 0.8 / (len(rows) + 1))
    columns = ((0.06, "left", ""), (0.49, "right", "Julia"), (0.565, "right", "Python"),
               (0.66, "right", "Python − Julia"))
    for x, ha, head in columns:
        fig.text(x, y, head, ha=ha, fontsize=8, fontweight="bold")
    for i, (q, a, b, d, relative) in enumerate(rows):
        yy = y - (i + 1) * dy
        if i % 2 == 0:
            fig.patches.append(Rectangle((0.055, yy - 0.3 * dy), 0.61, dy, transform=fig.transFigure,
                                         facecolor="#f2f4f7", edgecolor="none", zorder=0))
        for (x, ha, _), text in zip(columns, (q, f"{a:.5g}", f"{b:.5g}", fmt_diff(d, relative))):
            fig.text(x, yy, text, ha=ha, fontsize=7.5)

    x0, y = 0.70, 0.86
    fig.text(x0, y, "Known differences between the builds", fontsize=8, fontweight="bold")
    for name, julia, python, effect in KNOWN_DIFFERENCES:
        y -= 0.034
        fig.text(x0, y, name, fontsize=7.5, fontweight="bold", color="#222222")
        for prefix, text in (("Julia: ", julia), ("Python: ", python), ("Effect: ", effect)):
            for line in textwrap.wrap(prefix + text, 72):
                y -= 0.019
                fig.text(x0, y, line, fontsize=6.8, color="#333333")
    if run_py.get("stopped"):
        t_stop, message = run_py["stopped"]
        fig.text(0.06, 0.04, f"Python stopped at t = {t_stop:.2f} s: {message}", fontsize=8, color="#b00020")
    fig.text(0.06, 0.02, "The next page counts the unknowns and times each phase. Each page after "
             "it shows one quantity in three time windows, with Python minus Julia underneath.",
             fontsize=7.5, color="#555555")
    pdf.savefig(fig)
    plt.close(fig)


def text_table(fig, x0, y0, columns, rows, *, row_height=0.027, size=7.5, band=True,
               band_right=None):
    """Rows of text as a table: `columns` holds (x, alignment, heading) triples. Returns the y
    below the last row."""
    for x, ha, head in columns:
        fig.text(x, y0, head, ha=ha, fontsize=size + 0.5, fontweight="bold")
    left = x0 - 0.005
    right = band_right if band_right is not None else max(x for x, _, _ in columns) + 0.005
    for i, row in enumerate(rows):
        y = y0 - (i + 1) * row_height
        if band and i % 2 == 0:
            fig.patches.append(Rectangle((left, y - 0.3 * row_height), right - left, row_height,
                                         transform=fig.transFigure, facecolor="#f2f4f7",
                                         edgecolor="none", zorder=0))
        for (x, ha, _), text in zip(columns, row):
            fig.text(x, y, text, ha=ha, fontsize=size)
    return y0 - (len(rows) + 1) * row_height


def paragraphs(fig, x0, y0, texts, *, width=78, size=7.6, line=0.021, gap=0.012):
    y = y0
    for text in texts:
        for part in textwrap.wrap(text, width):
            fig.text(x0, y, part, fontsize=size, color="#333333", va="top")
            y -= line
        y -= gap
    return y


def numbers_page(pdf, inp, run_py):
    """How many unknowns each solver integrates, which of them are algebraic, and the wall time
    of each phase."""
    jl, py = inp.get("size", {}), run_py.get("size", {})
    fig = plt.figure(figsize=A4_LANDSCAPE)
    page_header(fig, "Problem size and wall time",
                "What each solver integrates for this case, and how long each phase takes.")

    y = text_table(fig, 0.06, 0.84, ((0.06, "left", "unknowns"), (0.33, "right", "Julia"),
                                     (0.40, "right", "Python")), size_rows(jl, py))
    julia_names = [(name.replace("₊", "."), str(count))
                   for name, count in jl.get("algebraic_by_name", {}).items()]
    y = text_table(fig, 0.06, y - 0.03, ((0.06, "left", "Julia's algebraic unknowns"),
                                         (0.40, "right", "count")), julia_names)
    python_names = [(name, str(e["count"]), components(e["in"]))
                    for name, e in py.get("algebraic_by_name", {}).items()]
    text_table(fig, 0.06, y - 0.03, ((0.06, "left", "Python's algebraic unknowns"),
                                     (0.30, "right", "count"), (0.315, "left", "in")), python_names,
               band_right=0.405)

    x0 = 0.47
    fig.text(0.72, 0.865, "Julia", ha="center", fontsize=8.5, fontweight="bold", color="#555555")
    fig.text(0.935, 0.865, "Python", ha="center", fontsize=8.5, fontweight="bold", color="#555555")
    columns = ((x0, "left", "wall time [s]"), (0.655, "right", "cold"), (0.745, "right", "same model"),
               (0.815, "right", "rebuilt"), (0.895, "right", "first pass"),
               (0.985, "right", "second pass"))
    y = text_table(fig, x0, 0.84, columns, timing_rows(run_py.get("timing", {})))

    texts = [
        f"ModelingToolkit removes aliases and solves every equation it can rearrange explicitly "
        f"before the solve, so Julia integrates {jl.get('unknowns', '-')} of the "
        f"{jl.get('before', '-')} unknowns it builds and recomputes the other "
        f"{jl.get('observed', '-')} from them afterwards. {jl.get('algebraic', '-')} of those "
        f"stay algebraic: the plate surface temperatures, one per face and cell, where "
        f"h(T_wall)·(T_wall − T) meets conduction in the plate and h itself depends on T_wall, "
        f"and the pressures at the two junctions where branches meet, the lower plenum and the "
        f"flapper node.",
        "Rodas5P integrates M·u' = f(u) with a zero on each algebraic row of M. It is a "
        "Rosenbrock method built for index-1 systems in that form, so a step costs a few linear "
        "solves and no Newton iterations.",
        f"Python hands IDA all {py.get('unknowns', '-')} unknowns. {py.get('algebraic', '-')} of "
        f"them are algebraic: the heat transfer coefficient as well as the wall temperature of "
        f"every face and cell, each component's inlet temperature and pressure change, and the "
        f"flow derivatives of its Kirchhoff formulation, which put the system above index 1.",
        "Julia's cold column includes compiling, with its share in brackets. The same-model "
        "column solves the built model again, and the rebuilt column builds it again in the same "
        "process, which compiles little. Python's second pass repeats the first in the same "
        "process.",
    ]
    paragraphs(fig, x0, y - 0.02, texts)
    pdf.savefig(fig)
    plt.close(fig)


def plot_pdf(inp, jl, py, run_py):
    """Every figure of the comparison, one quantity per page, in lofa_pool_comparison.pdf."""
    jl = jl.drop_duplicates("t", keep="last")
    tj, tp = jl["t"].to_numpy(), py["t"].to_numpy()
    case = inp["case"]
    keys = list(case["types"])
    n, hot = case["n"], inp["hot_cell"]

    def pair(col, label):
        return (label, tj, jl[col].to_numpy(), tp, py[col].to_numpy())

    def per_type(col):
        return [pair(f"{col}_{k}", f"{k} channel") for k in keys]

    cells = ", ".join(f"cell {hot[k]} of {n} in the {k} channel" for k in keys)
    pages = [
        ("Flow per channel", per_type("mdot"), "ṁ [kg/s]", "kg/s",
         dict(note="Positive is the forced, downward direction; natural circulation runs upward.")),
        ("Primary and flapper flow", [pair("mdot_primary", "primary"), pair("mdot_flapper", "flapper")],
         "ṁ [kg/s]", "kg/s", {}),
        ("Power", [pair("P", "total, P"), pair("P_neutron", "fission, P_neutron")],
         "share of rated power", "",
         dict(log=True, relative=True, floor=1e-5,
              note="The total is fission power plus decay heat. Below 1e-5 of rated power the "
                   "fission power is left off, and out of the difference.")),
        ("Hottest coolant", per_type("Tcool_max"), "T [°C]", "K",
         dict(note="The hottest axial cell at each time.")),
        ("Hottest wall", per_type("Twall_max"), "T [°C]", "K",
         dict(note="Plate surface facing the coolant, where boiling starts.")),
        ("Hottest plate", per_type("Tfuel_max"), "T [°C]", "K", {}),
        ("Heat transfer coefficient", per_type("h"), "h [kW/(m²·K)]", "",
         dict(relative=True, scale=1e-3,
              note=f"At the wall cell hottest at steady state, counted from the inlet: {cells}.")),
        ("Heat to the coolant", per_type("Q"), "Q per channel [kW]", "kW",
         dict(scale=1e-3, note="Through both faces of one channel.")),
        ("Pressure drop, inlet to outlet", per_type("dP"), "Δp [kPa]", "kPa",
         dict(scale=1e-3, note="Friction, hydrostatic head and inertia. The core runs downward, so "
                               "the head lowers the drop.")),
        ("Friction pressure drop", per_type("dPfric"), "Δp [kPa]", "kPa",
         dict(scale=1e-3, note="Darcy-Weisbach summed over the cells, with k_R scaling the "
                               "Reynolds number of both friction branches.")),
    ]
    marks = event_marks(inp, run_py)
    with plt.rc_context(STYLE), PdfPages(OUT / "lofa_pool_comparison.pdf") as pdf:
        summary_page(pdf, inp, run_py)
        if "size" in run_py:
            numbers_page(pdf, inp, run_py)
        for title, series, ylabel, unit, options in pages:
            comparison_page(pdf, inp, marks, title, series, ylabel, unit, **options)


def run_once(inp, steady_only):
    """Build the model, settle it and, unless `steady_only`, run the transient, timing each phase."""
    timing, sol, stopped = {}, None, None
    clock = time.perf_counter()
    m = build(inp)
    timing["build"] = time.perf_counter() - clock
    clock = time.perf_counter()
    y, steady = solve_steady(m, inp)
    timing["steady state"] = time.perf_counter() - clock
    if not steady_only:
        times = np.linspace(0.0, inp["t_end"], inp["n_saved"])
        # IDA's initial-condition solver cannot re-solve the loop after an instant step in the
        # pump head, so the head falls to zero over PUMP_RAMP instead and the steady state stays
        # a consistent start.
        head = m.pump.p
        m.agr.funcs[m.pump] = dict(pressure=lambda t: head * max(0.0, 1.0 - float(t) / PUMP_RAMP))
        # As in Python STREAM's own flapper coastdown test, the flow derivatives get a looser
        # absolute tolerance than the solver's default of 1e-12. The system is above index 1,
        # so its algebraic variables stay out of IDA's error test, the standard remedy. Even so
        # IDA's corrector stops converging half a second after the flapper opens unless its step
        # is capped; the cap also bounds how late the flapper and the scram, which Python checks
        # between steps, can be caught.
        atol = np.full(len(m.agr), 1e-12)
        atol[np.arange(len(m.agr))[m.agr.sections[m.K]][m.K.variables_by_type["mdot2"]]] = 1e-5
        clock = time.perf_counter()
        try:
            sol = m.agr.solve(y, time=times, atol=atol, exclude_algvar_from_error=True,
                              max_step_size=MAX_STEP)
        except TransientRuntimeError as e:
            # Keep what was solved before the failure, so the phase Python reached still compares.
            # A failure on the first step leaves no saved output at all.
            t_done = np.atleast_1d(np.asarray(e.t if e.t is not None else [], dtype=float))
            y_done = np.asarray(e.y if e.y is not None else [], dtype=float)
            sol = Solution(t_done, np.atleast_2d(y_done)) if t_done.size > 1 else None
            stopped = (float(t_done[-1]) if t_done.size else 0.0, str(e).splitlines()[0])
        timing["transient"] = time.perf_counter() - clock
    return SimpleNamespace(m=m, steady=steady, sol=sol, stopped=stopped, timing=timing)


def python_size(m):
    """How many unknowns Python hands IDA, with the algebraic ones counted by variable name
    across the components that carry them."""
    mass = np.asarray(m.agr.mass, dtype=float)
    rows = np.arange(len(mass))
    by_name = {}
    for comp, section in m.agr.sections.items():
        local = rows[section]
        for name, place in getattr(comp, "variables", {}).items():
            count = int(np.sum(mass[np.atleast_1d(local[place])] == 0))
            if not count:
                continue
            # Kirchhoff names its variables edge by edge; group them by kind instead.
            kind = next((k for k in ("mdot2", "p_abs") if k in str(name)), str(name))
            entry = by_name.setdefault(kind, {"count": 0, "in": []})
            entry["count"] += count
            if comp.name not in entry["in"]:
                entry["in"].append(comp.name)
    size = {"unknowns": len(mass), "differential": int(mass.sum())}
    size["algebraic"] = size["unknowns"] - size["differential"]
    size["algebraic_by_name"] = by_name
    return size


def size_rows(jl, py):
    def cell(d, key):
        return str(d[key]) if key in d else "-"

    return [
        ("unknowns in the model as built", cell(jl, "before"), cell(py, "unknowns")),
        ("unknowns the solver integrates", cell(jl, "unknowns"), cell(py, "unknowns")),
        ("of which differential", cell(jl, "differential"), cell(py, "differential")),
        ("of which algebraic", cell(jl, "algebraic"), cell(py, "algebraic")),
        ("observed, computed after the solve", cell(jl, "observed"), "-"),
    ]


def components(names):
    return ", ".join(names) if len(names) <= 3 else f"{len(names)} components"


def size_table(jl, py):
    """How large a system each solver integrates, and what its algebraic unknowns are. run.jl
    records Julia's sizes."""
    lines = ["Problem size. ModelingToolkit removes aliases and solves some algebraic equations "
             "symbolically before the solve; those come back afterwards as observed. Python hands "
             "the solver every unknown it builds.", "",
             "| | Julia | Python |", "|:---|---:|---:|"]
    lines += [f"| {a} | {b} | {c} |" for a, b, c in size_rows(jl, py)]
    if jl.get("algebraic_by_name"):
        lines += ["", "Julia's algebraic unknowns, by name:", "", "| unknown | count |", "|:---|---:|"]
        lines += [f"| `{name}` | {count} |" for name, count in jl["algebraic_by_name"].items()]
    if py.get("algebraic_by_name"):
        lines += ["", "Python's algebraic unknowns, by variable:", "", "| variable | count | in |",
                  "|:---|---:|:---|"]
        lines += [f"| `{name}` | {e['count']} | {', '.join(e['in'])} |"
                  for name, e in py["algebraic_by_name"].items()]
    return "\n".join(lines)


TIMING_PHASES = [("load packages", "import"), ("build and compile", "build"),
                 ("steady state", "steady state"), ("transient", "transient")]


def timing_rows(timing):
    """One row per phase: Julia cold (with its compiling share), same model and rebuilt model
    from the file timings.jl writes, then Python's first and second pass."""
    path = OUT / "julia_timings.csv"
    jl = pd.read_csv(path).set_index("phase") if path.exists() else None
    passes = timing.get("passes", [])

    def fmt(x):
        return "-" if x is None or not np.isfinite(x) else f"{x:.1f}"

    rows = []
    for j_phase, p_phase in TIMING_PHASES:
        if jl is not None and j_phase in jl.index:
            r = jl.loc[j_phase]
            share = r["cold_compiling"]
            cold = fmt(r["cold"]) + (f" ({100 * share:.0f}%)" if np.isfinite(share) else "")
            julia = [cold, fmt(r["same_model"]), fmt(r["rebuilt_model"])]
        else:
            julia = ["-"] * 3
        if p_phase == "import":
            python = [fmt(timing.get("import")), "-"]
        else:
            python = [fmt(p.get(p_phase)) for p in passes] + ["-"] * (2 - len(passes))
        rows.append([j_phase] + julia + python)
    return rows


def timing_table(timing):
    head = ["phase", "Julia cold", "Julia, same model", "Julia, rebuilt model",
            "Python first pass", "Python second pass"]
    lines = ["Wall time [s]. Julia's cold column gives the share spent compiling.", "",
             "| " + " | ".join(head) + " |", "|:---|" + "---:|" * (len(head) - 1)]
    lines += ["| " + " | ".join(row) + " |" for row in timing_rows(timing)]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--steady", action="store_true", help="stop after the steady state")
    parser.add_argument("--repeat", action="store_true", help="time a second pass as well")
    parser.add_argument("--plot", action="store_true", help="only redraw the figures from the last run")
    args = parser.parse_args()

    inp = json.loads((OUT / "julia_case.json").read_text())
    jl = pd.read_csv(OUT / "julia_series.csv")
    if args.plot:
        py = pd.read_csv(OUT / "python_series.csv")
        write_outputs(inp, jl, py, json.loads((OUT / "python_run.json").read_text()))
        return

    use_standards()
    t_import = time.perf_counter() - _T_START
    run = run_once(inp, args.steady)
    passes = [run.timing]
    if args.repeat:
        passes.append(run_once(inp, args.steady).timing)

    m, steady = run.m, run.steady
    steady_py = {"primary": steady[m.K.name][m.K.component_edge(m.pump)]}
    for key, t in m.types.items():
        steady_py[f"mdot_{key}"] = steady[m.K.name][m.K.component_edge(t.ch)]
        steady_py[f"T_out_{key}"] = float(np.asarray(steady[t.ch.name]["T_cool"])[-1])
    py = python_series(m, run.sol, inp) if run.sol is not None else None
    tripped = m.pk.controls.state == OneWayToSCRAM.SCRAM
    run_py = {
        "t_trip": float(m.pk.controls.t_state) if tripped else None,
        "t_flapper": float(m.flapper.t_open) if np.isfinite(m.flapper.t_open) else None,
        "stopped": run.stopped,
        "size": python_size(m),
        "timing": {"import": t_import, "passes": passes},
    }
    run_py["rows"] = report_rows(inp, steady_py, jl, py, run_py)
    (OUT / "python_run.json").write_text(json.dumps(run_py, indent=1))
    if py is not None:
        py.to_csv(OUT / "python_series.csv", index=False)
    elif run.stopped is not None:
        print(f"Python stopped at t = {run.stopped[0]:.3f} s with no series to compare: {run.stopped[1]}")
    write_outputs(inp, jl, py, run_py)
    print((OUT / "comparison.md").read_text())


def write_outputs(inp, jl, py, run_py):
    """comparison.md, and the PDF whenever there is a Python series to draw."""
    if py is not None:
        plot_pdf(inp, jl, py, run_py)
    tables = [
        report_md([tuple(r) for r in run_py["rows"]], run_py["stopped"]),
        size_table(inp.get("size", {}), run_py.get("size", {})),
        timing_table(run_py.get("timing", {})),
    ]
    (OUT / "comparison.md").write_text("\n\n".join(tables) + "\n")


if __name__ == "__main__":
    main()
