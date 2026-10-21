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
)
    # Dựng mô hình với các biến x, y, z và lambda là biến nhị phân.
    model, vars = build_model(
        data;
        integer_variables=true,
        time_limit=time_limit,
        mip_gap=mip_gap,
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

    # A zero-route incumbent is feasible but useless when a better heuristic
    # route is known. Keep its provenance explicit in the returned status.
    if initial_result !== nothing &&
       (!has_values(model) || objective_value(model) + 1.0e-5 < initial_result.objective)
        return SolveResult(
            "HiGHS Branch-and-Cut (heuristic fallback)",
            status * "_HEURISTIC_FALLBACK",
            initial_result.objective,
            objective_bound(model),
            0,
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
            0,
            elapsed,
            Dict{Tuple,Int}(),
        )
    end

    # Chuyển giá trị số gần 0/1 thành số nguyên để dễ đọc và dựng tuyến.
    decisions = Dict(
        key => round(Int, value(variable))
        for (key, variable) in vars.logical
    )

    return SolveResult(
        "HiGHS Branch-and-Cut",
        status,
        objective_value(model),
        objective_bound(model),
        0,
        elapsed,
        decisions,
    )
end

