# So sánh GA, Tabu Search và Branch-and-Cut trên cùng một instance.
include(joinpath(@__DIR__, "branch_and_cut.jl"))
include(joinpath(@__DIR__, "genetic_algorithm.jl"))
include(joinpath(@__DIR__, "tabu_search.jl"))
include(joinpath(@__DIR__, "simulated_annealing.jl"))
include(joinpath(@__DIR__, "alns.jl"))
include(joinpath(@__DIR__, "hill_climbing.jl"))
include(joinpath(@__DIR__, "rl_alns.jl"))
include(joinpath(@__DIR__, "..", "data_processing", "load_data.jl"))
include(joinpath(@__DIR__, "..", "data_processing", "data_profiles.jl"))
using JSON

config_path = get(
    ENV,
    "CONFIG_FILE",
    normpath(joinpath(@__DIR__, "..", "config.json")),
)
isfile(config_path) || error("Config file not found: $config_path")
config = JSON.parsefile(config_path)

config_value(key, default) = get(config, key, default)
data_profile = normalize_data_profile(
    get(ENV, "DATA_PROFILE", string(config_value("data_profile", "n40"))),
)
random_seed = Int(config_value("seed", 2026))
data_directory = profile_directory(data_profile)
if !isdir(data_directory)
    Bool(config_value("generate_if_missing", true)) || error(
        "Data profile '$data_profile' has not been generated. Run generate_data.jl first.",
    )
    include(joinpath(@__DIR__, "..", "data_processing", "generate_data.jl"))
    generate_named_profile(data_profile, random_seed)
end
data = load_data(data_directory)
println("Config: $config_path")
println("Data profile: $data_profile")
println("Instance: $(data.n) customers, $(data.K) officers, $(data.H) days")

# Profile large giảm ngân sách tính toán để benchmark không kéo dài quá mức.
# PowerShell: $env:BENCHMARK_PROFILE = "large"
# CMD:        set BENCHMARK_PROFILE=large
requested_profile = lowercase(get(
    ENV,
    "BENCHMARK_PROFILE",
    string(config_value("benchmark_profile", "auto")),
))
profile = requested_profile == "auto" ? automatic_benchmark_profile(data.n) : requested_profile
profile in ("standard", "large", "xlarge") || error(
    "BENCHMARK_PROFILE must be auto, standard, large, or xlarge",
)
large_profile = profile in ("large", "xlarge")
xlarge_profile = profile == "xlarge"
println("Benchmark profile: $profile")

ga = solve_genetic_algorithm(
    data;
    population_size=xlarge_profile ? 80 : large_profile ? 90 : 100,
    generations=xlarge_profile ? 500 : large_profile ? 750 : 1000,
    stagnation_generations=xlarge_profile ? 75 : large_profile ? 100 : 150,
    mutation_rate=0.03,
    elite_count=4,
    seed=random_seed,
)
print_result(data, ga)

tabu = solve_tabu_search(
    data;
    iterations=xlarge_profile ? 120 : large_profile ? 200 : 300,
    neighborhood_size=xlarge_profile ? 30 : large_profile ? 40 : 50,
    tabu_tenure=15,
    seed=random_seed,
)
print_result(data, tabu)

sa = solve_simulated_annealing(
    data;
    iterations=xlarge_profile ? 1000 : large_profile ? 1500 : 2000,
    initial_temperature=0.05,
    cooling_rate=0.995,
    seed=random_seed,
)
print_result(data, sa)

alns = solve_alns(
    data;
    iterations=xlarge_profile ? 180 : large_profile ? 300 : 500,
    destroy_fraction=0.20,
    segment_length=25,
    reaction_factor=0.20,
    cooling_rate=0.995,
    seed=random_seed,
)
print_result(data, alns)

hill = solve_hill_climbing(
    data;
    restarts=xlarge_profile ? 1 : large_profile ? 2 : 8,
    max_iterations=xlarge_profile ? 30 : large_profile ? 60 : 200,
    seed=random_seed,
)
print_result(data, hill)

rl_alns = solve_rl_alns(
    data;
    episodes=xlarge_profile ? 4 : large_profile ? 6 : 12,
    steps_per_episode=xlarge_profile ? 50 : large_profile ? 60 : 100,
    destroy_fraction=0.20,
    alpha=0.20,
    gamma=0.90,
    epsilon_start=0.90,
    epsilon_end=0.05,
    seed=random_seed,
)
print_result(data, rl_alns)

exact_time_limit = parse(Float64, get(
    ENV,
    "EXACT_TIME_LIMIT",
    string(config_value("exact_time_limit_seconds", 300)),
))
exact = solve_branch_and_cut(
    data;
    time_limit=exact_time_limit,
    mip_gap=1.0e-4,
)
print_result(data, exact)

println("\nSummary")
println("Method                    Objective          Time (s)      Gap (%)")
results = (ga, tabu, sa, alns, hill, rl_alns, exact)
reference_bound = isfinite(exact.bound) ?
    exact.bound :
    maximum(result.objective for result in results if isfinite(result.objective))
for result in results
    gap = 100.0 * (reference_bound - result.objective) / reference_bound
    println(
        rpad(result.method, 25),
        lpad(round(result.objective; digits=2), 18),
        lpad(round(result.elapsed; digits=3), 16),
        lpad(round(gap; digits=4), 14),
    )
end

# Lưu bảng để có thể phân tích lại mà không cần chụp toàn bộ terminal.
results_directory = normpath(joinpath(@__DIR__, "..", "results"))
mkpath(results_directory)
results_file = joinpath(results_directory, "comparison_$(data_profile).csv")
open(results_file, "w") do io
    println(io, "method,status,objective,time_seconds,gap_percent")
    for result in results
        gap = 100.0 * (reference_bound - result.objective) / reference_bound
        println(
            io,
            "$(result.method),$(result.status),$(result.objective)," *
            "$(result.elapsed),$gap",
        )
    end
end
println("\nSaved summary: $results_file")
