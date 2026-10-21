using Random
using Downloads
using JSON
using DelimitedFiles
using Dates

if !isdefined(Main, :DATA_PROFILES)
    include(joinpath(@__DIR__, "data_profiles.jl"))
end

# Chi nhánh mẫu gần khu vực Hoàn Kiếm, Hà Nội.
const DEPOT_LATITUDE = 21.0285
const DEPOT_LONGITUDE = 105.8542

# Hộp tọa độ gần đúng bao phủ khu vực đô thị Hà Nội.
const MIN_LATITUDE = 20.950
const MAX_LATITUDE = 21.100
const MIN_LONGITUDE = 105.750
const MAX_LONGITUDE = 105.950
const OSRM_TABLE_ENDPOINT = "https://router.project-osrm.org/table/v1/driving/"

# Khoảng cách đường chim bay Haversine, đơn vị km.
function haversine_km(lat1, lon1, lat2, lon2)
    earth_radius = 6371.0088
    phi1, phi2 = deg2rad(lat1), deg2rad(lat2)
    delta_phi = deg2rad(lat2 - lat1)
    delta_lambda = deg2rad(lon2 - lon1)
    a = sin(delta_phi / 2)^2 +
        cos(phi1) * cos(phi2) * sin(delta_lambda / 2)^2
    return 2 * earth_radius * asin(sqrt(a))
end

# Dự phòng: hệ số đường vòng 1.30 và vận tốc giả định 25 km/h.
function fallback_matrices(latitude, longitude)
    count = length(latitude)
    distance = zeros(count, count)
    duration = zeros(count, count)
    for i in 1:count, j in 1:count
        distance[i, j] = 1.30 * haversine_km(
            latitude[i], longitude[i], latitude[j], longitude[j],
        )
        duration[i, j] = distance[i, j] / 25.0
    end
    return distance, duration
end

# Lấy ma trận tuyến nhanh nhất từ OSRM. OSRM nhận longitude trước latitude.
function osrm_matrices(latitude, longitude)
    coordinates = join(
        ["$(longitude[i]),$(latitude[i])" for i in eachindex(latitude)], ";",
    )
    url = OSRM_TABLE_ENDPOINT * coordinates * "?annotations=duration,distance"
    # Chỉ định tên file tạm vì URL chứa dấu chấm phẩy không hợp lệ trong
    # tên file Windows nếu Downloads tự suy ra tên từ URL.
    temporary_file = tempname() * ".json"
    Downloads.download(url, temporary_file)
    response = JSON.parse(read(temporary_file, String))
    response["code"] == "Ok" || error("OSRM trả về trạng thái $(response["code"])")

    count = length(latitude)
    distance = zeros(count, count)
    duration = zeros(count, count)
    for i in 1:count, j in 1:count
        response["distances"][i][j] === nothing && error("OSRM không tìm được tuyến")
        response["durations"][i][j] === nothing && error("OSRM không tìm được thời gian")
        distance[i, j] = Float64(response["distances"][i][j]) / 1000.0
        duration[i, j] = Float64(response["durations"][i][j]) / 3600.0
    end
    return distance, duration
end

"""
Sinh hồ sơ nợ mô phỏng và ma trận di chuyển đường bộ cho Hà Nội.
Seed được cố định để có thể tái lập toàn bộ bộ dữ liệu.
"""
function generate_dataset(
    output_directory;
    n::Int=20,
    officers::Int=3,
    days::Int=5,
    seed::Int=2026,
)
    n >= 1 || error("Số khách hàng phải dương")
    n <= 100 || error("Giới hạn 100 khách hàng cho các profile benchmark")
    officers >= 1 || error("Số cán bộ phải dương")
    days >= 1 || error("Số ngày phải dương")

    rng = MersenneTwister(seed)
    mkpath(output_directory)
    latitude = vcat(
        DEPOT_LATITUDE,
        MIN_LATITUDE .+ (MAX_LATITUDE - MIN_LATITUDE) .* rand(rng, n),
    )
    longitude = vcat(
        DEPOT_LONGITUDE,
        MIN_LONGITUDE .+ (MAX_LONGITUDE - MIN_LONGITUDE) .* rand(rng, n),
    )

    # Khoản nợ log-normal, giới hạn từ 5 đến 300 triệu đồng.
    debt_vnd = [
        round(clamp(exp(log(45_000_000.0) + 0.75 * randn(rng)), 5e6, 3e8))
        for _ in 1:n
    ]
    overdue_days = rand(rng, 15:180, n)
    service_minutes = rand(rng, 15:30, n)
    max_visits = fill(min(2, days), n)

    # Xác suất giảm theo số ngày quá hạn, quy mô nợ và ngày thực hiện.
    probability = zeros(n, days)
    for i in 1:n
        debt_million = debt_vnd[i] / 1e6
        base_probability = 0.82 *
            exp(-0.005 * overdue_days[i]) /
            (1.0 + 0.004 * max(debt_million - 40.0, 0.0))
        base_probability = clamp(base_probability + 0.04 * randn(rng), 0.08, 0.80)
        for t in 1:days
            probability[i, t] = clamp(base_probability * 0.96^(t - 1), 0.05, 0.80)
        end
    end

    matrix_source = "OSRM fastest-route table based on OpenStreetMap"
    distance, duration = try
        osrm_matrices(latitude, longitude)
    catch error_message
        @warn "Không lấy được OSRM; dùng Haversine fallback" exception=error_message
        matrix_source = "Haversine x 1.30; assumed average speed 25 km/h"
        fallback_matrices(latitude, longitude)
    end

    open(joinpath(output_directory, "customers.csv"), "w") do io
        probability_header = join(["p_day_$t" for t in 1:days], ",")
        println(
            io,
            "customer_id,latitude,longitude,debt_vnd,overdue_days," *
            "service_hours,max_visits,$probability_header",
        )
        for i in 1:n
            p_values = join(
                [string(round(probability[i, t]; digits=6)) for t in 1:days], ",",
            )
            println(
                io,
                "KH$(lpad(i, 3, '0'))," *
                "$(round(latitude[i + 1]; digits=6))," *
                "$(round(longitude[i + 1]; digits=6))," *
                "$(Int(debt_vnd[i])),$(overdue_days[i])," *
                "$(round(service_minutes[i] / 60; digits=6))," *
                "$(max_visits[i]),$p_values",
            )
        end
    end

    open(joinpath(output_directory, "officers.csv"), "w") do io
        println(io, "officer_id,day,budget_hours")
        for k in 1:officers, t in 1:days
            println(io, "$k,$t,8.0")
        end
    end

    writedlm(joinpath(output_directory, "distance_matrix_km.csv"), distance, ',')
    writedlm(joinpath(output_directory, "travel_time_matrix_hours.csv"), duration, ',')

    open(joinpath(output_directory, "metadata.txt"), "w") do io
        println(io, "generated_at=$(Dates.now())")
        println(io, "seed=$seed")
        println(io, "customers=$n")
        println(io, "officers=$officers")
        println(io, "days=$days")
        println(io, "depot_latitude=$DEPOT_LATITUDE")
        println(io, "depot_longitude=$DEPOT_LONGITUDE")
        println(io, "matrix_source=$matrix_source")
        println(io, "customer_data=synthetic")
    end

    println("Đã tạo dữ liệu tại: $output_directory")
    println("Nguồn ma trận di chuyển: $matrix_source")
end

# Usage:
#   julia generate_data.jl n40 [seed]
#   julia generate_data.jl all [seed]
#   julia generate_data.jl customers officers days [seed]
function generate_named_profile(profile_name::AbstractString, seed::Int)
    profile = normalize_data_profile(profile_name)
    settings = DATA_PROFILES[profile]
    output_directory = profile_directory(profile)
    println(
        "Profile $profile: $(settings.customers) customers, " *
        "$(settings.officers) officers, $(settings.days) days, seed=$seed",
    )
    generate_dataset(
        output_directory;
        n=settings.customers,
        officers=settings.officers,
        days=settings.days,
        seed=seed,
    )
end

function main_generate_data(args=ARGS)
    if !isempty(args) && lowercase(args[1]) == "all"
        random_seed = length(args) >= 2 ? parse(Int, args[2]) : 2026
        ordered_profiles = sort(collect(keys(DATA_PROFILES)); by=p -> parse(Int, p[2:end]))
        for profile in ordered_profiles
            generate_named_profile(profile, random_seed)
        end
    elseif length(args) <= 2
        profile = isempty(args) ? "n40" : args[1]
        random_seed = length(args) == 2 ? parse(Int, args[2]) : 2026
        generate_named_profile(profile, random_seed)
    else
        customer_count = parse(Int, args[1])
        officer_count = parse(Int, args[2])
        day_count = parse(Int, args[3])
        random_seed = length(args) >= 4 ? parse(Int, args[4]) : 2026
        output_directory = normpath(joinpath(@__DIR__, "..", "data", "generated", "custom"))
        println(
            "Custom profile: $customer_count customers, $officer_count officers, " *
            "$day_count days, seed=$random_seed",
        )
        generate_dataset(
            output_directory;
            n=customer_count,
            officers=officer_count,
            days=day_count,
            seed=random_seed,
        )
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main_generate_data()
end
