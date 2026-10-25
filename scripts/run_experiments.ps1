# Run both experiment phases in parallel; logs go to outputs/experiments/*.log.
# Usage: powershell -ExecutionPolicy Bypass -File scripts\run_experiments.ps1
$env:JULIA_DEPOT_PATH = "D:\JuliaDepot"
$julia = "D:\julia-1.13.2\bin\julia.exe"
Set-Location (Split-Path $PSScriptRoot)
New-Item -ItemType Directory -Force "outputs\experiments" | Out-Null
$jobs = foreach ($config in "v3_experiments_gd1", "v3_experiments_gd2") {
    Start-Process $julia -NoNewWindow -PassThru `
        -ArgumentList "--project=.", "core\run_v3_experiments.jl", "configs\$config.json" `
        -RedirectStandardOutput "outputs\experiments\$config.log" `
        -RedirectStandardError "outputs\experiments\$config.err.log"
}
Write-Host "Running GD1 and GD2 (about 4 hours). Follow progress: Get-Content outputs\experiments\v3_experiments_gd2.log -Wait -Encoding UTF8"
$jobs | Wait-Process
Write-Host "Result tables: outputs\experiments\v3_experiments_gd1\summary.csv and v3_experiments_gd2\summary.csv"
