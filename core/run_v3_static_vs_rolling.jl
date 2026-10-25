include(joinpath(@__DIR__, "run_v3_dynamic.jl"))
using JSON
using Printf

# Static, rolling-horizon and myopic policies on common random numbers.
#
# static : one plan for the whole horizon. During execution a customer who has
#          paid is skipped (the officer drives on to the next unpaid customer);
#          the freed time is not used.
# rolling: every morning, re-solve days t..H for unpaid customers and the visits
#          left, and execute only day t (run_dynamic_method).
# myopic : as rolling, but each morning optimises day t only (lookahead = 1).
# A visit to customer i on day t in scenario s pays w_i if u(s,i,t) < p(i,t).

function solve_v3_method(label, data, config, seed)
    if label == "GA"
        c = config["ga"]
        return solve_genetic_algorithm(data; population_size=Int(c["population_size"]),
            generations=Int(c["generations"]),
            stagnation_generations=Int(c["stagnation_generations"]), seed=seed)
    elseif label == "Tabu"
        c = config["tabu"]
        return solve_tabu_search(data; iterations=Int(c["iterations"]),
            neighborhood_size=Int(c["neighborhood_size"]),
            tabu_tenure=Int(c["tabu_tenure"]),
            stagnation_iterations=Int(get(c, "stagnation_iterations", 0)), seed=seed)
    elseif label == "ALNS"
        # Same stopping rule as the daily re-solves in run_dynamic_method.
        c = config["alns"]
        return solve_alns(data; iterations=Int(c["iterations"]),
            stagnation_iterations=Int(get(c, "stagnation_iterations", 0)), seed=seed)
    elseif label == "Branch-and-Cut"
        c = config["branch_and_cut"]
        warm_start = solve_alns(data; iterations=Int(config["alns"]["iterations"]),
            stagnation_iterations=Int(get(config["alns"], "stagnation_iterations", 0)), seed=seed)
        return solve_branch_and_cut(data; time_limit=Float64(c["time_limit_seconds"]),
            mip_gap=Float64(c["mip_gap"]), initial_result=warm_start,
            minimize_distance=Bool(get(c, "minimize_distance", false)),
            distance_time_limit=Float64(get(c, "distance_time_limit_seconds", c["time_limit_seconds"])))
    end
    error("Unknown method: $label")
end

function execute_static_plan(data, plan, draws)
    paid = falses(data.n)
    attempts = zeros(Int, data.n)
    collected = 0.0
    distance = 0.0
    for day in 1:data.H, k in 1:data.K
        route = get(plan.routes, (k, day), Int[])
        isempty(route) && continue
        current = 0
        for i in route[2:end-1]
            paid[i] && continue
            distance += data.distance[current + 1, i + 1]
            current = i
            attempts[i] += 1
            if draws[i, day] < data.probability[i, day]
                paid[i] = true
                collected += data.debt[i]
            end
        end
        current == 0 || (distance += data.distance[current + 1, 1])
    end
    all(attempts .<= data.max_visits) || error("Static plan exceeds visit limit")
    return (collected=collected, distance=distance, visits=sum(attempts), paid=count(paid))
end

# Cornish-Fisher approximation of the 0.975 t quantile (error < 1e-3 for df >= 5).
function t975(df)
    z = 1.959963984540054
    return z + (z^3 + z) / (4df) + (5z^5 + 16z^3 + 3z) / (96df^2) +
           (3z^7 + 19z^5 + 17z^3 - 15z) / (384df^3)
end

function paired_stats(d)
    n = length(d)
    m = sum(d) / n
    sd = n > 1 ? sqrt(sum((x - m)^2 for x in d) / (n - 1)) : NaN
    se = sd / sqrt(n)
    half = n > 1 ? t975(n - 1) * se : NaN
    return (mean=m, sd=sd, se=se, lo=m - half, hi=m + half)
end

# Linear interpolation, as numpy's default quantile.
function quantile_linear(x, q)
    s = sort(x)
    h = (length(s) - 1) * q + 1
    lo = floor(Int, h)
    return lo >= length(s) ? s[end] : s[lo] + (h - lo) * (s[lo + 1] - s[lo])
end

fmt(x::Integer) = string(x)
fmt(x::Real) = isnan(x) ? "" : @sprintf("%.4f", x)
fmt(x) = string(x)

const POLICIES = ("static", "rolling", "myopic")
# (metric, field in runs, direction: +1 higher is better, -1 lower is better, 0 neither)
const METRICS = (("collected_million_vnd", "collected", 1), ("distance_km", "distance", -1),
                 ("visits", "visits", 0), ("seconds", "seconds", -1))

const RUN_COLUMNS = (:instance, :p_scenario, :method, :mc,
    :static_collected, :rolling_collected, :myopic_collected,
    :static_distance, :rolling_distance, :myopic_distance,
    :static_visits, :rolling_visits, :myopic_visits,
    :static_seconds, :rolling_seconds, :myopic_seconds, :static_expected)

function read_runs(path)
    lines = filter(!isempty, strip.(readlines(path)))
    header = Symbol.(split(lines[1], ','))
    header == collect(RUN_COLUMNS) || error("Unexpected columns in $path")
    return [begin
        f = split(l, ',')
        NamedTuple{RUN_COLUMNS}((String(f[1]), String(f[2]), String(f[3]), parse(Int, f[4]),
            (parse(Float64, v) for v in f[5:end])...))
    end for l in lines[2:end]]
end

value(r, policy, field) = Float64(getproperty(r, Symbol(policy, "_", field)))

#   policy_summary.csv      descriptive statistics per policy
#   paired_summary.csv      each policy against static
#   pairwise_comparison.csv every pair of policies
function write_summaries(outdir, runs)
    groups = unique((r.instance, r.p_scenario, r.method) for r in runs)
    policies = [p for p in POLICIES if !all(r -> isnan(value(r, p, "collected")), runs)]

    open(joinpath(outdir, "policy_summary.csv"), "w") do io
        println(io, "instance,p_scenario,method,policy,metric,n_mc,mean,sd,se,ci95_low,ci95_high,min,q25,median,q75,max,mean_planned_expected")
        for (inst, scen, meth) in groups, policy in policies, (metric, field, _) in METRICS
            sub = [r for r in runs if (r.instance, r.p_scenario, r.method) == (inst, scen, meth)]
            x = [value(r, policy, field) for r in sub]
            st = paired_stats(x)
            planned = policy == "static" && field == "collected" ?
                sum(r.static_expected for r in sub) / length(sub) : NaN
            println(io, join(fmt.((inst, scen, meth, policy, metric, length(x), st.mean, st.sd,
                st.se, st.lo, st.hi, minimum(x), quantile_linear(x, 0.25),
                quantile_linear(x, 0.5), quantile_linear(x, 0.75), maximum(x), planned)), ','))
        end
    end

    header = "n_mc,mean_a,mean_b,mean_diff,rel_diff_pct,sd_diff,se_diff,t_stat,ci95_low,ci95_high,n_better,n_tie,n_worse,share_better"
    function pair_row(sub, a, b, field, dir)
        xa = [value(r, a, field) for r in sub]
        xb = [value(r, b, field) for r in sub]
        d = xb .- xa
        st = paired_stats(d)
        ma, mb = sum(xa) / length(xa), sum(xb) / length(xb)
        sgn = dir == 0 ? 1 : dir
        better = count(>(1.0e-9), sgn .* d)
        worse = count(<(-1.0e-9), sgn .* d)
        tie = length(d) - better - worse
        return (length(d), ma, mb, st.mean, 100 * st.mean / ma, st.sd, st.se, st.mean / st.se,
                st.lo, st.hi, better, tie, worse, better / length(d))
    end

    # plot_results.py reads the first columns by name; keep them first.
    open(joinpath(outdir, "paired_summary.csv"), "w") do io
        println(io, "instance,p_scenario,method,n_mc,policy,metric,mean_static,mean_policy,mean_diff_policy_minus_static,sd_diff,ci95_low,ci95_high,share_policy_better,mean_static_solve_seconds,mean_policy_seconds_per_mc,rel_diff_pct,se_diff,t_stat,n_better,n_tie,n_worse")
        for (inst, scen, meth) in groups, policy in policies[2:end], (metric, field, dir) in METRICS
            field == "seconds" && continue
            sub = [r for r in runs if (r.instance, r.p_scenario, r.method) == (inst, scen, meth)]
            p = pair_row(sub, "static", policy, field, dir)
            seconds = sum(value(r, policy, "seconds") for r in sub) / length(sub)
            println(io, join(fmt.((inst, scen, meth, p[1], policy, metric, p[2], p[3], p[4],
                p[6], p[9], p[10], p[14], sub[1].static_seconds, seconds,
                p[5], p[7], p[8], p[11], p[12], p[13])), ','))
        end
    end

    open(joinpath(outdir, "pairwise_comparison.csv"), "w") do io
        println(io, "instance,p_scenario,method,policy_a,policy_b,metric,", header)
        pairs = [(a, b) for (i, a) in enumerate(policies) for b in policies[i+1:end]]
        for (inst, scen, meth) in groups, (a, b) in pairs, (metric, field, dir) in METRICS
            sub = [r for r in runs if (r.instance, r.p_scenario, r.method) == (inst, scen, meth)]
            println(io, join(fmt.((inst, scen, meth, a, b, metric,
                pair_row(sub, a, b, field, dir)...)), ','))
        end
    end
    for f in ("policy_summary.csv", "paired_summary.csv", "pairwise_comparison.csv")
        println("Saved: $(joinpath(outdir, f))")
    end
end

function write_runs(path, runs)
    open(path, "w") do io
        println(io, join(RUN_COLUMNS, ','))
        for row in runs
            println(io, join((fmt(getproperty(row, c)) for c in RUN_COLUMNS), ','))
        end
    end
end

# "best" / "fastest" in the config's methods: the heuristic with the smallest mean gap
# (ties: lower CPU) / smallest mean CPU on this instance in the five-day experiment.
function best_heuristic(instance, n; by=:gap, summary=normpath(joinpath(@__DIR__, "..",
                        "outputs", "experiments", "v3_experiments_gd2", "summary.csv")))
    lines = readlines(summary)
    col = Dict(name => i for (i, name) in enumerate(split(lines[1], ',')))
    rows = [split(l, ',') for l in lines[2:end] if !isempty(strip(l))]
    candidates = [(parse(Float64, r[col["mean_gap_percent"]]),
                   parse(Float64, r[col["mean_cpu_seconds"]]), String(r[col["method"]]))
                  for r in rows if r[col["instance"]] == instance &&
                      parse(Int, r[col["n"]]) == n && r[col["method"]] in ("Tabu", "ALNS", "GA")]
    isempty(candidates) && error("No heuristic results for $instance n=$n in $summary")
    gap, cpu, method = by == :gap ? minimum(candidates) :
        minimum(c -> (c[2], c[1], c[3]), candidates)[[2, 1, 3]]
    @printf("%s heuristic on %s n=%d (five days): %s, gap %.3f%%, CPU %.1f s\n",
        by == :gap ? "Best" : "Fastest", instance, n, method, gap, cpu)
    return method
end

function run_v3_static_vs_rolling(config_path)
    config = JSON.parsefile(config_path)
    instance = String(config["instance"])
    seed = Int(config["seed"])
    ids = haskey(config, "monte_carlo_range") ?
        collect(Int(config["monte_carlo_range"][1]):Int(config["monte_carlo_range"][2])) :
        Int.(config["monte_carlo_ids"])
    length(unique(ids)) == length(ids) || error("Duplicate Monte Carlo IDs")
    scenarios = String.(get(config, "p_scenarios", ["CO_SO"]))
    methods = String.(get(config, "methods", ["ALNS"]))
    include_myopic = Bool(get(config, "include_myopic", true))
    root = normpath(joinpath(@__DIR__, "..", "collection_routing_dataset_v3"))
    outdir = normpath(joinpath(@__DIR__, "..", "outputs", "v3_$(instance)", "static_vs_rolling"))
    mkpath(outdir)

    runs = NamedTuple[]
    if any(in(("best", "fastest")), methods)
        full, _ = load_v3_data(root, instance; scenario="CO_SO")
        methods = unique([m == "best" ? best_heuristic(instance, full.n) :
                          m == "fastest" ? best_heuristic(instance, full.n; by=:cpu) : m
                          for m in methods])
    end
    for scenario in scenarios
        data, customer_ids = load_v3_data(root, instance; scenario=scenario)
        draws = load_v3_draws(root, customer_ids, data.H, ids)
        for method in methods
            # A few iterations first, so that JIT compilation is not timed.
            small = deepcopy(config)
            for key in ("alns", "tabu")
                small[key]["iterations"] = 2
            end
            small["ga"]["generations"] = 2
            solve_v3_method(method, data, small, seed)
            run_dynamic_method(method, data, customer_ids, draws[ids[1]], ids[1],
                               small, seed; verbose=false)
            started = time()
            result = solve_v3_method(method, data, config, seed)
            static_seconds = time() - started
            plan = checked_plan(data, result)
            plan === nothing && error("$method: no feasible static plan")
            @printf("[%s | %s | %s] static plan: E = %.3f million VND, %.2f s\n",
                instance, scenario, method, result.objective, static_seconds)
            flush(stdout)
            for id in ids
                s = execute_static_plan(data, plan, draws[id])
                r, _, _ = run_dynamic_method(method, data, customer_ids, draws[id], id,
                                             config, seed; verbose=false)
                g = include_myopic ? first(run_dynamic_method(method, data, customer_ids,
                    draws[id], id, config, seed; verbose=false, lookahead=1)) :
                    (collected=NaN, distance=NaN, visits=0, seconds=NaN)
                push!(runs, (instance=instance, p_scenario=scenario, method=method, mc=id,
                    static_collected=s.collected, rolling_collected=r.collected,
                    myopic_collected=g.collected,
                    static_distance=s.distance, rolling_distance=r.distance,
                    myopic_distance=g.distance,
                    static_visits=s.visits, rolling_visits=r.visits, myopic_visits=g.visits,
                    static_seconds=static_seconds, rolling_seconds=r.seconds,
                    myopic_seconds=g.seconds, static_expected=result.objective))
                @printf("   MC %3d: static %.2f | rolling %.2f | myopic %.2f\n",
                    id, s.collected, r.collected, g.collected)
                flush(stdout)
                write_runs(joinpath(outdir, "runs.csv"), runs)
            end
            println("   done: $(length(ids)) Monte Carlo scenarios")
        end
    end
    write_summaries(outdir, runs)
end

# julia core/run_v3_static_vs_rolling.jl [config.json]
# julia core/run_v3_static_vs_rolling.jl --summarize <folder with runs.csv>
if abspath(PROGRAM_FILE) == @__FILE__
    if !isempty(ARGS) && ARGS[1] == "--summarize"
        outdir = abspath(ARGS[2])
        write_summaries(outdir, read_runs(joinpath(outdir, "runs.csv")))
    else
        config_path = isempty(ARGS) ?
            normpath(joinpath(@__DIR__, "..", "configs", "v3_static_vs_rolling.json")) : abspath(ARGS[1])
        run_v3_static_vs_rolling(config_path)
    end
end
