# Giải một instance và xuất kế hoạch nhiều ngày để vẽ hình (core/plot_v3_plan.py).
# Cách dùng: julia --project=. core/export_v3_plan.jl [instance] [số khách] [số ngày] [BnC|ALNS]
# Số khách = 0 nghĩa là giữ toàn bộ instance. Instance lớn nên dùng ALNS.
include(joinpath(@__DIR__, "run_v3_experiments.jl"))

function export_v3_plan(instance::String, n::Int, H::Int, method::String="BnC")
    root = normpath(joinpath(@__DIR__, "..", "collection_routing_dataset_v3"))
    full, ids = load_v3_data(root, instance; scenario="CO_SO")
    n = n == 0 ? full.n : n
    data = sub_instance(full, n, H; max_visits=2)
    result = method == "ALNS" ?
        solve_alns(data; iterations=300, stagnation_iterations=50, seed=2026) :
        solve_branch_and_cut(data; time_limit=300.0, symmetry_breaking=true)
    plan = checked_plan(data, result)
    plan === nothing && error("$method found no solution")
    println("method=$method, status=$(result.status), objective=$(result.objective), nodes=$(result.nodes)")

    outdir = normpath(joinpath(@__DIR__, "..", "outputs", "plans"))
    mkpath(outdir)
    file = joinpath(outdir, "plan_$(instance)_n$(n)_H$(H).csv")
    open(file, "w") do io
        println(io, "officer,day,stop_order,location_id,leg_km,leg_minutes")
        for ((k, t), route) in sort(collect(plan.routes))
            for (order, node) in enumerate(route)
                prev = order == 1 ? node : route[order - 1]
                println(io, join([k, t, order - 1, node == 0 ? "CN01" : ids[node],
                    fmt(data.distance[prev + 1, node + 1]),
                    fmt(60 * data.travel_time[prev + 1, node + 1])], ","))
            end
        end
    end
    println("Saved: $file")
end

if abspath(PROGRAM_FILE) == @__FILE__
    instance = length(ARGS) >= 1 ? ARGS[1] : "INS_XS"
    n = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 20
    H = length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 5
    method = length(ARGS) >= 4 ? ARGS[4] : "BnC"
    export_v3_plan(instance, n, H, method)
end
