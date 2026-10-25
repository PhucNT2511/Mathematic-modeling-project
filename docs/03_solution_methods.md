# Các phương pháp giải bài toán tối ưu lộ trình thu hồi nợ

## 1. Mục đích tài liệu

Tài liệu này giải thích các phương pháp đang được cài đặt trong dự án, gắn trực
tiếp với dữ liệu, biến quyết định và mã nguồn hiện tại. Mục tiêu là trả lời ba
câu hỏi cho mỗi phương pháp:

1. Phương pháp nhận dữ liệu nào?
2. Phương pháp tạo và cải thiện kế hoạch thu hồi nợ như thế nào?
3. Kết quả trả về có ý nghĩa gì và có bảo đảm tối ưu hay không?

Tài liệu mô hình toán học đầy đủ nằm trong
[01_mo_hinh_toan.md](01_mo_hinh_toan.md).

## 2. Dữ liệu đầu vào

Mọi phương pháp đọc cùng một đối tượng `DebtRoutingData` do
`data_processing/load_v3_data.jl` dựng từ bộ dữ liệu
`collection_routing_dataset_v3` (xem [00_tong_quan.md](00_tong_quan.md#3-dữ-liệu)):

- `debt[i]`: số tiền mục tiêu w(i) (triệu đồng);
- `probability[i,t]`: xác suất thu hồi p(i,t) theo kịch bản p đã chọn;
- `distance`, `travel_time`: ma trận (n+1)×(n+1) giữa chi nhánh và khách,
  tính bằng đường ngắn nhất trên mạng đường OSM;
- `service_time[i]`, `daily_budget[k,t]`, `max_visits[i]`.

Vì mọi phương pháp dùng đúng cùng dữ liệu này, khác biệt kết quả chỉ đến từ
thuật toán.

## 3. Biểu diễn nghiệm dùng chung

### 3.1. Biểu diễn trong MILP

Mô hình chính xác dùng:

- x(i,j,k,t): cán bộ k đi từ i đến j trong ngày t.
- y(i,k,t): cán bộ k thăm khách hàng i trong ngày t.
- z(k,t): cán bộ k có tuyến trong ngày t.
- lambda(i,S): khách hàng i chọn lịch thăm S.
- u(i,k,t): thứ tự MTZ để loại chu trình con.

### 3.2. Biểu diễn trong heuristic

GA, Tabu và ALNS dùng ma trận gene:

$$
G_{it}\in\{0,1,\ldots,K\}.
$$

- G(i,t)=0: không thăm khách hàng i trong ngày t.
- G(i,t)=k: cán bộ k thăm khách hàng i trong ngày t.

Ma trận gene quyết định khách hàng, ngày và cán bộ. Thứ tự đi trong mỗi tuyến
được dựng sau bằng nearest-neighbor và cải thiện bằng 2-opt.

### 3.3. Dựng tuyến

Với mỗi cặp cán bộ-ngày:

1. Lấy tất cả khách hàng được gán cho cán bộ đó.
2. Bắt đầu từ chi nhánh.
3. Chọn khách hàng chưa thăm gần vị trí hiện tại nhất.
4. Lặp đến khi hết khách hàng rồi quay về chi nhánh.
5. Thử đảo các đoạn bằng 2-opt để giảm quãng đường.

Ví dụ:

    0 -> 5 -> 2 -> 8 -> 0

trong đó 0 là chi nhánh.

### 3.4. Repair nghiệm

Mọi heuristic dùng cùng thủ tục repair:

1. Nếu khách hàng vượt max_visits, giữ những ngày có xác suất cao nhất.
2. Dựng tuyến cho từng cán bộ và từng ngày.
3. Tính tổng thời gian di chuyển và phục vụ.
4. Nếu vượt ngân sách, bỏ lần thăm có mất mát kỳ vọng biên nhỏ nhất.
5. Lặp đến khi mọi tuyến khả thi.

Nhờ vậy, giá trị được báo cáo bởi heuristic luôn thuộc một kế hoạch có thể
thực hiện theo các ràng buộc hiện tại.

### 3.5. So sánh hai nghiệm heuristic

Hai nghiệm được so sánh theo thứ tự từ điển:

1. Nghiệm có giá trị thu hồi kỳ vọng lớn hơn được ưu tiên.
2. Nếu giá trị kỳ vọng bằng nhau, nghiệm có tổng quãng đường nhỏ hơn được ưu
   tiên.

Không cộng tiền và kilomet thành một biểu thức tùy ý, tránh phải chọn một hệ
số quy đổi thiếu căn cứ.

## 4. Branch-and-Cut của HiGHS

File: core/branch_and_cut.jl.

JuMP chuyển mô hình MILP sang HiGHS. HiGHS thực hiện:

1. Presolve để loại biến và ràng buộc dư.
2. Giải LP relaxation tại nút gốc.
3. Thêm cutting planes để loại nghiệm phân số mà không loại nghiệm nguyên hợp
   lệ.
4. Dùng heuristic nội bộ để tìm incumbent.
5. Phân nhánh nếu vẫn còn biến phân số.
6. Duy trì cận trên và nghiệm nguyên tốt nhất.
7. Dừng khi gap đủ nhỏ hoặc hết time limit.

Với bài toán cực đại:

$$
\operatorname{gap}
=
\frac{\text{upper bound}-\text{incumbent}}
{\text{upper bound}}\times100\%.
$$

Nếu objective bằng bound thì gap bằng 0 và nghiệm được chứng minh tối ưu.

Hiện code MILP tối đa hóa giá trị thu hồi kỳ vọng. Mục tiêu quãng đường chưa
được giải thành pha MILP thứ hai; quãng đường hiện chỉ là tiêu chí phụ trong
các heuristic.

## 5. Genetic Algorithm

File: core/genetic_algorithm.jl.

### Khởi tạo

Mỗi cá thể là một ma trận G. Mỗi ô được chọn thăm với xác suất 0,35, sau đó
gán ngẫu nhiên cho một cán bộ. Repair đưa cá thể về miền khả thi.

### Một thế hệ

1. Đánh giá giá trị kỳ vọng và quãng đường của toàn bộ quần thể.
2. Xếp hạng theo giá trị kỳ vọng rồi quãng đường.
3. Giữ nguyên elite_count cá thể tốt nhất.
4. Tournament selection chọn bố và mẹ.
5. Uniform crossover chọn từng gene từ bố hoặc mẹ.
6. Mutation thay một gene bằng 0 hoặc một cán bộ ngẫu nhiên.
7. Repair cá thể con.
8. Lặp đến khi đủ population_size.

Tham số chuẩn hiện tại:

- population_size=80.
- generations=150.
- mutation_rate=0,03.
- elite_count=4.

Profile large giảm còn 60 cá thể và 100 thế hệ.
Profile xlarge dùng 40 cá thể và 60 thế hệ.

### Ý nghĩa

GA tìm kiếm nhiều vùng đồng thời nhưng crossover có thể phá cấu trúc tuyến tốt.
Repair vì vậy là thành phần bắt buộc.

## 6. Tabu Search

File: core/tabu_search.jl.

### Nghiệm đầu

Các lần thăm được xếp theo tỷ lệ gần đúng:

$$
\frac{w_i p_{it}}
{s_i+\tau_{0i}+\tau_{i0}}.
$$

Thuật toán chèn lần lượt các quyết định có tỷ lệ cao nếu vẫn khả thi.

### Một vòng lặp

1. Chọn ngẫu nhiên một khách hàng và một ngày.
2. Thay giá trị gene bằng không thăm hoặc một cán bộ khác.
3. Repair và đánh giá nghiệm.
4. Lặp để tạo neighborhood_size láng giềng.
5. Chọn láng giềng hợp lệ tốt nhất, kể cả khi kém hơn nghiệm hiện tại.
6. Cấm quay lại giá trị cũ trong tabu_tenure vòng.
7. Nếu move tabu tạo nghiệm toàn cục tốt nhất, aspiration cho phép thực hiện.

Tham số chuẩn:

- iterations=300.
- neighborhood_size=50.
- tabu_tenure=15.

Tabu memory giúp thuật toán không lặp qua lại giữa một vài kế hoạch.

## 7. Adaptive Large Neighborhood Search

File: core/alns.jl.

ALNS phá một phần lớn của kế hoạch rồi xây lại, phù hợp với việc chuyển nhiều
khách hàng giữa ngày và cán bộ.

### Toán tử phá

1. Random removal: xóa ngẫu nhiên các lần thăm.
2. Worst-value removal: xóa các lần thăm có giá trị biên thấp.
3. Related removal: chọn một khách hàng rồi xóa các khách hàng gần nó.
4. Route removal: xóa một phần của một tuyến cán bộ-ngày.

### Toán tử sửa

1. Greedy insertion: chọn phép chèn có giá trị kỳ vọng tăng lớn nhất, hòa thì
   chọn quãng đường tăng nhỏ nhất.
2. Regret-2 insertion: ưu tiên khách hàng chịu thiệt nhiều nhất nếu không dùng
   vị trí chèn tốt nhất.

### Một vòng lặp

1. Roulette wheel chọn destroy và repair theo trọng số.
2. Xóa khoảng 20% số lần thăm.
3. Chèn lại đến khi không còn phép chèn khả thi.
4. Dùng simulated annealing để quyết định chấp nhận nghiệm mới.
5. Chấm điểm toán tử: 10 cho nghiệm toàn cục mới, 5 cho cải thiện nghiệm hiện
   tại và 1 cho nghiệm được chấp nhận.
6. Sau mỗi 25 vòng, cập nhật trọng số với reaction factor 0,2.

ALNS chuẩn chạy 500 vòng; profile large chạy 300 vòng.

## 8. Quy trình thí nghiệm

`core/run_v3_experiments.jl` chạy cho mỗi instance, mỗi lần chạy r = 1..10
(seed = 2026 + r):

1. Tabu, ALNS, GA với cùng ngân sách: tối đa 300 vòng/thế hệ, dừng sớm khi
   50 vòng liên tiếp không cải thiện nghiệm tốt nhất.
2. Branch-and-Cut (HiGHS) với giới hạn thời gian của giai đoạn
   (GD1: 30 s, GD2: 150 s), `mip_rel_gap = 1e-4`, ràng buộc phá đối xứng (15).
3. Ở GD2 thêm Branch-and-Cut khởi động ấm từ nghiệm ALNS.
4. Ghi giá trị, cận trên, trạng thái, CPU và số node B&B của từng lần chạy vào
   `outputs/experiments/<config>/runs.csv`; tổng hợp trung bình vào `summary.csv`.

## 9. Cách đọc kết quả

### Objective

Tổng tiền thu hồi kỳ vọng, không phải số tiền chắc chắn thu được.

### Status

- OPTIMAL: HiGHS đã chứng minh tối ưu (gap ≤ 0,01%).
- TIME_LIMIT: có nghiệm nhưng chưa chứng minh tối ưu khi hết giờ.
- HEURISTIC: phương pháp không cung cấp chứng minh tối ưu.

### Gap

Bài toán là cực đại hóa nên cận trên UB do HiGHS cung cấp. Trong mỗi lần chạy,
UB* là cận nhỏ nhất (chặt nhất) trong các lần gọi Branch-and-Cut, và

$$
\operatorname{gap}=rac{UB^*-	ext{objective}}{	ext{objective}}	imes100\%.
$$

Mẫu số là giá trị nghiệm, giống quy ước của HiGHS. Gap = 0 nghĩa là nghiệm đã
được chứng minh tối ưu. Gap của heuristic là đánh giá bảo thủ: nghiệm thật sự
có thể tốt hơn so với tối ưu mà UB* chưa đủ chặt để chứng minh.

### Số node

`MOI.NodeCount` của HiGHS: số nút cây Branch-and-Bound đã duyệt. Bằng 0 hoặc 1
nghĩa là bài toán được giải (hoặc dừng) ngay tại nút gốc.

### CPU

Chỉ tính thời gian giải, không tính đọc CSV và dựng dữ liệu.

## 10. Phạm vi và hạn chế

1. Hồ sơ nợ và xác suất là dữ liệu mô phỏng có nguồn (xem README bộ dữ liệu),
   chưa hiệu chỉnh từ ngân hàng thật.
2. Các lần thăm được giả định độc lập có điều kiện; tiền thu theo mô hình
   "toàn bộ hoặc không".
3. Heuristic dựng tuyến bằng nearest-neighbor và 2-opt, không tối ưu chính xác
   thứ tự trong từng tuyến.
4. Instance nhỏ dễ khiến mọi phương pháp đạt gap 0, nên bộ thí nghiệm tăng dần
   tới 80 khách và dùng thêm 4 bộ REP để kiểm tra độ ổn định.
