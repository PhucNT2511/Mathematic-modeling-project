using JuMP
using HiGHS
import MathOptInterface as MOI
using Printf

# Cấu trúc lưu toàn bộ dữ liệu đầu vào của một instance.
# Ma trận khoảng cách và thời gian có kích thước (n+1)x(n+1);
# hàng/cột 1 trong Julia tương ứng với chi nhánh có chỉ số toán học 0.
struct DebtRoutingData
    n::Int
    K::Int
    H::Int
    debt::Vector{Float64}
    probability::Matrix{Float64}
    distance::Matrix{Float64}
    travel_time::Matrix{Float64}
    service_time::Vector{Float64}
    daily_budget::Matrix{Float64}
    max_visits::Vector{Int}
end

# Liệt kê mọi tập ngày không rỗng có nhiều nhất R lần thăm.
# Mỗi bit của mask biểu diễn việc một ngày có thuộc lịch hay không.
function visit_schedules(H::Int, R::Int)
    schedules = Vector{Vector{Int}}()
    for mask in 1:(2^H - 1)
        days = [t for t in 1:H if ((mask >> (t - 1)) & 1) == 1]
        length(days) <= R && push!(schedules, days)
    end
    return schedules
end

# Giá trị thu hồi kỳ vọng nếu khách hàng i được thăm theo schedule.
# Biểu thức được tính trước nên hệ số mục tiêu vẫn là tuyến tính.
expected_value(data, i, schedule) =
    data.debt[i] * (1.0 - prod((1.0 - data.probability[i, t] for t in schedule); init=1.0))

function logical_variable(model, name, integer_variables)
    variable = @variable(
        model,
        lower_bound=0.0,
        upper_bound=1.0,
        base_name=name,
    )
    integer_variables && set_binary(variable)
    return variable
end

# Dựng một mô hình dùng chung cho cả hai phương pháp:
# - integer_variables=true: dựng MILP cho Branch-and-Cut;
# - integer_variables=false: dựng LP relaxation cho Branch-and-Bound tự viết.
function build_model(
    data::DebtRoutingData;
    integer_variables::Bool,
    time_limit::Float64=300.0,
    mip_gap::Float64=1.0e-4,
)
    model = Model(HiGHS.Optimizer)
    set_silent(model)
    set_attribute(model, "time_limit", time_limit)
    integer_variables && set_attribute(model, "mip_rel_gap", mip_gap)

    n, K, H = data.n, data.K, data.H
    N, V = 1:n, 0:n
    schedules = Dict(i => visit_schedules(H, data.max_visits[i]) for i in N)

    # x: cung di chuyển; y: phân công; z: sử dụng cán bộ;
    # lambda: chọn lịch thăm; u: thứ tự MTZ.
    x = Dict{NTuple{4,Int},VariableRef}()
    y = Dict{NTuple{3,Int},VariableRef}()
    z = Dict{NTuple{2,Int},VariableRef}()
    lambda = Dict{Tuple{Int,Int},VariableRef}()
    u = Dict{NTuple{3,Int},VariableRef}()
    logical = Dict{Tuple,VariableRef}()

    # Khai báo biến cung x(i,j,k,t).
    for i in V, j in V, k in 1:K, t in 1:H
        i == j && continue
        v = logical_variable(model, "x_$(i)_$(j)_$(k)_$(t)", integer_variables)
        x[(i, j, k, t)] = v
        logical[(:x, i, j, k, t)] = v
    end
    # Khai báo biến thăm y(i,k,t) và biến thứ tự u(i,k,t).
    for i in N, k in 1:K, t in 1:H
        v = logical_variable(model, "y_$(i)_$(k)_$(t)", integer_variables)
        y[(i, k, t)] = v
        logical[(:y, i, k, t)] = v
        u[(i, k, t)] = @variable(
            model,
            lower_bound=0.0,
            base_name="u_$(i)_$(k)_$(t)",
        )
    end
    # Khai báo z(k,t): cán bộ k có ra ngoài làm việc trong ngày t.
    for k in 1:K, t in 1:H
        v = logical_variable(model, "z_$(k)_$(t)", integer_variables)
        z[(k, t)] = v
        logical[(:z, k, t)] = v
    end
    # Khai báo lambda(i,s): khách hàng i chọn lịch s.
    for i in N, s in eachindex(schedules[i])
        v = logical_variable(model, "lambda_$(i)_$(s)", integer_variables)
        lambda[(i, s)] = v
        logical[(:lambda, i, s)] = v
    end

    # (1) Tối đa hóa tổng giá trị khoản nợ thu hồi kỳ vọng.
    @objective(
        model,
        Max,
        sum(
            expected_value(data, i, schedules[i][s]) * lambda[(i, s)]
            for i in N for s in eachindex(schedules[i])
        ),
    )

    # (2) Mỗi khách hàng được chọn nhiều nhất một lịch thăm.
    for i in N
        @constraint(model, sum(lambda[(i, s)] for s in eachindex(schedules[i])) <= 1)
    end
    # (3) Nếu lịch chứa ngày t thì đúng một cán bộ phải thăm khách hàng.
    for i in N, t in 1:H
        @constraint(
            model,
            sum(y[(i, k, t)] for k in 1:K) ==
            sum(
                (t in schedules[i][s] ? 1.0 : 0.0) * lambda[(i, s)]
                for s in eachindex(schedules[i])
            ),
        )
    end
    # (4)-(5) Tuyến được sử dụng phải xuất phát và kết thúc ở chi nhánh.
    for k in 1:K, t in 1:H
        @constraint(model, sum(x[(0, j, k, t)] for j in N) == z[(k, t)])
        @constraint(model, sum(x[(i, 0, k, t)] for i in N) == z[(k, t)])
    end
    # (6)-(7) Mỗi khách hàng được thăm có đúng một cung vào và một cung ra.
    for i in N, k in 1:K, t in 1:H
        @constraint(model, sum(x[(i, j, k, t)] for j in V if j != i) == y[(i, k, t)])
        @constraint(model, sum(x[(j, i, k, t)] for j in V if j != i) == y[(i, k, t)])
    end
    # (8) Tổng thời gian di chuyển và phục vụ không vượt ngân sách ngày.
    for k in 1:K, t in 1:H
        @constraint(
            model,
            sum(
                data.travel_time[i + 1, j + 1] * x[(i, j, k, t)]
                for i in V for j in V if i != j
            ) +
            sum(data.service_time[i] * y[(i, k, t)] for i in N)
            <= data.daily_budget[k, t] * z[(k, t)],
        )
    end
    # (9)-(10) MTZ loại chu trình con không đi qua chi nhánh.
    # Biến u bằng 0 khi khách hàng không được chọn.
    for i in N, k in 1:K, t in 1:H
        @constraint(model, y[(i, k, t)] <= u[(i, k, t)])
        @constraint(model, u[(i, k, t)] <= n * y[(i, k, t)])
    end
    for i in N, j in N, k in 1:K, t in 1:H
        i == j && continue
        @constraint(
            model,
            u[(i, k, t)] - u[(j, k, t)] + n * x[(i, j, k, t)]
            <= n - 1 + n * (1 - y[(j, k, t)]),
        )
    end

    return model, (
        x=x, y=y, z=z, lambda=lambda, u=u,
        logical=logical, schedules=schedules,
    )
end

struct SolveResult
    method::String
    status::String
    objective::Float64
    bound::Float64
    nodes::Int
    elapsed::Float64
    decisions::Dict{Tuple,Int}
end

# Khôi phục thứ tự các tuyến từ các biến cung x có giá trị bằng 1.
function selected_routes(data::DebtRoutingData, result::SolveResult)
    routes = Dict{Tuple{Int,Int},Vector{Int}}()
    for k in 1:data.K, t in 1:data.H
        get(result.decisions, (:z, k, t), 0) == 0 && continue
        route = [0]
        current = 0
        visited = Set{Int}()
        while true
            next_location = nothing
            for j in 0:data.n
                j == current && continue
                if get(result.decisions, (:x, current, j, k, t), 0) == 1
                    next_location = j
                    break
                end
            end
            next_location === nothing && break
            push!(route, next_location)
            next_location == 0 && break
            next_location in visited && break
            push!(visited, next_location)
            current = next_location
        end
        routes[(k, t)] = route
    end
    return routes
end

# In thống kê thuật toán và tuyến của từng cán bộ trong từng ngày.
function print_result(data::DebtRoutingData, result::SolveResult)
    println("\n", result.method)
    println("  Status:    ", result.status)
    @printf("  Objective: %.4f\n", result.objective)
    isfinite(result.bound) && @printf("  Bound:     %.4f\n", result.bound)
    result.nodes > 0 && println("  LP nodes:  ", result.nodes)
    @printf("  Time:      %.3f seconds\n", result.elapsed)
    for ((k, t), route) in sort(collect(selected_routes(data, result)))
        println("  Officer $k, day $t: ", join(route, " -> "))
    end
end
