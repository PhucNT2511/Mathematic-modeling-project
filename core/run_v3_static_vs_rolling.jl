include(joinpath(@__DIR__, "run_v3_dynamic.jl"))   # run_dynamic_method, checked_plan, các solver
using JSON
using Printf

# So sánh chính sách TĨNH và CUỐN CHIẾU trên cùng số ngẫu nhiên Monte Carlo
# (common random numbers), đúng quy trình trong đề xuất và README của bộ v3.
#
# TĨNH      : giải một lần cho cả kỳ trước khi biết kết quả. Khi thực hiện, khách
#             đã trả được bỏ qua: cán bộ đi thẳng tới khách kế tiếp chưa trả
#             trong tuyến; thời gian rảnh không dùng để thăm thêm khách.
# CUỐN CHIẾU: đầu mỗi ngày giải lại cho ngày t..H với khách chưa trả và số lượt
#             còn lại; chỉ thực hiện tuyến ngày t (dùng run_dynamic_method).
# Chung     : lần thăm (i,t) thành công nếu u(s,i,t) < p(i,t); thành công thu đủ
#             số tiền mục tiêu, thất bại thu 0; không thu trùng một khoản nợ.

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
            tabu_tenure=Int(c["tabu_tenure"]), seed=seed)
    elseif label == "ALNS"
        return solve_alns(data; iterations=Int(config["alns"]["iterations"]), seed=seed)
    elseif label == "Branch-and-Cut"
        c = config["branch_and_cut"]
        warm_start = solve_alns(data; iterations=Int(config["alns"]["iterations"]), seed=seed)
        return solve_branch_and_cut(data; time_limit=Float64(c["time_limit_seconds"]),
            mip_gap=Float64(c["mip_gap"]), initial_result=warm_start,
            minimize_distance=Bool(get(c, "minimize_distance", false)),
            distance_time_limit=Float64(get(c, "distance_time_limit_seconds", c["time_limit_seconds"])))
    end
    error("Unknown method: $label")
end

"""Thực hiện một kế hoạch tĩnh trên một kịch bản số ngẫu nhiên."""
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
            paid[i] && continue                      # khách đã trả: bỏ qua
            distance += data.distance[current + 1, i + 1]
            current = i
            attempts[i] += 1
            if draws[i, day] < data.probability[i, day]
                paid[i] = true
                collected += data.debt[i]
            end
        end
        current == 0 || (distance += data.distance[current + 1, 1])   # về chi nhánh
    end
    all(attempts .<= data.max_visits) || error("Static plan exceeds visit limit")
    return (collected=collected, distance=distance, visits=sum(attempts), paid=count(paid))
end

# Phân vị t(0,975; df) xấp xỉ (sai số < 1e-3 với df ≥ 5), tránh thêm package.
function t975(df)
    z = 1.959963984540054
    return z + (z^3 + z) / (4df) + (5z^5 + 16z^3 + 3z) / (96df^2) +
           (3z^7 + 19z^5 + 17z^3 - 15z) / (384df^3)
end

function paired_stats(d)
    n = length(d)
    m = sum(d) / n
    sd = n > 1 ? sqrt(sum((x - m)^2 for x in d) / (n - 1)) : NaN
    half = n > 1 ? t975(n - 1) * sd / sqrt(n) : NaN
    return (mean=m, sd=sd, lo=m - half, hi=m + half)
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
    root = normpath(joinpath(@__DIR__, "..", "collection_routing_dataset_v3"))
    outdir = normpath(joinpath(@__DIR__, "..", "results", "v3_$(instance)", "static_vs_rolling"))
    mkpath(outdir)

    runs = NamedTuple[]
    for scenario in scenarios
        data, customer_ids = load_v3_data(root, instance; scenario=scenario)
        draws = load_v3_draws(root, customer_ids, data.H, ids)   # cùng u cho mọi chính sách và kịch bản p
        for method in methods
            started = time()
            result = solve_v3_method(method, data, config, seed)
            static_seconds = time() - started
            plan = checked_plan(data, result)
            plan === nothing && error("$method: no feasible static plan")
            @printf("[%s | %s | %s] kế hoạch tĩnh: E = %.3f tr, %.2f s\n",
                instance, scenario, method, result.objective, static_seconds)
            for id in ids
                s = execute_static_plan(data, plan, draws[id])
                r, _, _ = run_dynamic_method(method, data, customer_ids, draws[id], id,
                                             config, seed; verbose=false)
                push!(runs, (instance=instance, p_scenario=scenario, method=method, mc=id,
                    static_collected=s.collected, rolling_collected=r.collected,
                    static_distance=s.distance, rolling_distance=r.distance,
                    static_visits=s.visits, rolling_visits=r.visits,
                    static_seconds=static_seconds, rolling_seconds=r.seconds,
                    static_expected=result.objective))
            end
            println("   xong $(length(ids)) kịch bản Monte Carlo")
        end
    end

    open(joinpath(outdir, "runs.csv"), "w") do io
        cols = collect(keys(first(runs)))
        println(io, join(cols, ','))
        for row in runs
            println(io, join((getproperty(row, c) for c in cols), ','))
        end
    end
    open(joinpath(outdir, "paired_summary.csv"), "w") do io
        println(io, "instance,p_scenario,method,n_mc,metric,mean_static,mean_rolling,mean_diff_rolling_minus_static,sd_diff,ci95_low,ci95_high,share_rolling_better,mean_static_solve_seconds,mean_rolling_seconds_per_mc")
        for scenario in scenarios, method in methods
            sub = [r for r in runs if r.p_scenario == scenario && r.method == method]
            n = length(sub)
            for (metric, a, b, better) in (
                    ("collected_million_vnd", :static_collected, :rolling_collected, (y, x) -> y > x + 1.0e-9),
                    ("distance_km", :static_distance, :rolling_distance, (y, x) -> y < x - 1.0e-9))
                sa = [getproperty(r, a) for r in sub]; sb = [getproperty(r, b) for r in sub]
                st = paired_stats(sb .- sa)
                share = count(better(y, x) for (x, y) in zip(sa, sb)) / n
                println(io, join((instance, scenario, method, n, metric,
                    sum(sa) / n, sum(sb) / n, st.mean, st.sd, st.lo, st.hi, share,
                    sub[1].static_seconds, sum(r.rolling_seconds for r in sub) / n), ','))
            end
        end
    end
    println("Saved: $(joinpath(outdir, "paired_summary.csv"))")
end

if abspath(PROGRAM_FILE) == @__FILE__
    config_path = isempty(ARGS) ?
        normpath(joinpath(@__DIR__, "..", "v3_static_vs_rolling.json")) : abspath(ARGS[1])
    run_v3_static_vs_rolling(config_path)
end
