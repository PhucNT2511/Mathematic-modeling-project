# Standalone Simulated Annealing using the same representation and evaluation as GA.
if !isdefined(Main, :solve_genetic_algorithm)
    include(joinpath(@__DIR__, "genetic_algorithm.jl"))
end
if !isdefined(Main, :greedy_tabu_start)
    include(joinpath(@__DIR__, "tabu_search.jl"))
end

using Random

# Normalize recovery so temperature parameters remain comparable across instances.
# Distance is a small tie-breaking penalty, as in the ALNS acceptance score.
function sa_score(evaluation::GAEvaluation, data::DebtRoutingData)
    return evaluation.expected_recovery / sum(data.debt) -
           1.0e-4 * evaluation.total_distance
end

# Propose one feasible single-gene neighbor. Gene (i,t) is zero for no visit or
# is the officer assigned to customer i on day t.
function random_sa_neighbor(current_genes, data::DebtRoutingData, rng; max_attempts=20)
    for _ in 1:max_attempts
        customer = rand(rng, 1:data.n)
        day = rand(rng, 1:data.H)
        old_value = current_genes[customer, day]
        possible_values = [value for value in 0:data.K if value != old_value]
        new_value = rand(rng, possible_values)

        candidate_genes = copy(current_genes)
        candidate_genes[customer, day] = new_value
        repair!(candidate_genes, data)

        # Ignore a proposal when repair reverses the requested move.
        candidate_genes[customer, day] == new_value || continue
        return candidate_genes
    end
    return nothing
end

"""
Solve approximately with standalone Simulated Annealing.

Each iteration samples one feasible single-gene neighbor. A better score is
always accepted; a worse score is accepted with probability exp(delta / T).
Temperature follows geometric cooling: T_r = T_0 * cooling_rate^r.
"""
function solve_simulated_annealing(
    data::DebtRoutingData;
    iterations::Int=2000,
    initial_temperature::Float64=0.05,
    cooling_rate::Float64=0.995,
    seed::Int=2026,
)
    iterations > 0 || throw(ArgumentError("iterations must be positive"))
    initial_temperature > 0 ||
        throw(ArgumentError("initial_temperature must be positive"))
    0.0 < cooling_rate <= 1.0 ||
        throw(ArgumentError("cooling_rate must be in (0, 1]"))

    rng = MersenneTwister(seed)
    started = time()

    # The same greedy start as Tabu isolates the effect of their acceptance rules.
    current_genes = greedy_tabu_start(data)
    current_evaluation = evaluate_ga(current_genes, data)
    best_genes = copy(current_genes)
    best_evaluation = current_evaluation
    temperature = initial_temperature

    for _ in 1:iterations
        candidate_genes = random_sa_neighbor(current_genes, data, rng)
        if candidate_genes !== nothing
            candidate_evaluation = evaluate_ga(candidate_genes, data)
            delta = sa_score(candidate_evaluation, data) -
                    sa_score(current_evaluation, data)

            # Early on, accepting an inferior neighbor can escape a local optimum.
            accepted = delta >= 0.0 ||
                rand(rng) < exp(delta / max(temperature, 1.0e-12))
            if accepted
                current_genes = candidate_genes
                current_evaluation = candidate_evaluation
                if is_better(current_evaluation, best_evaluation)
                    best_genes = copy(current_genes)
                    best_evaluation = current_evaluation
                end
            end
        end
        temperature *= cooling_rate
    end

    return SolveResult(
        "Simulated Annealing",
        "HEURISTIC",
        best_evaluation.expected_recovery,
        NaN,
        0,
        time() - started,
        ga_decisions(best_genes, best_evaluation.routes, data),
    )
end
