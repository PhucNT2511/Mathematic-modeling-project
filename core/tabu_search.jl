# Tabu Search on the gene matrix of genetic_algorithm.jl.
if !isdefined(Main, :solve_genetic_algorithm)
    include(joinpath(@__DIR__, "genetic_algorithm.jl"))
end

using Random

# Greedy start: insert visits by w_i p_it / (s_i + round trip from the branch)
# while repair keeps them.
function greedy_tabu_start(data::DebtRoutingData)
    genes = zeros(Int, data.n, data.H)
    candidates = Tuple{Float64,Int,Int,Int}[]

    for i in 1:data.n, t in 1:data.H, k in 1:data.K
        approximate_time = data.service_time[i] +
            data.travel_time[1, i + 1] + data.travel_time[i + 1, 1]
        score = data.debt[i] * data.probability[i, t] /
                max(approximate_time, 1.0e-6)
        push!(candidates, (score, i, t, k))
    end
    sort!(candidates; by=item -> item[1], rev=true)

    for (_, i, t, k) in candidates
        count(genes[i, :] .> 0) >= data.max_visits[i] && continue
        genes[i, t] != 0 && continue
        candidate = copy(genes)
        candidate[i, t] = k
        repair!(candidate, data)
        candidate[i, t] == k && (genes = candidate)
    end
    return genes
end

"""
    solve_tabu_search(data; kwargs...)

A move sets one gene (customer, day) to "no visit" or to another officer. Each
iteration samples `neighborhood_size` moves and takes the best admissible one.
Returning a gene to its previous value is tabu for `tabu_tenure` iterations,
unless the move gives a new best solution. `stagnation_iterations` > 0 stops the
search after that many iterations without a new best.
"""
function solve_tabu_search(
    data::DebtRoutingData;
    iterations::Int=300,
    neighborhood_size::Int=50,
    tabu_tenure::Int=15,
    seed::Int=2026,
    stagnation_iterations::Int=0,
)
    stagnation_iterations >= 0 ||
        throw(ArgumentError("stagnation_iterations must be non-negative"))
    rng = MersenneTwister(seed)
    stagnant = 0
    started = time()

    current_genes = greedy_tabu_start(data)
    current_evaluation = evaluate_ga(current_genes, data)
    best_genes = copy(current_genes)
    best_evaluation = current_evaluation

    # (i, t, value) => last iteration at which assigning value to gene (i, t) is tabu
    tabu_until = Dict{Tuple{Int,Int,Int},Int}()

    for iteration in 1:iterations
        selected_genes = nothing
        selected_evaluation = nothing
        selected_move = nothing

        for _ in 1:neighborhood_size
            i = rand(rng, 1:data.n)
            t = rand(rng, 1:data.H)
            old_value = current_genes[i, t]
            possible_values = [value for value in 0:data.K if value != old_value]
            new_value = rand(rng, possible_values)
            candidate_genes = copy(current_genes)
            candidate_genes[i, t] = new_value
            repair!(candidate_genes, data)

            # Skip the move if repair undid it.
            candidate_genes[i, t] == new_value || continue
            candidate_evaluation = evaluate_ga(candidate_genes, data)

            is_tabu = get(tabu_until, (i, t, new_value), 0) >= iteration
            aspiration = is_better(candidate_evaluation, best_evaluation)
            is_tabu && !aspiration && continue

            if selected_evaluation === nothing ||
               is_better(candidate_evaluation, selected_evaluation)
                selected_genes = candidate_genes
                selected_evaluation = candidate_evaluation
                selected_move = (i, t, old_value)
            end
        end

        selected_genes === nothing && break
        current_genes = selected_genes
        current_evaluation = selected_evaluation

        tabu_until[selected_move] = iteration + tabu_tenure
        for (key, expiry) in collect(tabu_until)
            expiry < iteration && delete!(tabu_until, key)
        end

        if is_better(current_evaluation, best_evaluation)
            best_genes = copy(current_genes)
            best_evaluation = current_evaluation
            stagnant = 0
        else
            stagnant += 1
        end
        stagnation_iterations > 0 && stagnant >= stagnation_iterations && break
    end

    return SolveResult(
        "Tabu Search",
        "HEURISTIC",
        best_evaluation.expected_recovery,
        NaN,
        0,
        time() - started,
        ga_decisions(best_genes, best_evaluation.routes, data),
    )
end
