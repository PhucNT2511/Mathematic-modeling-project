# Mathematical model of the debt collection routing problem

## 1. Problem

The bank needs a debt collection plan for several officers over a number of
working days. Each day, each officer leaves the bank branch, visits some
customers and returns to the branch before the end of the working time.

Because resources are limited, the bank does not have to visit every customer.
A customer can be visited several times on different days if an earlier visit
was unsuccessful. The problem must decide:

- which customers are selected;
- on which days each customer is visited;
- which officer is responsible for each visit;
- the order in which each officer visits customers on each day.

The main objective is to maximise the total expected amount of debt collected.
If several plans have the same expected value, the bank chooses the one with
the smallest total travel distance.

## 2. Notation

### 2.1. Index sets

- $V=\{0,1,\ldots,n\}$: set of locations, where $0$ is the bank branch.
- $N=V\setminus\{0\}$: set of customers.
- $K=\{1,\ldots,m\}$: set of debt collection officers.
- $T=\{1,\ldots,H\}$: set of days in the planning period.
- $A=\{(i,j):i,j\in V,\ i\ne j\}$: set of arcs that can be used.
- $\mathcal S_i$: set of feasible visit schedules of customer $i$.

Each $S\in\mathcal S_i$ is a set of days on which customer $i$ is planned to be
visited. If a customer can be visited at most $R_i$ times, then:

$$
\mathcal S_i=\{S\subseteq T:1\le |S|\le R_i\}.
$$

For example, with three working days and at most two visits:

$$
\mathcal S_i=
\big\{\{1\},\{2\},\{3\},\{1,2\},\{1,3\},\{2,3\}\big\}.
$$

### 2.2. Parameters

- $w_i$: amount of debt that can be collected from customer $i$.
- $p_{it}$: probability of a successful collection when customer $i$ is visited on day $t$, given that the debt has not been collected before.
- $d_{ij}$: distance from location $i$ to location $j$.
- $\tau_{ij}$: travel time from location $i$ to location $j$.
- $s_i$: service time at customer $i$.
- $B_{kt}$: maximum working time of officer $k$ on day $t$.
- $R_i$: maximum number of visits allowed to customer $i$.
- $a_{tS}$: equals 1 if $t\in S$, and 0 otherwise.
- $v_{iS}$: expected collected value when schedule $S$ is chosen for customer $i$.

Assume that visits are conditionally independent and that a customer pays the
debt only once. The probability of at least one successful collection under
schedule $S$ is:

$$
1-\prod_{t\in S}(1-p_{it}).
$$

Hence:

$$
v_{iS}
=
w_i\left[1-\prod_{t\in S}(1-p_{it})\right].
$$

The value $v_{iS}$ is computed before solving the model, so no products of
decision variables appear.

### 2.3. Decision variables

Arc selection:

$$
x_{ijkt}=
\begin{cases}
1, & \text{if officer }k\text{ travels directly from }i\text{ to }j\text{ on day }t,\\
0, & \text{otherwise.}
\end{cases}
$$

Customer assignment:

$$
y_{ikt}=
\begin{cases}
1, & \text{if officer }k\text{ visits customer }i\text{ on day }t,\\
0, & \text{otherwise.}
\end{cases}
$$

Schedule selection:

$$
\lambda_{iS}=
\begin{cases}
1, & \text{if schedule }S\text{ is chosen for customer }i,\\
0, & \text{otherwise.}
\end{cases}
$$

Officer use:

$$
z_{kt}=
\begin{cases}
1, & \text{if officer }k\text{ performs a route on day }t,\\
0, & \text{otherwise.}
\end{cases}
$$

The variable $u_{ikt}\ge 0$ is the position of customer $i$ in the route of
officer $k$ on day $t$. It is used to eliminate subtours.

## 3. Mathematical model

### 3.1. Objective function

$$
\max Z=
\sum_{i\in N}\sum_{S\in\mathcal S_i}
v_{iS}\lambda_{iS}.
\tag{1}
$$

Subject to:

$$
\sum_{S\in\mathcal S_i}\lambda_{iS}\le 1,
\qquad \forall i\in N.
\tag{2}
$$

$$
\sum_{k\in K}y_{ikt}
=
\sum_{S\in\mathcal S_i}a_{tS}\lambda_{iS},
\qquad \forall i\in N,\ t\in T.
\tag{3}
$$

$$
\sum_{j\in N}x_{0jkt}=z_{kt},
\qquad \forall k\in K,\ t\in T.
\tag{4}
$$

$$
\sum_{i\in N}x_{i0kt}=z_{kt},
\qquad \forall k\in K,\ t\in T.
\tag{5}
$$

$$
\sum_{\substack{j\in V\\j\ne i}}x_{ijkt}=y_{ikt},
\qquad \forall i\in N,\ k\in K,\ t\in T.
\tag{6}
$$

$$
\sum_{\substack{j\in V\\j\ne i}}x_{jikt}=y_{ikt},
\qquad \forall i\in N,\ k\in K,\ t\in T.
\tag{7}
$$

$$
\sum_{(i,j)\in A}\tau_{ij}x_{ijkt}
+
\sum_{i\in N}s_i y_{ikt}
\le B_{kt}z_{kt},
\qquad \forall k\in K,\ t\in T.
\tag{8}
$$

$$
u_{ikt}-u_{jkt}+n x_{ijkt}
\le n-1+n(1-y_{jkt}),
\qquad
\forall i,j\in N,\ i\ne j,\ k\in K,\ t\in T.
\tag{9}
$$

$$
y_{ikt}\le u_{ikt}\le n y_{ikt},
\qquad
\forall i\in N,\ k\in K,\ t\in T.
\tag{10}
$$

$$
x_{ijkt},y_{ikt},z_{kt},\lambda_{iS}\in\{0,1\}.
\tag{11}
$$

$$
u_{ikt}\ge 0.
\tag{12}
$$

## 4. Explanation of the model

### Objective (1)

The objective maximises the total expected collected value. If
$\lambda_{iS}=1$, customer $i$ is served according to schedule $S$ and
contributes $v_{iS}$ to the objective. A customer who is not selected has all
$\lambda_{iS}$ equal to 0 and contributes nothing.

### Constraint (2): schedule choice

Each customer gets at most one schedule. The inequality lets the bank skip
customer $i$ if visiting them is not worthwhile or cannot fit within the time
limits.

The number of repeat visits is already controlled when building
$\mathcal S_i$, since every $S\in\mathcal S_i$ satisfies $|S|\le R_i$.

### Constraint (3): linking schedules and officers

The right-hand side is 1 if the schedule chosen for customer $i$ contains day
$t$. The left-hand side then forces exactly one officer to make that visit.

If day $t$ is not in the chosen schedule, the right-hand side is 0 and no
officer may visit customer $i$ on that day. This constraint also ensures that a
customer is not visited by two officers on the same day.

### Constraint (4): leaving the branch

If $z_{kt}=1$, officer $k$ must leave the branch exactly once on day $t$. If
$z_{kt}=0$, no arc may leave the branch for this officer.

### Constraint (5): returning to the branch

If officer $k$ works in the field on day $t$, they must return to the branch
exactly once. Together, (4) and (5) make every route start and end at the
branch.

### Constraint (6): arcs leaving a customer

If $y_{ikt}=1$, exactly one arc must leave customer $i$ on the route of officer
$k$ on day $t$. If this officer does not visit the customer, no arc may leave
it.

### Constraint (7): arcs entering a customer

If $y_{ikt}=1$, exactly one arc must enter customer $i$. Together, (6) and (7)
give each visited customer one predecessor and one successor on the route.

### Constraint (8): working time limit

The first term is the total travel time of officer $k$ on day $t$. The second
term is the total time spent directly with customers.

Their sum must not exceed $B_{kt}$. When $z_{kt}=0$, the right-hand side is 0,
so the officer cannot travel or serve customers on that day.

### Constraint (9): subtour elimination

The previous constraints allow a cycle among some customers that is not
connected to the branch, for example $i\rightarrow j\rightarrow i$. The MTZ
constraint uses the positions $u_{ikt}$ to rule out such cycles. The term
$n(1-y_{jkt})$ deactivates the constraint when customer $j$ is not selected.

If arc $(i,j)$ is chosen, i.e. $x_{ijkt}=1$, constraint (9) implies:

$$
u_{jkt}\ge u_{ikt}+1.
$$

Since positions must increase along the chosen arcs, a cycle among customers
cannot exist.

### Constraint (10): domain of the position variable

If customer $i$ is not visited, $y_{ikt}=0$ and the constraint forces
$u_{ikt}=0$. If the customer is visited, their position lies between 1 and $n$.

### Constraint (11): binary variables

The variables $x$, $y$, $z$ and $\lambda$ take only the values 0 or 1, so the
solution represents real decisions rather than fractional ones.

### Constraint (12): non-negativity

The position variable $u_{ikt}$ cannot be negative. Together with (10), it is
positive only for customers who actually appear on the route.

### Constraint (15): symmetry breaking between officers

Officers with the same time budget are interchangeable: swapping the labels of
two officers gives a different solution with the same value, which makes the
Branch-and-Bound tree explore duplicates. For two consecutive officers with
$B_{kt}=B_{k+1,t}$, we add

$$
z_{kt}\ \ge\ z_{k+1,t},\qquad k=1,\ldots,K-1,\ t\in T.
\tag{15}
$$

The constraint only removes duplicate solutions and does not change the
optimal value (enabled with `symmetry_breaking = true` in the experiment
config).

## 5. Secondary objective: distance

After solving the model above and obtaining the optimal expected value
$Z^\star$, the collection level can be kept fixed with the constraint:

$$
\sum_{i\in N}\sum_{S\in\mathcal S_i}
v_{iS}\lambda_{iS}
\ge Z^\star-\varepsilon,
\tag{13}
$$

where $\varepsilon$ is a small numerical tolerance. The objective is then
replaced by:

$$
\min
\sum_{t\in T}\sum_{k\in K}\sum_{(i,j)\in A}
d_{ij}x_{ijkt}.
\tag{14}
$$

Constraint (13) ensures that the collection objective does not decrease.
Objective (14) picks the plan with the smallest total distance among the plans
with optimal expected value.

## 6. From data to solution and dynamic simulation

There are two levels: (1) solve the routing problem for *the remaining days*
using the **expected** collection; (2) drive only today's routes, observe which
customers actually pay, update the data and solve again the next morning. No
algorithm is told the payment outcomes of future days.

### 6.1. Data mapping

Pick an `instance`, for example `INS_S`.
[load_v3_data.jl](../data_processing/load_v3_data.jl) reads the tables under
`collection_routing_dataset_v3/csv/`:

| File | Used in the model as |
|---|---|
| `thuc_the.csv` | Number of days `H`, working minutes per day, visit limit `R_i`, customer set ID. |
| `thuc_the_khach_hang.csv` | List of the `n` customers in the instance. |
| `thuc_the_can_bo.csv` | List of officers, which gives the number of officers `K`. |
| `khach_hang.csv` | Target amount `w_i`, service time `s_i`. |
| `xac_suat_thu_hoi.csv` | Probability `p(i,t)` of the **CO_SO** (base) scenario for customer `i`, day `t`. |
| `ma_tran_di_chuyen.csv` | Distance `d(i,j)` and travel time `tau(i,j)` in the **direction** `i -> j`; point 0 is branch `CN01`. |
| `kich_ban_monte_carlo.csv` | Random numbers for simulating outcomes; **not** given to the solver when planning routes. |

Money is converted from VND to **million VND**; minutes are converted to
**hours**. The travel matrix is cut to exactly the customers of the instance,
keeping both directions. `lich_tiep_can.csv` contains precomputed schedule
values, but the current code **does not read it**; it enumerates schedules and
computes their values itself. `can_bo.csv` is source information only; the
daily budget currently comes from `thuc_the.csv` and is the same for every
officer.

### 6.2. Encoding a plan

Let `N = {1,...,n}` be the customers, `k = 1..K` the officers and `t = 1..H`
the days. Customer `i` has target amount `w_i`; `p(i,t)` is the probability of a
successful collection when visiting on day `t`, **given that the customer has
not paid before**. A plan must answer three questions: visit **on which day**,
**who** visits, and in **what order**.

Example with 2 customers, 1 officer, 2 days: on day 1 the route is
`0 -> 1 -> 2 -> 0`, on day 2 it is `0 -> 1 -> 0`. The visit sets are then
`S_1 = {1,2}`, `S_2 = {1}`. If `w_1=10`, `p(1,1)=0.5`, `p(1,2)=0.4`,
`w_2=8`, `p(2,1)=0.25`, then:

$$
v_1(S_1)=10[1-(1-0.5)(1-0.4)]=7,\quad
v_2(S_2)=8(0.25)=2,\quad Z=9\text{ million VND}.
$$

This is the **expectation before the trip**, not a guaranteed 9 million. If a
customer is not visited, `S_i` is empty and `v_i(S_i)=0`. The formula assumes
that visits are conditionally independent given `p(i,t)`.

The same plan as a heuristic matrix (rows = customers, columns = days):

```text
             day 1    day 2
customer 1      1        1
customer 2      1        0
```

The number `1` is officer 1; `0` means no visit. This is **not yet a route**:
cells `G[1,1]=1` and `G[2,1]=1` only say that both customers are assigned on
day 1. The vector `0 -> 1 -> 2 -> 0` gives the order. The day-1 route is
feasible if `tau(0,1)+tau(1,2)+tau(2,0)+s_1+s_2 <= B(1,1)`. The order
`0 -> 2 -> 1 -> 0` may take a different time because the matrix is directed.

In [model.jl](../core/model.jl), BnC uses binary variables:

| Variable | Meaning |
|---|---|
| `lambda(i,S)` | Choose visit set `S` for customer `i`. |
| `y(i,k,t)` | Officer `k` visits customer `i` on day `t`. |
| `x(i,j,k,t)` | Travel directly from `i` to `j` on route `k,t`. |
| `z(k,t)` | Officer `k` drives a route on day `t`. |
| `u(i,k,t)` | MTZ position on the route, used to eliminate subtours. |

In the example: `lambda(1,{1,2})=1`, `lambda(2,{1})=1`;
`y(1,1,1)=y(1,1,2)=y(2,1,1)=1`; the day-1 arcs have
`x(0,1,1,1)=x(1,2,1,1)=x(2,0,1,1)=1`, and `z(1,1)=1`. All unselected variables
are 0. MTZ only prevents a separate cycle such as `1 -> 2 -> 1` that is
detached from the branch.

The BnC objective maximises the sum of `v_i(S)` over the chosen schedules. The
core links are:

$$
\sum_S\lambda_{iS}\le1,\qquad
\sum_k y_{ikt}=\sum_{S:\,t\in S}\lambda_{iS}.
$$

Each customer chooses at most one schedule; if the schedule contains day `t`,
exactly one officer visits on that day. The remaining constraints force routes
to leave and return to the branch, give every customer on a route one incoming
and one outgoing arc, rule out subtours, keep the number of visits within
`R_i`, and:

$$
\sum_{i,j}\tau_{ij}x_{ijkt}+\sum_i s_i y_{ikt}\le B_{kt}z_{kt}.
$$

`B(k,t)` is the number of working hours of officer `k` on day `t`. BnC uses
JuMP and HiGHS to solve this MILP. When `minimize_distance` is enabled, BnC
runs the second solve of Section 5 to minimise distance among plans with the
same expected value; otherwise distance is only computed for reporting.

In the **rolling-horizon** runner, before each BnC call the code builds a
feasible ALNS solution as a MIP start. If BnC hits its time limit without
improving on that solution, the runner keeps the ALNS solution and reports
`TIME_LIMIT_HEURISTIC_FALLBACK`. This is a fallback mechanism and is **not**
called the best solution *found by BnC*. The time limit applies only to HiGHS;
the time for the initial ALNS run and model construction is included in the
total time.

GA, Tabu and ALNS in [genetic_algorithm.jl](../core/genetic_algorithm.jl) do
not work directly on `x`, `y`, `lambda`. They use a matrix `G` of size
`n x H`, with each cell in `{0,1,...,K}`: `G[i,t]=0` means no visit and
`G[i,t]=k` means officer `k` visits. For each day column, the code groups
customers by officer, builds a route vector `0 -> ... -> 0` with
nearest-neighbour and 2-opt, and then recomputes time, distance and
`v_i(S_i)`. `repair!` removes visits that exceed the limit or make a route run
over time. GA crosses over and mutates cells of `G`; Tabu changes one cell and
remembers forbidden moves; ALNS removes a group of visits and inserts them
again. `ga_decisions` converts a heuristic solution back to `x,y,z` so it can
be checked and printed in the same format as BnC. Being heuristics, they give
no certificate of optimality.

### 6.3. Observation and daily update

For Monte Carlo scenario `s`, the file stores a number `u(s,i,t)` in `[0,1]`
for **each customer-day** (the CSV column is named `u`). The outcome is only
drawn when the customer is actually visited: if `u(s,i,t) < p(i,t)`, `w_i` is
collected; otherwise 0. For example, with `p(1,1)=0.5` and `u=0.3`, customer 1
pays on day 1, and the planned repeat visit to customer 1 on day 2 is no
longer needed. This column `u` is **completely different** from the MTZ
variable `u(i,k,t)` of the MILP. Neither is a decision variable about whether a
customer pays.

In the **rolling horizon**, at the start of day `t` we keep `A_t`: customers
who have not paid and whose number of visits so far is `a_i < R_i`.
[remaining_v3_data](../data_processing/dynamic_v3_data.jl) cuts the remaining
data: only customers in `A_t`, days `t..H`, probabilities `p(i,t..H)`, budgets
`B(k,t..H)`, remaining limit `R_i - a_i`, and the travel sub-matrix of the
branch and the remaining customers. The probabilities themselves are not
re-estimated: since `p(i,t)` is already conditional on not having paid, it
stays valid for every customer still in `A_t`. The solver plans **the whole
remaining period**, but [run_v3_dynamic.jl](../core/run_v3_dynamic.jl) only
executes today's routes. At the end of the day it records who has paid and
updates `a_i`, then discards the future part of the plan and solves again. In
the example above, if customer 1 pays on day 1, customer 1 is removed on the
morning of day 2; the free capacity can go to customer 2 or another customer.

A Monte Carlo scenario is **one sample path used for scoring**, not input that
the algorithm can see in advance. The same scenario `u(s,i,t)` is used for
every method. `planned_expected` is the expectation at planning time;
`collected_million_vnd` is the simulated **actual** collection. The BnC bound
only certifies the *remaining* MILP at that solve, not an optimal dynamic
policy over all scenarios.

### 6.4. The three compared policies

GA, Tabu, ALNS and BnC **do not learn** from the Monte Carlo scenarios; they
only re-solve when the state changes. The three policies differ in *when* they
plan and *how many days ahead* they look:

| Policy | Planning | Look-ahead |
|---|---|---|
| Static | Once at the start for all H days, then only executed | H days |
| Rolling horizon | At the start of each day t, for days t..H; only the day-t routes are executed | H − t + 1 days |
| Myopic (greedy) | At the start of each day t, for day t only | 1 day |

Under the static policy, a customer who has already paid is skipped when their
turn comes (the officer goes straight to the next customer), but no new
customer is inserted. All three use the **same** random numbers `u(s,i,t)` of
scenario s (common random numbers), so the paired differences come only from
the policy. Runner: `core/run_v3_static_vs_rolling.jl`.

All three policies produce feasible routes. The static policy solves the full
model (1)–(12), (15) once; skipping a customer who has paid only shortens a
route, because the matrix is built from shortest paths. The rolling-horizon and
myopic policies solve the same model on the remaining problem (customers
$A_t$, limits $R_i-a_{it}$); the myopic policy uses $H=1$, so constraint (3)
does not link it to later days.

### 6.5. The dynamic problem and how quality is measured

Denote the state **known at the start of day** $t$ by $X_t=(P_t,a_t)$, where
$P_t$ is the set of customers who have paid and $a_{it}$ is the number of
visits to customer $i$ before day $t$. The set of eligible customers is

$$
A_t=\{i\in N:i\notin P_t,\ a_{it}<R_i\}.
$$

From $X_t$, the remaining problem keeps only $A_t$, the days $t,\ldots,H$ and
the new visit limit $R_i-a_{it}$. Let $Q_t$ be its solution for **the whole
remaining period**; the executed action is *only the day-$t$ routes* of
$Q_t$. The set of customers actually visited on that day is $E_t$.

In Monte Carlo scenario $s$, let $\xi^{(s)}_{it}$ be the CSV column `u`. For a
customer $i\in E_t$, the collection outcome is

$$
Y^{(s)}_{it}=\mathbf{1}\{\xi^{(s)}_{it}<p_{it}\},\qquad
C^{(s)}_t=\sum_{i\in E_t}w_iY^{(s)}_{it}.
$$

At the end of the day the state moves on: $a_{i,t+1}=a_{it}+1$ if
$i\in E_t$, otherwise unchanged; $P_{t+1}=P_t\cup\{i\in E_t:Y^{(s)}_{it}=1\}$.
The next day is solved again on $X_{t+1}$. A **policy** $\pi$ is therefore a
rule that maps the observed state to today's routes, not a fixed schedule that
knows all outcomes in advance.

The total collection over the period under scenario $s$ is
$C^{(s)}(\pi)=\sum_{t=1}^{H}C_t^{(s)}$. For a set of test IDs $S_{\rm test}$,
we evaluate with the sample mean

$$
\widehat{C}(\pi)=\frac{1}{|S_{\rm test}|}
\sum_{s\in S_{\rm test}} C^{(s)}(\pi).
$$

To compare two methods $\pi_A,\pi_B$, we use *the same scenario IDs* and take
the mean paired difference
$\frac{1}{|S_{\rm test}|}\sum_s[C^{(s)}(\pi_A)-C^{(s)}(\pi_B)]$.
Future values $\xi^{(s)}_{it}$ are never used to choose routes; they are used
only **after** the routes are chosen, to generate outcomes. The BnC upper bound
for one problem $Q_t$ is not an upper bound for $\widehat{C}(\pi)$ or for the
optimal dynamic policy.

## 7. Conclusion

The MILP encodes visit schedules with $\lambda$, assignment with $y$, routes
with $x$, and eliminates subtours with the MTZ position variables $u$. On each
day of the rolling-horizon procedure, the model maximises the **expected
collection over the remaining period**; actual collection only appears after
the visit outcomes are simulated. Section 5 shows how to minimise distance
lexicographically; BnC performs this second solve when `minimize_distance` is
enabled, while the heuristics use distance to break ties between solutions with
equal expected value.
