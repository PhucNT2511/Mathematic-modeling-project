# Solution representation and transformations

This document connects the problem description with the algorithms. We
consider the **static plan**: choose the schedule for the whole period before
any collection outcome is known.

## 1. Data and indices

- \(N=\{1,\ldots,n\}\): customers; \(0\): branch.
- \(\mathcal K=\{1,\ldots,K\}\): officers; \(T=\{1,\ldots,H\}\): days.
- \(w_i\): target amount; \(p_{it}\): probability of collection if customer
  \(i\) is visited on day \(t\), given nothing has been collected before.
- \(d_{ij}\), \(\tau_{ij}\): distance and travel time from \(i\) to \(j\).
  Possibly \(d_{ij}\ne d_{ji}\) and \(\tau_{ij}\ne\tau_{ji}\).
- \(s_i\): service time; \(B_{kt}\): maximum working time of officer \(k\) on
  day \(t\); \(R_i\): maximum number of visits.

An instance of the dataset defines the customers, officers, days, \(B_{kt}\)
and \(R_i\). We take \(w_i,s_i,p_{it}\) for exactly those customers, then cut
the travel matrix to the points of the instance. Money and time must be in
consistent units before computing.

## 2. A solution is a matrix plus route vectors

### Assignment matrix

Let \(G=(g_{it})\in\{0,1,\ldots,K\}^{n\times H}\):

\[
g_{it}=\begin{cases}
0,&\text{customer }i\text{ is not visited on day }t,\\
k,&\text{officer }k\text{ visits customer }i\text{ on day }t.
\end{cases}
\]

A cell holds exactly one value, so the same customer cannot be assigned to two
officers on the same day. From \(G\) we get

\[
S_i(G)=\{t:g_{it}>0\},\qquad C_{kt}(G)=\{i:g_{it}=k\}.
\]

\(S_i\) is the **set of days** of customer \(i\); \(C_{kt}\) is the **set of
customers** assigned to officer \(k\) on day \(t\). Neither contains the
visiting order yet.

### Ordered route vectors

For **each officer-day pair** \((k,t)\), let

\[
r_{kt}=(0,i_1,i_2,\ldots,i_q,0),\qquad
\{i_1,\ldots,i_q\}=C_{kt}(G).
\]

An empty route is written \(r_{kt}=(0,0)\): the officer does not go out that
day. An officer has **one vector per day**; the whole plan has at most \(KH\)
vectors. Many different route orders can correspond to the same matrix \(G\).

## 3. Example: from matrix to vectors

Suppose \(n=4,K=2,H=2\):

| Customer | \(g_{i1}\) | \(g_{i2}\) | \(S_i\) |
|---|---:|---:|---|
| 1 | 1 | 0 | \(\{1\}\) |
| 2 | 1 | 2 | \(\{1,2\}\) |
| 3 | 0 | 2 | \(\{2\}\) |
| 4 | 2 | 0 | \(\{1\}\) |

Hence \(C_{1,1}=\{1,2\}\), \(C_{2,1}=\{4\}\),
\(C_{1,2}=\varnothing\), \(C_{2,2}=\{2,3\}\). One **possible** family of
routes is

\[
r_{1,1}=(0,1,2,0),\quad r_{2,1}=(0,4,0),\quad
r_{1,2}=(0,0),\quad r_{2,2}=(0,3,2,0).
\]

The order \(3\to2\) in the last route is only one choice; its cost must be
compared with \(2\to3\). Customer 2 is visited on two days by two different
officers, which the current model allows.

## 4. Value and constraints

The expected collection when customer \(i\) is visited on the set of days
\(S_i\) is

\[
v_i(S_i)=w_i\left[1-\prod_{t\in S_i}(1-p_{it})\right],
\qquad v_i(\varnothing)=0.
\]

The main objective is \(\max F(G)=\sum_i v_i(S_i(G))\). For
\(r_{kt}=(r_0,\ldots,r_{q+1})\), \(r_0=r_{q+1}=0\), let

\[
D(r_{kt})=\sum_{a=0}^{q}d_{r_a,r_{a+1}},\qquad
L(r_{kt})=\sum_{a=0}^{q}\tau_{r_a,r_{a+1}}+
\sum_{i\in C_{kt}(G)}s_i.
\]

A feasible solution must satisfy

\[
|S_i(G)|\le R_i\quad(\forall i),\qquad
L(r_{kt})\le B_{kt}\quad(\forall k,t),
\]

and each route vector goes from 0 back to 0 and contains every customer of
\(C_{kt}\) exactly once. When two solutions have the same expected value within
the comparison tolerance, the one with the smaller total distance
\(\sum_{k,t}D(r_{kt})\) is preferred.

**Key point:** \(F\) depends directly on the *visit days* \(S_i\), while the
officer assignment and the visiting order decide time feasibility. A good route
can free up time to add valuable customers.

## 5. Building the route order from a set of customers

Given \(G\), the algorithm must turn each set \(C_{kt}\) into a vector
\(r_{kt}\). The current heuristic goes from 0 to the nearest unvisited customer
by \(d_{ij}\), returns to 0, then tries reversing segments with 2-opt. Every
reversal is scored on the **full** distance because the matrix may be
asymmetric. Then \(L(r_{kt})\) is computed with the **time** matrix on the
chosen order.

This is a rule for building routes from \(G\); it does not guarantee the
shortest possible order. Whenever \(C_{kt}\) changes, the affected route vector
must be rebuilt.

## 6. Transformations between solutions

### Changing one cell: add, remove, reassign

Pick \((i,t)\) and replace \(g_{it}=a\) with \(b\ne a\):

| Change | Which sets change? |
|---|---|
| \(0\to k\) | Add \(t\) to \(S_i\), add \(i\) to \(C_{kt}\). |
| \(k\to0\) | Remove \(t\) from \(S_i\), remove \(i\) from \(C_{kt}\). |
| \(k\to k'\) | Move \(i\) from \(C_{kt}\) to \(C_{k't}\); \(S_i\) is unchanged. |

In the example of Section 3, changing \(g_{3,1}:0\to1\) gives

\[
S_3:\{2\}\to\{1,2\},\qquad
C_{1,1}:\{1,2\}\to\{1,2,3\}.
\]

We must rebuild \(r_{1,1}\), check \(|S_3|\le R_3\) and
\(L(r_{1,1})\le B_{1,1}\), and recompute \(v_3(S_3)\). Customer 3 cannot simply
be placed at the end of the route by default. Tabu uses this one-cell move.

### GA crossover and mutation

Given two matrices \(G^A,G^B\), the child \(G^C\) takes each cell from one of
the two parents: \(g^C_{it}\in\{g^A_{it},g^B_{it}\}\). Mutation replaces some
cells with a value in \(\{0,1,\ldots,K\}\). The child may exceed the visit
limit or run over time, so it must be repaired and its route vectors rebuilt.
The current GA crosses over the **assignment matrix**, not the route vectors
directly.

### ALNS destroy and repair

Choose a set of current visits

\[
Q\subseteq\{(i,t):g_{it}>0\},
\]

and set \(g_{it}=0\) for \((i,t)\in Q\). Destruction can be random, remove
low-value visits, remove a cluster of nearby customers, or remove some visits of
one route. The current route-removal operator deletes at most \(q\) visits from
the chosen route and **does not have to delete all of them**.

From the destroyed matrix \(G^-\), the repair operator inserts feasible triples
\((i,t,k)\) one by one. Greedy prefers the largest gain in \(v_i(S_i)\);
regret-2 prefers customers who would lose the most if they missed their best
insertion. Customers not previously in the plan can also be inserted. Each
insertion requires rebuilding the route and checking time.

## 7. Repairing infeasible solutions

Denote the greedy repair by \(\mathcal R(G)=\widehat G\):

1. If \(|S_i|>R_i\), keep only the \(R_i\) days with the largest \(p_{it}\).
2. If route \((k,t)\) runs over time, compute the marginal loss of removing one
   visit:

   \[
   \Delta_{it}=v_i(S_i)-v_i(S_i\setminus\{t\}).
   \]

   Remove the visit with the smallest \(\Delta_{it}\), rebuild the route and
   check time; repeat until \(L(r_{kt})\le B_{kt}\).

Repair does not guarantee that the kept set of visits has optimal value. If it
undoes exactly the change just proposed, Tabu skips the proposal. ALNS checks
feasibility before each insertion.

## 8. How does Branch-and-Cut express the same plan?

The MILP decides simultaneously:

- \(y_{ikt}=1\): officer \(k\) visits customer \(i\) on day \(t\); hence
  \(g_{it}=k\).
- \(x_{ijkt}=1\): officer \(k\) travels directly \(i\to j\) on day \(t\);
  following the arcs from 0 gives the vector \(r_{kt}\).
- \(\lambda_{iS}=1\): the set of days \(S\) is chosen for customer \(i\).
- \(z_{kt}=1\): the officer-day route is used; \(u_{ikt}\) is the position
  variable that eliminates subtours.

The constraints link \(x,y,\lambda\) so that the day schedule, the assignment
and the routes agree. Branch-and-Cut **optimises the route order as a
decision**. The current heuristics choose \(G\) and then build the order with
the rule of Section 5, so they may miss a feasible or better route that the
MILP could find.

## 9. Size of the solution space

One customer has

\[
1+\sum_{r=1}^{R_i}\binom{H}{r}K^r
\]

choices of days and officers, including no visit, **not counting the visiting
order**. With \(H=5,R_i=2,K=2\), this is
\(1+\binom51 2+\binom52 2^2=51\) choices per customer. With \(n\) customers,
a crude upper bound is \(51^n\) assignments, and the route orders still have to
be chosen. Time constraints eliminate many options, but not enough to make full
enumeration practical at large scale.

## 10. "Dynamic" during search and during execution

During **search**, \(G\) and \(r_{kt}\) change over the GA/Tabu/ALNS
iterations; the final output is still a static plan. During **rolling-horizon
execution**, after day \(t\) we remove customers who have paid, subtract the
visits already made from the limit \(R_i\), keep only days \(t+1,\ldots,H\),
and solve again to create the future routes. Routes already executed are not
changed. This is implemented in
[run_v3_dynamic.jl](../core/run_v3_dynamic.jl) and
[run_v3_static_vs_rolling.jl](../core/run_v3_static_vs_rolling.jl).

## 11. Notation and code

| Symbol | In the code |
|---|---|
| \(G=(g_{it})\) | `genes::Matrix{Int}` |
| \(S_i\) | `findall(genes[i, :] .> 0)` |
| \(C_{kt}\) | `findall(genes[:, t] .== k)` |
| \(r_{kt}\) | `routes[(k,t)]` from `build_route` |
| \(v_i(S_i)\) | `expected_value` / `customer_value` |
| \(\mathcal R(G)\) | `repair!` |
| \(F(G)\), \(\sum D\) | `evaluate_ga`, `is_better` |
| \(x,y,\lambda,z,u\) | `build_model` in `core/model.jl` |
