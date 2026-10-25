if !isdefined(Main, :DebtRoutingData)
    include(joinpath(@__DIR__, "..", "core", "model.jl"))
end
if !isdefined(Main, :v3_table)
    include(joinpath(@__DIR__, "load_v3_data.jl"))
end

"""Read common random draws for selected Monte Carlo scenarios and customers."""
function load_v3_draws(root, customer_ids, horizon, scenario_ids)
    customer_index = Dict(id => i for (i, id) in enumerate(customer_ids))
    draws = Dict(id => fill(NaN, length(customer_ids), horizon) for id in scenario_ids)
    col, rows = v3_table(joinpath(root, "csv"), "kich_ban_monte_carlo",
        ["kich_ban_id", "khach_hang_id", "ngay_thu", "u"])
    for fields in rows
        id = parse(Int, fields[col["kich_ban_id"]])
        haskey(draws, id) || continue
        i = get(customer_index, fields[col["khach_hang_id"]], 0)
        i == 0 && continue
        t = parse(Int, fields[col["ngay_thu"]])
        1 <= t <= horizon || continue
        isnan(draws[id][i, t]) || error("Duplicate Monte Carlo draw: $id, $(fields[col["khach_hang_id"]]), $t")
        draws[id][i, t] = parse(Float64, fields[col["u"]])
    end
    for (id, values) in draws
        all(x -> isfinite(x) && 0 <= x <= 1, values) ||
            error("Missing or invalid Monte Carlo draws for scenario $id")
    end
    return draws
end

"""Make the residual routing problem after prior days' payments and visits.

`lookahead = nothing` keeps all remaining days (rolling horizon); `1` keeps only
the current day (myopic).
"""
function remaining_v3_data(data::DebtRoutingData, paid, attempts, day;
                           lookahead::Union{Nothing,Int}=nothing)
    1 <= day <= data.H || error("Day outside planning horizon")
    active = [i for i in 1:data.n if !paid[i] && attempts[i] < data.max_visits[i]]
    nodes = [1; active .+ 1]
    last_day = lookahead === nothing ? data.H : min(data.H, day + lookahead - 1)
    H = last_day - day + 1
    residual = DebtRoutingData(
        length(active), data.K, H,
        data.debt[active], data.probability[active, day:last_day],
        data.distance[nodes, nodes], data.travel_time[nodes, nodes],
        data.service_time[active], data.daily_budget[:, day:last_day],
        min.(data.max_visits[active] .- attempts[active], H),
    )
    return residual, active
end
