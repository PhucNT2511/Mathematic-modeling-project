# Bộ dữ liệu v3: Tối ưu lộ trình thu hồi nợ cho cán bộ ngân hàng tại Hà Nội

Bộ dữ liệu phục vụ đề tài MPTOP có tiếp cận lại (MILP, Julia + JuMP), kèm so sánh kế hoạch tĩnh và cuốn chiếu bằng mô phỏng Monte Carlo. Phiên bản 3 sửa theo 10 mục góp ý; bảng đối chiếu nằm trong `DOI_CHIEU_YEU_CAU.md`.

> **Khách hàng là mô phỏng.** Không có bản ghi khách hàng thật, họ tên, số hợp đồng hay địa chỉ số nhà.
> - **Dữ liệu thật:** mạng đường, ranh giới hành chính, dân số phường, vị trí chi nhánh (OpenStreetMap) và hồ sơ nhân khẩu học (NVIDIA Nemotron-Personas-Vietnam).
> - **Giả định:** xác suất thu hồi và phần lớn tham số khoản vay. Chưa dùng số liệu thu hồi của ngân hàng Việt Nam.

## 1. Cái gì thật, cái gì giả định

| Thành phần | Loại | Chi tiết |
|---|---|---|
| Mạng đường | **OSM thật** | Geofabrik `vietnam-latest.osm.pbf`, dữ liệu đến 18/10/2026 20:25 UTC. Mạng xe máy: 57.242 nút, 130.220 cung có hướng, 6,6% cung một chiều, liên thông mạnh |
| Ranh giới 6 quận cũ | **OSM thật** | Relation `boundary=historic`, `end_date=2025-06-30` |
| Phường 2025 và dân số | **OSM thật** | Relation `admin_level=6`. Thẻ `population` có nguồn gis.vn, ngày 01/07/2025 |
| Mật độ công trình | **OSM thật** | 86.084 tâm công trình trong khung đệm |
| Chi nhánh CN01 | **OSM thật** (vị trí) | POI VPBank, 89 Phố Láng Hạ. Chức năng chi nhánh trong bài toán là giả định |
| Hồ sơ khách hàng | **NVIDIA thật** | Giới tính, tuổi, hôn nhân, học vấn, nghề lấy nguyên từ hồ sơ. Commit `950724d…`, 954 hồ sơ Hà Nội đô thị, 827 hồ sơ tuổi 20–65 |
| Cơ cấu nhóm nợ | Số liệu công bố | VPBank Q1/2025 và 27 ngân hàng niêm yết 2024 (toàn danh mục) |
| Hạn mức và tỷ lệ sử dụng thẻ | UCI (hình dạng phân bố) | Lấy hình dạng phân bố của khách trễ ≥ 2 tháng. Trung vị hạn mức 30 triệu là giả định |
| Gốc vay sản phẩm khác, lãi suất, kỳ hạn | **Giả định** | Log-chuẩn, xem `tham_so_san_pham` |
| Xác suất thu hồi p(i,t) | **Giả định** | Có 3 kịch bản THAP / CO_SO / CAO |
| Tốc độ, thời gian phục vụ, kỳ 02–06/11/2026 | **Giả định** | |

## 2. Thư mục

```
csv/                    23 bảng (UTF-8 có BOM, dấu thập phân ".")
collection_routing_dataset_v3.xlsx   cùng nội dung, sheet data_dictionary đứng đầu
raw/                    dữ liệu gốc đã trích (OSM, Nemotron, UCI) + README_raw.md
build/                  tệp trung gian của bước 1 (mạng chưa xuất bảng, đa giác ranh giới)
scripts/
  00_trich_xuat_trinh_duyet.js   lấy OSM (đọc PBF) và Nemotron trong trình duyệt
  01_xay_dung_mang_duong.py      lọc đường xe máy, một chiều, liên thông mạnh, rút gọn
  02_sinh_du_lieu.py             sinh khách hàng, khoản nợ, p, v(i,S), ma trận, thể hiện, Monte Carlo
  03_mo_phong_tinh_cuon_chieu.py heuristic minh họa: tĩnh và cuốn chiếu, độ nhạy p
  04_dong_goi.py                 nguồn, từ điển dữ liệu, Excel
  05_kiem_tra_du_lieu.py         34 phép kiểm tra, ghi validation_report.txt
  06_tao_sha256.py               ghi SHA256SUMS.txt (chạy trước bước 5)
ket_qua/                kết quả mô phỏng minh họa + BAO_CAO_MO_PHONG.md
de_xuat/Collection_routing_optimization_v3.docx   đề xuất đã sửa mục 2–3 cho đúng nguồn
hinh/ban_do_main.png    bản đồ mạng đường và 500 khách của bộ MAIN
DOI_CHIEU_YEU_CAU.md    đối chiếu 10 mục sửa
SHA256SUMS.txt          mã kiểm tra mọi tệp
validation_report.txt   kết quả kiểm tra
```

## 3. Các bảng

| Bảng | Số dòng | Khóa | Nội dung |
|---|---:|---|---|
| `tham_so_mo_hinh` | 16 | tham_so | Tham số toàn cục, có cột nguồn |
| `ngay_ky` | 5 | ngay_thu | 02–06/11/2026 |
| `tham_so_nhom_no` | 4 | nhom_no | DPD, tỷ trọng, tham số p cơ sở, thời gian phục vụ |
| `tham_so_san_pham` | 5 | loai_san_pham | Lãi suất, kỳ hạn, phân bố số tiền, nguồn |
| `kich_ban_xac_suat` | 3 | kich_ban_p | THAP ×0,5 / CO_SO / CAO ×1,5 (chặn 0,95) |
| `toc_do_loai_duong` | 13 | highway | Tốc độ xe máy theo loại đường OSM |
| `nut_duong` | 57.242 | node_id (ID OSM) | Nút mạng, quận cũ, phường 2025 |
| `canh_duong` | 130.220 | edge_id | Cung có hướng, way OSM, tên đường, một chiều |
| `phuong_lay_mau` | 27 | phuong_2025 | Dân số, diện tích trong vùng, tỷ trọng hạn ngạch |
| `chi_nhanh` | 1 | chi_nhanh_id | CN01 tại POI OSM |
| `can_bo` | 4 | can_bo_id | Mã cán bộ, xe máy, 480 phút |
| `bo_khach_hang` | 5 | bo_khach_hang_id | MAIN (500) và REP1–REP4 (200 mỗi bộ), mỗi bộ một seed |
| `khach_hang` | 1.300 | khach_hang_id | Hồ sơ, vị trí, khoản vay, khoản nợ |
| `xac_suat_thu_hoi` | 19.500 | khách × kịch bản × ngày | p(i,t) |
| `lich_tiep_can` | 40.300 | lich_id | 31 lịch/khách, v(i,S) cho 3 kịch bản |
| `ma_tran_di_chuyen` | 412.605 | bộ × từ × đến | Thời gian và quãng đường trên tuyến nhanh nhất |
| `thuc_the` | 12 | thuc_the_id | 4 thể hiện lồng nhau của MAIN và 8 thể hiện lặp |
| `thuc_the_khach_hang` | 1.930 | | Thành viên thể hiện |
| `thuc_the_can_bo` | 31 | | Cán bộ của thể hiện |
| `thiet_ke_thi_nghiem` | 972 | thi_nghiem_id | Lưới cấu hình, có mức ưu tiên |
| `kich_ban_monte_carlo` | 650.000 | kịch bản × khách × ngày | Số ngẫu nhiên chung u |
| `nguon_du_lieu` | 7 | nguon_id | Nguồn, phiên bản, giấy phép, phạm vi dùng |
| `data_dictionary` | (mọi cột) | bảng, cột | Kiểu, khóa, mô tả |

**Quan hệ chính:**
- `canh_duong.u/v`, `chi_nhanh.node_id` và `khach_hang.node_id` tham chiếu `nut_duong.node_id`.
- `khach_hang.khach_hang_id` được dùng trong `xac_suat_thu_hoi`, `lich_tiep_can`, `kich_ban_monte_carlo` và `thuc_the_khach_hang`.
- `ma_tran_di_chuyen` lọc theo `bo_khach_hang_id` của thể hiện; tập điểm là {CN01} ∪ khách của bộ đó.

## 4. Mạng đường

- **Phương tiện là xe máy.** Bị loại:
  - `motorway`/`motorway_link` (cấm xe máy);
  - đường đi bộ, đường mòn, bậc thang, đường đang xây;
  - way có `motorcycle=no`;
  - way có `motor_vehicle=no`, `vehicle=no`, `access=no/private`, trừ khi `motorcycle=yes`;
  - `service=parking_aisle/drive-through`.
- **Một chiều:** `oneway=yes/1/true/-1`, `junction=roundabout`. Riêng `oneway:motorcycle=no` thì xe máy được đi hai chiều.
- **Tốc độ** (km/h, giả định): trunk 30, primary 28, secondary 25, tertiary 22, unclassified 18, residential 15, service và living_street 10. Nếu `maxspeed` nhỏ hơn thì lấy `maxspeed`.
- **Liên thông mạnh:** chỉ giữ thành phần liên thông mạnh lớn nhất. Vì vậy mọi khách đều đi tới và về chi nhánh được (kiểm tra 05 và 12).
- **Rút gọn:** chỉ giữ nút giao, nút cụt và nút đổi way/loại đường. Nếu có cung song song thì giữ cung nhanh nhất.
- **Ma trận:** Dijkstra theo thời gian. Quãng đường là độ dài của đúng tuyến nhanh nhất, nên thời gian và quãng đường cùng một tuyến (kiểm tra 10). Thời gian trung bình giữa hai khách khoảng 11,9 phút, quãng đường 4,8 km, tốc độ hiệu dụng khoảng 24 km/h. Ma trận bất đối xứng ở 95,8% cặp điểm.

## 5. Vị trí khách hàng (lấy mẫu có chủ đích)

1. **Vùng lấy mẫu:** giao của 6 quận cũ và khung lat 20,980–21,050, lon 105,775–105,870.
2. **Hạn ngạch theo phường 2025:** dân số phường × (diện tích phường trong vùng / diện tích phường). Diện tích ước bằng lưới 50 m. Số khách mỗi phường lệch hạn ngạch không quá 1 do làm tròn.
3. **Chọn nút trong phường:** chỉ chọn nút trên đường dân cư (residential, living_street, service, unclassified, tertiary). Xác suất chọn tỷ lệ với số công trình OSM trong bán kính 100 m. Hai khách trong cùng bộ cách nhau ít nhất 40 m.
4. **Vị trí là nút mạng xấp xỉ, không phải địa chỉ đã xác minh.** Bảng chỉ ghi quận cũ và phường 2025.

## 6. Khoản nợ

**Ba đại lượng tách bạch:**

| Cột | Ý nghĩa |
|---|---|
| `tong_du_no_vnd` | Dư nợ gốc còn lại theo lịch trả góp niên kim. Với thẻ: hạn mức × tỷ lệ sử dụng |
| `so_tien_qua_han_vnd` | Nhóm 2–3, và mọi khoản có tài sản bảo đảm: (số kỳ quá hạn × kỳ trả) + lãi quá hạn 150% (TT 39/2016). Nhóm 4–5 không có tài sản bảo đảm (thẻ, tín chấp): toàn bộ dư nợ đến hạn + lãi quá hạn (giả định) |
| `so_tien_muc_tieu_vnd` = w(i) | Số tiền một lần thu thành công. Bằng khoản quá hạn |

**Thẻ tín dụng.** Lấy từ UCI hai thứ: hình dạng phân bố hạn mức (chia cho trung vị) và tỷ lệ BILL_AMT1/LIMIT_BAL của khách trễ ≥ 2 tháng. Số tiền sao kê của UCI không được dùng làm khoản quá hạn.

**Điều kiện sản phẩm theo hồ sơ (giả định):**
- Vay kinh doanh hộ cá thể: chỉ nhóm nghề Kinh doanh.
- Tín chấp: chỉ làm công ăn lương hoặc lao động tự do, tối đa 60 tuổi.
- Vay mua xe: 21–60 tuổi.
- Thế chấp nhà: 25–60 tuổi.
- Hưu trí và không có thu nhập thường xuyên: chỉ thẻ.

**Mốc thời gian khoản vay:** kỳ hạn luôn đủ dài để khoản vay chưa đáo hạn khi bắt đầu quá hạn. Điều kiện: số kỳ đã trả + số kỳ quá hạn ≤ kỳ hạn.

## 7. Xác suất thu hồi và mô hình tiền thu

- **Công thức (giả định):** p(i,t) = h · p₀(g) · (1 − 0,30·f(i)) · (1 − δ(g))^(t−1), chặn trên 0,95.
  - f(i) là vị trí DPD trong khoảng của nhóm.
  - h = 0,5 / 1 / 1,5 cho THAP / CO_SO / CAO.
  - p₀ = 0,35 / 0,22 / 0,12 / 0,06 và δ = 0,06 / 0,05 / 0,04 / 0,03 cho nhóm 2–5.
- **Phạm vi phụ thuộc:** p chỉ phụ thuộc nhóm nợ, DPD, ngày và kịch bản. Không dùng nhân khẩu học, không dùng xác suất vỡ nợ.
- **Mô hình tiền thu:** `mo_hinh_thu_tien = TOAN_BO_HOAC_KHONG`. Thành công thu đủ w(i); thất bại thu 0; khách đã trả không được tiếp cận nữa.
- **Giá trị lịch:** v(i,S) = w(i)·[1 − Π_{t∈S}(1 − p(i,t))], tính sẵn trong `lich_tiep_can` cho 3 kịch bản (cột `v_vnd_thap`, `v_vnd_co_so`, `v_vnd_cao`). Lọc `so_lan ≤ m` để chọn m.
- **Trả một phần** cần sửa đồng thời dữ liệu trạng thái, hàm mục tiêu và mô phỏng; phiên bản này không hỗ trợ.

## 8. Quy định so sánh tĩnh – cuốn chiếu

| | Tĩnh | Cuốn chiếu |
|---|---|---|
| Lập kế hoạch | Một lần đầu kỳ cho 5 ngày | Đầu mỗi ngày t, cho ngày t..5 |
| Khách đã trả | Bỏ qua lần tiếp cận; đi thẳng tới khách kế tiếp chưa trả trong tuyến; không chèn thêm khách | Loại khỏi danh sách trước khi lập lại kế hoạch |
| Số lần đã tiếp cận | Theo kế hoạch | Giữ lại: m còn = m − số lần đã tiếp cận |
| Thực hiện | Toàn bộ kế hoạch | Chỉ tuyến của ngày t |
| Kết quả tiếp cận (i,t) ở kịch bản s | Thành công nếu u(s,i,t) < p(i,t) | Như tĩnh (cùng bảng u) |

**Báo cáo cho mỗi thể hiện × kịch bản p:**
- trung bình tiền thu và quãng đường;
- thời gian tính toán;
- trung bình chênh lệch ghép cặp (cuốn chiếu − tĩnh) và KTC 95% trên 100 kịch bản.

`scripts/03_mo_phong_tinh_cuon_chieu.py` làm đúng quy trình này bằng heuristic. Kết quả minh họa nằm ở `ket_qua/BAO_CAO_MO_PHONG.md`:
- Ở CO_SO và CAO, cuốn chiếu thu thêm 1,0–4,1% và có ý nghĩa ở mọi thể hiện cỡ M và L.
- Ở THAP, chênh lệch thường không có ý nghĩa.
- Kết luận này phụ thuộc vào mức p giả định.

## 9. Thiết kế thí nghiệm

- **Thể hiện:**
  - INS_XS (30 khách) ⊂ INS_S (80) ⊂ INS_M (200) ⊂ INS_L (500), lấy từ bộ MAIN;
  - REPk_S (80) ⊂ REPk_M (200) cho k = 1..4, lấy từ các bộ khách sinh với seed khác.
- **`thiet_ke_thi_nghiem`:** mỗi thể hiện × 2/3/4 cán bộ × 360/420/480 phút × m = 1/2/3 × 3 kịch bản p.
  - `muc_uu_tien = 1`: cấu hình cơ sở (cán bộ mặc định, 480 phút, m = 2, CO_SO).
  - `muc_uu_tien = 2`: đổi đúng một yếu tố so với cơ sở.
  - `muc_uu_tien = 3`: các tổ hợp còn lại.

## 10. Tái tạo

```powershell
# Python 3.10+ với pandas numpy scipy networkx matplotlib openpyxl xlrd (Anaconda có sẵn)
python scripts/01_xay_dung_mang_duong.py
python scripts/02_sinh_du_lieu.py
python scripts/03_mo_phong_tinh_cuon_chieu.py      # khoảng 10 phút
python scripts/04_dong_goi.py
python scripts/06_tao_sha256.py                    # ghi mã kiểm tra tệp
python scripts/05_kiem_tra_du_lieu.py              # mã thoát 0 = đạt
```
- Chạy với cùng `raw/` và cùng seed sẽ cho kết quả giống hệt.
- Nếu đổi mạng đường, chạy lại từ bước 1, vì ma trận phải tính lại.
- Nếu đổi tiền hoặc p, chạy lại từ bước 2, vì v(i,S) phải tính lại.

Đọc bằng Julia:
```julia
using CSV, DataFrames
kh  = CSV.read("csv/khach_hang.csv", DataFrame)
ins = filter(r -> r.thuc_the_id == "INS_M", CSV.read("csv/thuc_the_khach_hang.csv", DataFrame))
mt  = filter(r -> r.bo_khach_hang_id == "MAIN", CSV.read("csv/ma_tran_di_chuyen.csv", DataFrame))
```

## 11. Hạn chế

- **Lọc "Hà Nội" trong Nemotron dựa trên nội dung mô tả**, vì bộ dữ liệu không có trường tỉnh/thành. Cách này có thể giữ hồ sơ chỉ có liên hệ với Hà Nội, và sót hồ sơ không nhắc tên thành phố.
- **Mẫu Nemotron dùng chung giữa các bộ.** 827 hồ sơ đủ cho bộ MAIN (500 khách không lặp). Các bộ REP rút độc lập từ cùng 827 hồ sơ, nên hồ sơ có thể trùng giữa các bộ, nhưng không trùng trong một bộ.
- **Dân số phường lấy từ thẻ OSM**, nguồn ghi là gis.vn. Chưa đối chiếu với nghị quyết sắp xếp đơn vị hành chính.
- **Cơ cấu nhóm nợ là của toàn danh mục ngân hàng**, không phải của danh sách thu hồi thực địa.
- **Tốc độ cố định theo loại đường.** Chưa mô hình hóa ùn tắc theo giờ hay ngập úng.
- **Kết quả ở `ket_qua/` là của heuristic**, không phải lời giải MILP.

## 12. Ghi nguồn

- © OpenStreetMap contributors, ODbL 1.0. Bản trích Geofabrik.
- NVIDIA, *Nemotron-Personas-Vietnam*, CC BY 4.0, https://huggingface.co/datasets/nvidia/Nemotron-Personas-Vietnam
- Yeh, I.-C. (2009). *Default of Credit Card Clients* [Dataset]. UCI Machine Learning Repository. https://doi.org/10.24432/C55S3H (CC BY 4.0)
- Các số liệu công bố và văn bản pháp luật: xem `csv/nguon_du_lieu.csv`.
