include(joinpath(@__DIR__, "rl_dynamic_policy.jl"))

function scenario_split(config)
    split = config["split"]
    ids = Dict(name => collect(Int(bounds[1]):Int(bounds[2])) for (name, bounds) in split)
    all(haskey(ids, name) && !isempty(ids[name]) for name in ("train", "validation", "test")) ||
        error("train/validation/test ranges must be nonempty")
    combined = vcat(ids["train"], ids["validation"], ids["test"])
    all(1 <= id <= 100 for id in combined) || error("Monte Carlo IDs must be in 1:100")
    length(unique(combined)) == length(combined) || error("Train/validation/test overlap")
    return ids
end

function rl_evaluation_rows(data, customer_ids, draws, ids, config, qtable; baselines)
    summaries, days, visits = NamedTuple[], NamedTuple[], NamedTuple[]
    for id in ids
        println("Evaluating held-out scenario $id")
        for label in (baselines ? ("GA", "Tabu", "ALNS", "Branch-and-Cut", "RL") : ("RL",))
            summary, daily, trace = if label == "RL"
                evaluate_dynamic_rl(data, customer_ids, draws, id, config, qtable)
            else
                run_dynamic_method(label, data, customer_ids, draws[id], id,
                                   config, Int(config["seed"]))
            end
            push!(summaries, summary)
            append!(days, daily)
            append!(visits, trace)
        end
    end
    return summaries, days, visits
end

function run_v3_rl_experiment(config_path)
    config = JSON.parsefile(config_path)
    split = scenario_split(config)
    root = normpath(joinpath(@__DIR__, "..", "collection_routing_dataset_v3"))
    instance = String(config["instance"])
    data, customer_ids = load_v3_data(root, instance; scenario="CO_SO")
    train_draws = load_v3_draws(root, customer_ids, data.H, split["train"])
    println("Training RL on $(length(split["train"])) scenarios")
    train_started = time()
    qtable = train_dynamic_rl(data, customer_ids, train_draws, split["train"], config)
    train_seconds = time() - train_started

    outdir = normpath(joinpath(@__DIR__, "..", "results", "v3_$(instance)", "rl_split"))
    mkpath(outdir)
    open(joinpath(outdir, "q_table.json"), "w") do io
        JSON.print(io, Dict("actions" => collect(RL_ACTIONS),
                            "split" => split,
                            "train_seconds" => train_seconds,
                            "q_values" => Dict(join(key, "_") => value
                                               for (key, value) in qtable)), 2)
    end

    for phase in ("validation", "test")
        ids = split[phase]
        # Held-out draws are loaded only after training has finished.
        phase_draws = load_v3_draws(root, customer_ids, data.H, ids)
        summaries, days, visits = rl_evaluation_rows(
            data, customer_ids, phase_draws, ids, config, qtable;
            baselines=phase == "test")
        write_dynamic_csv(joinpath(outdir, "$(phase)_summary.csv"),
            ["scenario", "method", "collected_million_vnd", "distance_km", "visits", "paid_customers", "total_seconds"],
            summaries, (:scenario, :method, :collected, :distance, :visits, :paid, :seconds))
        if phase == "test"
            write_dynamic_csv(joinpath(outdir, "test_daily.csv"),
                ["scenario", "method", "day", "selected_solver", "status", "planned_expected_million_vnd", "collected_million_vnd", "distance_km", "visits", "seconds"],
                days, (:scenario, :method, :day, :solver, :status, :planned_expected, :collected, :distance, :visits, :seconds))
            write_dynamic_csv(joinpath(outdir, "test_visits.csv"),
                ["scenario", "method", "day", "officer", "customer_index", "customer_id", "probability", "u", "success", "collected_million_vnd", "attempt_number"],
                visits, (:scenario, :method, :day, :officer, :stop, :customer, :probability, :draw, :success, :collected, :attempts))
            aggregate = NamedTuple[]
            bnc = Dict(row.scenario => row.collected for row in summaries
                       if row.method == "Branch-and-Cut")
            for label in ("GA", "Tabu", "ALNS", "Branch-and-Cut", "RL")
                rows = [row for row in summaries if row.method == label]
                values = [row.collected for row in rows]
                avg = sum(values) / length(values)
                sd = length(values) > 1 ?
                    sqrt(sum((value - avg)^2 for value in values) / (length(values) - 1)) : NaN
                push!(aggregate, (method=label, n=length(rows), mean=avg, sd=sd,
                    paired=sum(row.collected - bnc[row.scenario] for row in rows) / length(rows),
                    seconds=sum(row.seconds for row in rows) / length(rows)))
            end
            write_dynamic_csv(joinpath(outdir, "test_aggregate.csv"),
                ["method", "scenarios", "mean_collected_million_vnd", "stdev_collected_million_vnd", "mean_paired_difference_vs_bnc_million_vnd", "mean_seconds"],
                aggregate, (:method, :n, :mean, :sd, :paired, :seconds))
        end
    end
    println("Saved RL experiment: $outdir")
end

if abspath(PROGRAM_FILE) == @__FILE__
    config_path = isempty(ARGS) ?
        normpath(joinpath(@__DIR__, "..", "rl_experiment.json")) : abspath(ARGS[1])
    run_v3_rl_experiment(config_path)
end
