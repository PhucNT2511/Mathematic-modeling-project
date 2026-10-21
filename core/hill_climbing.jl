# Hill Climbing dùng cùng biểu diễn, repair và hàm đánh giá với GA.
if !isdefined(Main, :solve_genetic_algorithm)
    include(joinpath(@__DIR__, "genetic_algorithm.jl"))
end

using Random

# Tạo một nghiệm xuất phát ngẫu nhiên và sửa về miền khả thi.
function random_hill_start(data::DebtRoutingData, rng; selection_probability=0.35)
    genes = zeros(Int, data.n, data.H)
    for i in 1:data.n, t in 1:data.H
        if rand(rng) < selection_probability
            genes[i, t] = rand(rng, 1:data.K)
        end
    end
    return repair!(genes, data)
end

"""
Leo đồi best-improvement với nhiều điểm khởi đầu.

Một láng giềng được tạo bằng cách thay đổi đúng một gene (i,t):
- 0: không thăm khách hàng i trong ngày t;
- k: giao lần thăm cho cán bộ k.

Ở mỗi vòng, thuật toán đánh giá toàn bộ các move một-gene, chọn move tốt nhất
và chỉ di chuyển nếu nghiệm mới tốt hơn. Khi không còn move cải thiện, nghiệm
hiện tại là cực trị địa phương. Multi-start lặp lại quá trình từ nhiều nghiệm
ngẫu nhiên và giữ nghiệm tốt nhất chung.
"""
function solve_hill_climbing(
    data::DebtRoutingData;
    restarts::Int=8,
    max_iterations::Int=200,
    seed::Int=2026,
)
    rng = MersenneTwister(seed)
    started = time()
    global_best_genes = zeros(Int, data.n, data.H)
    global_best_evaluation = evaluate_ga(global_best_genes, data)

    for restart in 1:restarts
        # Điểm khởi đầu đầu tiên là nghiệm rỗng; các lần sau dùng nghiệm ngẫu nhiên.
        current_genes = restart == 1 ?
            zeros(Int, data.n, data.H) :
            random_hill_start(data, rng)
        current_evaluation = evaluate_ga(current_genes, data)

        for _ in 1:max_iterations
            best_neighbor_genes = nothing
            best_neighbor_evaluation = current_evaluation

            # Xét toàn bộ phép gán khác giá trị hiện tại cho từng gene.
            for i in 1:data.n, t in 1:data.H
                old_value = current_genes[i, t]
                for new_value in 0:data.K
                    new_value == old_value && continue
                    candidate_genes = copy(current_genes)
                    candidate_genes[i, t] = new_value
                    repair!(candidate_genes, data)

                    # Nếu repair hủy chính move vừa tạo, đây không phải láng giềng.
                    candidate_genes[i, t] == new_value || continue
                    candidate_evaluation = evaluate_ga(candidate_genes, data)
                    if is_better(candidate_evaluation, best_neighbor_evaluation)
                        best_neighbor_genes = candidate_genes
                        best_neighbor_evaluation = candidate_evaluation
                    end
                end
            end

            # Không có cải thiện: đã tới cực trị địa phương.
            best_neighbor_genes === nothing && break
            current_genes = best_neighbor_genes
            current_evaluation = best_neighbor_evaluation
        end

        if is_better(current_evaluation, global_best_evaluation)
            global_best_genes = copy(current_genes)
            global_best_evaluation = current_evaluation
        end
    end

    return SolveResult(
        "Hill Climbing",
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

