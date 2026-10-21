# Adaptive Large Neighborhood Search dùng chung biểu diễn và hàm đánh giá
# với GA để kết quả giữa các heuristic có thể so sánh trực tiếp.
if !isdefined(Main, :solve_genetic_algorithm)
    include(joinpath(@__DIR__, "genetic_algorithm.jl"))
end

using Random

# Danh sách mọi lần thăm đang có dưới dạng (khách hàng, ngày).
selected_visits(genes) = [
    (i, t) for i in axes(genes, 1) for t in axes(genes, 2) if genes[i, t] > 0
]

# Kiểm tra việc chèn khách hàng i vào cán bộ k, ngày t có khả thi không.
function feasible_insertion(genes, i, t, k, data)
    genes[i, t] == 0 || return false
    count(genes[i, :] .> 0) < data.max_visits[i] || return false
    customers = findall(genes[:, t] .== k)
    push!(customers, i)
    route = build_route(customers, data)
    used_time = route_cost(route, data.travel_time) +
                sum(data.service_time[customer] for customer in customers)
    return used_time <= data.daily_budget[k, t] + 1.0e-9
end

# Giá trị tăng thêm và quãng đường tăng thêm của một phép chèn.
function insertion_metrics(genes, i, t, k, data)
    old_days = findall(genes[i, :] .> 0)
    new_days = sort(vcat(old_days, t))
    gain = customer_value(data, i, new_days) - customer_value(data, i, old_days)

    old_customers = findall(genes[:, t] .== k)
    old_route = build_route(old_customers, data)
    new_route = build_route(vcat(old_customers, i), data)
    distance_increase = route_cost(new_route, data.distance) -
                        route_cost(old_route, data.distance)
    return gain, distance_increase
end

# Destroy 1: xóa q lần thăm ngẫu nhiên.
function random_removal!(genes, q, data, rng)
    visits = selected_visits(genes)
    shuffle!(rng, visits)
    for (i, t) in visits[1:min(q, length(visits))]
        genes[i, t] = 0
    end
end

# Destroy 2: xóa những lần thăm có đóng góp kỳ vọng biên thấp nhất.
function worst_value_removal!(genes, q, data, rng)
    visits = selected_visits(genes)
    scored = Tuple{Float64,Int,Int}[]
    for (i, t) in visits
        days = findall(genes[i, :] .> 0)
        remaining = filter(day -> day != t, days)
        loss = customer_value(data, i, days) -
               customer_value(data, i, remaining)
        push!(scored, (loss, i, t))
    end
    sort!(scored; by=item -> item[1])
    for (_, i, t) in scored[1:min(q, length(scored))]
        genes[i, t] = 0
    end
end

# Destroy 3: chọn một khách hàng rồi xóa các lần thăm của những khách hàng
# gần nó nhất. Toán tử này phá một vùng địa lý thay vì các điểm rời rạc.
function related_removal!(genes, q, data, rng)
    visits = selected_visits(genes)
    isempty(visits) && return
    seed_customer = rand(rng, visits)[1]
    sort!(
        visits;
        by=visit -> data.distance[seed_customer + 1, visit[1] + 1],
    )
    for (i, t) in visits[1:min(q, length(visits))]
        genes[i, t] = 0
    end
end

# Destroy 4: xóa toàn bộ một tuyến cán bộ-ngày được chọn ngẫu nhiên.
function route_removal!(genes, q, data, rng)
    nonempty_routes = [
        (k, t) for k in 1:data.K for t in 1:data.H
        if any(genes[:, t] .== k)
    ]
    isempty(nonempty_routes) && return
    k, t = rand(rng, nonempty_routes)
    customers = findall(genes[:, t] .== k)
    shuffle!(rng, customers)
    for i in customers[1:min(q, length(customers))]
        genes[i, t] = 0
    end
end

# Repair 1: liên tục chọn phép chèn có giá trị kỳ vọng tăng lớn nhất;
# khi bằng nhau, ưu tiên phép chèn làm tăng ít khoảng cách hơn.
function greedy_repair!(genes, data)
    while true
        best_move = nothing
        best_gain = -Inf
        best_distance = Inf
        for i in 1:data.n, t in 1:data.H, k in 1:data.K
            feasible_insertion(genes, i, t, k, data) || continue
            gain, distance = insertion_metrics(genes, i, t, k, data)
            if gain > best_gain + 1.0e-6 ||
               (abs(gain - best_gain) <= 1.0e-6 && distance < best_distance)
                best_move = (i, t, k)
                best_gain = gain
                best_distance = distance
            end
        end
        best_move === nothing && break
        genes[best_move[1], best_move[2]] = best_move[3]
    end
    return genes
end

# Repair 2: regret-2 ưu tiên khách hàng sẽ bị thiệt nhiều nhất nếu bỏ lỡ
# vị trí chèn tốt nhất và phải dùng vị trí tốt thứ hai.
function regret_repair!(genes, data)
    while true
        chosen_move = nothing
        highest_regret = -Inf
        chosen_gain = -Inf

        for i in 1:data.n
            count(genes[i, :] .> 0) < data.max_visits[i] || continue
            options = Tuple{Float64,Float64,Int,Int}[]
            for t in 1:data.H, k in 1:data.K
                feasible_insertion(genes, i, t, k, data) || continue
                gain, distance = insertion_metrics(genes, i, t, k, data)
                push!(options, (gain, distance, t, k))
            end
            isempty(options) && continue
            sort!(options; by=option -> (-option[1], option[2]))
            best = options[1]
            second_gain = length(options) >= 2 ? options[2][1] : 0.0
            regret = best[1] - second_gain
            if regret > highest_regret + 1.0e-6 ||
               (abs(regret - highest_regret) <= 1.0e-6 && best[1] > chosen_gain)
                highest_regret = regret
                chosen_gain = best[1]
                chosen_move = (i, best[3], best[4])
            end
        end

        chosen_move === nothing && break
        genes[chosen_move[1], chosen_move[2]] = chosen_move[3]
    end
    return genes
end

# Chọn toán tử theo roulette wheel dựa trên trọng số thích nghi.
function roulette_choice(weights, rng)
    threshold = rand(rng) * sum(weights)
    cumulative = 0.0
    for index in eachindex(weights)
        cumulative += weights[index]
        cumulative >= threshold && return index
    end
    return lastindex(weights)
end

# Điểm chuẩn hóa chỉ dùng cho xác suất chấp nhận; nghiệm tốt nhất vẫn được
# so sánh từ điển bằng expected recovery rồi mới đến distance.
function acceptance_score(evaluation, data)
    return evaluation.expected_recovery / sum(data.debt) -
           1.0e-4 * evaluation.total_distance
end

"""
Giải gần đúng bằng ALNS.

destroy_fraction quy định tỷ lệ lần thăm bị xóa mỗi vòng.
segment_length quy định chu kỳ cập nhật trọng số toán tử.
reaction_factor điều khiển tốc độ ALNS học trọng số mới.
cooling_rate điều khiển giảm nhiệt của cơ chế simulated annealing.
"""
function solve_alns(
    data::DebtRoutingData;
    iterations::Int=500,
    destroy_fraction::Float64=0.20,
    segment_length::Int=25,
    reaction_factor::Float64=0.20,
    cooling_rate::Float64=0.995,
    seed::Int=2026,
)
    rng = MersenneTwister(seed)
    started = time()

    # Greedy repair từ nghiệm rỗng tạo nghiệm xuất phát khả thi.
    current_genes = greedy_repair!(zeros(Int, data.n, data.H), data)
    current_evaluation = evaluate_ga(current_genes, data)
    best_genes = copy(current_genes)
    best_evaluation = current_evaluation

    destroy_operators = (
        random_removal!,
        worst_value_removal!,
        related_removal!,
        route_removal!,
    )
    repair_operators = (greedy_repair!, regret_repair!)
    destroy_weights = ones(length(destroy_operators))
    repair_weights = ones(length(repair_operators))
    destroy_scores = zeros(length(destroy_operators))
    repair_scores = zeros(length(repair_operators))
    destroy_uses = zeros(Int, length(destroy_operators))
    repair_uses = zeros(Int, length(repair_operators))

    # Nhiệt độ ban đầu trên thang điểm chuẩn hóa.
    temperature = 0.05

    for iteration in 1:iterations
        destroy_index = roulette_choice(destroy_weights, rng)
        repair_index = roulette_choice(repair_weights, rng)
        destroy_uses[destroy_index] += 1
        repair_uses[repair_index] += 1

        candidate_genes = copy(current_genes)
        visit_count = max(1, length(selected_visits(candidate_genes)))
        removal_count = max(1, round(Int, destroy_fraction * visit_count))
        destroy_operators[destroy_index](
            candidate_genes, removal_count, data, rng,
        )
        repair_operators[repair_index](candidate_genes, data)
        candidate_evaluation = evaluate_ga(candidate_genes, data)

        current_score = acceptance_score(current_evaluation, data)
        candidate_score = acceptance_score(candidate_evaluation, data)
        accepted = candidate_score >= current_score ||
            rand(rng) < exp((candidate_score - current_score) / max(temperature, 1e-9))

        reward = 0.0
        if is_better(candidate_evaluation, best_evaluation)
            best_genes = copy(candidate_genes)
            best_evaluation = candidate_evaluation
            reward = 10.0
        elseif is_better(candidate_evaluation, current_evaluation)
            reward = 5.0
        elseif accepted
            reward = 1.0
        end

        if accepted
            current_genes = candidate_genes
            current_evaluation = candidate_evaluation
        end
        destroy_scores[destroy_index] += reward
        repair_scores[repair_index] += reward
        temperature *= cooling_rate

        # Cuối mỗi segment, cập nhật trọng số theo điểm trung bình đạt được.
        if iteration % segment_length == 0
            for i in eachindex(destroy_weights)
                performance = destroy_uses[i] == 0 ? 0.0 :
                              destroy_scores[i] / destroy_uses[i]
                destroy_weights[i] =
                    (1 - reaction_factor) * destroy_weights[i] +
                    reaction_factor * max(performance, 0.1)
            end
            for i in eachindex(repair_weights)
                performance = repair_uses[i] == 0 ? 0.0 :
                              repair_scores[i] / repair_uses[i]
                repair_weights[i] =
                    (1 - reaction_factor) * repair_weights[i] +
                    reaction_factor * max(performance, 0.1)
            end
            fill!(destroy_scores, 0.0)
            fill!(repair_scores, 0.0)
            fill!(destroy_uses, 0)
            fill!(repair_uses, 0)
        end
    end

    return SolveResult(
        "ALNS",
        "HEURISTIC",
        best_evaluation.expected_recovery,
        NaN,
        0,
        time() - started,
        ga_decisions(best_genes, best_evaluation.routes, data),
    )
end

