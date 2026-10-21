# Dữ liệu rất nhỏ chỉ dùng để kiểm tra và so sánh hai thuật toán.
if !isdefined(Main, :DebtRoutingData)
    include(joinpath(@__DIR__, "..", "core", "model.jl"))
end

using Random

# Sinh dữ liệu Euclid có seed để mỗi lần kiểm thử cho cùng một kết quả.
function sample_data(; n=8, K=2, H=3, seed=2026)
    rng = MersenneTwister(seed)
    coordinates = 20.0 .* rand(rng, n + 1, 2)
    distance = zeros(n + 1, n + 1)
    for i in 1:(n + 1), j in 1:(n + 1)
        distance[i, j] = hypot(
            coordinates[i, 1] - coordinates[j, 1],
            coordinates[i, 2] - coordinates[j, 2],
        )
    end
    return DebtRoutingData(
        n,
        K,
        H,
        Float64.(rand(rng, 30:120, n)),
        0.20 .+ 0.55 .* rand(rng, n, H),
        distance,
        distance ./ 25.0,
        0.25 .+ 0.25 .* rand(rng, n),
        fill(4.0, K, H),
        fill(min(2, H), n),
    )
end
