"""Vẽ biểu đồ kết quả thí nghiệm số từ outputs/ vào figures/experiments/.

Cách dùng: python core/plot_results.py

Đọc outputs/experiments/v3_experiments_gd{1,2}/summary.csv (10 lần chạy) và,
nếu có, outputs/v3_INS_S/static_vs_rolling/paired_summary.csv.
"""
import sys
sys.stdout.reconfigure(encoding="utf-8")
import json
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs"
FIG = ROOT / "figures" / "experiments"
METHOD_COLORS = {
    "Tabu": "#2b6cb0",
    "ALNS": "#c53030",
    "GA": "#6b46c1",
    "Branch-and-Cut": "#1a202c",
    "BnC + ALNS start": "#d69e2e",
}
PHASES = [("v3_experiments_gd1", "GD1: một ngày (H = 1)"),
          ("v3_experiments_gd2", "GD2: năm ngày (H = 5)")]
plt.rcParams.update({"axes.grid": True, "grid.alpha": 0.3, "axes.spines.top": False,
                     "axes.spines.right": False})


def load(phase):
    path = OUT / "experiments" / phase / "summary.csv"
    return pd.read_csv(path) if path.exists() else None


def time_limit(phase):
    config = json.loads((ROOT / "configs" / f"{phase}.json").read_text(encoding="utf-8"))
    return config["phases"][0]["time_limit_seconds"]


def main_series(df):
    """Chuỗi tăng dần số khách trên bộ MAIN: INS_XS n=10,20,30 rồi INS_S n=50,80."""
    return df[df.instance.isin(["INS_XS", "INS_S"])].sort_values("n")


def save(fig, name):
    FIG.mkdir(parents=True, exist_ok=True)
    fig.tight_layout()
    fig.savefig(FIG / f"{name}.png", dpi=170)
    plt.close(fig)
    print("Saved:", (FIG / f"{name}.png").relative_to(ROOT))


def line_panels(metric, ylabel, name, log=True, limit_line=False, symlog=False):
    fig, axes = plt.subplots(1, 2, figsize=(12, 4.6), sharey=True)
    for ax, (phase, title) in zip(axes, PHASES):
        df = load(phase)
        if df is None:
            continue
        df = main_series(df)
        for method, color in METHOD_COLORS.items():
            part = df[df.method == method]
            if part.empty:
                continue
            ax.plot(part.n, part[metric], "o-", color=color, lw=2, ms=6, label=method)
        if limit_line:
            ax.axhline(time_limit(phase), color="#718096", ls="--", lw=1)
            ax.text(10, time_limit(phase) * 1.08, f"giới hạn {time_limit(phase)} s",
                    fontsize=8, color="#4a5568")
        if symlog:
            ax.set_yscale("symlog", linthresh=0.1)
        elif log:
            ax.set_yscale("log")
        ax.set_xticks(sorted(df.n.unique()))
        ax.set_xlabel("số khách n (bộ MAIN, K = 2)")
        ax.set_title(title)
    axes[0].set_ylabel(ylabel)
    axes[1].legend(fontsize=8)
    save(fig, name)


def objective_n80():
    fig, axes = plt.subplots(1, 2, figsize=(13, 4.6))
    for ax, (phase, title) in zip(axes, PHASES):
        df = load(phase)
        if df is None:
            continue
        df = df[df.n == 80]
        instances = list(dict.fromkeys(df.instance))
        methods = [m for m in METHOD_COLORS if m in set(df.method)]
        width = 0.8 / len(methods)
        x = np.arange(len(instances))
        for j, method in enumerate(methods):
            vals = [df[(df.instance == i) & (df.method == method)].mean_objective.iloc[0]
                    for i in instances]
            ax.bar(x + (j - (len(methods) - 1) / 2) * width, vals, width,
                   color=METHOD_COLORS[method], label=method)
        bound = [df[df.instance == i].mean_upper_bound.min() for i in instances]
        ax.scatter(x, bound, marker="_", s=900, color="#e53e3e", lw=2, zorder=5,
                   label="cận trên BnC")
        ax.set_xticks(x, instances)
        ax.set_ylabel("giá trị thu hồi kỳ vọng (triệu đồng)")
        ax.set_title(f"{title}: các instance 80 khách")
    axes[1].legend(fontsize=8, loc="lower right")
    save(fig, "objective_n80")


def model_size():
    fig, ax = plt.subplots(figsize=(7, 4.4))
    for (phase, title), style in zip(PHASES, ["o-", "s--"]):
        path = OUT / "experiments" / phase / "instances.csv"
        if not path.exists():
            continue
        df = pd.read_csv(path)
        df = df[df.source_instance.isin(["INS_XS", "INS_S"])].sort_values("customers")
        ax.plot(df.customers, df.num_vars, style, color="#2b6cb0", label=f"biến – {title}")
        ax.plot(df.customers, df.num_constraints, style, color="#c53030",
                label=f"ràng buộc – {title}")
    ax.set_yscale("log")
    ax.set_xlabel("số khách n")
    ax.set_ylabel("kích thước MILP")
    ax.set_title("Kích thước mô hình theo số khách")
    ax.legend(fontsize=8)
    save(fig, "model_size")


def static_vs_rolling():
    candidates = [OUT / "v3_INS_S" / "static_vs_rolling" / "paired_summary.csv",
                  ROOT / "results" / "v3_INS_S" / "static_vs_rolling" / "paired_summary.csv"]
    path = next((p for p in candidates if p.exists()), None)
    if path is None:
        print("Chưa có paired_summary.csv của INS_S, bỏ qua hình so sánh chính sách")
        return
    df = pd.read_csv(path)
    df = df[df.metric == "collected_million_vnd"]
    scenarios = [s for s in ["THAP", "CO_SO", "CAO"] if s in set(df.p_scenario)]
    fig, axes = plt.subplots(1, 2, figsize=(12, 4.6))
    x = np.arange(len(scenarios))
    static = [df[df.p_scenario == s].mean_static.iloc[0] for s in scenarios]
    bars = [("Tĩnh", static, "#718096")]
    labels = {"rolling": ("Cuốn chiếu", "#2b6cb0"), "myopic": ("Tham lam", "#c53030")}
    for policy, (label, color) in labels.items():
        part = df[df.policy == policy]
        if not part.empty:
            bars.append((label, [part[part.p_scenario == s].mean_policy.iloc[0]
                                 for s in scenarios], color))
    width = 0.8 / len(bars)
    for j, (label, vals, color) in enumerate(bars):
        axes[0].bar(x + (j - (len(bars) - 1) / 2) * width, vals, width, color=color, label=label)
    axes[0].set_xticks(x, scenarios)
    axes[0].set_ylabel("tiền thu thực tế trung bình (triệu đồng)")
    axes[0].set_title(f"INS_S: trung bình trên {int(df.n_mc.iloc[0])} kịch bản Monte Carlo")
    axes[0].legend(fontsize=8)
    for j, (policy, (label, color)) in enumerate(labels.items()):
        part = df[df.policy == policy]
        if part.empty:
            continue
        mid = [part[part.p_scenario == s].mean_diff_policy_minus_static.iloc[0] for s in scenarios]
        lo = [part[part.p_scenario == s].ci95_low.iloc[0] for s in scenarios]
        hi = [part[part.p_scenario == s].ci95_high.iloc[0] for s in scenarios]
        offset = (j - 0.5) * 0.25
        axes[1].errorbar(x + offset, mid, yerr=[np.subtract(mid, lo), np.subtract(hi, mid)],
                         fmt="o", color=color, capsize=5, lw=2, label=label)
    axes[1].axhline(0, color="#1a202c", lw=1)
    axes[1].set_xticks(x, scenarios)
    axes[1].set_ylabel("chênh lệch so với tĩnh (triệu đồng)")
    axes[1].set_title("Chênh lệch ghép cặp và khoảng tin cậy 95%")
    axes[1].legend(fontsize=8)
    save(fig, "static_vs_rolling")


if __name__ == "__main__":
    line_panels("mean_cpu_seconds", "CPU trung bình (s, thang log)", "cpu_time",
                limit_line=True)
    line_panels("mean_gap_percent", "gap trung bình (%, thang symlog)", "gap", symlog=True)
    line_panels("mean_bb_nodes", "số node B&B trung bình", "bb_nodes", log=False)
    objective_n80()
    model_size()
    static_vs_rolling()
