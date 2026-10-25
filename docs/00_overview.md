# Overview: multi-day debt collection routing

This document describes the problem, the data and the solution approaches at a
high level. Details are in the other documents:

| Document | Contents |
|---|---|
| [01_mathematical_model.md](01_mathematical_model.md) | Notation, MILP model (1)–(15), secondary objective, dynamic model |
| [02_solution_representation.md](02_solution_representation.md) | Solution representation, transformations between MILP and heuristics |
| [03_solution_methods.md](03_solution_methods.md) | Branch-and-Cut, GA, Tabu Search, ALNS; how to read the gap |
| [04_experiments.md](04_experiments.md) | Experimental design, result tables, figures, discussion |
| [de_xuat_de_tai.docx](de_xuat_de_tai.docx) | Original project proposal (Vietnamese) |

## 1. Problem

A bank branch has **K debt collection officers** on motorbikes and **n overdue
customers** over a period of **H working days**. Each day, each officer leaves
the branch, visits some customers and returns, within a limit of **B minutes**
(travel plus time spent with customers).

When visited on day t, customer i pays the full target amount w(i) with
probability p(i,t); otherwise nothing is collected. The probability
**decreases day by day**: the longer we wait, the harder it is to collect. A
customer may be visited again, at most m times in the period.

**Question:** on each day, which officer visits which customers and in what
order, so that the **total expected amount collected** over the period is
maximised? When two plans have the same expected value, choose the one with the
shorter total distance.

The expected value of customer i when visited on the set of days S is

$$
v(i,S)=w_i\Bigl[1-\prod_{t\in S}\bigl(1-p_{it}\bigr)\Bigr],
$$

i.e. w(i) times the probability that the customer pays at at least one visit.
This function is not linear in the visits, so the model chooses a **visit
schedule S** for each customer (variable λ) whose value v(i,S) is precomputed.

### Relation to the course's reference problem

The reference problem (Orange ROADEF 2026, T-Adaptive Segment Routing) solves
several **linked time periods**: Step 6 solves one period, Step 9 solves several
periods with linking constraints between them. This project has the same
structure:

| Orange T-ASR | Debt collection project |
|---|---|
| Step 6: one period | **Phase 1**: one day (H = 1), each customer visited at most once |
| Step 9: several linked periods | **Phase 2**: five days (H = 5), schedule λ links the days through constraint (3) and the limit of m visits |
| Time limit 1800 s / 3600 s, proportional to the number of periods | 30 s / 150 s = 30 s × 5 days |

## 2. Graphs

The problem uses two graph layers:

1. **Data layer:** the OSM road network of inner Hanoi, 57,242 nodes and
   130,220 directed edges (including one-way streets, speeds by road type).
2. **Model layer:** a complete directed graph G = (V, A) with
   |V| = n + 1 vertices (branch 0 and n customers) and |A| = n(n + 1) arcs.
   Each arc (i, j) carries the distance and travel time of the **shortest
   path** from i to j in the data layer.

![Two graph layers](../figures/INS_XS_n20_H5/graph.png)

## 3. Data

The dataset `collection_routing_dataset_v3/` (with its own README) is built from
public sources plus explicitly stated assumptions:

| Component | Source | Fixed or chosen |
|---|---|---|
| Road network, branch location | OpenStreetMap | Fixed |
| Customer locations | Sampled by population of 27 wards | Fixed by the seed of each customer set |
| Demographic profiles | NVIDIA Nemotron Personas (Vietnam) | Fixed |
| Credit limit, card utilisation | UCI Default of Credit Card (distribution shape) | Fixed |
| Loan amount, debt group, days past due | Assumed (log-normal, shares by groups 2–5) | Fixed |
| Probability p(i,t) | Assumed: h · p₀(group) · (1 − 0.3·f(DPD)) · (1 − δ)^(t−1) | Choose scenario h = 0.5 / 1 / 1.5 |
| Officers, working hours | 4 officers, 480 min/day, period 02–06/11/2026 | Choose K, B |
| Maximum visits m | Model parameter | Choose m |

There are 5 customer sets: **MAIN** (500 customers) and **REP1–REP4** (200
customers each), each generated with a different seed. The instances are
nested: INS_XS (30) ⊂ INS_S (80) ⊂ INS_M (200) ⊂ INS_L (500) are taken from
MAIN; REPk_S (80) ⊂ REPk_M (200) are taken from REPk.

![Customer locations, INS_S](../figures/INS_S_n80_H5/customers.png)

**Instance selection for the experiments** (details in
[04_experiments.md](04_experiments.md)): all parameters are fixed except the
number of customers n (K = 2, B = 480 minutes, m = 2, base p-scenario), and n is
increased through 10, 20, 30, 50, 80 by taking the first n customers of the
nested instances. At 80 customers REP1–REP4 are also used, to check that the
results do not depend on one particular customer set.

## 4. Solution approaches

### 4.1. Static planning (main problem)

Solve **once** for all H days, maximising expected value:

| Method | Type | Guarantee | File |
|---|---|---|---|
| Branch-and-Cut (HiGHS) | Exact | Upper bound; proves optimality if time allows | [branch_and_cut.jl](../core/branch_and_cut.jl) |
| Warm-started BnC | Exact + heuristic | Starts from the ALNS solution | same |
| Tabu Search | Metaheuristic | None | [tabu_search.jl](../core/tabu_search.jl) |
| ALNS | Metaheuristic | None | [alns.jl](../core/alns.jl) |
| Genetic Algorithm | Metaheuristic | None | [genetic_algorithm.jl](../core/genetic_algorithm.jl) |

The three metaheuristics share the matrix representation G(i,t) ∈ {0, 1, …, K}
(customer i, day t, which officer visits), the same route construction
(nearest-neighbour + 2-opt) and the same stopping rule: at most 300
iterations, stopping early after 50 consecutive iterations without
improvement.

### 4.2. Execution under uncertainty (extension)

A static plan does not use new information: a customer who paid on day 1 is
still in the day-3 schedule. Three policies are compared by Monte Carlo
simulation:

| Policy | When it plans | For how many days |
|---|---|---|
| Static | Once, at the start of the period | All H days |
| Rolling horizon | At the start of each day, after observing who has paid | The remaining days |
| Myopic (greedy) | At the start of each day | That day only |

All three use ALNS as the solver and the same random numbers within each
scenario.

## 5. Main results

Summary; full tables in [04_experiments.md](04_experiments.md).

- Up to 30 customers, Branch-and-Cut proves optimality in both phases and every
  metaheuristic finds the optimal solution.
- From 50 customers, Branch-and-Cut runs out of time almost at the root node,
  and its solutions are very poor (gaps from hundreds to tens of thousands of
  percent), even though the upper bound is fairly tight.
- The metaheuristics reach gaps of 0.1–3.7% against that bound in a few seconds
  to a few tens of seconds. ALNS has the smallest gap in Phase 2, Tabu is the
  fastest.
- Warm-starting Branch-and-Cut from the ALNS solution keeps the ALNS quality but
  does not improve it within 150 s.

![5-day routes, INS_S](../figures/INS_S_n80_H5/routes_overview.png)
