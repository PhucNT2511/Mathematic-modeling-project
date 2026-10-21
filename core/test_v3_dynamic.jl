include(joinpath(@__DIR__, "run_v3_dynamic.jl"))
include(joinpath(@__DIR__, "..", "data_processing", "sample_data.jl"))

data = sample_data(n=3, K=1, H=2)
ids = ["TEST_$i" for i in 1:data.n]
draws = fill(0.0, data.n, data.H)
draws[:, 1] .= 1.0
config = Dict(
    "ga" => Dict("population_size" => 8, "generations" => 4,
                 "stagnation_generations" => 2),
    "tabu" => Dict("iterations" => 4, "neighborhood_size" => 4,
                   "tabu_tenure" => 2),
    "alns" => Dict("iterations" => 4),
    "branch_and_cut" => Dict("time_limit_seconds" => 10.0, "mip_gap" => 0.001),
)
summaries = NamedTuple[]
for method in ("GA", "Tabu", "ALNS", "Branch-and-Cut")
    summary, daily, visits = run_dynamic_method(method, data, ids, draws, 1, config, 2026)
    push!(summaries, summary)
    @assert length(daily) == data.H
    @assert summary.visits == length(visits)
    @assert summary.paid <= data.n
    @assert any(row.day == 2 for row in visits)
    @assert all(row.success == (row.day == 2) for row in visits)
    @assert all(row.attempts <= 2 for row in visits)
end
@assert length(dynamic_aggregate(summaries, [1])) == 4
println("Dynamic rolling-horizon smoke test passed")

# Even a near-immediate solver stop must not discard a feasible warm start.
initial = solve_alns(data; iterations=4, seed=2026)
limited = solve_branch_and_cut(data; time_limit=0.0, initial_result=initial)
@assert limited.objective + 1.0e-5 >= initial.objective
@assert !isempty(selected_routes(data, limited))
println("Branch-and-Cut warm-start smoke test passed")

# Check that the actual v3 probability and common-random-number tables align.
root = normpath(joinpath(@__DIR__, "..", "collection_routing_dataset_v3"))
v3, customer_ids = load_v3_data(root, "INS_XS"; scenario="CO_SO")
sample = load_v3_draws(root, customer_ids, v3.H, [1])
@assert size(sample[1]) == size(v3.probability)
@assert all(x -> 0 <= x <= 1, sample[1])
println("V3 data alignment test passed")
