# Preset data sizes. Capacity is roughly 6-8 customer visits per officer-day.
const DATA_PROFILES = Dict(
    "n10" => (customers=10, officers=1, days=2),
    "n20" => (customers=20, officers=2, days=3),
    "n40" => (customers=40, officers=3, days=5),
    "n50" => (customers=50, officers=4, days=5),
    "n80" => (customers=80, officers=5, days=7),
    "n100" => (customers=100, officers=6, days=7),
)

function normalize_data_profile(value::AbstractString)
    profile = lowercase(strip(value))
    all(isdigit, profile) && (profile = "n" * profile)
    haskey(DATA_PROFILES, profile) || error(
        "Unknown DATA_PROFILE='$value'. Choose: " *
        join(sort(collect(keys(DATA_PROFILES)); by=p -> parse(Int, p[2:end])), ", "),
    )
    return profile
end

function profile_directory(profile::AbstractString)
    normalized = normalize_data_profile(profile)
    return normpath(joinpath(@__DIR__, "..", "data", "generated", normalized))
end

function automatic_benchmark_profile(customer_count::Int)
    customer_count <= 20 && return "standard"
    customer_count <= 50 && return "large"
    return "xlarge"
end
