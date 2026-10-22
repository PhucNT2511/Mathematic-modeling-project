include(joinpath(@__DIR__, "branch_and_cut.jl"))
include(joinpath(@__DIR__, "genetic_algorithm.jl"))
include(joinpath(@__DIR__, "tabu_search.jl"))
include(joinpath(@__DIR__, "alns.jl"))
include(joinpath(@__DIR__, "..", "data_processing", "load_v3_data.jl"))
using JSON

# Convert solver decisions back to visit days to check every method against
# the same expected-value formula, independently of the reported objective.
function checked_plan(data, result)
    !isfinite(result.objective) && return nothing
    visits = zeros(Int, data.n, data.H)
    for i in 1:data.n, t in 1:data.H, k in 1:data.K
        get(result.decisions, (:y, i, k, t), 0) == 1 || continue
        visits[i, t] += 1
    end
    all(visits .<= 1) || error("$(result.method): duplicate customer-day assignment")
    all(sum(visits; dims=2)[:] .<= data.max_visits) ||
        error("$(result.method): visit limit exceeded")

    objective = sum(
        expected_value(data, i, findall(visits[i, :] .> 0))
        for i in 1:data.n
    )
    isapprox(objective, result.objective; atol=1.0e-4, rtol=1.0e-7) ||
        error("$(result.method): objective does not match assigned visits")

    routes = selected_routes(data, result)
    total_distance = 0.0
    for k in 1:data.K, t in 1:data.H
        assigned = findall(
            i -> get(result.decisions, (:y, i, k, t), 0) == 1,
            1:data.n,
        )
        route = get(routes, (k, t), Int[])
        if isempty(assigned)
            isempty(route) || error("$(result.method): route without assignments")
            continue
        end
        length(route) == length(assigned) + 2 &&
            first(route) == 0 && last(route) == 0 &&
            sort(route[2:end-1]) == assigned ||
            error("$(result.method): route does not match assigned customers")
        used = route_cost(route, data.travel_time) +
               sum(data.service_time[i] for i in assigned)
        used <= data.daily_budget[k, t] + 1.0e-5 ||
            error("$(result.method): daily time budget exceeded")
        total_distance += route_cost(route, data.distance)
    end
    return (visit_count=sum(visits), distance=total_distance, routes=routes)
end

function run_v3_comparison(config_path)
    config = JSON.parsefile(config_path)
    instance = String(config["instance"])
    seed = Int(config["seed"])
    root = normpath(joinpath(@__DIR__, "..", "collection_routing_dataset_v3"))
    data, customer_ids = load_v3_data(root, instance; scenario="CO_SO")
    println("Instance $instance: $(data.n) customers, $(data.K) officers, $(data.H) days; p = CO_SO")

    ga_config = config["ga"]
    tabu_config = config["tabu"]
    alns_config = config["alns"]
    exact_config = config["branch_and_cut"]
    records = NamedTuple[]

    methods = (
        ("GA", () -> solve_genetic_algorithm(
            data;
            population_size=Int(ga_config["population_size"]),
            generations=Int(ga_config["generations"]),
            stagnation_generations=Int(ga_config["stagnation_generations"]),
            seed=seed,
        )),
        ("Tabu", () -> solve_tabu_search(
            data;
            iterations=Int(tabu_config["iterations"]),
            neighborhood_size=Int(tabu_config["neighborhood_size"]),
            tabu_tenure=Int(tabu_config["tabu_tenure"]),
            seed=seed,
        )),
        ("ALNS", () -> solve_alns(
            data;
            iterations=Int(alns_config["iterations"]),
            seed=seed,
        )),
        ("Branch-and-Cut", () -> solve_branch_and_cut(
            data;
            time_limit=Float64(exact_config["time_limit_seconds"]),
            mip_gap=Float64(exact_config["mip_gap"]),
            minimize_distance=Bool(get(exact_config, "minimize_distance", false)),
            distance_time_limit=Float64(get(exact_config, "distance_time_limit_seconds",
                exact_config["time_limit_seconds"])),
        )),
    )

    for (label, solve) in methods
        println("Running $label...")
        started = time()
        result = solve()
        total_seconds = time() - started
        plan = checked_plan(data, result)
        println(
            "  status=$(result.status), objective=$(result.objective) million VND, " *
            "total=$(round(total_seconds; digits=2)) s",
        )
        push!(records, (result=result, plan=plan, total_seconds=total_seconds))
    end

    # Only a finite MILP bound can certify an optimality gap. The solver may
    # time out without an integer solution; that case remains visible in CSV.
    exact = records[end].result
    bound = isfinite(exact.bound) ? exact.bound : NaN
    outdir = normpath(joinpath(@__DIR__, "..", "results", "v3_$(instance)"))
    mkpath(outdir)
    summary_file = joinpath(outdir, "base_method_comparison.csv")
    open(summary_file, "w") do io
        println(io, "method,status,objective_million_vnd,upper_bound_million_vnd,gap_percent,solver_seconds,total_seconds,visits,distance_km")
        for record in records
            result, plan = record.result, record.plan
            objective = isfinite(result.objective) ? string(result.objective) : ""
            upper = isfinite(bound) ? string(bound) : ""
            gap = isfinite(bound) && isfinite(result.objective) && bound > 0 ?
                string(max(0.0, 100 * (bound - result.objective) / bound)) : ""
            visits = plan === nothing ? "" : string(plan.visit_count)
            distance = plan === nothing ? "" : string(plan.distance)
            println(
                io,
                "$(result.method),$(result.status),$objective,$upper,$gap," *
                "$(result.elapsed),$(record.total_seconds),$visits,$distance",
            )
        end
    end

    routes_file = joinpath(outdir, "base_routes.csv")
    open(routes_file, "w") do io
        println(io, "method,officer,day,stop_order,location_id")
        for record in records
            record.plan === nothing && continue
            for ((k, t), route) in sort(collect(record.plan.routes))
                for (order, node) in enumerate(route)
                    id = node == 0 ? "CN01" : customer_ids[node]
                    println(io, "$(record.result.method),$k,$t,$(order - 1),$id")
                end
            end
        end
    end
    println("Saved comparison: $summary_file")
    println("Saved routes: $routes_file")
end

if abspath(PROGRAM_FILE) == @__FILE__
    config_path = isempty(ARGS) ?
        normpath(joinpath(@__DIR__, "..", "v3_comparison.json")) : abspath(ARGS[1])
    run_v3_comparison(config_path)
end
