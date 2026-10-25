if !isdefined(Main, :DebtRoutingData)
    include(joinpath(@__DIR__, "..", "core", "model.jl"))
end

# Reader for the v3 CSV tables, by column name. Some quoted cells contain commas,
# so lines are split with csv_fields (RFC 4180, no line breaks inside cells) rather
# than split(line, ','). Tables are streamed, so a small instance does not load the
# whole travel matrix.

"""Split one CSV line, handling quoted cells and "" escapes."""
function csv_fields(line::AbstractString)
    fields = String[]
    buf = IOBuffer()
    inquote = false
    chars = collect(line)
    i = 1
    while i <= length(chars)
        c = chars[i]
        if inquote
            if c == '"'
                if i < length(chars) && chars[i + 1] == '"'
                    write(buf, '"'); i += 1
                else
                    inquote = false
                end
            else
                write(buf, c)
            end
        elseif c == '"'
            inquote = true
        elseif c == ','
            push!(fields, String(take!(buf)))
        else
            write(buf, c)
        end
        i += 1
    end
    inquote && error("Unterminated quoted field in CSV line: $line")
    push!(fields, String(take!(buf)))
    return fields
end

"""Open a v3 table; return (column index by name, iterator over data rows)."""
function v3_table(csvdir::AbstractString, name::AbstractString, required)
    path = joinpath(csvdir, name * ".csv")
    lines = eachline(path)
    header_line, state = iterate(lines)
    header = csv_fields(replace(header_line, "﻿" => ""))   # strip the UTF-8 BOM
    col = Dict(h => i for (i, h) in enumerate(header))
    missing_cols = [c for c in required if !haskey(col, c)]
    isempty(missing_cols) || error("$name.csv is missing columns: $(join(missing_cols, ", "))")
    ncol = length(header)
    rows = Iterators.map(Iterators.filter(!isempty, Iterators.rest(lines, state))) do line
        f = csv_fields(line)
        length(f) == ncol || error("$name.csv: expected $ncol fields, got $(length(f)) in line: $line")
        f
    end
    return col, rows
end

function load_v3_data(root::AbstractString, instance::AbstractString; scenario="CO_SO")
    csvdir = joinpath(root, "csv")

    col, rows = v3_table(csvdir, "thuc_the",
        ["thuc_the_id", "bo_khach_hang_id", "so_ngay", "phut_lam_viec_ngay", "m_mac_dinh"])
    instance_row = nothing
    for f in rows
        if f[col["thuc_the_id"]] == instance
            instance_row = f
            break
        end
    end
    instance_row === nothing && error("Unknown v3 instance: $instance")
    dataset_id = instance_row[col["bo_khach_hang_id"]]
    H = parse(Int, instance_row[col["so_ngay"]])
    budget_hours = parse(Float64, instance_row[col["phut_lam_viec_ngay"]]) / 60
    max_visits = parse(Int, instance_row[col["m_mac_dinh"]])

    customers = String[]
    col, rows = v3_table(csvdir, "thuc_the_khach_hang", ["thuc_the_id", "khach_hang_id"])
    for f in rows
        f[col["thuc_the_id"]] == instance && push!(customers, f[col["khach_hang_id"]])
    end
    officers = String[]
    col, rows = v3_table(csvdir, "thuc_the_can_bo", ["thuc_the_id", "can_bo_id"])
    for f in rows
        f[col["thuc_the_id"]] == instance && push!(officers, f[col["can_bo_id"]])
    end
    isempty(customers) && error("No customers for $instance")
    isempty(officers) && error("No officers for $instance")
    customer_index = Dict(id => i for (i, id) in enumerate(customers))
    n, K = length(customers), length(officers)

    debt = fill(NaN, n)
    service_time = fill(NaN, n)
    col, rows = v3_table(csvdir, "khach_hang",
        ["khach_hang_id", "so_tien_muc_tieu_vnd", "thoi_gian_phuc_vu_phut"])
    for f in rows
        i = get(customer_index, f[col["khach_hang_id"]], 0)
        i == 0 && continue
        debt[i] = parse(Float64, f[col["so_tien_muc_tieu_vnd"]]) / 1e6      # million VND
        service_time[i] = parse(Float64, f[col["thoi_gian_phuc_vu_phut"]]) / 60  # hours
    end

    probability = fill(NaN, n, H)
    col, rows = v3_table(csvdir, "xac_suat_thu_hoi",
        ["khach_hang_id", "kich_ban_p", "ngay_thu", "p_thu_hoi"])
    for f in rows
        f[col["kich_ban_p"]] == scenario || continue
        i = get(customer_index, f[col["khach_hang_id"]], 0)
        i == 0 && continue
        probability[i, parse(Int, f[col["ngay_thu"]])] = parse(Float64, f[col["p_thu_hoi"]])
    end

    point_index = Dict("CN01" => 1)
    for (i, id) in enumerate(customers)
        point_index[id] = i + 1
    end
    distance = fill(NaN, n + 1, n + 1)
    travel_time = fill(NaN, n + 1, n + 1)
    col, rows = v3_table(csvdir, "ma_tran_di_chuyen",
        ["bo_khach_hang_id", "tu_id", "den_id", "khoang_cach_km", "thoi_gian_phut"])
    for f in rows
        f[col["bo_khach_hang_id"]] == dataset_id || continue
        i = get(point_index, f[col["tu_id"]], 0)
        j = get(point_index, f[col["den_id"]], 0)
        (i == 0 || j == 0) && continue
        distance[i, j] = parse(Float64, f[col["khoang_cach_km"]])
        travel_time[i, j] = parse(Float64, f[col["thoi_gian_phut"]]) / 60     # hours
    end

    all(isfinite, debt) && all(debt .> 0) || error("Missing customer debt")
    # Service times are 15-30 minutes by design; anything else means a misread column.
    all(x -> isfinite(x) && 0.25 - 1e-9 <= x <= 0.5 + 1e-9, service_time) ||
        error("Service time outside 15–30 minutes; check column parsing")
    all(isfinite, probability) || error("Incomplete probability table")
    all(x -> 0 < x < 1, probability) || error("Probability outside (0, 1)")
    all(isfinite, distance) || error("Incomplete distance matrix")
    all(isfinite, travel_time) || error("Incomplete travel-time matrix")
    data = DebtRoutingData(
        n, K, H, debt, probability, distance, travel_time,
        service_time, fill(budget_hours, K, H), fill(max_visits, n),
    )
    return data, customers
end
