if !isdefined(Main, :run_dynamic_method)
    include(joinpath(@__DIR__, "run_v3_dynamic.jl"))
end
using Random

const RL_ACTIONS = ("GA", "Tabu", "ALNS")

# The state contains only information observable at the start of a day.
function dynamic_rl_state(data, day, paid, attempts)
    paid_fraction = count(paid) / data.n
    remaining_fraction = sum(max(0, data.max_visits[i] - attempts[i])
                             for i in 1:data.n if !paid[i]) / sum(data.max_visits)
    return (day, min(3, floor(Int, 4 * paid_fraction)),
            min(3, floor(Int, 4 * remaining_fraction)))
end

function rl_action_index(qvalues, epsilon, rng)
    rand(rng) < epsilon && return rand(rng, eachindex(qvalues))
    # Fixed tie break also makes held-out evaluation reproducible.
    return findfirst(==(maximum(qvalues)), qvalues)
end

"""Learn a daily meta-policy from realized collection on train scenario IDs only."""
function train_dynamic_rl(data, customer_ids, draws, train_ids, config)
    c = config["rl"]
    alpha = Float64(c["alpha"])
    gamma = Float64(c["gamma"])
    epsilon_start = Float64(c["epsilon_start"])
    epsilon_end = Float64(c["epsilon_end"])
    epochs = Int(c["epochs"])
    epochs >= 1 || error("RL epochs must be positive")
    0 < alpha <= 1 && 0 <= gamma <= 1 &&
        0 <= epsilon_start <= 1 && 0 <= epsilon_end <= 1 ||
        error("Invalid RL learning parameters")
    qtable = Dict{NTuple{3,Int},Vector{Float64}}()
    rng = MersenneTwister(Int(config["seed"]))
    total_episodes = epochs * length(train_ids)
    episode = 0
    for _ in 1:epochs, id in shuffle(rng, collect(train_ids))
        episode += 1
        epsilon = epsilon_start +
            (epsilon_end - epsilon_start) * (episode - 1) / max(1, total_episodes - 1)
        policy = (day, paid, attempts) -> begin
            state = dynamic_rl_state(data, day, paid, attempts)
            index = rl_action_index(get!(qtable, state, zeros(3)), epsilon, rng)
            RL_ACTIONS[index]
        end
        on_transition = (day, before_paid, before_attempts, action,
                         collected, after_paid, after_attempts) -> begin
            state = dynamic_rl_state(data, day, before_paid, before_attempts)
            index = findfirst(==(action), RL_ACTIONS)
            remaining = any(!after_paid[i] && after_attempts[i] < data.max_visits[i]
                            for i in 1:data.n)
            next_value = if day < data.H && remaining
                next_state = dynamic_rl_state(data, day + 1, after_paid, after_attempts)
                maximum(get!(qtable, next_state, zeros(3)))
            else
                0.0
            end
            reward = collected / sum(data.debt)
            values = get!(qtable, state, zeros(3))
            values[index] += alpha * (reward + gamma * next_value - values[index])
        end
        run_dynamic_method("RL", data, customer_ids, draws[id], id, config,
                           Int(config["seed"]) + episode * 100;
                           policy=policy, on_transition=on_transition,
                           verbose=false)
        if episode % 10 == 0 || episode == total_episodes
            println("  RL training episode $episode/$total_episodes")
        end
    end
    return qtable
end

"""Run a frozen policy; test draws influence outcomes but never Q-values."""
function evaluate_dynamic_rl(data, customer_ids, draws, id, config, qtable)
    policy = (day, paid, attempts) -> begin
        state = dynamic_rl_state(data, day, paid, attempts)
        RL_ACTIONS[rl_action_index(get(qtable, state, zeros(3)), 0.0,
                                   MersenneTwister(0))]
    end
    return run_dynamic_method("RL", data, customer_ids, draws, id, config,
                              Int(config["seed"]); policy=policy)
end
