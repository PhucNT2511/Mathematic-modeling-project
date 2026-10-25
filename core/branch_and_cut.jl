# Nạp dữ liệu và hàm dựng mô hình nếu file này được chạy độc lập.
if !isdefined(Main, :DebtRoutingData)
    include(joinpath(@__DIR__, "model.jl"))
end

"""
Giải MILP bằng Branch-and-Cut của HiGHS.

Khác với file branch_and_bound.jl, toàn bộ biến logic được khai báo nhị phân.
HiGHS tự thực hiện presolve, tìm nghiệm ban đầu, thêm cutting planes, phân
nhánh và tính cận. Đây là phương pháp nên dùng cho dữ liệu thực tế.

Đầu vào:
- data: dữ liệu bài toán.
- time_limit: thời gian chạy tối đa, tính bằng giây.
- mip_gap: độ lệch tối ưu tương đối chấp nhận được.
- initial_result: nghiệm heuristic khả thi để làm MIP start và dự phòng.
- minimize_distance: nếu true, giải lần hai theo thứ tự từ điển như đề xuất:
  giữ giá trị thu hồi kỳ vọng ≥ Z* − value_tolerance·max(1, |Z*|) rồi tối
  thiểu tổng quãng đường. Lần hai dùng nghiệm lần một làm MIP start và giới
  hạn thời gian distance_time_limit.
- symmetry_breaking: thêm ràng buộc (15) z[k,t] ≥ z[k+1,t] cho cán bộ cùng ngân sách.
- random_seed: seed của HiGHS, dùng khi lặp nhiều lần chạy trên cùng instance.

Số nút cây Branch-and-Bound (`nodes`) lấy từ HiGHS sau lần giải chính (tối đa
tiền thu kỳ vọng); lần giải phụ cực tiểu quãng đường không được cộng vào.

Đầu ra là một SolveResult chứa nghiệm tốt nhất và cận do solver cung cấp.
"""
function set_routing_start!(vars, data::DebtRoutingData, initial_result::SolveResult)
    for (key, variable) in vars.logical
        if key[1] != :lambda
            set_start_value(variable, Float64(get(initial_result.decisions, key, 0)))
        end
    end
    for i in 1:data.n
        days = [t for t in 1:data.H if any(
            get(initial_result.decisions, (:y, i, k, t), 0) == 1 for k in 1:data.K
        )]
        chosen = findfirst(==(days), vars.schedules[i])
        isempty(days) || chosen !== nothing || error("Warm-start visit schedule is invalid")
        for s in eachindex(vars.schedules[i])
            set_start_value(vars.lambda[(i, s)], chosen == s ? 1.0 : 0.0)
        end
    end
    for variable in values(vars.u)
        set_start_value(variable, 0.0)
    end
    for ((k, t), route) in selected_routes(data, initial_result)
        for (order, i) in enumerate(route[2:end-1])
            set_start_value(vars.u[(i, k, t)], Float64(order))
        end
    end
end

function solve_branch_and_cut(
    data::DebtRoutingData;
    time_limit::Float64=300.0,
    mip_gap::Float64=1.0e-4,
    initial_result::Union{Nothing,SolveResult}=nothing,
    minimize_distance::Bool=false,
    distance_time_limit::Float64=time_limit,
    value_tolerance::Float64=1.0e-6,
    symmetry_breaking::Bool=false,
    random_seed::Union{Nothing,Int}=nothing,
)
    # Dựng mô hình với các biến x, y, z và lambda là biến nhị phân.
    model, vars = build_model(
        data;
        integer_variables=true,
        time_limit=time_limit,
        mip_gap=mip_gap,
        symmetry_breaking=symmetry_breaking,
        random_seed=random_seed,
    )
    if initial_result !== nothing
        isfinite(initial_result.objective) || error("Warm start needs a feasible objective")
        set_routing_start!(vars, data, initial_result)
    end

    # Solver thực hiện toàn bộ quy trình Branch-and-Cut.
    started = time()
    optimize!(model)
    elapsed = time() - started
    status = string(termination_status(model))
    nodes = try
        Int(MOI.get(model, MOI.NodeCount()))
    catch
        0
    end

    # A zero-route incumbent is feasible but useless when a better heuristic
    # route is known. Keep its provenance explicit in the returned status.
    if initial_result !== nothing &&
       (!has_values(model) || objective_value(model) + 1.0e-5 < initial_result.objective)
        return SolveResult(
            "HiGHS Branch-and-Cut (heuristic fallback)",
            status * "_HEURISTIC_FALLBACK",
            initial_result.objective,
            objective_bound(model),
            nodes,
            elapsed,
            initial_result.decisions,
        )
    end

    # Solver có thể dừng mà chưa tìm được nghiệm nguyên khả thi.
    if !has_values(model)
        return SolveResult(
            "HiGHS Branch-and-Cut",
            status,
            -Inf,
            objective_bound(model),
            nodes,
            elapsed,
            Dict{Tuple,Int}(),
        )
    end

    stage1_objective = objective_value(model)
    stage1_bound = objective_bound(model)
    method = "HiGHS Branch-and-Cut"

    # Giải lần hai (thứ tự từ điển): giữ giá trị kỳ vọng tối ưu, giảm quãng đường.
    if minimize_distance
        expected_expr = objective_function(model)
        # Đọc hết nghiệm lần một trước khi sửa mô hình (JuMP xóa nghiệm khi mô hình đổi).
        stage1_values = Dict(variable => value(variable) for variable in all_variables(model))
        for (variable, v) in stage1_values
            set_start_value(variable, v)
        end
        @constraint(model, expected_expr >=
            stage1_objective - value_tolerance * max(1.0, abs(stage1_objective)))
        @objective(model, Min, sum(
            data.distance[i + 1, j + 1] * variable
            for ((i, j, k, t), variable) in vars.x
        ))
        set_attribute(model, "time_limit", distance_time_limit)
        started2 = time()
        optimize!(model)
        elapsed += time() - started2
        status2 = string(termination_status(model))
        if has_values(model)
            decisions = Dict(
                key => round(Int, value(variable))
                for (key, variable) in vars.logical
            )
            return SolveResult(
                method * " + min distance",
                status * "+DIST_" * status2,
                value(expected_expr),
                stage1_bound,
                nodes,
                elapsed,
                decisions,
            )
        end
        # Lần hai không trả nghiệm: giữ nghiệm lần một (đã lưu trong start value).
        decisions = Dict(
            key => round(Int, start_value(variable))
            for (key, variable) in vars.logical
        )
        return SolveResult(method, status * "+DIST_" * status2 * "_KEEP_STAGE1",
            stage1_objective, stage1_bound, nodes, elapsed, decisions)
    end

    # Chuyển giá trị số gần 0/1 thành số nguyên để dễ đọc và dựng tuyến.
    decisions = Dict(
        key => round(Int, value(variable))
        for (key, variable) in vars.logical
    )

    return SolveResult(
        method,
        status,
        stage1_objective,
        stage1_bound,
        nodes,
        elapsed,
        decisions,
    )
end

