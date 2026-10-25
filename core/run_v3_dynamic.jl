include(joinpath(@__DIR__, "run_v3_comparison.jl"))
include(joinpath(@__DIR__, "..", "data_processing", "dynamic_v3_data.jl"))

# Re-solve every morning from the observed state (who paid, visits made) and
# execute only that day. `draws` are the scenario's common random numbers.
function run_dynamic_method(label, data, customer_ids, draws, scenario_id, config, seed;
                            policy=nothing, on_transition=nothing, verbose=true,
                            lookahead::Union{Nothing,Int}=nothing)
    paid = falses(data.n)
    attempts = zeros(Int, data.n)
    daily = NamedTuple[]
    visits = NamedTuple[]
    collected = 0.0
    distance = 0.0
    runtime = 0.0

    for day in 1:data.H
        residual, active = remaining_v3_data(data, paid, attempts, day; lookahead=lookahead)
        if isempty(active)
            push!(daily, (scenario=scenario_id, method=label, day=day,
                solver="", status="NO_ELIGIBLE_CUSTOMERS", planned_expected=0.0,
                collected=0.0, distance=0.0, visits=0, seconds=0.0))
            continue
        end
        started = time()
        before_paid = copy(paid)
        before_attempts = copy(attempts)
        solver_label = policy === nothing ? label : policy(day, paid, attempts)
        result = if solver_label == "GA"
            c = config["ga"]
            solve_genetic_algorithm(residual; population_size=Int(c["population_size"]),
                generations=Int(c["generations"]),
                stagnation_generations=Int(c["stagnation_generations"]),
                seed=seed + day - 1)
        elseif solver_label == "Tabu"
            c = config["tabu"]
            solve_tabu_search(residual; iterations=Int(c["iterations"]),
                neighborhood_size=Int(c["neighborhood_size"]),
                tabu_tenure=Int(c["tabu_tenure"]),
                stagnation_iterations=Int(get(c, "stagnation_iterations", 0)),
                seed=seed + day - 1)
        elseif solver_label == "ALNS"
            c = config["alns"]
            solve_alns(residual; iterations=Int(c["iterations"]),
                stagnation_iterations=Int(get(c, "stagnation_iterations", 0)), seed=seed + day - 1)
        elseif solver_label == "Branch-and-Cut"
            c = config["branch_and_cut"]
            warm_start = solve_alns(residual; iterations=Int(config["alns"]["iterations"]),
                stagnation_iterations=Int(get(config["alns"], "stagnation_iterations", 0)),
                seed=seed + day - 1)
            solve_branch_and_cut(residual; time_limit=Float64(c["time_limit_seconds"]),
                mip_gap=Float64(c["mip_gap"]), initial_result=warm_start,
                minimize_distance=Bool(get(c, "minimize_distance", false)),
                distance_time_limit=Float64(get(c, "distance_time_limit_seconds",
                    c["time_limit_seconds"])))
        else
            error("Unknown method: $solver_label")
        end
        plan = checked_plan(residual, result)
        plan === nothing && error("$label has no feasible solution on day $day, scenario $scenario_id; increase the Branch-and-Cut time limit")
        seconds = time() - started
        runtime += seconds

        # Execute day 1 of the residual plan; later days are re-planned tomorrow.
        day_collected = 0.0
        day_distance = 0.0
        day_visits = 0
        for k in 1:residual.K
            route = get(plan.routes, (k, 1), Int[])
            isempty(route) && continue
            day_distance += route_cost(route, residual.distance)
            for local_i in route[2:end-1]
                global_i = active[local_i]
                paid[global_i] && error("A paid customer was routed")
                attempts[global_i] += 1
                day_visits += 1
                success = draws[global_i, day] < data.probability[global_i, day]
                amount = success ? data.debt[global_i] : 0.0
                if success
                    paid[global_i] = true
                    day_collected += amount
                end
                push!(visits, (scenario=scenario_id, method=label, day=day,
                    officer=k, stop=global_i, customer=customer_ids[global_i],
                    probability=data.probability[global_i, day],
                    draw=draws[global_i, day], success=success,
                    collected=amount, attempts=attempts[global_i]))
            end
        end
        collected += day_collected
        distance += day_distance
        if on_transition !== nothing
            on_transition(day, before_paid, before_attempts, solver_label,
                          day_collected, paid, attempts)
        end
        push!(daily, (scenario=scenario_id, method=label, day=day,
            solver=solver_label, status=result.status,
            planned_expected=result.objective,
            collected=day_collected, distance=day_distance,
            visits=day_visits, seconds=seconds))
        verbose && println("  $label day $day: solver=$solver_label, visits=$day_visits, collected=$day_collected, status=$(result.status)")
    end
    summary = (scenario=scenario_id, method=label, collected=collected,
        distance=distance, visits=sum(attempts), paid=count(paid), seconds=runtime)
    return summary, daily, visits
end

function write_dynamic_csv(path, header, rows, fields)
    open(path, "w") do io
        println(io, join(header, ','))
        for row in rows
            println(io, join((getproperty(row, field) for field in fields), ','))
        end
    end
end

function dynamic_aggregate(summaries, ids)
    baseline = Dict(row.scenario => row.collected for row in summaries
                    if row.method == "Branch-and-Cut")
    rows = NamedTuple[]
    for label in ("GA", "Tabu", "ALNS", "Branch-and-Cut")
        subset = [row for row in summaries if row.method == label]
        length(subset) == length(ids) || error("Missing run for $label")
        values = [row.collected for row in subset]
        mean_value = sum(values) / length(values)
        stdev = length(values) > 1 ?
            sqrt(sum((value - mean_value)^2 for value in values) / (length(values) - 1)) : NaN
        paired = [row.collected - baseline[row.scenario] for row in subset]
        push!(rows, (method=label, scenarios=length(values),
            mean_collected=mean_value, stdev_collected=stdev,
            mean_paired_vs_bnc=sum(paired) / length(paired),
            mean_distance=sum(row.distance for row in subset) / length(subset),
            mean_seconds=sum(row.seconds for row in subset) / length(subset)))
    end
    return rows
end

function run_v3_dynamic(config_path)
    config = JSON.parsefile(config_path)
    instance = String(config["instance"])
    ids = Int.(config["monte_carlo_ids"])
    isempty(ids) && error("monte_carlo_ids cannot be empty")
    length(unique(ids)) == length(ids) || error("Duplicate Monte Carlo scenario IDs")
    root = normpath(joinpath(@__DIR__, "..", "collection_routing_dataset_v3"))
    data, customer_ids = load_v3_data(root, instance; scenario="CO_SO")
    draws = load_v3_draws(root, customer_ids, data.H, ids)
    summaries, days, visits = NamedTuple[], NamedTuple[], NamedTuple[]
    for id in ids
        println("Scenario $id, instance $instance, p=CO_SO")
        for label in ("GA", "Tabu", "ALNS", "Branch-and-Cut")
            summary, daily, trace = run_dynamic_method(label, data, customer_ids,
                draws[id], id, config, Int(config["seed"]))
            push!(summaries, summary)
            append!(days, daily)
            append!(visits, trace)
        end
    end
    outdir = normpath(joinpath(@__DIR__, "..", "outputs", "v3_$(instance)"))
    mkpath(outdir)
    write_dynamic_csv(joinpath(outdir, "dynamic_summary.csv"),
        ["scenario", "method", "collected_million_vnd", "distance_km", "visits", "paid_customers", "total_seconds"],
        summaries, (:scenario, :method, :collected, :distance, :visits, :paid, :seconds))
    write_dynamic_csv(joinpath(outdir, "dynamic_daily.csv"),
        ["scenario", "method", "day", "selected_solver", "status", "planned_expected_million_vnd", "collected_million_vnd", "distance_km", "visits", "seconds"],
        days, (:scenario, :method, :day, :solver, :status, :planned_expected, :collected, :distance, :visits, :seconds))
    write_dynamic_csv(joinpath(outdir, "dynamic_visits.csv"),
        ["scenario", "method", "day", "officer", "customer_index", "customer_id", "probability", "u", "success", "collected_million_vnd", "attempt_number"],
        visits, (:scenario, :method, :day, :officer, :stop, :customer, :probability, :draw, :success, :collected, :attempts))
    write_dynamic_csv(joinpath(outdir, "dynamic_aggregate.csv"),
        ["method", "scenarios", "mean_collected_million_vnd", "stdev_collected_million_vnd", "mean_paired_difference_vs_bnc_million_vnd", "mean_distance_km", "mean_seconds"],
        dynamic_aggregate(summaries, ids),
        (:method, :scenarios, :mean_collected, :stdev_collected,
         :mean_paired_vs_bnc, :mean_distance, :mean_seconds))
    println("Saved dynamic results: $outdir")
end

if abspath(PROGRAM_FILE) == @__FILE__
    config_path = isempty(ARGS) ?
        normpath(joinpath(@__DIR__, "..", "configs", "v3_comparison.json")) : abspath(ARGS[1])
    run_v3_dynamic(config_path)
end
