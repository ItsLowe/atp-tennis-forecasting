"""Redraw three dissertation figures from reviewed, rounded aggregate CSVs.

Presentation only: no R scripts, raw data, features, predictions or models are
loaded. These images do not establish independent statistical replication.
Run from the repository root: python3 reproducibility/make_portfolio_figures.py
"""

from pathlib import Path
import csv
import hashlib

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import MultipleLocator, PercentFormatter

ROOT = Path(__file__).resolve().parents[1]
INPUT = ROOT / "outputs" / "selected_results" / "reported_aggregates"
OUTPUT = ROOT / "figures"
SOURCES = {
    "figure_4_1_gap_reduction_reported.csv":
        "eb692ace73af88ddb38b629c1c8923e425df243a82bf67fba4712a48385255cd",
    "figure_4_2_disagreement_by_uncertainty_reported.csv":
        "affa41a6080051a51263b61f6a7f251ce3ae16e1d8b12cd18be5d71be2bc3fe6",
    "figure_4_3_disagreement_logloss_reported.csv":
        "9436eb55817b6279d458a45783f4092e3a3f8a1d539a6eace2fd928f05c2d940",
}
INK, MUTED, GRID = "#1E293B", "#526174", "#E2E8F0"
LOGISTIC, NN, TTT, BOOK = "#0072B2", "#009E73", "#D55E00", "#263238"
EXTENSION = "#CBD5E1"
DPI = 200

plt.rcParams.update({
    "font.family": "DejaVu Sans",
    "font.size": 12,
    "text.color": INK,
    "axes.labelcolor": INK,
    "axes.edgecolor": "#94A3B8",
    "xtick.color": MUTED,
    "ytick.color": MUTED,
    "axes.titleweight": "bold",
    "axes.spines.top": False,
    "axes.spines.right": False,
    "figure.facecolor": "white",
    "axes.facecolor": "white",
})


def read_reviewed(name):
    path = INPUT / name
    if hashlib.sha256(path.read_bytes()).hexdigest() != SOURCES[name]:
        raise ValueError(f"Reviewed source bytes changed: {name}")
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def heading(fig, title, subtitle):
    fig.text(.055, .957, title, fontsize=21, weight="bold", va="top")
    fig.text(.055, .905, subtitle, fontsize=12, color=MUTED, va="top")


def finish(fig, name, page, note):
    fig.text(.055, .083, note, fontsize=10.5, color=MUTED, va="top")
    fig.text(
        .055, .041,
        f"Redraw of dissertation-reported aggregates. {page}. Models not rerun.",
        fontsize=10, color=MUTED, va="top",
    )
    # Check the actual raster layout before writing, including labels and notes.
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    frame = fig.bbox
    texts = list(fig.texts)
    for ax in fig.axes:
        texts.extend(child for child in ax.get_children()
                     if isinstance(child, matplotlib.text.Text))
        texts.extend([ax.xaxis.label, ax.yaxis.label])
        # Locators also create tick labels outside the displayed limits.
        # Matplotlib does not draw those; check the displayed ticks only.
        for axis, limits in [(ax.xaxis, ax.get_xlim()), (ax.yaxis, ax.get_ylim())]:
            lo, hi = sorted(limits)
            texts.extend(label for position, label in
                         zip(axis.get_ticklocs(), axis.get_ticklabels())
                         if lo <= position <= hi)
    for legend in fig.legends:
        texts.extend(legend.get_texts())
    for text in texts:
        if text.get_visible() and text.get_text():
            box = text.get_window_extent(renderer=renderer)
            if (box.x0 < frame.x0 - 2 or box.y0 < frame.y0 - 2 or
                    box.x1 > frame.x1 + 2 or box.y1 > frame.y1 + 2):
                raise ValueError(f"Text outside figure bounds: {text.get_text()}")
    OUTPUT.mkdir(exist_ok=True)
    fig.savefig(
        OUTPUT / name, dpi=DPI,
        metadata={
            "Title": name.removesuffix(".png"),
            "Source": f"Zhiheng Huang, MSc dissertation, August 2026; {page}",
            "Verification": "SOURCE-CHECKED reported aggregates; no model execution",
            "Generator": f"Python / Matplotlib {matplotlib.__version__}",
        },
    )
    plt.close(fig)
    print(f"Created figures/{name} from reviewed reported aggregates")


def gap_figure():
    rows = read_reviewed("figure_4_1_gap_reduction_reported.csv")
    fig, axes = plt.subplots(2, 1, figsize=(12.2, 8.4))
    fig.subplots_adjust(left=.335, right=.925, top=.825, bottom=.215, hspace=.48)
    heading(
        fig, "Closing the test log-loss gap",
        "Overall test set, 2023-2025: 7,725 matches",
    )
    labels = [
        ["Full + short-term", "Full + short-term\n+ head-to-head",
         "Full + short-term\n+ common opponent",
         "Full + short-term + head-to-head\n+ common opponent"],
        ["Short-term", "Short-term + head-to-head",
         "Short-term + common opponent",
         "Short-term + head-to-head\n+ common opponent"],
    ]
    for ax, family, color, ticklabels in zip(
            axes, ["Logistic regression", "Neural network"], [LOGISTIC, NN], labels):
        group = [row for row in rows if row["model_family"] == family]
        values = [float(row["gap_closed_percent"]) for row in group]
        colors = [color if row["model_role"] == "primary" else EXTENSION for row in group]
        bars = ax.barh(range(4), values, height=.58, color=colors)
        ax.set_yticks(range(4), ticklabels, fontsize=11)
        ax.invert_yaxis()
        ax.set_xlim(0, 70)
        ax.xaxis.set_major_locator(MultipleLocator(10))
        ax.xaxis.set_major_formatter(PercentFormatter(100, decimals=0))
        ax.set_axisbelow(True)
        ax.grid(axis="x", color=GRID, linewidth=.8)
        ax.spines["left"].set_visible(False)
        ax.tick_params(axis="y", length=0, pad=12)
        ax.set_title(family, loc="left", fontsize=14, pad=12)
        for bar, row, value, tick in zip(bars, group, values, ax.get_yticklabels()):
            primary = row["model_role"] == "primary"
            tick.set_weight("bold" if primary else "normal")
            ax.text(value + .8, bar.get_y() + bar.get_height() / 2,
                    f"{value:.1f}%", va="center", fontsize=11.5,
                    weight="bold" if primary else "normal",
                    color=color if primary else INK)
    axes[1].set_xlabel("TTT-bookmaker log-loss gap closed (%)", labelpad=10)
    finish(
        fig, "test_gap_reduction.png", "Figure 4.1, PDF p.57",
        "Colored bars: validation-selected primaries. Gray bars: predefined extensions.",
    )


def rate_figure():
    rows = read_reviewed("figure_4_2_disagreement_by_uncertainty_reported.csv")
    values = [float(row["test_disagreement_rate_percent"]) for row in rows]
    fig, ax = plt.subplots(figsize=(10.6, 6.3))
    fig.subplots_adjust(left=.105, right=.945, top=.775, bottom=.255)
    heading(
        fig, "Disagreement rises with TTT uncertainty",
        "All test matches, 2023-2025: 7,725 matches",
    )
    ax.plot(range(1, 5), values, color=TTT, linewidth=2.5, marker="o", markersize=8)
    ax.set_xlim(.7, 4.3)
    ax.set_ylim(0, 30)
    ax.set_xticks([1, 2, 3, 4], ["Q1\nLowest", "Q2", "Q3", "Q4\nHighest"])
    ax.yaxis.set_major_locator(MultipleLocator(5))
    ax.yaxis.set_major_formatter(PercentFormatter(100, decimals=0))
    ax.set_axisbelow(True)
    ax.grid(axis="y", color=GRID, linewidth=.8)
    ax.set_ylabel("TTT-bookmaker disagreement rate", labelpad=10)
    ax.set_xlabel("TTT skill uncertainty group", labelpad=10)
    for x, value in enumerate(values, 1):
        ax.annotate(f"{value:.2f}%", (x, value), xytext=(0, 11),
                    textcoords="offset points", ha="center", color=TTT, weight="bold")
    finish(
        fig, "disagreement_by_uncertainty.png", "Figure 4.2, PDF p.60",
        "Training quartile cutoffs held fixed. Each rate uses all test matches in that group.",
    )


def logloss_figure():
    rows = read_reviewed("figure_4_3_disagreement_logloss_reported.csv")
    fig, ax = plt.subplots(figsize=(10.6, 6.9))
    fig.subplots_adjust(left=.105, right=.945, top=.74, bottom=.235)
    heading(
        fig, "Forecast error within disagreement matches",
        "Test disagreement subset, 2023-2025: 1,496 matches. Lower log loss is better.",
    )
    series = [
        ("bookmaker_logloss", "Bookmaker benchmark", BOOK, "o", "-"),
        ("ttt_logloss", "TTT baseline", TTT, "^", "--"),
        ("primary_logistic_logloss", "Primary logistic", LOGISTIC, "s", "-."),
        ("primary_nn_logloss", "Primary neural network", NN, "D", ":"),
    ]
    for column, label, color, marker, style in series:
        values = [float(row[column]) for row in rows]
        ax.plot(range(1, 5), values, label=label, color=color, marker=marker,
                linestyle=style, linewidth=2.4, markersize=6)
        ax.text(4.09, values[-1], f"{values[-1]:.4f}",
                va="center", color=color, fontsize=11, weight="bold")
    ax.set_xlim(.75, 4.52)
    ax.set_ylim(.58, 1.045)
    ax.yaxis.set_major_locator(MultipleLocator(.1))
    ax.set_xticks(
        range(1, 5),
        [f"{row['ttt_uncertainty_quartile']}\nn = {row['disagreement_match_count']}"
         for row in rows],
    )
    ax.set_ylabel("Log loss", labelpad=10)
    ax.set_xlabel("TTT uncertainty group (Q1 lowest, Q4 highest)", labelpad=10)
    ax.set_axisbelow(True)
    ax.grid(axis="y", color=GRID, linewidth=.8)
    fig.legend(*ax.get_legend_handles_labels(), loc="upper left",
               bbox_to_anchor=(.098, .833), ncol=2, frameon=False,
               fontsize=11, columnspacing=2.4, handlelength=2.8)
    finish(
        fig, "disagreement_logloss_by_uncertainty.png", "Figure 4.3, PDF pp.61-62",
        "Training quartile cutoffs held fixed. Counts refer only to test disagreement matches.",
    )


if __name__ == "__main__":
    gap_figure()
    rate_figure()
    logloss_figure()
