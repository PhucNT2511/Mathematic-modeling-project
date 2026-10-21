# Tabu Search dùng chung biểu diễn, repair và dựng tuyến với GA.
if !isdefined(Main, :solve_genetic_algorithm)
    include(joinpath(@__DIR__, "genetic_algorithm.jl"))
end

using Random

# Tạo nghiệm xuất phát bằng cách ưu tiên lần thăm có giá trị kỳ vọng cao
# so với thời gian phục vụ và thời gian đi-về chi nhánh.
function greedy_tabu_start(data::DebtRoutingData)
    genes = zeros(Int, data.n, data.H)
    candidates = Tuple{Float64,Int,Int,Int}[]

    for i in 1:data.n, t in 1:data.H, k in 1:data.K
        approximate_time = data.service_time[i] +
            data.travel_time[1, i + 1] + data.travel_time[i + 1, 1]
        score = data.debt[i] * data.probability[i, t] /
                max(approximate_time, 1.0e-6)
        push!(candidates, (score, i, t, k))
    end
    sort!(candidates; by=item -> item[1], rev=true)

    # Thử lần lượt các ứng viên tốt nhất. Repair loại quyết định gây quá giờ.
    for (_, i, t, k) in candidates
        count(genes[i, :] .> 0) >= data.max_visits[i] && continue
        genes[i, t] != 0 && continue
        candidate = copy(genes)
        candidate[i, t] = k
        repair!(candidate, data)
        candidate[i, t] == k && (genes = candidate)
    end
    return genes
end

"""
Giải gần đúng bằng Tabu Search.

Mỗi move thay đổi một gene (khách hàng, ngày) từ cán bộ hiện tại sang
không thăm hoặc một cán bộ khác. Tabu memory cấm gán lại giá trị cũ trong
tabu_tenure vòng. Aspiration cho phép move tabu nếu nó tạo nghiệm toàn cục
tốt nhất mới.
"""
function solve_tabu_search(
    data::DebtRoutingData;
    iterations::Int=300,
    neighborhood_size::Int=50,
    tabu_tenure::Int=15,
    seed::Int=2026,
)
    rng = MersenneTwister(seed)
    started = time()

    current_genes = greedy_tabu_start(data)
    current_evaluation = evaluate_ga(current_genes, data)
    best_genes = copy(current_genes)
    best_evaluation = current_evaluation

    # Key (i,t,value) bị cấm đến iteration được lưu trong Dict.
    tabu_until = Dict{Tuple{Int,Int,Int},Int}()

    for iteration in 1:iterations
        selected_genes = nothing
        selected_evaluation = nothing
        selected_move = nothing

        for _ in 1:neighborhood_size
            i = rand(rng, 1:data.n)
            t = rand(rng, 1:data.H)
            old_value = current_genes[i, t]

            # Chọn giá trị mới khác giá trị hiện tại.
            possible_values = [value for value in 0:data.K if value != old_value]
            new_value = rand(rng, possible_values)
            candidate_genes = copy(current_genes)
            candidate_genes[i, t] = new_value
            repair!(candidate_genes, data)

            # Bỏ move nếu repair đã hoàn tác chính thay đổi vừa đề xuất.
            candidate_genes[i, t] == new_value || continue
            candidate_evaluation = evaluate_ga(candidate_genes, data)

            # Move bị tabu nếu nó gán một giá trị đang bị cấm.
            is_tabu = get(tabu_until, (i, t, new_value), 0) >= iteration
            aspiration = is_better(candidate_evaluation, best_evaluation)
            is_tabu && !aspiration && continue

            if selected_evaluation === nothing ||
               is_better(candidate_evaluation, selected_evaluation)
                selected_genes = candidate_genes
                selected_evaluation = candidate_evaluation
                selected_move = (i, t, old_value)
            end
        end

        # Không có move hợp lệ nghĩa là lân cận hiện tại đã bị khóa.
        selected_genes === nothing && break
        current_genes = selected_genes
        current_evaluation = selected_evaluation

        # Cấm quay lại giá trị cũ trong một số vòng tiếp theo.
        tabu_until[selected_move] = iteration + tabu_tenure

        # Xóa các entry hết hạn để tabu memory không tăng vô hạn.
        for (key, expiry) in collect(tabu_until)
            expiry < iteration && delete!(tabu_until, key)
        end

        if is_better(current_evaluation, best_evaluation)
            best_genes = copy(current_genes)
            best_evaluation = current_evaluation
        end
    end

    return SolveResult(
        "Tabu Search",
        "HEURISTIC",
        best_evaluation.expected_recovery,
        NaN,
        0,
        time() - started,
        ga_decisions(best_genes, best_evaluation.routes, data),
    )
end

