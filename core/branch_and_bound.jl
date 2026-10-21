# Nạp dữ liệu và hàm dựng mô hình nếu file này được chạy độc lập.
if !isdefined(Main, :DebtRoutingData)
    include(joinpath(@__DIR__, "model.jl"))
end

"""
Giải MILP bằng thuật toán Branch-and-Bound tự cài đặt.

Ý tưởng:
1. Thư giãn mọi biến nhị phân thành biến liên tục trong đoạn [0, 1].
2. Giải LP relaxation để thu được cận trên vì đây là bài toán cực đại.
3. Nếu nghiệm LP nguyên, dùng nó để cập nhật nghiệm nguyên tốt nhất.
4. Nếu nghiệm phân số, chọn biến phân số nhất và tạo hai nhánh 0/1.
5. Loại một nút nếu cận trên của nó không tốt hơn nghiệm hiện có.

Đầu vào:
- data: dữ liệu bài toán.
- max_nodes: số nút LP tối đa được phép xét.
- time_limit: thời gian chạy tối đa, tính bằng giây.
- tolerance: sai số dùng khi kiểm tra tính nguyên và so sánh cận.

Đầu ra là một SolveResult chứa trạng thái, giá trị mục tiêu, số nút,
thời gian chạy và các quyết định nhị phân tốt nhất tìm được.
"""
function solve_branch_and_bound(
    data::DebtRoutingData;
    max_nodes::Int=20_000,
    time_limit::Float64=300.0,
    tolerance::Float64=1.0e-6,
)
    started = time()

    # Nghiệm incumbent là nghiệm nguyên tốt nhất đã tìm được.
    incumbent = -Inf
    best_decisions = Dict{Tuple,Int}()
    explored = 0

    # Mỗi nút lưu một tập các biến đã bị cố định bằng 0 hoặc 1.
    # Danh sách hoạt động như stack nên thuật toán duyệt theo chiều sâu.
    stack = [Dict{Tuple,Int}()]

    while !isempty(stack) && explored < max_nodes && time() - started < time_limit
        fixed_values = pop!(stack)
        remaining_time = max(1.0, time_limit - (time() - started))

        # Dựng LP relaxation: các biến logic chỉ bị chặn trong [0, 1].
        model, vars = build_model(
            data;
            integer_variables=false,
            time_limit=remaining_time,
        )

        # Áp dụng các quyết định phân nhánh của nút hiện tại.
        for (key, fixed_value) in fixed_values
            fix(vars.logical[key], fixed_value; force=true)
        end

        # HiGHS dùng thuật toán LP để giải bài toán thư giãn.
        optimize!(model)
        explored += 1

        # Nút không có nghiệm khả thi hoặc không được giải tối ưu sẽ bị loại.
        termination_status(model) == MOI.OPTIMAL || continue

        # Với bài toán cực đại, giá trị LP relaxation là cận trên của nút.
        lp_bound = objective_value(model)
        lp_bound <= incumbent + tolerance && continue

        # Chọn biến gần 0.5 nhất, tức biến có mức phân số lớn nhất.
        branch_key = nothing
        highest_fractionality = tolerance
        for (key, variable) in vars.logical
            variable_value = value(variable)
            fractionality = min(variable_value, 1.0 - variable_value)
            if fractionality > highest_fractionality
                highest_fractionality = fractionality
                branch_key = key
            end
        end

        if branch_key === nothing
            # Không còn biến phân số: nghiệm LP hiện tại là nghiệm MILP hợp lệ.
            incumbent = lp_bound
            best_decisions = Dict(
                key => round(Int, value(variable))
                for (key, variable) in vars.logical
            )
        else
            # Nhánh trái cố định biến được chọn bằng 0.
            child_zero = copy(fixed_values)
            child_zero[branch_key] = 0
            push!(stack, child_zero)

            # Nhánh phải cố định biến được chọn bằng 1.
            # Vì được đưa vào stack sau, nhánh 1 sẽ được xét trước.
            child_one = copy(fixed_values)
            child_one[branch_key] = 1
            push!(stack, child_one)
        end
    end

    # Chỉ kết luận tối ưu khi không còn nút nào chưa được xét.
    complete = isempty(stack)
    status = !isfinite(incumbent) ? "NO_INTEGER_SOLUTION" :
             complete ? "OPTIMAL" : "LIMIT_REACHED"

    # Bản minh họa không lưu cận của toàn bộ các nút đang mở.
    # Vì vậy nếu dừng sớm thì bound được trả về là NaN.
    return SolveResult(
        "Custom Branch-and-Bound",
        status,
        incumbent,
        complete ? incumbent : NaN,
        explored,
        time() - started,
        best_decisions,
    )
end

