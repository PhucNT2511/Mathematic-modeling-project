# RL-assisted ALNS: Q-learning thay cơ chế roulette/adaptive weights để chọn
# cặp destroy-repair. Đây là RL dạng bảng, chưa sử dụng mạng neural.
if !isdefined(Main, :solve_alns)
    include(joinpath(@__DIR__, "alns.jl"))
end

using Random

# Trạng thái rời rạc gồm:
# 1. phase: đầu, giữa hoặc cuối episode;
# 2. stagnation: số bước chưa cải thiện nghiệm tốt nhất;
# 3. gap: nghiệm hiện tại gần hay xa nghiệm tốt nhất.
function rl_state(step, steps_per_episode, stagnation, current, best, data)
    phase = min(3, 1 + div(3 * (step - 1), steps_per_episode))
    stagnation_level = stagnation < 10 ? 1 : stagnation < 30 ? 2 : 3
    scale = max(sum(data.debt), 1.0)
    relative_gap = (
        best.expected_recovery - current.expected_recovery
    ) / scale
    gap_level = relative_gap <= 1.0e-6 ? 1 :
                relative_gap <= 0.01 ? 2 : 3
    return (phase, stagnation_level, gap_level)
end

# Epsilon-greedy: thăm dò ngẫu nhiên với xác suất epsilon, còn lại chọn action
# có Q-value lớn nhất. Khi hòa, chọn ngẫu nhiên để tránh thiên lệch action đầu.
function select_rl_action(q_values, epsilon, rng)
    rand(rng) < epsilon && return rand(rng, eachindex(q_values))
    best_value = maximum(q_values)
    best_actions = findall(value -> abs(value - best_value) <= 1.0e-12, q_values)
    return rand(rng, best_actions)
end

"""
Q-learning điều khiển ALNS.

Mỗi action tương ứng một cặp trong 4 destroy x 2 repair = 8 action.
Agent được huấn luyện online qua nhiều episode trên cùng instance. Reward:
- 10 nếu tạo nghiệm tốt nhất toàn cục mới;
- 3 cộng phần cải thiện nếu tốt hơn nghiệm hiện tại;
- 0.5 nếu nghiệm kém hơn nhưng được chấp nhận để đa dạng hóa;
- -1 nếu bị từ chối.

alpha là learning rate, gamma là discount factor. Epsilon giảm dần qua các
episode để chuyển từ exploration sang exploitation.
"""
function solve_rl_alns(
    data::DebtRoutingData;
    episodes::Int=12,
    steps_per_episode::Int=100,
    destroy_fraction::Float64=0.20,
    alpha::Float64=0.20,
    gamma::Float64=0.90,
    epsilon_start::Float64=0.90,
    epsilon_end::Float64=0.05,
    cooling_rate::Float64=0.995,
    seed::Int=2026,
)
    rng = MersenneTwister(seed)
    started = time()

    destroy_operators = (
        random_removal!,
        worst_value_removal!,
        related_removal!,
        route_removal!,
    )
    repair_operators = (greedy_repair!, regret_repair!)
    action_count = length(destroy_operators) * length(repair_operators)

    # Mỗi state ánh xạ tới vector 8 Q-values, ban đầu đều bằng 0.
    q_table = Dict{NTuple{3,Int},Vector{Float64}}()
    global_best_genes = zeros(Int, data.n, data.H)
    global_best_evaluation = evaluate_ga(global_best_genes, data)

    for episode in 1:episodes
        # Mỗi episode bắt đầu từ nghiệm greedy rồi có một ít nhiễu ngẫu nhiên.
        current_genes = greedy_repair!(zeros(Int, data.n, data.H), data)
        if episode > 1
            visits = selected_visits(current_genes)
            shuffle!(rng, visits)
            noise_count = max(1, round(Int, 0.10 * length(visits)))
            for (i, t) in visits[1:min(noise_count, length(visits))]
                current_genes[i, t] = 0
            end
            random_repair = rand(rng, repair_operators)
            random_repair(current_genes, data)
        end
        current_evaluation = evaluate_ga(current_genes, data)

        if is_better(current_evaluation, global_best_evaluation)
            global_best_genes = copy(current_genes)
            global_best_evaluation = current_evaluation
        end

        epsilon = epsilon_start +
            (epsilon_end - epsilon_start) * (episode - 1) / max(episodes - 1, 1)
        temperature = 0.05
        stagnation = 0

        for step in 1:steps_per_episode
            state = rl_state(
                step, steps_per_episode, stagnation,
                current_evaluation, global_best_evaluation, data,
            )
            q_values = get!(q_table, state, zeros(action_count))
            action = select_rl_action(q_values, epsilon, rng)

            # Action 1-2 dùng destroy 1; 3-4 dùng destroy 2; ...
            destroy_index = div(action - 1, length(repair_operators)) + 1
            repair_index = mod(action - 1, length(repair_operators)) + 1

            candidate_genes = copy(current_genes)
            visit_count = max(1, length(selected_visits(candidate_genes)))
            removal_count = max(1, round(Int, destroy_fraction * visit_count))
            destroy_operators[destroy_index](
                candidate_genes, removal_count, data, rng,
            )
            repair_operators[repair_index](candidate_genes, data)
            candidate_evaluation = evaluate_ga(candidate_genes, data)

            old_score = acceptance_score(current_evaluation, data)
            new_score = acceptance_score(candidate_evaluation, data)
            accepted = new_score >= old_score ||
                rand(rng) < exp((new_score - old_score) / max(temperature, 1.0e-9))

            reward = -1.0
            improved_global = is_better(
                candidate_evaluation, global_best_evaluation,
            )
            if improved_global
                reward = 10.0
                global_best_genes = copy(candidate_genes)
                global_best_evaluation = candidate_evaluation
                stagnation = 0
            elseif is_better(candidate_evaluation, current_evaluation)
                reward = 3.0 + 10.0 * max(new_score - old_score, 0.0)
                stagnation += 1
            elseif accepted
                reward = 0.5
                stagnation += 1
            else
                stagnation += 1
            end

            accepted && begin
                current_genes = candidate_genes
                current_evaluation = candidate_evaluation
            end

            next_state = rl_state(
                min(step + 1, steps_per_episode),
                steps_per_episode,
                stagnation,
                current_evaluation,
                global_best_evaluation,
                data,
            )
            next_q_values = get!(q_table, next_state, zeros(action_count))

            # Phương trình cập nhật Q-learning.
            target = reward + gamma * maximum(next_q_values)
            q_values[action] += alpha * (target - q_values[action])
            temperature *= cooling_rate
        end
    end

    return SolveResult(
        "Q-learning ALNS",
        "HEURISTIC",
        global_best_evaluation.expected_recovery,
        NaN,
        0,
        time() - started,
        ga_decisions(
            global_best_genes,
            global_best_evaluation.routes,
            data,
        ),
    )
end

