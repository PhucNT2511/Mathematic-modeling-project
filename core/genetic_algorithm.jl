# Genetic Algorithm giải gần đúng bài toán mà không gọi MILP solver.
if !isdefined(Main, :DebtRoutingData)
    include(joinpath(@__DIR__, "model.jl"))
end

using Random

# Kết quả đánh giá một cá thể: tiền kỳ vọng, quãng đường và các tuyến.
struct GAEvaluation
    expected_recovery::Float64
    total_distance::Float64
    routes::Dict{Tuple{Int,Int},Vector{Int}}
end

# So sánh từ điển: ưu tiên tiền kỳ vọng, sau đó mới đến quãng đường.
function is_better(left::GAEvaluation, right::GAEvaluation; tolerance=1.0e-6)
    if left.expected_recovery > right.expected_recovery + tolerance
        return true
    elseif right.expected_recovery > left.expected_recovery + tolerance
        return false
    end
    return left.total_distance < right.total_distance
end

# Tính tổng khoảng cách hoặc thời gian của một tuyến 0 -> ... -> 0.
function route_cost(route::Vector{Int}, matrix::Matrix{Float64})
    return sum(matrix[route[index] + 1, route[index + 1] + 1]
               for index in 1:(length(route) - 1))
end

# Dựng tuyến ban đầu bằng nearest-neighbor từ chi nhánh.
function nearest_neighbor_route(customers::Vector{Int}, distance)
    isempty(customers) && return Int[0, 0]
    remaining = copy(customers)
    route = Int[0]
    current = 0
    while !isempty(remaining)
        position = argmin([distance[current + 1, customer + 1] for customer in remaining])
        current = remaining[position]
        push!(route, current)
        deleteat!(remaining, position)
    end
    push!(route, 0)
    return route
end

# 2-opt thử đảo từng đoạn và giữ phép đảo làm giảm tổng khoảng cách.
# Cách tính lại toàn tuyến vẫn đúng khi ma trận đường bộ là bất đối xứng.
function two_opt!(route::Vector{Int}, distance; max_passes=20)
    length(route) <= 4 && return route
    for _ in 1:max_passes
        improved = false
        current_cost = route_cost(route, distance)
        for first in 2:(length(route) - 2)
            for last in (first + 1):(length(route) - 1)
                candidate = copy(route)
                candidate[first:last] = reverse(candidate[first:last])
                candidate_cost = route_cost(candidate, distance)
                if candidate_cost + 1.0e-9 < current_cost
                    route .= candidate
                    current_cost = candidate_cost
                    improved = true
                end
            end
        end
        improved || break
    end
    return route
end

function build_route(customers, data)
    route = nearest_neighbor_route(collect(customers), data.distance)
    return two_opt!(route, data.distance)
end

# Giá trị kỳ vọng của tập ngày đang được chọn cho một khách hàng.
function customer_value(data, customer, days)
    isempty(days) && return 0.0
    return expected_value(data, customer, collect(days))
end

# Repair bảo đảm số lần thăm và ngân sách thời gian của mọi tuyến.
function repair!(genes::Matrix{Int}, data::DebtRoutingData)
    n, H = data.n, data.H

    # Nếu vượt số lần thăm, giữ các ngày có xác suất cao nhất.
    for i in 1:n
        selected_days = findall(genes[i, :] .> 0)
        if length(selected_days) > data.max_visits[i]
            ordered_days = sort(
                selected_days;
                by=t -> data.probability[i, t],
                rev=true,
            )
            for t in ordered_days[(data.max_visits[i] + 1):end]
                genes[i, t] = 0
            end
        end
    end

    # Nếu một tuyến quá giờ, lần lượt bỏ lần thăm có mất mát kỳ vọng nhỏ nhất.
    for k in 1:data.K, t in 1:H
        while true
            customers = findall(genes[:, t] .== k)
            isempty(customers) && break
            route = build_route(customers, data)
            used_time = route_cost(route, data.travel_time) +
                        sum(data.service_time[i] for i in customers)
            used_time <= data.daily_budget[k, t] + 1.0e-9 && break

            marginal_losses = Float64[]
            for i in customers
                all_days = findall(genes[i, :] .> 0)
                remaining_days = filter(day -> day != t, all_days)
                push!(
                    marginal_losses,
                    customer_value(data, i, all_days) -
                    customer_value(data, i, remaining_days),
                )
            end
            genes[customers[argmin(marginal_losses)], t] = 0
        end
    end
    return genes
end

# Đánh giá một cá thể sau khi repair.
function evaluate_ga(genes::Matrix{Int}, data::DebtRoutingData)
    expected_recovery = 0.0
    for i in 1:data.n
        days = findall(genes[i, :] .> 0)
        expected_recovery += customer_value(data, i, days)
    end

    routes = Dict{Tuple{Int,Int},Vector{Int}}()
    total_distance = 0.0
    for k in 1:data.K, t in 1:data.H
        customers = findall(genes[:, t] .== k)
        isempty(customers) && continue
        route = build_route(customers, data)
        routes[(k, t)] = route
        total_distance += route_cost(route, data.distance)
    end
    return GAEvaluation(expected_recovery, total_distance, routes)
end

# Chọn một bố/mẹ bằng tournament selection.
function tournament_select(population, evaluations, rng; tournament_size=3)
    candidates = rand(rng, eachindex(population), tournament_size)
    winner = candidates[1]
    for candidate in candidates[2:end]
        is_better(evaluations[candidate], evaluations[winner]) && (winner = candidate)
    end
    return population[winner]
end

# Lai ghép đồng nhất: mỗi gene được lấy ngẫu nhiên từ bố hoặc mẹ.
function crossover(parent_a, parent_b, rng)
    child = similar(parent_a)
    for index in eachindex(child)
        child[index] = rand(rng, Bool) ? parent_a[index] : parent_b[index]
    end
    return child
end

# Đột biến một ô: bỏ lần thăm hoặc gán cho một cán bộ ngẫu nhiên.
function mutate!(genes, data, rng, mutation_rate)
    for index in eachindex(genes)
        if rand(rng) < mutation_rate
            genes[index] = rand(rng, 0:data.K)
        end
    end
    return genes
end

# Chuyển cá thể GA thành định dạng quyết định chung để dùng hàm print_result.
function ga_decisions(best_genes, routes, data)
    decisions = Dict{Tuple,Int}()
    for i in 1:data.n, k in 1:data.K, t in 1:data.H
        decisions[(:y, i, k, t)] = best_genes[i, t] == k ? 1 : 0
    end
    for k in 1:data.K, t in 1:data.H
        route = get(routes, (k, t), Int[])
        decisions[(:z, k, t)] = isempty(route) ? 0 : 1
        for edge in 1:max(0, length(route) - 1)
            decisions[(:x, route[edge], route[edge + 1], k, t)] = 1
        end
    end
    return decisions
end

"""
Chạy Genetic Algorithm.

population_size: số cá thể trong một thế hệ.
generations: số thế hệ tối đa.
stagnation_generations: dừng sớm sau số thế hệ liên tiếp không cải thiện;
đặt bằng 0 để tắt dừng sớm.
mutation_rate: xác suất đột biến của mỗi gene.
elite_count: số cá thể tốt nhất được giữ nguyên sang thế hệ sau.
"""
function solve_genetic_algorithm(
    data::DebtRoutingData;
    population_size::Int=100,
    generations::Int=1000,
    stagnation_generations::Int=150,
    mutation_rate::Float64=0.03,
    elite_count::Int=4,
    seed::Int=2026,
)
    population_size > 0 || throw(ArgumentError("population_size must be positive"))
    generations > 0 || throw(ArgumentError("generations must be positive"))
    stagnation_generations >= 0 ||
        throw(ArgumentError("stagnation_generations must be non-negative"))
    0 < elite_count <= population_size ||
        throw(ArgumentError("elite_count must be in 1:population_size"))

    rng = MersenneTwister(seed)
    started = time()

    # Gene (i,t) bằng 0 nếu không thăm, hoặc bằng k nếu cán bộ k thực hiện.
    population = Matrix{Int}[]
    for _ in 1:population_size
        genes = zeros(Int, data.n, data.H)
        for i in 1:data.n, t in 1:data.H
            if rand(rng) < 0.35
                genes[i, t] = rand(rng, 1:data.K)
            end
        end
        push!(population, repair!(genes, data))
    end

    best_genes = copy(population[1])
    best_evaluation = evaluate_ga(best_genes, data)
    stagnant_generations = 0
    generations_run = 0

    for generation in 1:generations
        generations_run = generation
        evaluations = [evaluate_ga(individual, data) for individual in population]
        ranking = sortperm(
            eachindex(population);
            lt=(a, b) -> is_better(evaluations[a], evaluations[b]),
        )

        if is_better(evaluations[ranking[1]], best_evaluation)
            best_genes = copy(population[ranking[1]])
            best_evaluation = evaluations[ranking[1]]
            stagnant_generations = 0
        else
            stagnant_generations += 1
        end

        # A value of zero disables early stopping.
        if stagnation_generations > 0 &&
           stagnant_generations >= stagnation_generations
            break
        end

        # Elitism giữ lại các cá thể tốt nhất.
        next_population = [
            copy(population[ranking[index]]) for index in 1:elite_count
        ]
        while length(next_population) < population_size
            parent_a = tournament_select(population, evaluations, rng)
            parent_b = tournament_select(population, evaluations, rng)
            child = crossover(parent_a, parent_b, rng)
            mutate!(child, data, rng, mutation_rate)
            repair!(child, data)
            push!(next_population, child)
        end
        population = next_population
    end

    if generations_run < generations
        println(
            "GA early stopping: no improvement for " *
            "$(stagnation_generations) generations (stopped at generation " *
            "$(generations_run)/$(generations)).",
        )
    end

    # Đánh giá thế hệ cuối để không bỏ sót cá thể mới sinh ở vòng cuối.
    for individual in population
        evaluation = evaluate_ga(individual, data)
        if is_better(evaluation, best_evaluation)
            best_genes = copy(individual)
            best_evaluation = evaluation
        end
    end

    return SolveResult(
        "Genetic Algorithm",
        "HEURISTIC",
        best_evaluation.expected_recovery,
        NaN,
        0,
        time() - started,
        ga_decisions(best_genes, best_evaluation.routes, data),
    )
end

