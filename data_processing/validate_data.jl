# Kiểm tra bộ CSV có đầy đủ, đúng kích thước và nằm trong miền hợp lệ.
include(joinpath(@__DIR__, "load_data.jl"))
include(joinpath(@__DIR__, "data_profiles.jl"))

data_profile = normalize_data_profile(
    !isempty(ARGS) ? ARGS[1] : get(ENV, "DATA_PROFILE", "n40"),
)
data_directory = profile_directory(data_profile)
isdir(data_directory) || error(
    "Data profile '$data_profile' has not been generated. Run generate_data.jl first.",
)
data = load_data(data_directory)

all(data.debt .> 0) || error("Khoản nợ phải dương")
all((0.0 .<= data.probability) .& (data.probability .<= 1.0)) ||
    error("Xác suất phải nằm trong [0, 1]")
all(data.service_time .> 0) || error("Thời gian phục vụ phải dương")
all(data.daily_budget .> 0) || error("Ngân sách thời gian phải dương")
all(data.distance .>= 0) || error("Khoảng cách không được âm")
all(data.travel_time .>= 0) || error("Thời gian di chuyển không được âm")

println("Dữ liệu hợp lệ")
println("  Profile:     $data_profile")
println("  Khách hàng:  $(data.n)")
println("  Cán bộ:      $(data.K)")
println("  Số ngày:     $(data.H)")
println("  Distance:    $(size(data.distance))")
println("  Probability: $(size(data.probability))")
