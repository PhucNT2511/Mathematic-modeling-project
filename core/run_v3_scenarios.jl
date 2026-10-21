include(joinpath(@__DIR__, "alns.jl"))
include(joinpath(@__DIR__, "..", "data_processing", "load_v3_data.jl"))
using JSON
using Random

sample_mean(values) = sum(values) / length(values)
sample_std(values) = sqrt(
    sum((value - sample_mean(values))^2 for value in values) /
    (length(values) - 1),
)
function percentile(values, p)
    sorted = sort(values)
    position = 1 + (length(sorted) - 1) * p
    lower = floor(Int, position)
    upper = ceil(Int, position)
    return sorted[lower] + (position - lower) * (sorted[upper] - sorted[lower])
end

config_path = isempty(ARGS) ?
    normpath(joinpath(@__DIR__, "..", "v3_scenarios.json")) : abspath(ARGS[1])
config = JSON.parsefile(config_path)
instance = String(config["instance"])
sample_count = Int(config["mixed_samples"])
sample_count >= 2 || error("mixed_samples must be at least 2 for a comparison")
seed = Int(config["seed"])
iterations = Int(config["alns_iterations"])
iterations > 0 || error("alns_iterations must be positive")
root = normpath(joinpath(@__DIR__, "..", "collection_routing_dataset_v3"))

base, customer_ids = load_v3_data(root, instance; scenario="CO_SO")
low, _ = load_v3_data(root, instance; scenario="THAP")
high, _ = load_v3_data(root, instance; scenario="CAO")

function with_probability(data, probability)
    return DebtRoutingData(
        data.n, data.K, data.H, data.debt, probability,
        data.distance, data.travel_time, data.service_time,
        data.daily_budget, data.max_visits,
    )
end

function mixed_data(base, low, high, rng)
    # One multiplier per customer for the entire horizon. Interpolate between
    # the dataset's low and high tables, including its probability cap.
    factors = rand(rng, base.n)
    probabilities = similar(base.probability)
    for i in 1:base.n, t in 1:base.H
        probabilities[i, t] = low.probability[i, t] + factors[i] *
            (high.probability[i, t] - low.probability[i, t])
    end
    return with_probability(base, probabilities), factors
end

function solution_genes(result, data)
    genes = zeros(Int, data.n, data.H)
    for i in 1:data.n, k in 1:data.K, t in 1:data.H
        if get(result.decisions, (:y, i, k, t), 0) == 1
            genes[i, t] = k
        end
    end
    return genes
end

function plan_value(genes, data)
    return sum(
        expected_value(data, i, findall(genes[i, :] .> 0))
        for i in 1:data.n
    )
end

cases = [
    ("THAP", low, Float64[], seed),
    ("CO_SO", base, Float64[], seed),
    ("CAO", high, Float64[], seed),
]
for sample in 1:sample_count
    sample_seed = seed + sample
    data, factors = mixed_data(base, low, high, MersenneTwister(sample_seed))
    push!(cases, ("MIX_$(lpad(sample, 3, '0'))", data, factors, sample_seed))
end

# Optimize one plan per case, then evaluate every plan under every case.
# Rows therefore reveal whether a plan tuned to one scenario remains useful
# when customers' probabilities differ independently.
plans = Dict{String,Matrix{Int}}()
run_rows = String[]
for (name, data, _, case_seed) in cases
    println("Optimizing $name on $instance ($(data.n) customers)")
    # Common optimizer seed for the three fixed scenarios. Mixed optimizations
    # use their own seed; the cross-evaluation uses identical mixed draws.
    result = solve_alns(data; iterations=iterations, seed=case_seed)
    genes = solution_genes(result, data)
    plans[name] = genes
    push!(run_rows, "$name,$case_seed,$(result.objective),$(result.elapsed)")
end

outdir = normpath(joinpath(@__DIR__, "..", "results", "v3_$(instance)"))
mkpath(outdir)
open(joinpath(outdir, "optimization.csv"), "w") do io
    println(io, "case,seed,expected_recovery_million_vnd,time_seconds")
    foreach(row -> println(io, row), run_rows)
end
open(joinpath(outdir, "cross_evaluation.csv"), "w") do io
    println(io, "optimized_for,evaluated_on,evaluation_seed,expected_recovery_million_vnd")
    for (plan_name, genes) in sort(collect(plans); by=first)
        for (case_name, data, _, case_seed) in cases
            println(io, "$plan_name,$case_name,$case_seed,$(plan_value(genes, data))")
        end
    end
end
open(joinpath(outdir, "mixed_factors.csv"), "w") do io
    println(io, "case,seed,customer_id,factor_from_low_to_high")
    for (name, _, factors, case_seed) in cases
        isempty(factors) && continue
        for (i, id) in enumerate(customer_ids)
            println(io, "$name,$case_seed,$id,$(factors[i])")
        end
    end
end

# Bootstrap the mean over independently drawn customer-level probability
# scenarios. Paired differences reuse the same draws for both fixed plans.
function bootstrap_ci(values, rng; replicates=2000)
    n = length(values)
    estimates = [sample_mean(values[rand(rng, 1:n, n)]) for _ in 1:replicates]
    return percentile(estimates, 0.025), percentile(estimates, 0.975)
end

mixed_cases = [(name, data) for (name, data, _, _) in cases if startswith(name, "MIX_")]
fixed_names = ("THAP", "CO_SO", "CAO")
scores = Dict(
    name => [plan_value(plans[name], data) for (_, data) in mixed_cases]
    for name in fixed_names
)
reoptimized = [plan_value(plans[name], data) for (name, data) in mixed_cases]
summary_path = joinpath(outdir, "mixed_summary.csv")
bootstrap_rng = MersenneTwister(seed + 1_000_000)
open(summary_path, "w") do io
    println(io, "plan,samples,mean_million_vnd,std_million_vnd,mean_ci95_low,mean_ci95_high,mean_delta_vs_co_so,delta_ci95_low,delta_ci95_high")
    for name in fixed_names
        values = scores[name]
        lower, upper = bootstrap_ci(values, bootstrap_rng)
        delta = values .- scores["CO_SO"]
        delta_lower, delta_upper = bootstrap_ci(delta, bootstrap_rng)
        println(io, "$name,$sample_count,$(sample_mean(values)),$(sample_std(values)),$lower,$upper,$(sample_mean(delta)),$delta_lower,$delta_upper")
    end
    lower, upper = bootstrap_ci(reoptimized, bootstrap_rng)
    println(io, "MIX_REOPT_HEURISTIC,$sample_count,$(sample_mean(reoptimized)),$(sample_std(reoptimized)),$lower,$upper,,,")
end

conclusion_path = joinpath(outdir, "conclusion.txt")
open(conclusion_path, "w") do io
    println(io, "Instance: $instance; mixed samples: $sample_count; ALNS iterations: $iterations")
    println(io, "Each customer has an independent uniform factor between its low and high probabilities, held fixed across days.")
    println(io, "Fixed-plan performance on the same mixed scenarios (million VND):")
    for name in fixed_names
        values = scores[name]
        delta = values .- scores["CO_SO"]
        delta_lower, delta_upper = bootstrap_ci(delta, bootstrap_rng)
        verdict = name == "CO_SO" ? "baseline" :
            delta_lower > 0 ? "higher than CO_SO on these draws" :
            delta_upper < 0 ? "lower than CO_SO on these draws" :
            "no clear difference from CO_SO"
        println(io, "  $name: mean=$(round(sample_mean(values); digits=3)), std=$(round(sample_std(values); digits=3)); paired delta=$(round(sample_mean(delta); digits=3)), bootstrap 95% CI=[$(round(delta_lower; digits=3)), $(round(delta_upper; digits=3))]; $verdict")
    end
    println(io, "Per-MIX ALNS re-optimization mean=$(round(sample_mean(reoptimized); digits=3)); each run uses only $iterations iterations, so this is not an upper bound and can be worse than a fixed plan.")
    println(io, "These are sensitivity results for assumed probabilities, not a prediction of realized collections. ALNS solutions are heuristic, not proven optimal.")
end
println("Saved results: $outdir")
