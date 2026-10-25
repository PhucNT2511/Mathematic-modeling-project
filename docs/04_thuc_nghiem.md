# Thực nghiệm số

Mục tiêu: đo **thời gian CPU, gap và số node Branch-and-Bound** của các phương
pháp khi kích thước bài toán tăng, ở bài toán một ngày (GD1) và năm ngày (GD2),
mỗi cấu hình chạy **10 lần** rồi lấy trung bình.

## 1. Môi trường

| Mục | Giá trị |
|---|---|
| Máy | Laptop Intel Core i7-1165G7 (4 nhân), Windows 10 |
| Ngôn ngữ | Julia 1.13.2, JuMP, HiGHS (MIP, một luồng) |
| Runner | [run_v3_experiments.jl](../core/run_v3_experiments.jl) |
| Cấu hình | [v3_experiments_gd1.json](../configs/v3_experiments_gd1.json), [v3_experiments_gd2.json](../configs/v3_experiments_gd2.json) |
| Kết quả thô | `outputs/experiments/v3_experiments_gd{1,2}/runs.csv`, `summary.csv`, `instances.csv` |

GD1 và GD2 chạy song song trên hai nhân riêng; HiGHS giải MIP gần như một
luồng nên hai tiến trình không tranh CPU đáng kể.

## 2. Thiết kế thí nghiệm

### 2.1. Instance

Bộ dữ liệu có sẵn nhiều tham số (số cán bộ, phút/ngày, m, kịch bản p). Để thấy
rõ ảnh hưởng của **kích thước**, nhóm cố định mọi tham số khác và chỉ tăng số
khách:

| Tham số | Giá trị cố định | Lý do |
|---|---|---|
| Số cán bộ K | 2 | Mặc định của INS_XS và INS_S trong bộ dữ liệu |
| Phút làm việc B | 480 phút/ngày | Một ngày làm việc 8 giờ |
| Số lần thăm tối đa m | 2 | Mặc định của INS_S; dùng chung cho mọi instance để so sánh công bằng |
| Kịch bản p | CO_SO (h = 1) | Kịch bản cơ sở |
| Số ngày H | 1 (GD1), 5 (GD2) | Tương ứng Step 6 / Step 9 của đề gốc |

Số khách n lấy theo mốc **10, 20, 30, 50, 80**: n khách đầu tiên của INS_XS
(n ≤ 30) hoặc INS_S (n = 50, 80). Vì các instance lồng nhau, instance nhỏ là
tập con của instance lớn, nên thay đổi kết quả chỉ do n. Mốc 50 nằm giữa 30
(BnC còn giải được) và 80 (BnC không còn giải được). Ở n = 80 dùng thêm
REP1_S–REP4_S (GD1) và REP1_S–REP2_S (GD2), sinh với seed khác, để kiểm tra kết
luận không phụ thuộc một bộ khách.

### 2.2. Giới hạn thời gian

Đề gốc dùng 1800 s cho một chu kỳ và 3600 s cho hai chu kỳ, tức **tỉ lệ với số
chu kỳ**. Nhóm áp dụng cùng nguyên tắc: GD1 **30 s** cho một ngày, GD2
**150 s = 30 s × 5 ngày**. Giới hạn giống nhau cho mọi instance trong một giai
đoạn để CPU giữa các instance so sánh được.

### 2.3. Phương pháp và tham số

| Phương pháp | Tham số |
|---|---|
| Branch-and-Cut | HiGHS, `mip_rel_gap = 1e-4`, phá đối xứng (15), `random_seed` = seed lần chạy |
| BnC + ALNS start (chỉ GD2) | Như trên, nghiệm ALNS làm nghiệm khởi đầu |
| Tabu Search | 300 vòng, 40 láng giềng/vòng, tabu tenure 15 |
| ALNS | 300 vòng, 4 toán tử phá, 2 toán tử sửa, simulated annealing |
| GA | Quần thể 80, 300 thế hệ |

Ba metaheuristic có **cùng luật dừng**: tối đa 300 vòng/thế hệ, dừng sớm khi 50
vòng liên tiếp không cải thiện nghiệm tốt nhất. Lần chạy r dùng seed 2026 + r
cho mọi phương pháp.

### 2.4. Chỉ số

- **Giá trị TB:** trung bình giá trị thu hồi kỳ vọng (triệu đồng) trên 10 lần.
- **Gap TB:** (UB* − giá trị)/giá trị, với UB* là cận trên chặt nhất của
  Branch-and-Cut trong cùng lần chạy (xem [03_phuong_phap_giai.md](03_phuong_phap_giai.md#9-cách-đọc-kết-quả)).
- **CPU TB:** giây, chỉ tính thời gian giải.
- **Node TB:** số nút cây Branch-and-Bound của HiGHS.
- **Tối ưu:** số lần HiGHS chứng minh tối ưu trên 10 lần.

## 3. Kích thước instance

### GD1: một ngày

| Instance | n | K | H | |V| | |A| | Biến | Ràng buộc |
|---|---|---|---|---|---|---|---|
| INS_XS | 10 | 2 | 1 | 11 | 110 | 272 | 287 |
| INS_XS | 20 | 2 | 1 | 21 | 420 | 942 | 967 |
| INS_XS | 30 | 2 | 1 | 31 | 930 | 2.012 | 2.047 |
| INS_S | 50 | 2 | 1 | 51 | 2550 | 5.352 | 5.407 |
| INS_S | 80 | 2 | 1 | 81 | 6480 | 13.362 | 13.447 |
| REP1_S | 80 | 2 | 1 | 81 | 6480 | 13.362 | 13.447 |
| REP2_S | 80 | 2 | 1 | 81 | 6480 | 13.362 | 13.447 |
| REP3_S | 80 | 2 | 1 | 81 | 6480 | 13.362 | 13.447 |
| REP4_S | 80 | 2 | 1 | 81 | 6480 | 13.362 | 13.447 |

### GD2: năm ngày

| Instance | n | K | H | |V| | |A| | Biến | Ràng buộc |
|---|---|---|---|---|---|---|---|
| INS_XS | 10 | 2 | 5 | 11 | 110 | 1.460 | 1.395 |
| INS_XS | 20 | 2 | 5 | 21 | 420 | 4.910 | 4.755 |
| INS_XS | 30 | 2 | 5 | 31 | 930 | 10.360 | 10.115 |
| INS_S | 50 | 2 | 5 | 51 | 2550 | 27.260 | 26.835 |
| INS_S | 80 | 2 | 5 | 81 | 6480 | 67.610 | 66.915 |
| REP1_S | 80 | 2 | 5 | 81 | 6480 | 67.610 | 66.915 |
| REP2_S | 80 | 2 | 5 | 81 | 6480 | 67.610 | 66.915 |

Số biến tăng xấp xỉ theo K·H·n² do biến cung x(i,j,k,t). Cùng n = 80, mô hình
năm ngày lớn gấp khoảng 5 lần mô hình một ngày.

![Kích thước mô hình](../figures/experiments/model_size.png)

## 4. Kết quả GD1: một ngày, giới hạn 30 s

| Instance | n | Phương pháp | Giá trị TB | Gap TB (%) | CPU TB (s) | Node TB | Tối ưu |
|---|---|---|---|---|---|---|---|
| INS_XS | 10 | Tabu | 62,26 | 0,00 | 0,65 | – | – |
| INS_XS | 10 | ALNS | 62,26 | 0,00 | 0,02 | – | – |
| INS_XS | 10 | GA | 62,26 | 0,00 | 0,49 | – | – |
| INS_XS | 10 | Branch-and-Cut | 62,26 | 0,00 | 0,23 | 1,0 | 10/10 |
| INS_XS | 20 | Tabu | 96,97 | 0,00 | 0,42 | – | – |
| INS_XS | 20 | ALNS | 96,97 | 0,00 | 0,28 | – | – |
| INS_XS | 20 | GA | 96,97 | 0,00 | 1,13 | – | – |
| INS_XS | 20 | Branch-and-Cut | 96,97 | 0,00 | 1,15 | 1,0 | 10/10 |
| INS_XS | 30 | Tabu | 139,18 | 0,00 | 1,25 | – | – |
| INS_XS | 30 | ALNS | 139,18 | 0,00 | 1,05 | – | – |
| INS_XS | 30 | GA | 139,18 | 0,00 | 2,75 | – | – |
| INS_XS | 30 | Branch-and-Cut | 139,18 | 0,00 | 1,76 | 1,0 | 10/10 |
| INS_S | 50 | Tabu | 200,84 | 0,67 | 2,28 | – | – |
| INS_S | 50 | ALNS | 200,94 | 0,62 | 7,14 | – | – |
| INS_S | 50 | GA | 200,90 | 0,64 | 6,76 | – | – |
| INS_S | 50 | Branch-and-Cut | 68,51 | 270,88 | 30,63 | 3,5 | 0/10 |
| INS_S | 80 | Tabu | 273,43 | 2,74 | 2,21 | – | – |
| INS_S | 80 | ALNS | 274,81 | 2,22 | 13,91 | – | – |
| INS_S | 80 | GA | 274,32 | 2,40 | 7,71 | – | – |
| INS_S | 80 | Branch-and-Cut | 38,44 | 877,24 | 31,98 | 0,0 | 0/10 |
| REP1_S | 80 | Tabu | 282,27 | 3,63 | 2,03 | – | – |
| REP1_S | 80 | ALNS | 282,14 | 3,68 | 13,41 | – | – |
| REP1_S | 80 | GA | 283,22 | 3,28 | 7,42 | – | – |
| REP1_S | 80 | Branch-and-Cut | 35,60 | 2.005,39 | 32,62 | 0,0 | 0/10 |
| REP2_S | 80 | Tabu | 228,79 | 3,71 | 2,66 | – | – |
| REP2_S | 80 | ALNS | 228,82 | 3,70 | 14,72 | – | – |
| REP2_S | 80 | GA | 229,67 | 3,31 | 8,23 | – | – |
| REP2_S | 80 | Branch-and-Cut | 35,17 | 482,99 | 32,61 | 0,1 | 0/10 |
| REP3_S | 80 | Tabu | 265,45 | 2,57 | 2,26 | – | – |
| REP3_S | 80 | ALNS | 266,35 | 2,23 | 18,16 | – | – |
| REP3_S | 80 | GA | 266,23 | 2,27 | 8,27 | – | – |
| REP3_S | 80 | Branch-and-Cut | 38,26 | 24.330,70 | 32,59 | 0,0 | 0/10 |
| REP4_S | 80 | Tabu | 280,93 | 2,73 | 2,33 | – | – |
| REP4_S | 80 | ALNS | 281,01 | 2,70 | 14,83 | – | – |
| REP4_S | 80 | GA | 281,01 | 2,70 | 5,92 | – | – |
| REP4_S | 80 | Branch-and-Cut | 22,91 | 5.872,45 | 31,83 | 0,0 | 0/10 |

## 5. Kết quả GD2: năm ngày, giới hạn 150 s

| Instance | n | Phương pháp | Giá trị TB | Gap TB (%) | CPU TB (s) | Node TB | Tối ưu |
|---|---|---|---|---|---|---|---|
| INS_XS | 10 | Tabu | 109,92 | 0,00 | 0,72 | – | – |
| INS_XS | 10 | ALNS | 109,92 | 0,00 | 0,08 | – | – |
| INS_XS | 10 | GA | 109,92 | 0,00 | 0,99 | – | – |
| INS_XS | 10 | Branch-and-Cut | 109,92 | 0,00 | 0,79 | 1,0 | 10/10 |
| INS_XS | 10 | BnC + ALNS start | 109,92 | 0,00 | 0,21 | 0,0 | 10/10 |
| INS_XS | 20 | Tabu | 168,77 | 0,00 | 0,76 | – | – |
| INS_XS | 20 | ALNS | 168,77 | 0,00 | 1,09 | – | – |
| INS_XS | 20 | GA | 168,77 | 0,00 | 2,93 | – | – |
| INS_XS | 20 | Branch-and-Cut | 168,77 | 0,00 | 6,15 | 0,9 | 10/10 |
| INS_XS | 20 | BnC + ALNS start | 168,77 | 0,00 | 0,86 | 0,0 | 10/10 |
| INS_XS | 30 | Tabu | 246,80 | 0,00 | 2,57 | – | – |
| INS_XS | 30 | ALNS | 246,80 | 0,00 | 3,54 | – | – |
| INS_XS | 30 | GA | 246,80 | 0,00 | 10,21 | – | – |
| INS_XS | 30 | Branch-and-Cut | 246,80 | 0,00 | 19,62 | 56,5 | 10/10 |
| INS_XS | 30 | BnC + ALNS start | 246,80 | 0,00 | 1,94 | 0,0 | 10/10 |
| INS_S | 50 | Tabu | 361,56 | 0,17 | 4,98 | – | – |
| INS_S | 50 | ALNS | 361,90 | 0,08 | 9,91 | – | – |
| INS_S | 50 | GA | 361,59 | 0,16 | 18,34 | – | – |
| INS_S | 50 | Branch-and-Cut | 35,82 | 1.264,36 | 155,03 | 2,0 | 0/10 |
| INS_S | 50 | BnC + ALNS start | 361,90 | 0,08 | 154,74 | 1,8 | 0/10 |
| INS_S | 80 | Tabu | 545,20 | 1,09 | 5,80 | – | – |
| INS_S | 80 | ALNS | 549,03 | 0,38 | 30,67 | – | – |
| INS_S | 80 | GA | 542,49 | 1,59 | 23,30 | – | – |
| INS_S | 80 | Branch-and-Cut | 6,99 | 16.594,40 | 156,76 | 0,0 | 0/10 |
| INS_S | 80 | BnC + ALNS start | 549,03 | 0,38 | 157,37 | 0,0 | 0/10 |
| REP1_S | 80 | Tabu | 604,09 | 1,18 | 6,26 | – | – |
| REP1_S | 80 | ALNS | 608,27 | 0,49 | 33,47 | – | – |
| REP1_S | 80 | GA | 595,97 | 2,56 | 23,46 | – | – |
| REP1_S | 80 | Branch-and-Cut | 42,26 | 41.049,20 | 160,48 | 0,0 | 0/10 |
| REP1_S | 80 | BnC + ALNS start | 608,27 | 0,49 | 160,64 | 0,0 | 0/10 |
| REP2_S | 80 | Tabu | 489,51 | 1,01 | 6,56 | – | – |
| REP2_S | 80 | ALNS | 492,25 | 0,45 | 39,70 | – | – |
| REP2_S | 80 | GA | 483,75 | 2,21 | 23,86 | – | – |
| REP2_S | 80 | Branch-and-Cut | 2,96 | 14.769,40 | 160,03 | 0,0 | 0/10 |
| REP2_S | 80 | BnC + ALNS start | 492,25 | 0,45 | 160,24 | 0,0 | 0/10 |

## 6. Biểu đồ

![CPU](../figures/experiments/cpu_time.png)

![Gap](../figures/experiments/gap.png)

![Số node](../figures/experiments/bb_nodes.png)

![Giá trị ở 80 khách](../figures/experiments/objective_n80.png)

## 7. Nhận xét

1. **Instance nhỏ (n ≤ 30).** Branch-and-Cut chứng minh tối ưu 10/10 lần ở cả
   hai giai đoạn; Tabu, ALNS, GA đều tìm đúng nghiệm tối ưu (gap 0). Bài toán
   một ngày giải ngay tại nút gốc (1 node); bài toán 5 ngày 30 khách cần
   khoảng 56 node và 20 s, cho thấy liên kết giữa các ngày làm bài toán khó hơn
   rõ rệt dù cùng số khách.
2. **Ngưỡng khó (n = 50).** Branch-and-Cut hết giờ ở cả GD1 và GD2 với chỉ 2–4
   node: HiGHS dành gần hết thời gian cho nút gốc (cắt, presolve) mà chưa tìm
   được nghiệm nguyên tốt. Cận trên đã khá chặt (heuristic chỉ cách 0,1–0,7%)
   nhưng nghiệm của BnC rất kém.
3. **Instance lớn (n = 80).** Branch-and-Cut không rời nút gốc (0 node), giá
   trị chỉ bằng khoảng 1–14% của metaheuristic. Metaheuristic đạt gap 2,2–3,7% ở
   GD1 và 0,4–2,6% ở GD2. Kết quả giống nhau trên INS_S và các bộ REP, nên
   không phụ thuộc một bộ khách cụ thể.
4. **So sánh metaheuristic.** Ở GD2, ALNS cho gap nhỏ nhất (0,08–0,49%), Tabu
   nhanh nhất (5–7 s) với gap khoảng 1%, GA chậm và kém hơn. Ở GD1 ba phương
   pháp sát nhau, GA nhỉnh hơn một chút trên REP1_S và REP2_S.
5. **Khởi động ấm.** BnC + ALNS start có gap bằng đúng ALNS: HiGHS nhận nghiệm
   ALNS làm nghiệm ban đầu nhưng trong 150 s không tìm được nghiệm tốt hơn và
   cũng không đủ thời gian đóng gap. Ở n = 30, khởi động ấm giảm CPU từ 19,6 s
   xuống 1,9 s.
6. **Gap của heuristic là cận bảo thủ.** Khi BnC chưa tối ưu, UB* có thể còn
   lỏng, nên chất lượng thật của heuristic có thể tốt hơn con số gap.

## 8. Mở rộng: tĩnh, cuốn chiếu và tham lam

Cấu hình: [v3_static_vs_rolling_report.json](../configs/v3_static_vs_rolling_report.json),
runner [run_v3_static_vs_rolling.jl](../core/run_v3_static_vs_rolling.jl). Instance
INS_S (80 khách, 2 cán bộ, 5 ngày, m = 2), bộ giải ALNS cho cả ba chính sách,
20 kịch bản Monte Carlo cho mỗi kịch bản p, cùng số ngẫu nhiên giữa các chính
sách. Kết quả: `outputs/v3_INS_S/static_vs_rolling/paired_summary.csv`.

![Tĩnh, cuốn chiếu, tham lam](../figures/experiments/static_vs_rolling.png)

Kết quả tham khảo từ bộ dữ liệu (script Python mẫu, 100 kịch bản, chỉ tĩnh và
cuốn chiếu; `collection_routing_dataset_v3/ket_qua/BAO_CAO_MO_PHONG.md`):
trên INS_S, cuốn chiếu hơn tĩnh −0,2% (THAP), +0,3% (CO_SO), +0,7% (CAO); trên
INS_L lần lượt +1,6%, +3,6%, +4,1%. Lợi ích của việc lập lại kế hoạch tăng khi
xác suất trả nợ cao và khi số khách lớn.

## 9. Hình minh họa kế hoạch

Kế hoạch 5 ngày của INS_S (ALNS). Mỗi cán bộ một họ màu; ngày 1 đậm nhất,
nhạt dần đến ngày 5.

![Theo ngày](../figures/INS_S_n80_H5/routes_by_day.png)

![Theo cán bộ](../figures/INS_S_n80_H5/routes_by_officer.png)

![Lịch thăm](../figures/INS_S_n80_H5/schedule.png)

## 10. Tái lập

```powershell
# Bảng chính (khoảng 4 giờ, GD1 và GD2 song song)
powershell -ExecutionPolicy Bypass -File scripts
un_experiments.ps1
# So sánh ba chính sách (khoảng 3 giờ)
& "D:\julia-1.13.2in\julia.exe" --project=. core/run_v3_static_vs_rolling.jl configs/v3_static_vs_rolling_report.json
# Hình
python core/plot_results.py
python core/plot_v3_plan.py
```
