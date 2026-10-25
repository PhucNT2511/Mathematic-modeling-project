# Multi-Day Debt Collection Routing

Course project for **Mathematical Modeling** (SOICT). We plan routes for K debt
collection officers who visit n overdue customers over H days on the real road
network of Hanoi, so that the **total expected amount collected** is as large
as possible. A customer can be visited more than once, and the probability of
repayment decreases day by day.

![5-day routes of 2 officers, 80 customers](figures/INS_S_n80_H5/routes_grid.png)

*Each row is an officer and each column is a day. An officer starts at the
branch ★, visits customers in the order 1, 2, 3, … and returns to ★. Each
officer has one colour family (blue, red, …); day 1 is darkest and the colour
fades towards day 5.*

## Contents

- **MILP model** with visit-schedule variables λ(i,S), arcs x(i,j,k,t),
  assignment y(i,k,t), MTZ constraints, symmetry breaking between officers, and
  a second solve that minimises distance.
- **Solution methods:** Branch-and-Cut (HiGHS), Tabu Search, ALNS, Genetic
  Algorithm, and Branch-and-Cut warm-started from ALNS.
- **Numerical experiments:** 10 runs per configuration, measuring CPU time, gap
  and B&B node count for the one-day (Phase 1) and five-day (Phase 2) problems,
  n = 10 → 80 customers.
- **Extension:** comparison of the static, rolling-horizon and myopic (greedy)
  policies by Monte Carlo simulation.

## Documentation

| File | Contents |
|---|---|
| [docs/00_overview.md](docs/00_overview.md) | Problem, graphs, data, solution approaches, main results |
| [docs/01_mathematical_model.md](docs/01_mathematical_model.md) | Mathematical model (1)–(15) and the dynamic model |
| [docs/02_solution_representation.md](docs/02_solution_representation.md) | Solution representation, MILP ↔ heuristic mapping |
| [docs/03_solution_methods.md](docs/03_solution_methods.md) | Each method in detail, how the gap is computed |
| [docs/04_experiments.md](docs/04_experiments.md) | Experimental design, result tables, charts, discussion |
| [collection_routing_dataset_v3/README.md](collection_routing_dataset_v3/README.md) | Data sources and generation |

## Main results

Average over 10 runs, 80-customer instance INS_S, 2 officers:

| Phase | Method | Gap | CPU |
|---|---|---|---|
| Phase 1 (1 day, 30 s) | Branch-and-Cut | 877% (time limit, 0 nodes) | 32 s |
| | Tabu / ALNS / GA | 2.7% / 2.2% / 2.4% | 2 / 14 / 8 s |
| Phase 2 (5 days, 150 s) | Branch-and-Cut | 16,594% (time limit, 0 nodes) | 157 s |
| | Tabu / ALNS / GA | 1.1% / **0.4%** / 1.6% | 6 / 31 / 23 s |
| | BnC + ALNS start | 0.4% | 157 s |

Up to 30 customers, Branch-and-Cut proves optimality in 10/10 runs and every
metaheuristic finds the optimal solution. Full tables:
[docs/04_experiments.md](docs/04_experiments.md).

## Repository layout

```
core/                       models and algorithms
  model.jl                    DebtRoutingData, MILP (1)–(15)
  branch_and_cut.jl           HiGHS, warm start, second solve on distance
  genetic_algorithm.jl        GA, route construction, repair, shared evaluation
  tabu_search.jl, alns.jl     Tabu Search, ALNS
  run_v3_comparison.jl        compare methods on one instance (single run)
  run_v3_experiments.jl       10-run experiments for the report (resumable)
  run_v3_dynamic.jl           rolling-horizon / myopic policy on one scenario
  run_v3_static_vs_rolling.jl compare the three policies over many Monte Carlo scenarios
  export_v3_plan.jl           export a plan for plotting
  plot_v3_plan.py             plot customer maps and routes
  plot_results.py             plot experiment results
  test_v3_dynamic.jl          quick tests
data_processing/            v3 data loader, dynamic state, small test instances
configs/                    JSON configs for every experiment
scripts/                    run Phase 1 + Phase 2 in parallel (PowerShell, CMD)
collection_routing_dataset_v3/  dataset (CSV, sources, generation scripts)
outputs/                    results: experiments/, plans/, v3_<instance>/
figures/                    figures: experiments/, <instance>_n<n>_H<H>/
docs/                       documentation and project proposal
```

## Setup

- Julia 1.13 (packages in `Project.toml`, `Manifest.toml`): JuMP, HiGHS, JSON.
- Python 3 with `pandas`, `matplotlib`, `networkx` (plotting only).

```powershell
$env:JULIA_DEPOT_PATH = "D:\JuliaDepot"   # if you use a separate depot
$julia = "D:\julia-1.13.2\bin\julia.exe"  # or "julia" if it is on PATH
& $julia --project=. -e "using Pkg; Pkg.instantiate()"
```

## Running

Run all commands from the repository root in PowerShell.

```powershell
# Quick tests (about 1 minute)
& $julia --project=. core/test_v3_dynamic.jl
& $julia --project=. core/run_v3_experiments.jl configs/v3_experiments_smoke.json

# Main experiments: Phase 1 + Phase 2 in parallel, about 4 hours, resumable
powershell -ExecutionPolicy Bypass -File scripts\run_experiments.ps1
Get-Content outputs\experiments\v3_experiments_gd2.log -Wait -Tail 20 -Encoding UTF8

# Static vs rolling horizon vs myopic (about 3 hours)
& $julia --project=. core/run_v3_static_vs_rolling.jl configs/v3_static_vs_rolling_report.json

# One quick comparison on a single instance
& $julia --project=. core/run_v3_comparison.jl configs/v3_comparison.json

# Figures
& $julia --project=. core/export_v3_plan.jl INS_S 0 5 ALNS   # 0 = all customers
python core/plot_v3_plan.py      # plots every outputs/plans/plan_*.csv
python core/plot_results.py
```

The main experiments write `runs.csv` after every run; rerunning the same
command skips runs that are already finished. Set `"resume": false` in the
config to start from scratch.

### Configs

| File | Used for |
|---|---|
| `v3_experiments_gd1.json` | Phase 1: H = 1, 30 s, 9 instances |
| `v3_experiments_gd2.json` | Phase 2: H = 5, 150 s, 7 instances, plus warm start |
| `v3_experiments_smoke.json` | Quick test, 1 run |
| `v3_static_vs_rolling_report.json` | Three policies, 20 MC scenarios × 3 p-scenarios |
| `v3_static_vs_rolling.json` | Same with 100 MC scenarios (about 12–15 hours) |
| `v3_static_vs_rolling_smoke.json` | Quick test on INS_XS |
| `v3_comparison.json` | Single comparison, rolling-horizon policy on one scenario |

## Team

Mathematical Modeling course project, School of Information and Communication
Technology (SOICT), Hanoi University of Science and Technology.
