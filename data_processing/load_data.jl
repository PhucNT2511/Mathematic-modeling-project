# Chuyển các CSV đã xử lý thành cấu trúc DebtRoutingData cho mô hình.
if !isdefined(Main, :DebtRoutingData)
    include(joinpath(@__DIR__, "..", "core", "model.jl"))
end

using DelimitedFiles

function load_data(data_directory::AbstractString)
    customer_lines = readlines(joinpath(data_directory, "customers.csv"))
    length(customer_lines) >= 2 || error("customers.csv không có dữ liệu")
    header = split(customer_lines[1], ",")
    column = Dict(name => index for (index, name) in enumerate(header))
    rows = [split(line, ",") for line in customer_lines[2:end] if !isempty(strip(line))]

    probability_columns = sort(
        [name for name in header if startswith(name, "p_day_")];
        by=name -> parse(Int, replace(name, "p_day_" => "")),
    )
    n, H = length(rows), length(probability_columns)
    debt = [parse(Float64, row[column["debt_vnd"]]) for row in rows]
    service_time = [parse(Float64, row[column["service_hours"]]) for row in rows]
    max_visits = [parse(Int, row[column["max_visits"]]) for row in rows]
    probability = [
        parse(Float64, rows[i][column[probability_columns[t]]])
        for i in 1:n, t in 1:H
    ]

    officer_lines = readlines(joinpath(data_directory, "officers.csv"))
    officer_rows = [
        split(line, ",") for line in officer_lines[2:end] if !isempty(strip(line))
    ]
    K = maximum(parse(Int, row[1]) for row in officer_rows)
    daily_budget = zeros(K, H)
    for row in officer_rows
        k, t = parse(Int, row[1]), parse(Int, row[2])
        daily_budget[k, t] = parse(Float64, row[3])
    end

    distance = Matrix{Float64}(readdlm(
        joinpath(data_directory, "distance_matrix_km.csv"), ',', Float64,
    ))
    travel_time = Matrix{Float64}(readdlm(
        joinpath(data_directory, "travel_time_matrix_hours.csv"), ',', Float64,
    ))
    size(distance) == (n + 1, n + 1) || error("Sai kích thước ma trận khoảng cách")
    size(travel_time) == (n + 1, n + 1) || error("Sai kích thước ma trận thời gian")

    return DebtRoutingData(
        n, K, H, debt, probability, distance, travel_time,
        service_time, daily_budget, max_visits,
    )
end
