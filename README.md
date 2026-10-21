# Tối ưu lộ trình thu hồi nợ

Repository chứa mã nguồn, tài liệu và CSV v3 cần để chạy các ví dụ. Các file
nguồn tải từ bên thứ ba, slide bài giảng, dữ liệu sinh lại và kết quả chạy
được giữ ở máy cục bộ (xem `.gitignore`); script xây dựng lại toàn bộ bộ v3
cần các nguồn gốc đó và không chạy chỉ với repository này.

Đồ án xây dựng mô hình tối ưu lộ trình thu hồi nợ nhiều cán bộ, nhiều ngày và
có tái viếng thăm. Mã nguồn gồm phương pháp chính xác và các heuristic:

1. Branch-and-Bound tự cài đặt.
2. Branch-and-Cut của HiGHS thông qua JuMP.
3. Genetic Algorithm.
4. Tabu Search.
5. Simulated Annealing độc lập.
6. Adaptive Large Neighborhood Search.
7. Hill Climbing.
8. Q-learning assisted ALNS.

Mô hình toán học, cách mã hóa từ CSV, ví dụ nghiệm và quy trình cuốn chiếu
được trình bày tại [Mo_hinh_toan_va_chien_luoc_giai.md](Mo_hinh_toan_va_chien_luoc_giai.md).
Giải thích chi tiết từng thuật toán và cách chúng sử dụng dữ liệu nằm tại
[TAI_LIEU_PHUONG_PHAP.md](TAI_LIEU_PHUONG_PHAP.md).

Biểu diễn nghiệm bằng ma trận phân công, vector tuyến và phép biến đổi toán
học nằm tại [BIEU_DIEN_NGHIEM_VA_BIEN_DOI_TOAN_HOC.md](BIEU_DIEN_NGHIEM_VA_BIEN_DOI_TOAN_HOC.md).

## Yêu cầu

- Julia 1.9 trở lên.
- Julia được giải nén tại `D:\julia-1.13.2`.
- Các package Julia được lưu tại `D:\JuliaDepot`.
- Mã nguồn dự án nằm tại `D:\Mathematical_modeling`.

## Chạy bằng PowerShell

### Cài dependency lần đầu

Mở PowerShell và chạy từng dòng sau:

```powershell
$env:JULIA_DEPOT_PATH = "D:\JuliaDepot"
Set-Location "D:\Mathematical_modeling"
& "D:\julia-1.13.2\bin\julia.exe" --project=. -e "using Pkg; Pkg.instantiate()"
```

### Chạy hai phương pháp

```powershell
$env:JULIA_DEPOT_PATH = "D:\JuliaDepot"
Set-Location "D:\Mathematical_modeling"
& "D:\julia-1.13.2\bin\julia.exe" --project=. "core\run_comparison.jl"
```

Trong PowerShell không sử dụng `cd /d`. Lệnh đó chỉ hợp lệ trong CMD.

## Chạy bằng Command Prompt (CMD)

### Cài dependency lần đầu

Mở Command Prompt và chạy từng dòng sau:

```bat
set JULIA_DEPOT_PATH=D:\JuliaDepot
cd /d D:\Mathematical_modeling
D:\julia-1.13.2\bin\julia.exe --project=. -e "using Pkg; Pkg.instantiate()"
```

### Chạy hai phương pháp

```bat
set JULIA_DEPOT_PATH=D:\JuliaDepot
cd /d D:\Mathematical_modeling
D:\julia-1.13.2\bin\julia.exe --project=. core\run_comparison.jl
```

Biến `JULIA_DEPOT_PATH` phải được đặt trong mỗi cửa sổ terminal mới. Nếu bỏ
qua dòng này, Julia có thể tìm package tại depot mặc định và báo không tìm
thấy JuMP hoặc HiGHS.

## Kết quả mong đợi

Chương trình lần lượt in kết quả của:

1. Custom Branch-and-Bound.
2. HiGHS Branch-and-Cut.

Hai phương pháp phải trả về cùng giá trị mục tiêu trên instance mẫu. Tuyến của
từng phương pháp có thể khác nhau nếu tồn tại nhiều nghiệm tối ưu.

## Tạo bộ dữ liệu mô phỏng

Pipeline tạo hồ sơ nợ mô phỏng tại Hà Nội và gọi OSRM để lấy ma trận khoảng
cách/thời gian đường bộ dựa trên OpenStreetMap:

```powershell
$env:JULIA_DEPOT_PATH = "D:\JuliaDepot"
Set-Location "D:\Mathematical_modeling"
& "D:\julia-1.13.2\bin\julia.exe" --project=. "data_processing\generate_data.jl" n40
```

Các file được tạo trong `data/generated/n40`:

- `customers.csv`: khoản nợ, ngày quá hạn, tọa độ, thời gian phục vụ và xác suất.
- `officers.csv`: thời gian làm việc của từng cán bộ theo ngày.
- `distance_matrix_km.csv`: ma trận khoảng cách.
- `travel_time_matrix_hours.csv`: ma trận thời gian di chuyển.
- `metadata.txt`: seed, kích thước và nguồn của ma trận di chuyển.

Nếu không truy cập được OSRM, chương trình dùng khoảng cách Haversine hiệu
chỉnh và ghi rõ nguồn fallback trong `metadata.txt`.

Kiểm tra cấu trúc và miền giá trị của bộ dữ liệu:

```powershell
$env:JULIA_DEPOT_PATH = "D:\JuliaDepot"
Set-Location "D:\Mathematical_modeling"
& "D:\julia-1.13.2\bin\julia.exe" --project=. "data_processing\validate_data.jl" n40
```

## So sánh các heuristic và Branch-and-Cut

### Thử độ nhạy xác suất trên bộ v3

Sửa `v3_scenarios.json` rồi chạy:

```bat
cd /d D:\Mathematical_modeling
set JULIA_DEPOT_PATH=D:\JuliaDepot
D:\julia-1.13.2\bin\julia.exe --project=. core\run_v3_scenarios.jl
```

`instance` nhận `INS_XS`, `INS_S`, `INS_M`, `INS_L` hoặc các bộ `REP`.
Runner dùng ALNS để tối ưu ba kịch bản đồng bộ `THAP`, `CO_SO`, `CAO`, rồi
`mixed_samples` kịch bản hỗn hợp (mặc định 30 seed). Mỗi lần lặp dùng seed
`seed + r`; mỗi khách nhận một hệ số độc lập, phân bố đều giữa mức thấp và cao
của chính khách đó; cùng hệ số được giữ qua cả năm ngày. Đây là phép thử độ
nhạy trên xác suất giả định, không phải mô phỏng kết quả thu tiền thực tế.

Kết quả nằm trong `results/v3_<instance>/`:

- `optimization.csv`: giá trị kỳ vọng và thời gian khi tối ưu từng kịch bản,
  đơn vị triệu đồng.
- `cross_evaluation.csv`: chấm **cùng một kế hoạch** trên tất cả kịch bản;
  dùng bảng này để so độ ổn định của kế hoạch.
- `mixed_factors.csv`: hệ số đã lấy cho mỗi khách và mỗi mẫu, trong khoảng
  0 (mức thấp) đến 1 (mức cao).
- `mixed_summary.csv`: trung bình, độ lệch chuẩn và khoảng tin cậy bootstrap
  95% trên các mẫu hỗn hợp. Chênh lệch giữa các kế hoạch được ghép cặp theo
  cùng seed, lấy kế hoạch `CO_SO` làm mốc.
- `conclusion.txt`: kết luận tự động từ các khoảng tin cậy. Dòng
  `MIX_REOPT_HEURISTIC` là ALNS chạy lại trên từng MIX với ngân sách giới hạn;
  đây không phải cận trên hay nghiệm tối ưu.

Chạy lại phép thử nhỏ 30 khách bằng:

```bat
D:\julia-1.13.2\bin\julia.exe --project=. core\run_v3_scenarios.jl v3_scenarios_xs.json
```

`INS_XS` có 30 khách và năng lực 2 cán bộ trong 5 ngày; các kế hoạch có thể
giống nhau vì đủ khả năng thăm gần hết khách. `INS_S` có 80 khách phù hợp hơn
để xem kế hoạch thay đổi khi xác suất từng khách dao động.

Script sau đọc profile được chọn trong `data/generated` và chạy tất cả phương
pháp trên cùng một instance:

```powershell
$env:JULIA_DEPOT_PATH = "D:\JuliaDepot"
Set-Location "D:\Mathematical_modeling"
& "D:\julia-1.13.2\bin\julia.exe" --project=. "core\run_metaheuristic_comparison.jl"
```

Tabu Search bắt đầu từ nghiệm tham lam, thay đổi một quyết định
khách hàng-ngày-cán bộ trong mỗi move và dùng tabu tenure để tránh quay lại
nghiệm cũ. Aspiration cho phép thực hiện move tabu nếu tạo nghiệm tốt nhất mới.

Simulated Annealing độc lập dùng cùng nghiệm tham lam và lân cận đổi một gene
như Tabu. Nghiệm tốt hơn luôn được nhận; nghiệm kém hơn được nhận với xác suất
`exp(delta / temperature)`. Nhiệt độ giảm theo cấp số nhân sau mỗi vòng.

ALNS sử dụng bốn toán tử phá: random removal, worst-value removal,
related removal và route removal. Hai toán tử sửa là greedy insertion và
regret-2 insertion. Trọng số chọn toán tử được cập nhật theo kết quả của từng
segment; simulated annealing cho phép tạm chấp nhận nghiệm kém hơn để thoát
cực trị địa phương.

Hill Climbing dùng best-improvement: duyệt các phép đổi một gene, chọn láng
giềng tốt nhất và dừng ở cực trị địa phương. Multi-start chạy từ nhiều nghiệm
ban đầu để giảm phụ thuộc vào điểm xuất phát. Đây là baseline đơn giản; việc
quét toàn bộ lân cận có thể khiến nó chậm hơn các metaheuristic khác.

Q-learning ALNS thay roulette/adaptive weights bằng một RL agent chọn 1 trong
8 cặp destroy-repair. State gồm giai đoạn tìm kiếm, mức trì trệ và khoảng cách
giữa nghiệm hiện tại với nghiệm tốt nhất. Thời gian benchmark bao gồm cả huấn
luyện online; đây là RL dạng bảng, chưa phải mạng neural DQN/PPO.

## Benchmark dữ liệu lớn bằng CMD

### Chọn kích thước dữ liệu

Cách đơn giản nhất là sửa `config.json`:

```json
{
  "data_profile": "n40",
  "benchmark_profile": "auto",
  "exact_time_limit_seconds": 60,
  "seed": 2026,
  "generate_if_missing": true
}
```

Sau đó chỉ cần chạy:

```bat
D:\julia-1.13.2\bin\julia.exe --project=. core\run_metaheuristic_comparison.jl
```

Đổi `data_profile` thành `n10`, `n20`, `n40`, `n50`, `n80` hoặc `n100` để
chọn bộ dữ liệu. Khi `generate_if_missing` là `true`, chương trình tự sinh profile
chưa tồn tại. Các biến môi trường vẫn có thể ghi đè cấu hình JSON khi cần.

Các profile dữ liệu có sẵn:

| `DATA_PROFILE` | Khách hàng | Cán bộ | Ngày |
|---|---:|---:|---:|
| `n10` | 10 | 1 | 2 |
| `n20` | 20 | 2 | 3 |
| `n40` | 40 | 3 | 5 |
| `n50` | 50 | 4 | 5 |
| `n80` | 80 | 5 | 7 |
| `n100` | 100 | 6 | 7 |

Tạo toàn bộ các bộ dữ liệu một lần:

```bat
D:\julia-1.13.2\bin\julia.exe --project=. data_processing\generate_data.jl all 2026
```

Chọn một bộ để chạy, ví dụ 40 khách hàng:

```bat
set DATA_PROFILE=n40
set BENCHMARK_PROFILE=auto
D:\julia-1.13.2\bin\julia.exe --project=. core\run_metaheuristic_comparison.jl
```

`DATA_PROFILE` chọn dữ liệu, còn `BENCHMARK_PROFILE` chọn ngân sách tính toán.
Giá trị `auto` tự dùng `standard` cho tối đa 20 khách, `large` cho 40-50 khách
và `xlarge` cho 80-100 khách. Có thể thay `n40` bằng `n10`, `n20`, `n50`,
`n80` hoặc `n100` mà không ghi đè bộ dữ liệu khác.

Ví dụ tạo lại profile 50 khách hàng, 4 cán bộ, 5 ngày và seed 2026:

```bat
set JULIA_DEPOT_PATH=D:\JuliaDepot
cd /d D:\Mathematical_modeling
D:\julia-1.13.2\bin\julia.exe --project=. data_processing\generate_data.jl n50 2026
```

Kiểm tra dữ liệu vừa tạo:

```bat
D:\julia-1.13.2\bin\julia.exe --project=. data_processing\validate_data.jl n50
```

Chạy tất cả phương pháp với profile lớn và giới hạn Branch-and-Cut 120 giây:

```bat
set BENCHMARK_PROFILE=large
set DATA_PROFILE=n50
set EXACT_TIME_LIMIT=120
D:\julia-1.13.2\bin\julia.exe --project=. core\run_metaheuristic_comparison.jl
```

Kết quả tóm tắt được lưu theo profile, ví dụ `results/comparison_n50.csv`. Nếu OSRM không truy
cập được, kiểm tra `data/generated/n50/metadata.txt` để biết pipeline đang dùng
ma trận Haversine fallback.

### Ví dụ profile 40 khách hàng

Lệnh sau tạo bộ gồm 40 khách hàng, 3 cán bộ và 5 ngày:

```bat
set JULIA_DEPOT_PATH=D:\JuliaDepot
cd /d D:\Mathematical_modeling
D:\julia-1.13.2\bin\julia.exe --project=. data_processing\generate_data.jl n40 2026
D:\julia-1.13.2\bin\julia.exe --project=. data_processing\validate_data.jl n40
```

Chạy với ngân sách thuật toán tự động và giới hạn Branch-and-Cut 60 giây:

```bat
set BENCHMARK_PROFILE=auto
set DATA_PROFILE=n40
set EXACT_TIME_LIMIT=60
D:\julia-1.13.2\bin\julia.exe --project=. core\run_metaheuristic_comparison.jl
```

GA trong benchmark dùng các cấu hình sau:

| Profile | Quần thể | Số thế hệ tối đa | Dừng sớm khi không cải thiện |
|---|---:|---:|---:|
| `standard` | 100 | 1.000 | 150 thế hệ |
| `large` | 90 | 750 | 100 thế hệ |
| `xlarge` | 80 | 500 | 75 thế hệ |

Một thế hệ được xem là không cải thiện khi nghiệm tốt nhất không tăng giá trị thu
hồi kỳ vọng và cũng không giảm quãng đường ở trường hợp hai giá trị kỳ vọng bằng
nhau. Đặt `stagnation_generations=0` khi gọi `solve_genetic_algorithm` để tắt dừng
sớm.

Các file mã nguồn:

- core/model.jl: dữ liệu, mô hình MILP và hàm in kết quả dùng chung.
- core/branch_and_bound.jl: thuật toán Branch-and-Bound tự cài đặt.
- core/branch_and_cut.jl: Branch-and-Cut sử dụng HiGHS.
- core/run_comparison.jl: chạy hai phương pháp trên cùng một instance.
- core/genetic_algorithm.jl: Genetic Algorithm và các toán tử repair/2-opt.
- core/tabu_search.jl: Tabu Search, tabu memory và aspiration criterion.
- core/simulated_annealing.jl: Simulated Annealing độc lập với geometric cooling.
- core/alns.jl: ALNS với destroy/repair operators và adaptive weights.
- core/hill_climbing.jl: Hill Climbing best-improvement và multi-start.
- core/rl_alns.jl: Q-learning điều khiển lựa chọn toán tử ALNS.
- core/run_metaheuristic_comparison.jl: benchmark tất cả các phương pháp.
- data_processing/generate_data.jl: tạo hồ sơ và lấy ma trận di chuyển.
- data_processing/load_data.jl: kiểm tra và chuyển CSV thành dữ liệu mô hình.
- data_processing/sample_data.jl: sinh instance nhỏ để kiểm tra thuật toán.
- data_processing/validate_data.jl: kiểm tra kích thước và miền dữ liệu.

Branch-and-Bound tự cài đặt nhằm minh họa thuật toán và chỉ phù hợp với
instance nhỏ. Với dữ liệu thực tế nên dùng Branch-and-Cut của solver.

## So sánh bốn phương pháp trên xác suất cơ sở của bộ v3

Sửa `v3_comparison.json` để chọn `instance` (`INS_XS`, `INS_S`, `INS_M`,
`INS_L`) và ngân sách chạy. Runner `core/run_v3_comparison.jl` chỉ đọc xác
suất `CO_SO` của từng khách; không dùng `THAP`, `CAO` hay `MIX`. GA, Tabu,
ALNS và Branch-and-Cut giải cùng một instance với cùng dữ liệu đầu vào.
`seed` áp dụng cho ba heuristic. Các giới hạn vòng lặp không tương đương
về thời gian, nên bảng kết quả ghi cả thời gian thực tế.

PowerShell:

```powershell
$env:JULIA_DEPOT_PATH = "D:\JuliaDepot"
Set-Location "D:\Mathematical_modeling"
& "D:\julia-1.13.2\bin\julia.exe" --project=. core\run_v3_comparison.jl
```

CMD:

```bat
set JULIA_DEPOT_PATH=D:\JuliaDepot
cd /d D:\Mathematical_modeling
D:\julia-1.13.2\bin\julia.exe --project=. core\run_v3_comparison.jl
```

Có thể truyền đường dẫn JSON khác làm đối số cuối. Kết quả nằm trong
`results/v3_<instance>/base_method_comparison.csv` và `base_routes.csv`.
`objective_million_vnd` là tiền thu kỳ vọng, không phải tiền đã thu thực tế;
`upper_bound_million_vnd` là cận trên do Branch-and-Cut cung cấp. Cột
`gap_percent` so nghiệm của từng cách với cận đó, không chứng nhận tính
tối ưu của heuristic. Nếu Branch-and-Cut hết giờ mà chưa có nghiệm nguyên,
ô mục tiêu của nó để trống. `solver_seconds` của Branch-and-Cut chỉ tính
thời gian `optimize!`; `total_seconds` còn gồm dựng mô hình và kiểm tra nghiệm.
Giới hạn `time_limit_seconds` trong JSON chỉ áp dụng cho `optimize!`, nên
thời gian chạy thực có thể dài hơn giới hạn. Trên instance lớn, nên thử
`INS_XS` trước rồi tăng kích thước dần.

`run_v3_comparison.jl` ở trên là mốc **tĩnh**: lập một lịch cho toàn bộ các ngày.
Để đánh giá chính, dùng runner **cuốn chiếu** bên dưới. Đầu ngày `t`, mỗi phương
pháp giải lại cho `t..H` với những khách chưa trả và số lượt thăm còn lại; chỉ
thực hiện tuyến ngày `t`. Kết quả thu nợ được xác định bằng `u(i,t) < p_CO_SO(i,t)`
trong `kich_ban_monte_carlo.csv`. Bốn phương pháp dùng chung `u(i,t)` của từng
kịch bản, nhưng có trạng thái riêng vì tuyến của chúng có thể khác nhau.

Chọn `monte_carlo_ids` trong `v3_comparison.json`, ví dụ `[1, 2, 3]`. Mỗi ID
cho một lần mô phỏng độc lập. Với Branch-and-Cut, `time_limit_seconds` áp dụng
**mỗi lần giải lại**, không phải cho toàn bộ kỳ hay thời gian dựng mô hình.
Runner động tạo trước một nghiệm ALNS khả thi, đưa nó vào HiGHS làm MIP start.
Nếu HiGHS hết giờ mà chỉ có nghiệm rỗng hoặc không cải thiện được ALNS,
runner dùng lại tuyến ALNS và ghi trạng thái `*_HEURISTIC_FALLBACK`;
đó **không phải** nghiệm do BnC tự tìm ra. Thời gian ALNS khởi tạo được
tính vào thời gian tổng, không tính trong `time_limit_seconds` của HiGHS.
Để thử nhanh, nên bắt đầu bằng `INS_XS` và một ID.

PowerShell:

```powershell
$env:JULIA_DEPOT_PATH = "D:\JuliaDepot"
Set-Location "D:\Mathematical_modeling"
& "D:\julia-1.13.2\bin\julia.exe" --project=. core\run_v3_dynamic.jl
```

CMD:

```bat
set JULIA_DEPOT_PATH=D:\JuliaDepot
cd /d D:\Mathematical_modeling
D:\julia-1.13.2\bin\julia.exe --project=. core\run_v3_dynamic.jl
```

Kết quả `dynamic_summary.csv` là **tiền thực thu mô phỏng** cho từng kịch bản
và phương pháp; `dynamic_daily.csv` ghi từng ngày, còn `dynamic_visits.csv`
ghi từng lần ghé và kết quả trả nợ. Khi dùng nhiều ID Monte Carlo, hãy so trung
bình tiền thu và chênh lệch ghép cặp với BnC trong `dynamic_aggregate.csv`.
Độ lệch chuẩn của một kịch bản được để `NaN`; không nên kết luận thuật toán nào
tốt hơn từ một lần mô phỏng. Đây vẫn là mô phỏng
với xác suất giả định, không phải dữ liệu thu nợ thực tế.

## Train/test cho chính sách RL động

`core/run_v3_rl_experiment.jl` học một **Q-learning dạng bảng**, không phải mạng
neural. Đầu mỗi ngày, trạng thái quan sát được gồm ngày hiện tại, tỷ lệ khách
đã trả và tỷ lệ lượt ghé còn lại. Hành động là chọn GA, Tabu hoặc ALNS để lập
tuyến cho ngày đó; thưởng học là tiền thực thu ngày đó chia tổng dư nợ. Q được
cập nhật sau khi quan sát kết quả, không xem trước số ngẫu nhiên `u` tương lai.
Đây là bộ điều khiển chọn thuật toán; nó không tự sinh tuyến từ đầu.

`rl_experiment.json` chia ID Monte Carlo của bộ v3 thành train `1..60`,
validation `61..80` và test `81..100`. Các khoảng không được trùng nhau.
Chỉ train cập nhật Q; validation xem chất lượng nhưng không tự động chỉnh mô
hình; test dùng Q đã đóng băng và so trên cùng 20 kịch bản với GA, Tabu,
ALNS, Branch-and-Cut. Không đổi tham số sau khi xem kết quả test nếu vẫn định
gọi đó là tập test độc lập. Các ID test chỉ được nạp sau khi huấn luyện xong.

PowerShell:

```powershell
$env:JULIA_DEPOT_PATH = "D:\JuliaDepot"
Set-Location "D:\Mathematical_modeling"
& "D:\julia-1.13.2\bin\julia.exe" --project=. core\run_v3_rl_experiment.jl
```

CMD:

```bat
set JULIA_DEPOT_PATH=D:\JuliaDepot
cd /d D:\Mathematical_modeling
D:\julia-1.13.2\bin\julia.exe --project=. core\run_v3_rl_experiment.jl
```

Mặc định dùng `INS_XS` để kiểm tra khả năng chạy. Kết quả nằm trong
`results/v3_<instance>/rl_split/`: `q_table.json` chứa chính sách, split và
thời gian huấn luyện; `validation_summary.csv` chỉ chứa RL;
`test_summary.csv`, `test_daily.csv`, `test_visits.csv` và `test_aggregate.csv`
chứa phép so sánh cuối. BnC có giới hạn thời gian **mỗi ngày mỗi kịch bản**;
toàn bộ phép thử có thể chạy lâu, nhất là khi tăng instance. Chưa chạy toàn
bộ 100 kịch bản trong quá trình phát triển; các phép thử nhỏ nằm ở
`core/test_rl_dynamic.jl` và `core/test_v3_dynamic.jl`.
`test_daily.csv` có cột `selected_solver` để thấy hành động RL mỗi ngày.
Split này kiểm tra diễn biến ngẫu nhiên mới trên **cùng bộ khách**, chưa kiểm
tra khả năng chuyển sang bộ khách mới như `REP1`.
