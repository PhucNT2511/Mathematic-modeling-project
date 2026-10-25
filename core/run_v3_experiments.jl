# Repeated runs for the report: every method on every instance, `runs` times with
# seeds base_seed + r, recording value, bound, gap, times, nodes and distance.
#
# Phase 1 (days = 1) has no link between days, like Steps 5-6 of the reference
# problem; phase 2 (days = 5) links the days through constraint (3), like Steps 7-9.
include(joinpath(@__DIR__, "run_v3_comparison.jl"))
using Statistics

# First n customers and first H days of an instance. `max_visits` fixes m for all
# instances so that sizes differ only in n; m is capped at H.
function sub_instance(data::DebtRoutingData, n::Int, H::Int;
                      max_visits::Union{Nothing,Int}=nothing)
    1 <= n <= data.n || error("customers must be in 1..$(data.n)")
    1 <= H <= data.H || error("days must be in 1..$(data.H)")
    idx = collect(1:n)
    points = [1; idx .+ 1]
    return DebtRoutingData(
        n, data.K, H,
        data.debt[idx],
        data.probability[idx, 1:H],
        data.distance[points, points],
        data.travel_time[points, points],
        data.service_time[idx],
        data.daily_budget[:, 1:H],
        min.(max_visits === nothing ? data.max_visits[idx] : fill(max_visits, n), H),
    )
end

# Course formula for a maximisation problem: (bound - value) / value.
report_gap(objective, bound) =
    isfinite(objective) && isfinite(bound) && objective > 0 ?
        (g = (bound - objective) / objective; g < 1.0e-9 ? 0.0 : g) : NaN

fmt(x) = x isa AbstractFloat ? (isfinite(x) ? @sprintf("%.6g", x) : "") : string(x)
nanmean(v) = (w = filter(isfinite, v); isempty(w) ? NaN : mean(w))
nanstd(v) = (w = filter(isfinite, v); length(w) < 2 ? NaN : std(w))

function run_heuristic(label, data, config, seed)
    if label == "Tabu"
        return solve_tabu_search(data;
            iterations=Int(config["iterations"]),
            neighborhood_size=Int(config["neighborhood_size"]),
            tabu_tenure=Int(config["tabu_tenure"]),
            stagnation_iterations=Int(get(config, "stagnation_iterations", 0)),
            seed=seed)
    elseif label == "ALNS"
        return solve_alns(data; iterations=Int(config["iterations"]),
            stagnation_iterations=Int(get(config, "stagnation_iterations", 0)), seed=seed)
    elseif label == "GA"
        return solve_genetic_algorithm(data;
            population_size=Int(config["population_size"]),
            generations=Int(config["generations"]),
            stagnation_generations=Int(config["stagnation_generations"]),
            seed=seed)
    end
    error("Unknown heuristic $label")
end

# cpu_seconds: solver only (optimize! for Branch-and-Cut, the call for a heuristic).
# total_seconds: everything for that method in the run, including JuMP model building,
# the ALNS warm start and the plan check. distance_solve_seconds: the second
# Branch-and-Cut solve on distance.
const RUNS_HEADER = "phase,instance,n,K,H,vertices,arcs,num_vars,num_constraints,run,seed," *
                    "method,status,objective_million_vnd,upper_bound_million_vnd," *
                    "gap_percent,cpu_seconds,bb_nodes,total_seconds,distance_km,visits,distance_solve_seconds"

runs_line(x) = join([x.phase, x.instance, x.n, x.K, x.H, x.vertices, x.arcs,
    x.num_vars, x.num_cons, x.run, x.seed, x.method, x.status,
    fmt(x.objective), fmt(x.bound), fmt(100 * x.gap), fmt(x.cpu),
    x.nodes < 0 ? "" : x.nodes, fmt(x.total), fmt(x.distance),
    x.visits < 0 ? "" : x.visits, fmt(x.dist_cpu)], ",")

# Previous runs.csv, for resuming; empty cells become NaN (-1 for counts). A file with
# other columns is moved to runs_old_format.csv and the experiment starts over.
function read_runs(file)
    rows = NamedTuple[]
    isfile(file) || return rows
    lines = readlines(file)
    if isempty(lines) || lines[1] != RUNS_HEADER
        backup = joinpath(dirname(file), "runs_old_format.csv")
        mv(file, backup; force=true)
        println("runs.csv has an older format; moved to $backup, starting over")
        return rows
    end
    num(x) = isempty(x) ? NaN : parse(Float64, x)
    for line in lines[2:end]
        isempty(strip(line)) && continue
        f = split(line, ",")
        length(f) == 22 || error("Malformed line in $file: $line")
        push!(rows, (phase=String(f[1]), instance=String(f[2]), n=parse(Int, f[3]),
            K=parse(Int, f[4]), H=parse(Int, f[5]), vertices=parse(Int, f[6]),
            arcs=parse(Int, f[7]), num_vars=parse(Int, f[8]), num_cons=parse(Int, f[9]),
            run=parse(Int, f[10]), seed=parse(Int, f[11]), method=String(f[12]),
            status=String(f[13]), objective=num(f[14]), bound=num(f[15]),
            gap=num(f[16]) / 100, cpu=num(f[17]),
            nodes=isempty(f[18]) ? -1 : parse(Int, f[18]),
            total=num(f[19]), distance=num(f[20]),
            visits=isempty(f[21]) ? -1 : parse(Int, f[21]), dist_cpu=num(f[22])))
    end
    return rows
end

# Run every method once on a tiny instance so that JIT compilation is not timed.
function warm_up(data, heuristics, exact_config)
    small = sub_instance(data, min(5, data.n), min(2, data.H))
    for (label, hconfig) in heuristics
        checked_plan(small, run_heuristic(label, small, hconfig, 1))
    end
    initial = run_heuristic("ALNS", small, Dict("iterations" => 5), 1)
    for start in (nothing, initial)
        solve_branch_and_cut(small; time_limit=5.0,
            mip_gap=Float64(exact_config["mip_gap"]),
            symmetry_breaking=Bool(exact_config["symmetry_breaking"]),
            random_seed=1, initial_result=start, minimize_distance=true,
            distance_time_limit=5.0)
    end
    println("Warm-up done")
end

function run_v3_experiments(config_path)
    config = JSON.parsefile(config_path)
    runs = Int(config["runs"])
    base_seed = Int(config["seed"])
    root = normpath(joinpath(@__DIR__, "..", "collection_routing_dataset_v3"))
    # One output folder per config, so configs can run in parallel.
    outdir = normpath(joinpath(@__DIR__, "..", "outputs", "experiments",
        splitext(basename(config_path))[1]))
    mkpath(outdir)
    exact_config = config["branch_and_cut"]
    fixed_m = haskey(config, "max_visits") ? Int(config["max_visits"]) : nothing
    exact_modes = String.(exact_config["modes"])
    all(in(("cold", "warm")), exact_modes) || error("modes must be \"cold\" and/or \"warm\"")
    heuristics = [
        (label, config[lowercase(label)]) for label in ("Tabu", "ALNS", "GA")
        if Bool(get(config[lowercase(label)], "enabled", true))
    ]

    # Resume: keep runs with every method done, drop partial ones.
    runs_file = joinpath(outdir, "runs.csv")
    methods_per_run = length(heuristics) + length(exact_modes)
    previous = Bool(get(config, "resume", true)) ? read_runs(runs_file) : NamedTuple[]
    run_key(x) = (x.phase, x.instance, x.n, x.H, x.run)
    counts = Dict{Any,Int}()
    for x in previous
        counts[run_key(x)] = get(counts, run_key(x), 0) + 1
    end
    rows = NamedTuple[x for x in previous if counts[run_key(x)] == methods_per_run]
    done = Set(run_key(x) for x in rows)
    isempty(done) || println("Resume: $(length(done)) runs already in $runs_file")
    open(runs_file, "w") do io
        println(io, RUNS_HEADER)
        foreach(x -> println(io, runs_line(x)), rows)
    end
    instance_rows = NamedTuple[]
    loaded = Dict{String,Any}()
    warmed = false
    for phase in config["phases"]
        phase_name = String(phase["name"])
        H = Int(phase["days"])
        for item in phase["instances"]
            instance = String(item["instance"])
            full, _ = get!(() -> load_v3_data(root, instance; scenario="CO_SO"),
                loaded, instance)
            n = Int(get(item, "customers", full.n))
            time_limit = Float64(get(item, "time_limit_seconds", phase["time_limit_seconds"]))
            data = sub_instance(full, n, H; max_visits=fixed_m)
            if !warmed
                warm_up(data, heuristics, exact_config)
                warmed = true
            end
            # Built only to count variables and constraints.
            counter, _ = build_model(data; integer_variables=true,
                symmetry_breaking=Bool(exact_config["symmetry_breaking"]))
            num_vars = num_variables(counter)
            num_cons = num_constraints(counter; count_variable_in_set_constraints=false)
            println("\n[$phase_name] $instance n=$n K=$(data.K) H=$H m=$(maximum(data.max_visits)): " *
                    "$num_vars variables, $num_cons constraints, time limit $(time_limit) s")
            flush(stdout)
            push!(instance_rows, (phase=phase_name, name="$(instance)_n$(n)_H$(H)",
                source=instance, n=n, K=data.K, H=H, m=maximum(data.max_visits),
                minutes=round(Int, 60 * data.daily_budget[1, 1]),
                total_debt=sum(data.debt), num_vars=num_vars, num_cons=num_cons))

            for r in 1:runs
                if (phase_name, instance, n, H, r) in done
                    println("  run $(lpad(r, 2)) already done")
                    continue
                end
                seed = base_seed + r
                run_rows = NamedTuple[]
                for (label, hconfig) in heuristics
                    started = time()
                    result = run_heuristic(label, data, hconfig, seed)
                    cpu = time() - started
                    plan = checked_plan(data, result)
                    push!(run_rows, (method=label, status=result.status,
                        objective=result.objective, bound=NaN, nodes=-1, cpu=cpu,
                        total=time() - started, distance=plan.distance,
                        visits=plan.visit_count, dist_cpu=NaN))
                end

                # "warm" starts HiGHS from the ALNS solution of the same seed.
                exact_bounds = Float64[]
                for mode in exact_modes
                    started = time()
                    initial = mode == "warm" ?
                        run_heuristic("ALNS", data, config["alns"], seed) : nothing
                    exact = solve_branch_and_cut(data;
                        time_limit=time_limit,
                        mip_gap=Float64(exact_config["mip_gap"]),
                        symmetry_breaking=Bool(exact_config["symmetry_breaking"]),
                        random_seed=seed,
                        initial_result=initial,
                        minimize_distance=Bool(get(exact_config, "minimize_distance", false)),
                        distance_time_limit=time_limit,
                        distance_only_if_optimal=true)
                    plan = isfinite(exact.objective) ? checked_plan(data, exact) : nothing
                    push!(run_rows, (method=mode == "warm" ? "BnC + ALNS start" : "Branch-and-Cut",
                        status=exact.status, objective=exact.objective, bound=exact.bound,
                        nodes=exact.nodes, cpu=exact.elapsed, total=time() - started,
                        distance=plan === nothing ? NaN : plan.distance,
                        visits=plan === nothing ? -1 : plan.visit_count,
                        dist_cpu=exact.distance_seconds))
                    isfinite(exact.bound) && push!(exact_bounds, exact.bound)
                end
                # Every method in the run is measured against the tightest bound of the
                # run. Rows are appended at once so an interrupted experiment can resume.
                best_bound = isempty(exact_bounds) ? NaN : minimum(exact_bounds)
                new_rows = [(phase=phase_name, instance=instance, n=n, K=data.K, H=H,
                        vertices=n + 1, arcs=(n + 1) * n, num_vars=num_vars,
                        num_cons=num_cons, run=r, seed=seed, method=row.method,
                        status=row.status, objective=row.objective, bound=best_bound,
                        gap=report_gap(row.objective, best_bound),
                        cpu=row.cpu, nodes=row.nodes, total=row.total,
                        distance=row.distance, visits=row.visits,
                        dist_cpu=row.dist_cpu) for row in run_rows]
                append!(rows, new_rows)
                open(runs_file, "a") do io
                    foreach(x -> println(io, runs_line(x)), new_rows)
                end
                for row in run_rows
                    @printf("  run %2d %-15s obj=%10.3f gap=%7.3f%% cpu=%8.2fs %s\n",
                        r, row.method, row.objective,
                        100 * report_gap(row.objective, best_bound), row.cpu, row.status)
                    flush(stdout)
                end
            end
        end
    end

    open(joinpath(outdir, "instances.csv"), "w") do io
        println(io, "phase,name,source_instance,customers,officers,days,max_visits," *
                    "minutes_per_day,total_debt_million_vnd,num_vars,num_constraints")
        for x in instance_rows
            println(io, join([x.phase, x.name, x.source, x.n, x.K, x.H, x.m, x.minutes,
                fmt(x.total_debt), x.num_vars, x.num_cons], ","))
        end
    end

    # Means over the runs of each (phase, instance, method).
    summary_file = joinpath(outdir, "summary.csv")
    open(summary_file, "w") do io
        println(io, "phase,instance,n,K,H,vertices,arcs,num_vars,num_constraints,method," *
                    "runs,optimal_runs,best_objective,mean_objective,mean_upper_bound," *
                    "mean_gap_percent,mean_cpu_seconds,std_cpu_seconds,mean_bb_nodes,statuses," *
                    "std_objective,mean_total_seconds,mean_distance_km,std_distance_km,mean_visits," *
                    "mean_distance_solve_seconds")
        keys = unique([(x.phase, x.instance, x.n, x.H, x.method) for x in rows])
        for key in keys
            group = [x for x in rows if (x.phase, x.instance, x.n, x.H, x.method) == key]
            g = first(group)
            objectives = [x.objective for x in group]
            statuses = join(sort(unique([x.status for x in group])), "|")
            optimal = count(x -> startswith(x.status, "OPTIMAL"), group)
            nodes = g.nodes < 0 ? "" : fmt(mean(Float64[x.nodes for x in group]))
            println(io, join([g.phase, g.instance, g.n, g.K, g.H, g.vertices, g.arcs,
                g.num_vars, g.num_cons, g.method, length(group),
                g.nodes >= 0 ? optimal : "",
                fmt(maximum(objectives)), fmt(nanmean(objectives)),
                fmt(nanmean([x.bound for x in group])),
                fmt(100 * nanmean([x.gap for x in group])),
                fmt(mean([x.cpu for x in group])), fmt(nanstd([x.cpu for x in group])),
                nodes, statuses, fmt(nanstd(objectives)),
                fmt(mean([x.total for x in group])),
                fmt(nanmean([x.distance for x in group])),
                fmt(nanstd([x.distance for x in group])),
                fmt(nanmean(Float64[x.visits for x in group if x.visits >= 0])),
                fmt(nanmean([x.dist_cpu for x in group]))], ","))
        end
    end
    println("\nSaved: $runs_file")
    println("Saved: $summary_file")
end

if abspath(PROGRAM_FILE) == @__FILE__
    config_path = isempty(ARGS) ?
        normpath(joinpath(@__DIR__, "..", "configs", "v3_experiments_gd1.json")) : abspath(ARGS[1])
    run_v3_experiments(config_path)
end
