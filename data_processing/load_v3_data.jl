if !isdefined(Main, :DebtRoutingData)
    include(joinpath(@__DIR__, "..", "core", "model.jl"))
end

# The required columns in these CSVs contain no quoted commas. Stream the large
# probability and travel tables so INS_XS does not load the entire benchmark.

function load_v3_data(root::AbstractString, instance::AbstractString; scenario="CO_SO")
    csvdir = joinpath(root, "csv")
    instance_row = nothing
    for line in Iterators.drop(eachline(joinpath(csvdir, "thuc_the.csv")), 1)
        fields = split(line, ',')
        if fields[1] == instance
            instance_row = fields
            break
        end
    end
    instance_row === nothing && error("Unknown v3 instance: $instance")
    dataset_id = instance_row[2]
    H = parse(Int, instance_row[5])
    budget_hours = parse(Float64, instance_row[6]) / 60
    max_visits = parse(Int, instance_row[7])

    customers = String[]
    for line in Iterators.drop(eachline(joinpath(csvdir, "thuc_the_khach_hang.csv")), 1)
        fields = split(line, ',')
        fields[1] == instance && push!(customers, fields[2])
    end
    officers = String[]
    for line in Iterators.drop(eachline(joinpath(csvdir, "thuc_the_can_bo.csv")), 1)
        fields = split(line, ',')
        fields[1] == instance && push!(officers, fields[2])
    end
    isempty(customers) && error("No customers for $instance")
    isempty(officers) && error("No officers for $instance")
    customer_index = Dict(id => i for (i, id) in enumerate(customers))
    n, K = length(customers), length(officers)
    debt = zeros(n)
    service_time = zeros(n)
    for line in Iterators.drop(eachline(joinpath(csvdir, "khach_hang.csv")), 1)
        fields = split(line, ',')
        i = get(customer_index, fields[1], 0)
        i == 0 && continue
        debt[i] = parse(Float64, fields[31]) / 1e6
        service_time[i] = parse(Float64, fields[32]) / 60
    end

    probability = fill(NaN, n, H)
    for line in Iterators.drop(eachline(joinpath(csvdir, "xac_suat_thu_hoi.csv")), 1)
        fields = split(line, ',')
        i = get(customer_index, fields[1], 0)
        i == 0 && continue
        fields[2] == scenario || continue
        probability[i, parse(Int, fields[3])] = parse(Float64, fields[5])
    end

    point_index = Dict("CN01" => 1)
    for (i, id) in enumerate(customers)
        point_index[id] = i + 1
    end
    distance = fill(NaN, n + 1, n + 1)
    travel_time = fill(NaN, n + 1, n + 1)
    for line in Iterators.drop(eachline(joinpath(csvdir, "ma_tran_di_chuyen.csv")), 1)
        fields = split(line, ',')
        fields[1] == dataset_id || continue
        i = get(point_index, fields[2], 0)
        j = get(point_index, fields[3], 0)
        (i == 0 || j == 0) && continue
        distance[i, j] = parse(Float64, fields[4])
        travel_time[i, j] = parse(Float64, fields[5]) / 60
    end
    all(isfinite, debt) && all(debt .> 0) || error("Missing customer debt")
    all(isfinite, probability) || error("Incomplete probability table")
    all(isfinite, distance) || error("Incomplete distance matrix")
    all(isfinite, travel_time) || error("Incomplete travel-time matrix")
    data = DebtRoutingData(
        n, K, H, debt, probability, distance, travel_time,
        service_time, fill(budget_hours, K, H), fill(max_visits, n),
    )
    return data, customers
end
