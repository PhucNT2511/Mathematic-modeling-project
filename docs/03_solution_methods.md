# Solution methods for the debt collection routing problem

## 1. Purpose

This document explains the methods implemented in the project, tied directly to
the data, the decision variables and the current source code. For each method
it answers three questions:

1. What data does the method take?
2. How does it build and improve a collection plan?
3. What does the result mean, and is it guaranteed to be optimal?

The full mathematical model is in
[01_mathematical_model.md](01_mathematical_model.md).

## 2. Input data

Every method reads the same `DebtRoutingData` object, built by
`data_processing/load_v3_data.jl` from the dataset
`collection_routing_dataset_v3` (see [00_overview.md](00_overview.md#3-data)):

- `debt[i]`: target amount w(i) (million VND);
- `probability[i,t]`: collection probability p(i,t) under the chosen
  p-scenario;
- `distance`, `travel_time`: (n+1)×(n+1) matrices between the branch and the
  customers, computed as shortest paths on the OSM road network;
- `service_time[i]`, `daily_budget[k,t]`, `max_visits[i]`.

Since every method uses exactly the same data, differences in the results come
only from the algorithms.

## 3. Shared solution representation

### 3.1. MILP representation

The exact model uses:

- x(i,j,k,t): officer k travels from i to j on day t.
- y(i,k,t): officer k visits customer i on day t.
- z(k,t): officer k has a route on day t.
- lambda(i,S): customer i is given schedule S.
- u(i,k,t): MTZ position, used to eliminate subtours.

### 3.2. Heuristic representation

GA, Tabu and ALNS use a gene matrix:

$$
G_{it}\in\{0,1,\ldots,K\}.
$$

- G(i,t)=0: customer i is not visited on day t.
- G(i,t)=k: officer k visits customer i on day t.

The gene matrix decides the customer, the day and the officer. The order of
each route is built afterwards with nearest-neighbour and improved with 2-opt.

### 3.3. Route construction

For each officer-day pair:

1. Take all customers assigned to that officer.
2. Start at the branch.
3. Choose the unvisited customer closest to the current position.
4. Repeat until no customers are left, then return to the branch.
5. Try reversing segments with 2-opt to reduce distance.

Example:

    0 -> 5 -> 2 -> 8 -> 0

where 0 is the branch.

### 3.4. Repair

All heuristics use the same repair procedure:

1. If a customer exceeds max_visits, keep the days with the highest
   probability.
2. Build the route for every officer and every day.
3. Compute the total travel and service time.
4. If the budget is exceeded, remove the visit with the smallest marginal
   expected loss.
5. Repeat until every route is feasible.

As a result, the value reported by a heuristic always belongs to a plan that
can be executed under the current constraints.

### 3.5. Comparing two heuristic solutions

Two solutions are compared lexicographically:

1. The solution with the larger expected collection is preferred.
2. If the expected values are equal, the solution with the smaller total
   distance is preferred.

Money and kilometres are not added into one arbitrary expression, which avoids
choosing a conversion factor without justification.

## 4. Branch-and-Cut with HiGHS

File: core/branch_and_cut.jl.

JuMP passes the MILP model to HiGHS. HiGHS performs:

1. Presolve to remove redundant variables and constraints.
2. Solve the LP relaxation at the root node.
3. Add cutting planes that remove fractional solutions without removing valid
   integer solutions.
4. Use internal heuristics to find an incumbent.
5. Branch if fractional variables remain.
6. Maintain the upper bound and the best integer solution.
7. Stop when the gap is small enough or the time limit is reached.

For a maximisation problem, HiGHS reports:

$$
\operatorname{gap}
=
\frac{\text{upper bound}-\text{incumbent}}
{\text{upper bound}}\times100\%.
$$

If the objective equals the bound, the gap is 0 and the solution is proved
optimal. (The report uses a slightly different gap, see Section 9.)

The MILP maximises the expected collection. With `minimize_distance = true`,
BnC runs a second MILP solve that fixes the expected value with constraint (13)
and minimises distance (14). The Phase 1 / Phase 2 experiment configs do not
enable it, so in those tables distance is a secondary criterion only in the
heuristics.

## 5. Genetic Algorithm

File: core/genetic_algorithm.jl.

### Initialisation

Each individual is a matrix G. Each cell is chosen for a visit with probability
0.35 and then assigned to a random officer. Repair brings the individual back
into the feasible region.

### One generation

1. Evaluate the expected value and distance of the whole population.
2. Rank by expected value, then by distance.
3. Keep the elite_count best individuals unchanged.
4. Tournament selection picks the two parents.
5. Uniform crossover takes each gene from one parent or the other.
6. Mutation replaces a gene with 0 or a random officer.
7. Repair the child.
8. Repeat until population_size is reached.

Current standard parameters:

- population_size=80.
- generations=150.
- mutation_rate=0.03.
- elite_count=4.

The large profile reduces this to 60 individuals and 100 generations.
The xlarge profile uses 40 individuals and 60 generations.

### Interpretation

GA searches several regions at once, but crossover can destroy good route
structure. Repair is therefore an essential component.

## 6. Tabu Search

File: core/tabu_search.jl.

### Initial solution

Visits are ranked by the approximate ratio:

$$
\frac{w_i p_{it}}
{s_i+\tau_{0i}+\tau_{i0}}.
$$

The algorithm inserts the decisions with the highest ratio one by one while
they remain feasible.

### One iteration

1. Pick a random customer and a random day.
2. Replace the gene value with no visit or another officer.
3. Repair and evaluate the solution.
4. Repeat to create neighborhood_size neighbours.
5. Choose the best valid neighbour, even if it is worse than the current
   solution.
6. Forbid returning to the old value for tabu_tenure iterations.
7. If a tabu move produces a new global best, aspiration allows it.

Standard parameters:

- iterations=300.
- neighborhood_size=50.
- tabu_tenure=15.

The tabu memory keeps the algorithm from cycling between a few plans.

## 7. Adaptive Large Neighborhood Search

File: core/alns.jl.

ALNS destroys a large part of the plan and rebuilds it, which suits moving many
customers between days and officers.

### Destroy operators

1. Random removal: remove random visits.
2. Worst-value removal: remove visits with low marginal value.
3. Related removal: pick a customer and remove the customers close to them.
4. Route removal: remove part of one officer-day route.

### Repair operators

1. Greedy insertion: choose the insertion with the largest gain in expected
   value; ties go to the smallest increase in distance.
2. Regret-2 insertion: prefer the customer who would lose the most if their
   best insertion position were not used.

### One iteration

1. Roulette-wheel selection of destroy and repair operators by weight.
2. Remove about 20% of the visits.
3. Reinsert until no feasible insertion remains.
4. Use simulated annealing to decide whether to accept the new solution.
5. Score the operators: 10 for a new global best, 5 for improving the current
   solution and 1 for an accepted solution.
6. Every 25 iterations, update the weights with reaction factor 0.2.

Standard ALNS runs 500 iterations; the large profile runs 300.

## 8. Experimental procedure

`core/run_v3_experiments.jl` runs, for each instance and each run r = 1..10
(seed = 2026 + r):

1. Tabu, ALNS and GA with the same budget: at most 300 iterations/generations,
   stopping early after 50 consecutive iterations without improving the best
   solution.
2. Branch-and-Cut (HiGHS) with the time limit of the phase
   (Phase 1: 30 s, Phase 2: 150 s), `mip_rel_gap = 1e-4`, symmetry breaking
   (15).
3. In Phase 2, additionally Branch-and-Cut warm-started from the ALNS solution.
4. The value, upper bound, status, CPU time and number of B&B nodes of every
   run are written to `outputs/experiments/<config>/runs.csv`; averages go to
   `summary.csv`.

## 9. Reading the results

### Objective

Total expected collection, not an amount that is certain to be collected.

### Status

- OPTIMAL: HiGHS has proved optimality (gap ≤ 0.01%).
- TIME_LIMIT: a solution exists but optimality was not proved before the time
  limit.
- HEURISTIC: the method does not provide a proof of optimality.

### Gap

The problem is a maximisation, so the upper bound UB comes from HiGHS. In each
run, UB* is the smallest (tightest) bound over the Branch-and-Cut calls, and

$$
\operatorname{gap}=\frac{UB^*-\text{objective}}{\text{objective}}\times100\%.
$$

The denominator is the solution value. A gap of 0 means the solution is proved
optimal. The gap of a heuristic is a conservative estimate: the solution may
actually be closer to the optimum than UB* is tight enough to show.

### Node count

HiGHS `MOI.NodeCount`: the number of Branch-and-Bound tree nodes explored. A
value of 0 or 1 means the problem was solved (or stopped) at the root node.

### CPU

Only solving time is counted, not reading the CSV files or building the data.

## 10. Scope and limitations

1. Debt records and probabilities are simulated data with documented sources
   (see the dataset README), not calibrated on real bank data.
2. Visits are assumed conditionally independent; collection is "all or
   nothing".
3. The heuristics build routes with nearest-neighbour and 2-opt and do not
   optimise the order within each route exactly.
4. Small instances easily let every method reach a gap of 0, so the experiments
   grow up to 80 customers and use 4 additional REP sets to check stability.
