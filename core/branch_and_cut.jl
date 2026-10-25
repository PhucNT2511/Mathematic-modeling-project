if !isdefined(Main, :DebtRoutingData)
    include(joinpath(@__DIR__, "model.jl"))
end

# MIP start from a heuristic solution: x, y, z as given, the lambda of the matching
# day set, and MTZ positions in route order.
function set_routing_start!(vars, data::DebtRoutingData, initial_result::SolveResult)
    for (key, variable) in vars.logical
        if key[1] != :lambda
            set_start_value(variable, Float64(get(initial_result.decisions, key, 0)))
        end
    end
    for i in 1:data.n
        days = [t for t in 1:data.H if any(
            get(initial_result.decisions, (:y, i, k, t), 0) == 1 for k in 1:data.K
        )]
        chosen = findfirst(==(days), vars.schedules[i])
        isempty(days) || chosen !== nothing || error("Warm-start visit schedule is invalid")
        for s in eachindex(vars.schedules[i])
            set_start_value(vars.lambda[(i, s)], chosen == s ? 1.0 : 0.0)
        end
    end
    for variable in values(vars.u)
        set_start_value(variable, 0.0)
    end
    for ((k, t), route) in selected_routes(data, initial_result)
        for (order, i) in enumerate(route[2:end-1])
            set_start_value(vars.u[(i, k, t)], Float64(order))
        end
    end
end

"""
    solve_branch_and_cut(data; kwargs...)

Solve the MILP with the HiGHS branch-and-cut solver.

- `initial_result`: feasible heuristic solution used as MIP start. If HiGHS ends
  without anything at least as good, that solution is returned and the status
  gets the suffix `_HEURISTIC_FALLBACK`.
- `minimize_distance`: second, lexicographic solve that keeps
  Z >= Z* - value_tolerance * max(1, |Z*|) and minimises total distance, starting
  from the first solution, with its own `distance_time_limit`. With
  `distance_only_if_optimal` it runs only when the first solve is OPTIMAL.
- `symmetry_breaking`: add (15), z[k,t] >= z[k+1,t] for officers with equal budgets.

`elapsed` and `nodes` refer to the first solve; the second solve's time is in
`distance_seconds`.
"""
function solve_branch_and_cut(
    data::DebtRoutingData;
    time_limit::Float64=300.0,
    mip_gap::Float64=1.0e-4,
    initial_result::Union{Nothing,SolveResult}=nothing,
    minimize_distance::Bool=false,
    distance_time_limit::Float64=time_limit,
    value_tolerance::Float64=1.0e-6,
    symmetry_breaking::Bool=false,
    random_seed::Union{Nothing,Int}=nothing,
    distance_only_if_optimal::Bool=false,
)
    model, vars = build_model(
        data;
        integer_variables=true,
        time_limit=time_limit,
        mip_gap=mip_gap,
        symmetry_breaking=symmetry_breaking,
        random_seed=random_seed,
    )
    if initial_result !== nothing
        isfinite(initial_result.objective) || error("Warm start needs a feasible objective")
        set_routing_start!(vars, data, initial_result)
    end

    started = time()
    optimize!(model)
    elapsed = time() - started
    status = string(termination_status(model))
    nodes = try
        Int(MOI.get(model, MOI.NodeCount()))
    catch
        0
    end

    # HiGHS may stop on an incumbent worse than the start (often the empty plan);
    # return the start and say so in the status.
    if initial_result !== nothing &&
       (!has_values(model) || objective_value(model) + 1.0e-5 < initial_result.objective)
        return SolveResult(
            "HiGHS Branch-and-Cut (heuristic fallback)",
            status * "_HEURISTIC_FALLBACK",
            initial_result.objective,
            objective_bound(model),
            nodes,
            elapsed,
            initial_result.decisions,
        )
    end

    if !has_values(model)
        return SolveResult(
            "HiGHS Branch-and-Cut",
            status,
            -Inf,
            objective_bound(model),
            nodes,
            elapsed,
            Dict{Tuple,Int}(),
        )
    end

    stage1_objective = objective_value(model)
    stage1_bound = objective_bound(model)
    method = "HiGHS Branch-and-Cut"

    # Keeping Z >= Z* only makes the second solve lexicographic if Z* is optimal,
    # hence distance_only_if_optimal.
    if minimize_distance && (!distance_only_if_optimal || status == "OPTIMAL")
        expected_expr = objective_function(model)
        # JuMP drops the solution once the model is modified, so copy it first.
        stage1_values = Dict(variable => value(variable) for variable in all_variables(model))
        for (variable, v) in stage1_values
            set_start_value(variable, v)
        end
        @constraint(model, expected_expr >=
            stage1_objective - value_tolerance * max(1.0, abs(stage1_objective)))
        @objective(model, Min, sum(
            data.distance[i + 1, j + 1] * variable
            for ((i, j, k, t), variable) in vars.x
        ))
        set_attribute(model, "time_limit", distance_time_limit)
        started2 = time()
        optimize!(model)
        distance_seconds = time() - started2
        status2 = string(termination_status(model))
        if has_values(model)
            decisions = Dict(
                key => round(Int, value(variable))
                for (key, variable) in vars.logical
            )
            return SolveResult(
                method * " + min distance",
                status * "+DIST_" * status2,
                value(expected_expr),
                stage1_bound,
                nodes,
                elapsed,
                decisions,
                distance_seconds,
            )
        end
        # No solution from the second solve: keep the first (stored as start values).
        decisions = Dict(
            key => round(Int, start_value(variable))
            for (key, variable) in vars.logical
        )
        return SolveResult(method, status * "+DIST_" * status2 * "_KEEP_STAGE1",
            stage1_objective, stage1_bound, nodes, elapsed, decisions, distance_seconds)
    end

    decisions = Dict(
        key => round(Int, value(variable))
        for (key, variable) in vars.logical
    )

    return SolveResult(
        method,
        status,
        stage1_objective,
        stage1_bound,
        nodes,
        elapsed,
        decisions,
    )
end
