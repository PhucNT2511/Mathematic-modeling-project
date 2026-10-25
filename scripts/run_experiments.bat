@echo off
rem Run GD1 and GD2 in parallel (about 4 hours). Double-click or run from CMD.
cd /d "%~dp0.."
set JULIA_DEPOT_PATH=D:\JuliaDepot
set JULIA=D:\julia-1.13.2\bin\julia.exe
if not exist outputs\experiments mkdir outputs\experiments
start "GD1" /b cmd /c ""%JULIA%" --project=. core\run_v3_experiments.jl configs\v3_experiments_gd1.json > outputs\experiments\v3_experiments_gd1.log 2>&1 & echo done > outputs\experiments\gd1.done"
start "GD2" /b cmd /c ""%JULIA%" --project=. core\run_v3_experiments.jl configs\v3_experiments_gd2.json > outputs\experiments\v3_experiments_gd2.log 2>&1 & echo done > outputs\experiments\gd2.done"
echo Running GD1 and GD2 in parallel.
echo Logs: outputs\experiments\v3_experiments_gd1.log and v3_experiments_gd2.log
:wait
timeout /t 30 /nobreak > nul
if not exist outputs\experiments\gd1.done goto wait
if not exist outputs\experiments\gd2.done goto wait
del outputs\experiments\gd1.done outputs\experiments\gd2.done
echo Finished. Results: outputs\experiments\v3_experiments_gd1\summary.csv and v3_experiments_gd2\summary.csv
if not "%1"=="nopause" pause
