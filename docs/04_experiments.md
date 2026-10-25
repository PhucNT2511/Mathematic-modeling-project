# Numerical experiments

Goal: measure the **CPU time, gap and number of Branch-and-Bound nodes** of the
methods as the problem size grows, for the one-day problem (Phase 1) and the
five-day problem (Phase 2). Each configuration is run **10 times** and the
results are averaged.

## 1. Environment

| Item | Value |
|---|---|
| Machine | Laptop, Intel Core i7-1165G7 (4 cores), Windows 10 |
| Language | Julia 1.13.2, JuMP, HiGHS (MIP, single thread) |
| Runner | [run_v3_experiments.jl](../core/run_v3_experiments.jl) |
| Configs | [v3_experiments_gd1.json](../configs/v3_experiments_gd1.json), [v3_experiments_gd2.json](../configs/v3_experiments_gd2.json) |
| Raw results | `outputs/experiments/v3_experiments_gd{1,2}/runs.csv`, `summary.csv`, `instances.csv` |

Phase 1 and Phase 2 run in parallel on two separate cores; HiGHS solves MIPs
almost single-threaded, so the two processes do not compete much for CPU.

## 2. Experimental design

### 2.1. Instances

The dataset offers many parameters (number of officers, minutes per day, m,
p-scenario). To isolate the effect of **size**, we fix all other parameters and
only increase the number of customers:

| Parameter | Fixed value | Reason |
|---|---|---|
| Number of officers K | 2 | Default of INS_XS and INS_S in the dataset |
| Working time B | 480 min/day | An 8-hour working day |
| Maximum visits m | 2 | Default of INS_S; used for every instance for a fair comparison |
| p-scenario | CO_SO (base, h = 1) | Base scenario |
| Number of days H | 1 (Phase 1), 5 (Phase 2) | Correspond to Step 6 / Step 9 of the reference problem |

The number of customers n takes the values **10, 20, 30, 50, 80**: the first n
customers of INS_XS (n ≤ 30) or INS_S (n = 50, 80). Because the instances are
nested, a small instance is a subset of a larger one, so changes in the results
are due to n only. The value 50 lies between 30 (BnC still solves it) and 80
(BnC no longer does). At n = 80 we also use REP1_S–REP4_S (Phase 1) and
REP1_S–REP2_S (Phase 2), generated with different seeds, to check that the
conclusions do not depend on one customer set.

### 2.2. Time limits

The reference problem uses 1800 s for one period and 3600 s for two periods,
i.e. **proportional to the number of periods**. We apply the same principle:
Phase 1 gets **30 s** for one day, Phase 2 gets **150 s = 30 s × 5 days**. The
limit is the same for every instance within a phase, so CPU times are
comparable across instances.

### 2.3. Methods and parameters

| Method | Parameters |
|---|---|
| Branch-and-Cut | HiGHS, `mip_rel_gap = 1e-4`, symmetry breaking (15), `random_seed` = run seed |
| BnC + ALNS start (Phase 2 only) | As above, with the ALNS solution as starting solution |
| Tabu Search | 300 iterations, 40 neighbours per iteration, tabu tenure 15 |
| ALNS | 300 iterations, 4 destroy operators, 2 repair operators, simulated annealing |
| GA | Population 80, 300 generations |

The three metaheuristics share **the same stopping rule**: at most 300
iterations/generations, stopping early after 50 consecutive iterations without
improving the best solution. Run r uses seed 2026 + r for every method.

### 2.4. Metrics

- **Mean value:** mean expected collection (million VND) over 10 runs.
- **Mean gap:** (UB* − value)/value, where UB* is the tightest Branch-and-Cut
  upper bound in the same run (see [03_solution_methods.md](03_solution_methods.md#9-reading-the-results)).
- **Mean CPU:** seconds, solving time only.
- **Mean nodes:** number of HiGHS Branch-and-Bound tree nodes.
- **Optimal:** number of runs out of 10 in which HiGHS proved optimality.

## 3. Instance sizes

### Phase 1: one day

| Instance | n | K | H | \|V\| | \|A\| | Variables | Constraints |
|---|---|---|---|---|---|---|---|
| INS_XS | 10 | 2 | 1 | 11 | 110 | 272 | 287 |
| INS_XS | 20 | 2 | 1 | 21 | 420 | 942 | 967 |
| INS_XS | 30 | 2 | 1 | 31 | 930 | 2,012 | 2,047 |
| INS_S | 50 | 2 | 1 | 51 | 2,550 | 5,352 | 5,407 |
| INS_S | 80 | 2 | 1 | 81 | 6,480 | 13,362 | 13,447 |
| REP1_S | 80 | 2 | 1 | 81 | 6,480 | 13,362 | 13,447 |
| REP2_S | 80 | 2 | 1 | 81 | 6,480 | 13,362 | 13,447 |
| REP3_S | 80 | 2 | 1 | 81 | 6,480 | 13,362 | 13,447 |
| REP4_S | 80 | 2 | 1 | 81 | 6,480 | 13,362 | 13,447 |

### Phase 2: five days

| Instance | n | K | H | \|V\| | \|A\| | Variables | Constraints |
|---|---|---|---|---|---|---|---|
| INS_XS | 10 | 2 | 5 | 11 | 110 | 1,460 | 1,395 |
| INS_XS | 20 | 2 | 5 | 21 | 420 | 4,910 | 4,755 |
| INS_XS | 30 | 2 | 5 | 31 | 930 | 10,360 | 10,115 |
| INS_S | 50 | 2 | 5 | 51 | 2,550 | 27,260 | 26,835 |
| INS_S | 80 | 2 | 5 | 81 | 6,480 | 67,610 | 66,915 |
| REP1_S | 80 | 2 | 5 | 81 | 6,480 | 67,610 | 66,915 |
| REP2_S | 80 | 2 | 5 | 81 | 6,480 | 67,610 | 66,915 |

The number of variables grows roughly as K·H·n² because of the arc variables
x(i,j,k,t). For the same n = 80, the five-day model is about 5 times larger
than the one-day model.

![Model size](../figures/experiments/model_size.png)

## 4. Phase 1 results: one day, 30 s limit

| Instance | n | Method | Mean value | Mean gap (%) | Mean CPU (s) | Mean nodes | Optimal |
|---|---|---|---|---|---|---|---|
| INS_XS | 10 | Tabu | 62.26 | 0.00 | 0.65 | – | – |
| INS_XS | 10 | ALNS | 62.26 | 0.00 | 0.02 | – | – |
| INS_XS | 10 | GA | 62.26 | 0.00 | 0.49 | – | – |
| INS_XS | 10 | Branch-and-Cut | 62.26 | 0.00 | 0.23 | 1.0 | 10/10 |
| INS_XS | 20 | Tabu | 96.97 | 0.00 | 0.42 | – | – |
| INS_XS | 20 | ALNS | 96.97 | 0.00 | 0.28 | – | – |
| INS_XS | 20 | GA | 96.97 | 0.00 | 1.13 | – | – |
| INS_XS | 20 | Branch-and-Cut | 96.97 | 0.00 | 1.15 | 1.0 | 10/10 |
| INS_XS | 30 | Tabu | 139.18 | 0.00 | 1.25 | – | – |
| INS_XS | 30 | ALNS | 139.18 | 0.00 | 1.05 | – | – |
| INS_XS | 30 | GA | 139.18 | 0.00 | 2.75 | – | – |
| INS_XS | 30 | Branch-and-Cut | 139.18 | 0.00 | 1.76 | 1.0 | 10/10 |
| INS_S | 50 | Tabu | 200.84 | 0.67 | 2.28 | – | – |
| INS_S | 50 | ALNS | 200.94 | 0.62 | 7.14 | – | – |
| INS_S | 50 | GA | 200.90 | 0.64 | 6.76 | – | – |
| INS_S | 50 | Branch-and-Cut | 68.51 | 270.88 | 30.63 | 3.5 | 0/10 |
| INS_S | 80 | Tabu | 273.43 | 2.74 | 2.21 | – | – |
| INS_S | 80 | ALNS | 274.81 | 2.22 | 13.91 | – | – |
| INS_S | 80 | GA | 274.32 | 2.40 | 7.71 | – | – |
| INS_S | 80 | Branch-and-Cut | 38.44 | 877.24 | 31.98 | 0.0 | 0/10 |
| REP1_S | 80 | Tabu | 282.27 | 3.63 | 2.03 | – | – |
| REP1_S | 80 | ALNS | 282.14 | 3.68 | 13.41 | – | – |
| REP1_S | 80 | GA | 283.22 | 3.28 | 7.42 | – | – |
| REP1_S | 80 | Branch-and-Cut | 35.60 | 2,005.39 | 32.62 | 0.0 | 0/10 |
| REP2_S | 80 | Tabu | 228.79 | 3.71 | 2.66 | – | – |
| REP2_S | 80 | ALNS | 228.82 | 3.70 | 14.72 | – | – |
| REP2_S | 80 | GA | 229.67 | 3.31 | 8.23 | – | – |
| REP2_S | 80 | Branch-and-Cut | 35.17 | 482.99 | 32.61 | 0.1 | 0/10 |
| REP3_S | 80 | Tabu | 265.45 | 2.57 | 2.26 | – | – |
| REP3_S | 80 | ALNS | 266.35 | 2.23 | 18.16 | – | – |
| REP3_S | 80 | GA | 266.23 | 2.27 | 8.27 | – | – |
| REP3_S | 80 | Branch-and-Cut | 38.26 | 24,330.70 | 32.59 | 0.0 | 0/10 |
| REP4_S | 80 | Tabu | 280.93 | 2.73 | 2.33 | – | – |
| REP4_S | 80 | ALNS | 281.01 | 2.70 | 14.83 | – | – |
| REP4_S | 80 | GA | 281.01 | 2.70 | 5.92 | – | – |
| REP4_S | 80 | Branch-and-Cut | 22.91 | 5,872.45 | 31.83 | 0.0 | 0/10 |

## 5. Phase 2 results: five days, 150 s limit

| Instance | n | Method | Mean value | Mean gap (%) | Mean CPU (s) | Mean nodes | Optimal |
|---|---|---|---|---|---|---|---|
| INS_XS | 10 | Tabu | 109.92 | 0.00 | 0.72 | – | – |
| INS_XS | 10 | ALNS | 109.92 | 0.00 | 0.08 | – | – |
| INS_XS | 10 | GA | 109.92 | 0.00 | 0.99 | – | – |
| INS_XS | 10 | Branch-and-Cut | 109.92 | 0.00 | 0.79 | 1.0 | 10/10 |
| INS_XS | 10 | BnC + ALNS start | 109.92 | 0.00 | 0.21 | 0.0 | 10/10 |
| INS_XS | 20 | Tabu | 168.77 | 0.00 | 0.76 | – | – |
| INS_XS | 20 | ALNS | 168.77 | 0.00 | 1.09 | – | – |
| INS_XS | 20 | GA | 168.77 | 0.00 | 2.93 | – | – |
| INS_XS | 20 | Branch-and-Cut | 168.77 | 0.00 | 6.15 | 0.9 | 10/10 |
| INS_XS | 20 | BnC + ALNS start | 168.77 | 0.00 | 0.86 | 0.0 | 10/10 |
| INS_XS | 30 | Tabu | 246.80 | 0.00 | 2.57 | – | – |
| INS_XS | 30 | ALNS | 246.80 | 0.00 | 3.54 | – | – |
| INS_XS | 30 | GA | 246.80 | 0.00 | 10.21 | – | – |
| INS_XS | 30 | Branch-and-Cut | 246.80 | 0.00 | 19.62 | 56.5 | 10/10 |
| INS_XS | 30 | BnC + ALNS start | 246.80 | 0.00 | 1.94 | 0.0 | 10/10 |
| INS_S | 50 | Tabu | 361.56 | 0.17 | 4.98 | – | – |
| INS_S | 50 | ALNS | 361.90 | 0.08 | 9.91 | – | – |
| INS_S | 50 | GA | 361.59 | 0.16 | 18.34 | – | – |
| INS_S | 50 | Branch-and-Cut | 35.82 | 1,264.36 | 155.03 | 2.0 | 0/10 |
| INS_S | 50 | BnC + ALNS start | 361.90 | 0.08 | 154.74 | 1.8 | 0/10 |
| INS_S | 80 | Tabu | 545.20 | 1.09 | 5.80 | – | – |
| INS_S | 80 | ALNS | 549.03 | 0.38 | 30.67 | – | – |
| INS_S | 80 | GA | 542.49 | 1.59 | 23.30 | – | – |
| INS_S | 80 | Branch-and-Cut | 6.99 | 16,594.40 | 156.76 | 0.0 | 0/10 |
| INS_S | 80 | BnC + ALNS start | 549.03 | 0.38 | 157.37 | 0.0 | 0/10 |
| REP1_S | 80 | Tabu | 604.09 | 1.18 | 6.26 | – | – |
| REP1_S | 80 | ALNS | 608.27 | 0.49 | 33.47 | – | – |
| REP1_S | 80 | GA | 595.97 | 2.56 | 23.46 | – | – |
| REP1_S | 80 | Branch-and-Cut | 42.26 | 41,049.20 | 160.48 | 0.0 | 0/10 |
| REP1_S | 80 | BnC + ALNS start | 608.27 | 0.49 | 160.64 | 0.0 | 0/10 |
| REP2_S | 80 | Tabu | 489.51 | 1.01 | 6.56 | – | – |
| REP2_S | 80 | ALNS | 492.25 | 0.45 | 39.70 | – | – |
| REP2_S | 80 | GA | 483.75 | 2.21 | 23.86 | – | – |
| REP2_S | 80 | Branch-and-Cut | 2.96 | 14,769.40 | 160.03 | 0.0 | 0/10 |
| REP2_S | 80 | BnC + ALNS start | 492.25 | 0.45 | 160.24 | 0.0 | 0/10 |

## 6. Charts

![CPU](../figures/experiments/cpu_time.png)

![Gap](../figures/experiments/gap.png)

![Number of nodes](../figures/experiments/bb_nodes.png)

![Value at 80 customers](../figures/experiments/objective_n80.png)

## 7. Discussion

1. **Small instances (n ≤ 30).** Branch-and-Cut proves optimality in 10/10 runs
   in both phases; Tabu, ALNS and GA all find the optimal solution (gap 0). The
   one-day problem is solved at the root node (1 node); the five-day problem
   with 30 customers needs about 56 nodes and 20 s, which shows that linking
   the days makes the problem clearly harder for the same number of customers.
2. **Difficulty threshold (n = 50).** Branch-and-Cut hits the time limit in
   both Phase 1 and Phase 2 with only 2–4 nodes: HiGHS spends almost all its
   time at the root node (cuts, presolve) without finding a good integer
   solution. The upper bound is already fairly tight (the heuristics are only
   0.1–0.7% away), but the BnC solution is very poor.
3. **Large instances (n = 80).** Branch-and-Cut does not leave the root node (0
   nodes), and its value is only about 1–14% of the metaheuristics'. The
   metaheuristics reach gaps of 2.2–3.7% in Phase 1 and 0.4–2.6% in Phase 2.
   The results are similar on INS_S and the REP sets, so they do not depend on
   one particular customer set.
4. **Comparing the metaheuristics.** In Phase 2, ALNS has the smallest gap
   (0.08–0.49%), Tabu is the fastest (5–7 s) with a gap of about 1%, and GA is
   slower and worse. In Phase 1 the three methods are close, with GA slightly
   ahead on REP1_S and REP2_S.
5. **Warm start.** BnC + ALNS start has exactly the same gap as ALNS: HiGHS
   accepts the ALNS solution as its starting solution but finds nothing better
   within 150 s and does not have time to close the gap. At n = 30, the warm
   start reduces CPU time from 19.6 s to 1.9 s.
6. **The heuristic gap is a conservative bound.** When BnC is not optimal, UB*
   may still be loose, so the true quality of the heuristics may be better than
   the gap suggests.

## 8. Extension: static, rolling horizon and myopic

Config: [v3_static_vs_rolling_report.json](../configs/v3_static_vs_rolling_report.json),
runner [run_v3_static_vs_rolling.jl](../core/run_v3_static_vs_rolling.jl).
Instance INS_S (80 customers, 2 officers, 5 days, m = 2), ALNS as the solver
for all three policies, 20 Monte Carlo scenarios per p-scenario, the same
random numbers across policies. Results in
`outputs/v3_INS_S/static_vs_rolling/`:

| File | Contents |
|---|---|
| `runs.csv` | One row per Monte Carlo scenario: collection, distance, visits and seconds of each policy |
| `policy_summary.csv` | Per policy and metric: mean, sd, se, 95% CI, min, quartiles, max |
| `paired_summary.csv` | Rolling horizon and myopic, each paired against static |
| `pairwise_comparison.csv` | Every pair of policies, including rolling horizon vs myopic |

The statistics can be recomputed from `runs.csv` without rerunning:
`julia --project=. core/run_v3_static_vs_rolling.jl --summarize outputs/v3_INS_S/static_vs_rolling`.

**Mean actual collection** (million VND, 20 scenarios; planned expectation of
the static plan in the last column):

| p-scenario | Static | Rolling horizon | Myopic | Static, planned E |
|---|---|---|---|---|
| THAP (low) | 289.62 | 288.41 | 289.18 | 287.98 |
| CO_SO (base) | 514.38 | **516.67** | 507.99 | 549.49 |
| CAO (high) | 735.90 | **740.83** | 733.40 | 783.45 |

**Paired differences** (policy − static; 95% CI; number of scenarios where the
policy is better out of 20):

| p-scenario | Policy | Collection (million VND) | Distance (km) |
|---|---|---|---|
| THAP | Rolling horizon | −1.21 (−0.4%) [−8.46; 6.05], 10/20 | −19.5 (−6.0%) [−25.0; −13.9], 18/20 |
| THAP | Myopic | −0.44 (−0.2%) [−10.99; 10.10], 11/20 | −41.7 (−12.8%) [−45.2; −38.2], 20/20 |
| CO_SO | Rolling horizon | +2.28 (+0.4%) [−4.28; 8.84], 12/20 | −27.7 (−8.8%) [−31.9; −23.5], 20/20 |
| CO_SO | Myopic | −6.40 (−1.2%) [−21.09; 8.30], 9/20 | −54.4 (−17.2%) [−57.8; −50.9], 20/20 |
| CAO | Rolling horizon | +4.93 (+0.7%) [−8.09; 17.95], 11/20 | −25.0 (−8.1%) [−30.4; −19.7], 20/20 |
| CAO | Myopic | −2.50 (−0.3%) [−23.37; 18.37], 9/20 | −50.8 (−16.4%) [−54.8; −46.8], 20/20 |

Rolling horizon minus myopic, collection: −0.76 (THAP), +8.68 (CO_SO),
+7.44 (CAO) million VND, none significant (|t| ≤ 1.4); see
`pairwise_comparison.csv`.

![Static, rolling horizon, myopic](../figures/experiments/static_vs_rolling.png)

**Discussion.**

1. **Collection: no significant difference.** Every 95% confidence interval for
   the collection difference contains 0. The rolling horizon has the highest
   mean under CO_SO and CAO, and its advantage over static grows with the
   repayment probability (−0.4%, +0.4%, +0.7%), but 20 scenarios are not enough
   to separate this from noise. The 100-scenario config
   (`v3_static_vs_rolling.json`) is needed for a firm conclusion.
2. **Distance: a clear gain.** Re-planning drops repeat visits to customers who
   have already paid, so the rolling horizon collects about the same amount
   with 6–9% less travel, and the interval lies entirely below 0.
3. **Myopic is the riskiest policy.** It travels the least because it never
   schedules repeat visits for later days, but its collection varies the most:
   the standard deviation of its paired difference is 1.5–2.2 times that of the
   rolling horizon (22–45 vs 14–28).
4. **Why the rolling horizon is not clearly best.** Each re-solve maximises the
   expectation as if no further re-planning will happen, so it is not the
   optimal dynamic policy; and ALNS is a heuristic whose solution quality varies
   by 1–2% between solves, about the size of the re-planning gain on INS_S.

Reference results from the dataset (sample Python script, 100 scenarios,
static and rolling horizon only;
`collection_routing_dataset_v3/ket_qua/BAO_CAO_MO_PHONG.md`): on INS_S, the
rolling horizon differs from static by −0.2% (THAP, low), +0.3% (CO_SO, base),
+0.7% (CAO, high); on INS_L by +1.6%, +3.6%, +4.1% respectively. The benefit of
re-planning grows when repayment probabilities are high and when there are many
customers.

## 9. Plan illustrations

Five-day plan of INS_S (ALNS). Each officer has one colour family; day 1 is
darkest and the colour fades towards day 5.

![Officer × day](../figures/INS_S_n80_H5/routes_grid.png)

![By day](../figures/INS_S_n80_H5/routes_by_day.png)

![By officer](../figures/INS_S_n80_H5/routes_by_officer.png)

![Visit schedule](../figures/INS_S_n80_H5/schedule.png)

## 10. Reproduction

```powershell
# Main tables (about 4 hours, Phase 1 and Phase 2 in parallel)
powershell -ExecutionPolicy Bypass -File scripts\run_experiments.ps1
# Compare the three policies (about 3 hours)
& "D:\julia-1.13.2\bin\julia.exe" --project=. core/run_v3_static_vs_rolling.jl configs/v3_static_vs_rolling_report.json
# Figures
python core/plot_results.py
python core/plot_v3_plan.py
```
