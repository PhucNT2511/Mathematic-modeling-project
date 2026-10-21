include(joinpath(@__DIR__, "run_v3_rl_experiment.jl"))
include(joinpath(@__DIR__, "..", "data_processing", "sample_data.jl"))

data = sample_data(n=3, K=1, H=2)
customer_ids = ["TEST_$i" for i in 1:data.n]
draws = Dict(1 => fill(0.0, data.n, data.H),
             2 => fill(0.0, data.n, data.H),
             3 => fill(0.5, data.n, data.H))
config = Dict(
    "seed" => 2026,
    "split" => Dict("train" => [1, 1], "validation" => [2, 2],
                    "test" => [3, 3]),
    "rl" => Dict("epochs" => 1, "alpha" => 0.2, "gamma" => 0.9,
                 "epsilon_start" => 0.5, "epsilon_end" => 0.1),
    "ga" => Dict("population_size" => 8, "generations" => 4,
                 "stagnation_generations" => 2),
    "tabu" => Dict("iterations" => 4, "neighborhood_size" => 4,
                   "tabu_tenure" => 2),
    "alns" => Dict("iterations" => 4),
    "branch_and_cut" => Dict("time_limit_seconds" => 10.0, "mip_gap" => 0.001),
)
@assert scenario_split(config) == Dict("train" => [1], "validation" => [2], "test" => [3])
qtable = train_dynamic_rl(data, customer_ids, draws, [1], config)
@assert !isempty(qtable)
@assert any(any(!iszero, values) for values in values(qtable))
frozen = deepcopy(qtable)
summary, daily, visits = evaluate_dynamic_rl(data, customer_ids, draws[3], 3, config, qtable)
@assert qtable == frozen
@assert summary.method == "RL"
@assert length(daily) == data.H
@assert summary.visits == length(visits)
@assert length(scenario_split(JSON.parsefile(joinpath(@__DIR__, "..", "rl_experiment.json")))["test"]) == 20
buffer = IOBuffer()
JSON.print(buffer, Dict("q_values" => Dict(join(key, "_") => value
                                           for (key, value) in qtable)), 2)
@assert !isempty(String(take!(buffer)))
println("RL train/test separation smoke test passed")
