# Nạp riêng hai phương pháp. File đầu tiên sẽ tự nạp model.jl.
include(joinpath(@__DIR__, "branch_and_bound.jl"))
include(joinpath(@__DIR__, "branch_and_cut.jl"))
include(joinpath(@__DIR__, "..", "data_processing", "sample_data.jl"))

# Giữ instance nhỏ vì Branch-and-Bound tự cài đặt chưa có các tăng tốc
# như presolve, cutting planes và primal heuristics của solver.
data = sample_data(n=4, K=1, H=2, seed=2026)
println("Instance: $(data.n) customers, $(data.K) officers, $(data.H) days")

bnb = solve_branch_and_bound(data; max_nodes=20_000, time_limit=120.0)
print_result(data, bnb)

bnc = solve_branch_and_cut(data; time_limit=120.0, mip_gap=1.0e-4)
print_result(data, bnc)

if isfinite(bnb.objective) && isfinite(bnc.objective)
    println("\nAbsolute objective difference: ", abs(bnb.objective - bnc.objective))
end
