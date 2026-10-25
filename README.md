# Tối ưu lộ trình thu hồi nợ nhiều ngày

Đồ án môn **Mô hình hóa toán học** (SOICT). Lập kế hoạch cho K cán bộ thu hồi
nợ đi thăm n khách quá hạn trong H ngày trên mạng đường thật của Hà Nội, sao
cho **tổng tiền thu hồi kỳ vọng** lớn nhất. Một khách có thể được thăm lại, và
xác suất trả nợ giảm dần theo ngày.

![Tuyến 5 ngày của 2 cán bộ, 80 khách](figures/INS_S_n80_H5/routes_grid.png)

*Mỗi hàng là một cán bộ, mỗi cột là một ngày. Cán bộ xuất phát từ chi nhánh ★,
thăm khách theo số 1, 2, 3, … rồi quay về ★. Mỗi cán bộ một họ màu (xanh, đỏ, …),
ngày 1 đậm nhất, nhạt dần đến ngày 5.*

## Nội dung

- **Mô hình MILP** với biến lịch thăm λ(i,S), cung x(i,j,k,t), phân công y(i,k,t),
  MTZ, phá đối xứng giữa các cán bộ, và lượt giải thứ hai tối thiểu quãng đường.
- **Phương pháp giải:** Branch-and-Cut (HiGHS), Tabu Search, ALNS, Genetic
  Algorithm, và Branch-and-Cut khởi động ấm từ ALNS.
- **Thí nghiệm số:** 10 lần chạy cho mỗi cấu hình, đo CPU, gap và số node B&B ở
  bài toán một ngày (GD1) và năm ngày (GD2), n = 10 → 80 khách.
- **Mở rộng:** so sánh chính sách tĩnh, cuốn chiếu và tham lam bằng mô phỏng
  Monte Carlo.

## Tài liệu

| File | Nội dung |
|---|---|
| [docs/00_tong_quan.md](docs/00_tong_quan.md) | Bài toán, đồ thị, dữ liệu, các hướng giải, kết quả chính |
| [docs/01_mo_hinh_toan.md](docs/01_mo_hinh_toan.md) | Mô hình toán (1)–(15) và mô hình động |
| [docs/02_bieu_dien_nghiem.md](docs/02_bieu_dien_nghiem.md) | Biểu diễn nghiệm, chuyển đổi MILP ↔ heuristic |
| [docs/03_phuong_phap_giai.md](docs/03_phuong_phap_giai.md) | Chi tiết từng phương pháp, cách tính gap |
| [docs/04_thuc_nghiem.md](docs/04_thuc_nghiem.md) | Thiết kế thí nghiệm, bảng kết quả, biểu đồ, nhận xét |
| [collection_routing_dataset_v3/README.md](collection_routing_dataset_v3/README.md) | Nguồn và cách sinh dữ liệu |

## Kết quả chính

Trung bình 10 lần chạy, instance 80 khách INS_S, 2 cán bộ:

| Giai đoạn | Phương pháp | Gap | CPU |
|---|---|---|---|
| GD1 (1 ngày, 30 s) | Branch-and-Cut | 877% (hết giờ, 0 node) | 32 s |
| | Tabu / ALNS / GA | 2,7% / 2,2% / 2,4% | 2 / 14 / 8 s |
| GD2 (5 ngày, 150 s) | Branch-and-Cut | 16.594% (hết giờ, 0 node) | 157 s |
| | Tabu / ALNS / GA | 1,1% / **0,4%** / 1,6% | 6 / 31 / 23 s |
| | BnC + ALNS start | 0,4% | 157 s |

Đến 30 khách, Branch-and-Cut chứng minh tối ưu 10/10 lần và mọi metaheuristic
đều tìm đúng nghiệm tối ưu. Bảng đầy đủ: [docs/04_thuc_nghiem.md](docs/04_thuc_nghiem.md).

## Cấu trúc thư mục

```
core/                       mô hình và thuật toán
  model.jl                    dữ liệu DebtRoutingData, MILP (1)–(15)
  branch_and_cut.jl           HiGHS, khởi động ấm, giải lần hai theo quãng đường
  genetic_algorithm.jl        GA, dựng tuyến, repair, hàm đánh giá dùng chung
  tabu_search.jl, alns.jl     Tabu Search, ALNS
  run_v3_comparison.jl        so các phương pháp trên một instance (một lần)
  run_v3_experiments.jl       thí nghiệm 10 lần chạy cho báo cáo (có resume)
  run_v3_dynamic.jl           chính sách cuốn chiếu / tham lam trên một kịch bản
  run_v3_static_vs_rolling.jl so ba chính sách trên nhiều kịch bản Monte Carlo
  export_v3_plan.jl           xuất kế hoạch để vẽ
  plot_v3_plan.py             vẽ bản đồ khách và tuyến
  plot_results.py             vẽ biểu đồ kết quả thí nghiệm
  test_v3_dynamic.jl          kiểm thử nhanh
data_processing/            đọc bộ dữ liệu v3, trạng thái động, instance nhỏ để test
configs/                    cấu hình JSON của mọi thí nghiệm
scripts/                    chạy GD1 + GD2 song song (PowerShell, CMD)
collection_routing_dataset_v3/  bộ dữ liệu (CSV, nguồn, script sinh)
outputs/                    kết quả: experiments/, plans/, v3_<instance>/
figures/                    hình: experiments/, <instance>_n<n>_H<H>/
docs/                       tài liệu và đề xuất đề tài
```

## Cài đặt

- Julia 1.13 (gói trong `Project.toml`, `Manifest.toml`): JuMP, HiGHS, JSON.
- Python 3 với `pandas`, `matplotlib`, `networkx` (chỉ để vẽ hình).

```powershell
$env:JULIA_DEPOT_PATH = "D:\JuliaDepot"   # nếu dùng depot riêng
$julia = "D:\julia-1.13.2\bin\julia.exe"  # hoặc "julia" nếu đã có trong PATH
& $julia --project=. -e "using Pkg; Pkg.instantiate()"
```

## Chạy

Các lệnh chạy từ thư mục gốc của repo, trong PowerShell.

```powershell
# Kiểm thử nhanh (khoảng 1 phút)
& $julia --project=. core/test_v3_dynamic.jl
& $julia --project=. core/run_v3_experiments.jl configs/v3_experiments_smoke.json

# Thí nghiệm chính: GD1 + GD2 song song, khoảng 4 giờ, có resume khi bị ngắt
powershell -ExecutionPolicy Bypass -File scripts\run_experiments.ps1
Get-Content outputs\experiments\v3_experiments_gd2.log -Wait -Tail 20 -Encoding UTF8

# So sánh tĩnh / cuốn chiếu / tham lam (khoảng 3 giờ)
& $julia --project=. core/run_v3_static_vs_rolling.jl configs/v3_static_vs_rolling_report.json

# Một lần so sánh nhanh trên một instance
& $julia --project=. core/run_v3_comparison.jl configs/v3_comparison.json

# Hình
& $julia --project=. core/export_v3_plan.jl INS_S 0 5 ALNS   # 0 = toàn bộ khách
python core/plot_v3_plan.py      # vẽ mọi outputs/plans/plan_*.csv
python core/plot_results.py
```

Thí nghiệm chính ghi `runs.csv` sau mỗi lần chạy; chạy lại cùng lệnh sẽ bỏ qua
các lần đã xong. Đặt `"resume": false` trong cấu hình để chạy lại từ đầu.

### Cấu hình

| File | Dùng cho |
|---|---|
| `v3_experiments_gd1.json` | GD1: H = 1, 30 s, 9 instance |
| `v3_experiments_gd2.json` | GD2: H = 5, 150 s, 7 instance, thêm khởi động ấm |
| `v3_experiments_smoke.json` | Kiểm thử nhanh, 1 lần chạy |
| `v3_static_vs_rolling_report.json` | Ba chính sách, 20 kịch bản MC × 3 kịch bản p |
| `v3_static_vs_rolling.json` | Như trên với 100 kịch bản MC (khoảng 12–15 giờ) |
| `v3_static_vs_rolling_smoke.json` | Kiểm thử nhanh trên INS_XS |
| `v3_comparison.json` | So sánh một lần, chính sách cuốn chiếu trên một kịch bản |

## Nhóm

Đồ án môn Mô hình hóa toán học, Trường Công nghệ Thông tin và Truyền thông
(SOICT), Đại học Bách khoa Hà Nội.

## Project Report

The report is written in LaTeX on Overleaf.
(https://www.overleaf.com/project/6adc64df993ecc93342937cd/share#0cb3b0da80856dc2e617d4bb8c8405ea78f29ab8c936fa72))
