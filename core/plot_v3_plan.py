"""Maps of customers and routes from a plan written by export_v3_plan.jl.

Usage: python core/plot_v3_plan.py outputs/plans/plan_INS_S_n80_H5.csv [...]

Each officer has one colour family, darkest on day 1. Output in figures/<plan>/:
- customers.png: customer locations, size by target amount, colour by debt group;
- graph.png: OSM road network (data layer) and complete graph G=(V,A) (model layer);
- routes_grid.png: officer x day panels, customers numbered in visiting order;
- routes_overview.png: all routes on one map;
- routes_by_day.png, routes_by_officer.png: one panel per day / per officer;
- schedule.png: customer x day schedule.
"""
import sys
sys.stdout.reconfigure(encoding="utf-8")
import math
from pathlib import Path

import matplotlib
import matplotlib.colors as mcolors
import matplotlib.pyplot as plt
import numpy as np
import networkx as nx
import pandas as pd
from matplotlib.collections import LineCollection
from matplotlib.lines import Line2D

ROOT = Path(__file__).resolve().parents[1]
CSV = ROOT / "collection_routing_dataset_v3" / "csv"
FIGURES = ROOT / "figures"
BASE_COLORS = ["#3e7cb1", "#e0605e", "#8e6bbf", "#e3a33b", "#3ba99c"]
FAMILY_NAMES = ["blue", "red", "purple", "yellow", "teal"]
FAMILIES = BASE_COLORS
GROUP_COLORS = {2: "#8fcf9b", 3: "#f2d16b", 4: "#f0a35e", 5: "#d9534f"}
ROAD = "#e5e9f0"


def _mix(color, other, w):
    a, b = np.array(mcolors.to_rgb(color)), np.array(mcolors.to_rgb(other))
    return tuple((1 - w) * a + w * b)


def shade(k, t, H):
    """Officer k's colour on day t: 15% black on day 1 down to 40% white on day H."""
    base = BASE_COLORS[(k - 1) % len(BASE_COLORS)]
    x = 0.0 if H == 1 else (t - 1) / (H - 1)
    return _mix(base, "black", 0.15 * (1 - 2 * x)) if x <= 0.5 else _mix(base, "white", 0.40 * (2 * x - 1))


def text_color(rgb):
    """White text on dark fills, dark text on light ones."""
    r, g, b = rgb[:3]
    return "white" if 0.299 * r + 0.587 * g + 0.114 * b < 0.62 else "#1a202c"



def load_points(plan):
    customers = pd.read_csv(CSV / "khach_hang.csv", encoding="utf-8-sig")
    branch = pd.read_csv(CSV / "chi_nhanh.csv", encoding="utf-8-sig")
    ids = [x for x in dict.fromkeys(plan["location_id"]) if x != "CN01"]
    cols = ["lat", "lon", "node_id"]
    pts = customers.set_index("khach_hang_id").loc[
        ids, cols + ["so_tien_muc_tieu_vnd", "nhom_no"]]
    depot = branch.set_index("chi_nhanh_id").loc[["CN01"], cols]
    return pd.concat([depot, pts])


def all_customers(instance, n):
    """First n customers of the instance, visited or not, in load_v3_data order."""
    links = pd.read_csv(CSV / "thuc_the_khach_hang.csv", encoding="utf-8-sig")
    ids = links[links.thuc_the_id == instance].khach_hang_id.head(n)
    customers = pd.read_csv(CSV / "khach_hang.csv", encoding="utf-8-sig")
    return customers.set_index("khach_hang_id").loc[ids]


def load_road(points, margin=0.008):
    nodes = pd.read_csv(CSV / "nut_duong.csv", encoding="utf-8-sig").set_index("node_id")
    edges = pd.read_csv(CSV / "canh_duong.csv", encoding="utf-8-sig")
    graph = nx.DiGraph()
    for u, v, w, oneway in edges[["u", "v", "travel_time_s", "oneway"]].itertuples(index=False):
        graph.add_edge(u, v, weight=w)
        if oneway == 0:
            graph.add_edge(v, u, weight=w)
    inside = nodes[nodes.lat.between(points.lat.min() - margin, points.lat.max() + margin)
                   & nodes.lon.between(points.lon.min() - margin, points.lon.max() + margin)]
    shown = edges[edges.u.isin(inside.index) & edges.v.isin(inside.index)]
    return graph, nodes, shown


def setup(ax, points):
    ax.set_aspect(1 / math.cos(math.radians(points.lat.mean())))
    ax.set_xticks([])
    ax.set_yticks([])
    for side in ax.spines.values():
        side.set_color("#a0aec0")


def draw_road(ax, nodes, shown):
    a = nodes.loc[shown.u, ["lon", "lat"]].to_numpy()
    b = nodes.loc[shown.v, ["lon", "lat"]].to_numpy()
    ax.add_collection(LineCollection(list(zip(a, b)), colors=ROAD, lw=0.35, zorder=1))
    ax.autoscale_view()


def draw_depot(ax, points):
    ax.scatter(points.lon["CN01"], points.lat["CN01"], marker="*", s=600,
               color="#1a202c", edgecolor="white", lw=1.2, zorder=7)


class Plotter:
    def __init__(self, plan_file):
        self.plan_file = Path(plan_file)
        self.plan = pd.read_csv(self.plan_file)
        self.points = load_points(self.plan)
        self.graph, self.nodes, self.shown = load_road(self.points)
        stem = self.plan_file.stem.replace("plan_", "")
        self.instance = stem.split("_n")[0]
        self.n = int(stem.split("_n")[1].split("_")[0])
        self.H = int(stem.split("_H")[-1])
        self.K = int(self.plan.officer.max())
        self.outdir = FIGURES / stem
        self.outdir.mkdir(parents=True, exist_ok=True)
        self.title = (f"{self.instance}: {len(self.points) - 1} customers visited, "
                      f"{self.K} officers, {self.H} days")
        self.cache = {}

    def road_path(self, a, b):
        if (a, b) not in self.cache:
            path = nx.shortest_path(self.graph, self.points.node_id[a],
                                    self.points.node_id[b], weight="weight")
            self.cache[(a, b)] = list(zip(self.nodes.lon[path], self.nodes.lat[path]))
        return self.cache[(a, b)]

    def routes(self):
        for (k, t), stops in self.plan.groupby(["officer", "day"]):
            yield int(k), int(t), stops.sort_values("stop_order")

    def draw_route(self, ax, k, t, stops, lw=2.0, size=55, numbered=False):
        seq = stops.location_id.tolist()
        color = shade(k, t, self.H)
        segments = [self.road_path(a, b) for a, b in zip(seq, seq[1:])]
        ax.add_collection(LineCollection(segments, colors=[color], lw=lw,
                                         alpha=0.9, zorder=3 + (self.H - t) * 0.01))
        # Arrow at the middle of each leg shows the direction.
        for seg in segments:
            if len(seg) >= 2:
                m = len(seg) // 2
                (x0, y0), (x1, y1) = seg[max(m - 1, 0)], seg[m]
                ax.annotate("", xy=(x1, y1), xytext=(x0, y0), zorder=4,
                            arrowprops=dict(arrowstyle="-|>", color=color, lw=0,
                                            mutation_scale=12))
        visited = [x for x in seq if x != "CN01"]
        ax.scatter(self.points.lon[visited], self.points.lat[visited], s=size,
                   color=[color], edgecolor="white", lw=1.0, zorder=5)
        if numbered:
            for order, cid in enumerate(visited, start=1):
                ax.text(self.points.lon[cid], self.points.lat[cid], str(order),
                        ha="center", va="center", fontsize=6.5, fontweight="bold",
                        color=text_color(color), zorder=6)

    def legend(self, ax, officers=None, days=None, **kw):
        officers = officers or range(1, self.K + 1)
        days = days or range(1, self.H + 1)
        handles = [Line2D([], [], color=shade(k, t, self.H), lw=3,
                          label=f"Officer {k} – day {t}")
                   for k in officers for t in days]
        ax.legend(handles=handles, fontsize=7.5, ncol=len(list(officers)),
                  framealpha=0.92, **kw)

    def figure_customers(self):
        everyone = all_customers(self.instance, self.n)
        visited = set(self.points.index) - {"CN01"}
        fig, ax = plt.subplots(figsize=(9, 8))
        setup(ax, everyone)
        draw_road(ax, self.nodes, self.shown)
        size = 15 + 250 * everyone.so_tien_muc_tieu_vnd / everyone.so_tien_muc_tieu_vnd.max()
        for g, color in GROUP_COLORS.items():
            sel = everyone.nhom_no == g
            edge = ["#1a202c" if i in visited else "white" for i in everyone.index[sel]]
            ax.scatter(everyone.lon[sel], everyone.lat[sel], s=size[sel], color=color,
                       edgecolor=edge, lw=0.8, alpha=0.9, zorder=4, label=f"debt group {g}")
        draw_depot(ax, self.points)
        ax.legend(fontsize=9, loc="lower left", framealpha=0.92,
                  title="marker size ∝ target amount\nblack edge = visited", title_fontsize=8)
        ax.set_title(f"{self.instance}: locations of {len(everyone)} customers and the branch (★)",
                     fontsize=12)
        self.save(fig, "customers")

    def figure_graph(self):
        points = self.points.iloc[:21] if len(self.points) > 21 else self.points
        fig, axes = plt.subplots(1, 2, figsize=(14, 6.5))
        ax = axes[0]
        setup(ax, self.points)
        draw_road(ax, self.nodes, self.shown)
        route = next(self.routes())[2]
        seq = route.location_id.tolist()
        j = int(route.leg_km.to_numpy().argmax())
        a, b = seq[j - 1], seq[j]
        xs, ys = zip(*self.road_path(a, b))
        ax.plot(xs, ys, color="#e53e3e", lw=2.2, zorder=4)
        ax.plot([self.points.lon[a], self.points.lon[b]], [self.points.lat[a], self.points.lat[b]],
                color="#e53e3e", lw=1.2, ls="--", zorder=4)
        ax.scatter(self.points.lon[1:], self.points.lat[1:], s=16, color="#4a5568", zorder=5)
        draw_depot(ax, self.points)
        ax.set_title(f"Data layer: OSM road network ({len(self.shown):,} edges in view)\n"
                     f"solid red = shortest path; dashed red = one model arc (i, j), "
                     f"{route.leg_km.iloc[j]:.1f} km", fontsize=10)
        ax = axes[1]
        setup(ax, points)
        labels = list(points.index)
        pairs = [[(points.lon[u], points.lat[u]), (points.lon[v], points.lat[v])]
                 for u in labels for v in labels if u < v]
        ax.add_collection(LineCollection(pairs, colors="#a0aec0", lw=0.35, alpha=0.7))
        ax.scatter(points.lon[1:], points.lat[1:], s=22, color="#4a5568", zorder=5)
        draw_depot(ax, points)
        for i, name in enumerate(labels):
            ax.annotate("0" if name == "CN01" else str(i), (points.lon[name], points.lat[name]),
                        xytext=(3, 3), textcoords="offset points", fontsize=7, zorder=6)
        n = len(labels) - 1
        ax.set_title(f"Model layer: complete graph G = (V, A) (showing {n} customers)\n"
                     f"|V| = {n + 1} nodes, |A| = n(n+1) = {n * (n + 1)} directed arcs",
                     fontsize=10)
        # Same map extent in both panels, so they have the same size and scale.
        ax.set_xlim(axes[0].get_xlim())
        ax.set_ylim(axes[0].get_ylim())
        self.save(fig, "graph")

    def figure_overview(self):
        fig, ax = plt.subplots(figsize=(12, 11))
        setup(ax, self.points)
        draw_road(ax, self.nodes, self.shown)
        for k, t, stops in sorted(self.routes(), key=lambda r: -r[1]):
            self.draw_route(ax, k, t, stops, lw=2.4, size=90)
        draw_depot(ax, self.points)
        self.legend(ax, loc="lower left")
        ax.set_title(f"{self.title}\none colour per officer; day 1 darkest, fading towards "
                     f"day {self.H}", fontsize=12)
        self.save(fig, "routes_overview")

    def figure_by_day(self):
        cols = min(self.H, 3 if self.H > 3 else self.H)
        rows = math.ceil(self.H / cols)
        fig, axes = plt.subplots(rows, cols, figsize=(5.6 * cols, 5.4 * rows), squeeze=False)
        for t, ax in zip(range(1, self.H + 1), axes.flat):
            setup(ax, self.points)
            draw_road(ax, self.nodes, self.shown)
            ax.scatter(self.points.lon[1:], self.points.lat[1:], s=8, color="#cbd5e0", zorder=2)
            notes = []
            for k, day, stops in self.routes():
                if day != t:
                    continue
                self.draw_route(ax, k, t, stops)
                notes.append(f"Officer {k}: {len(stops) - 2} customers, {stops.leg_km.sum():.1f} km")
            draw_depot(ax, self.points)
            ax.set_title(f"Day {t}\n" + (" | ".join(notes) or "no routes"),
                         fontsize=10)
        for ax in list(axes.flat)[self.H:]:
            ax.axis("off")
            self.legend(ax, loc="center")
        fig.suptitle(self.title, fontsize=13)
        self.save(fig, "routes_by_day")

    def figure_by_officer(self):
        fig, axes = plt.subplots(1, self.K, figsize=(7 * self.K, 6.8), squeeze=False)
        for k, ax in zip(range(1, self.K + 1), axes.flat):
            setup(ax, self.points)
            draw_road(ax, self.nodes, self.shown)
            total = 0.0
            for kk, t, stops in sorted(self.routes(), key=lambda r: -r[1]):
                if kk == k:
                    self.draw_route(ax, k, t, stops)
                    total += stops.leg_km.sum()
            draw_depot(ax, self.points)
            self.legend(ax, officers=[k], loc="lower left")
            ax.set_title(f"Officer {k} ({FAMILY_NAMES[(k - 1) % len(FAMILIES)]} shades): "
                         f"{total:.1f} km over {self.H} days", fontsize=11)
        fig.suptitle(self.title, fontsize=13)
        self.save(fig, "routes_by_officer")

    def figure_schedule(self):
        cust = list(self.points.index[1:])
        cells = {(r.location_id, int(r.day)): int(r.officer)
                 for r in self.plan[self.plan.location_id != "CN01"].itertuples()}
        height = max(4.0, 0.2 * len(cust) + 1.5)
        fig, ax = plt.subplots(figsize=(1.2 * self.H + 3, height))
        for r, cid in enumerate(cust):
            for t in range(1, self.H + 1):
                k = cells.get((cid, t))
                color = shade(k, t, self.H) if k else "#f1f4f8"
                ax.add_patch(plt.Rectangle((t - 1, r), 0.94, 0.88, color=color))
                if k and len(cust) <= 90:
                    ax.text(t - 0.53, r + 0.44, f"O{k}", ha="center", va="center",
                            fontsize=6, color="white" if t <= self.H / 2 + 1 else "#1a202c")
        ax.set_xlim(0, self.H)
        ax.set_ylim(len(cust), 0)
        ax.set_xticks([t - 0.53 for t in range(1, self.H + 1)],
                      [f"Day {t}" for t in range(1, self.H + 1)])
        step = 1 if len(cust) <= 60 else 5
        ax.set_yticks([r + 0.44 for r in range(0, len(cust), step)],
                      [f"{r + 1}: {cust[r]}" for r in range(0, len(cust), step)], fontsize=6)
        for side in ax.spines.values():
            side.set_visible(False)
        self.legend(ax, loc="upper left", bbox_to_anchor=(1.01, 1))
        ax.set_title(f"Visit schedule y(i,k,t): {self.title}", fontsize=10)
        self.save(fig, "schedule")

    def save(self, fig, name):
        fig.tight_layout()
        path = self.outdir / f"{name}.png"
        fig.savefig(path, dpi=170, bbox_inches="tight", pad_inches=0.1)
        plt.close(fig)
        print("Saved:", path.relative_to(ROOT))

    def figure_grid(self):
        """Officer x day panels, customers numbered in visiting order."""
        fig, axes = plt.subplots(self.K, self.H, figsize=(4.6 * self.H, 4.6 * self.K + 0.8),
                                 squeeze=False)
        routes = {(k, t): stops for k, t, stops in self.routes()}
        for k in range(1, self.K + 1):
            for t in range(1, self.H + 1):
                ax = axes[k - 1, t - 1]
                setup(ax, self.points)
                draw_road(ax, self.nodes, self.shown)
                ax.scatter(self.points.lon[1:], self.points.lat[1:], s=6,
                           color="#cbd5e0", zorder=2)
                stops = routes.get((k, t))
                if stops is None:
                    ax.set_title(f"Officer {k} – day {t}: no route", fontsize=10)
                else:
                    self.draw_route(ax, k, t, stops, lw=2.2, size=120, numbered=True)
                    ax.set_title(f"Officer {k} – day {t}: {len(stops) - 2} customers, "
                                 f"{stops.leg_km.sum():.1f} km", fontsize=10,
                                 color=shade(k, 1, self.H))
                draw_depot(ax, self.points)
        fig.suptitle(f"{self.title}\neach panel is one officer's route on one day: "
                     f"start at the branch ★, visit customers in the order 1, 2, 3, …, return to ★",
                     fontsize=13)
        self.save(fig, "routes_grid")

    def all(self):
        self.figure_grid()
        self.figure_customers()
        self.figure_graph()
        self.figure_overview()
        self.figure_by_day()
        self.figure_by_officer()
        self.figure_schedule()


if __name__ == "__main__":
    files = sys.argv[1:] or sorted((ROOT / "outputs" / "plans").glob("plan_*.csv"))
    for f in files:
        Plotter(f).all()
