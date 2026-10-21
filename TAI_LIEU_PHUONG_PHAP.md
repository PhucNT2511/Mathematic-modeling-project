# Các phương pháp giải bài toán tối ưu lộ trình thu hồi nợ

## 1. Mục đích tài liệu

Tài liệu này giải thích các phương pháp đang được cài đặt trong dự án, gắn trực
tiếp với dữ liệu, biến quyết định và mã nguồn hiện tại. Mục tiêu là trả lời ba
câu hỏi cho mỗi phương pháp:

1. Phương pháp nhận dữ liệu nào?
2. Phương pháp tạo và cải thiện kế hoạch thu hồi nợ như thế nào?
3. Kết quả trả về có ý nghĩa gì và có bảo đảm tối ưu hay không?

Tài liệu mô hình toán học đầy đủ nằm trong
[Mo_hinh_toan_va_chien_luoc_giai.md](Mo_hinh_toan_va_chien_luoc_giai.md).

## 2. Dữ liệu đầu vào

### 2.1. Hồ sơ khách hàng

File data/generated/customers.csv chứa một dòng cho mỗi khách hàng:

- customer_id: mã khách hàng.
- latitude, longitude: tọa độ mô phỏng trong khu vực Hà Nội.
- debt_vnd: số tiền nợ.
- overdue_days: số ngày quá hạn.
- service_hours: thời gian làm việc trực tiếp với khách hàng.
- max_visits: số lần thăm tối đa.
- p_day_1, ..., p_day_H: xác suất thu hồi theo từng ngày.

Ví dụ, nếu một khách hàng nợ 100 triệu đồng và có xác suất thu hồi 0,6 trong
ngày đầu thì giá trị kỳ vọng của một lần thăm là:

$$
100\,000\,000 \times 0.6 = 60\,000\,000\text{ đồng}.
$$

Nếu khách hàng được thăm vào tập ngày S, giá trị thu hồi kỳ vọng là:

$$
v_{iS}
=
w_i\left[1-\prod_{t\in S}(1-p_{it})\right].
$$

Biểu thức này giả định khách hàng chỉ cần trả nợ một lần và kết quả các lần
thăm độc lập có điều kiện.

### 2.2. Cán bộ và thời gian làm việc

File data/generated/officers.csv chứa:

- officer_id: mã cán bộ.
- day: ngày làm việc.
- budget_hours: số giờ tối đa cán bộ được sử dụng trong ngày.

Một tuyến chỉ khả thi nếu:

$$
\text{thời gian di chuyển}
+
\text{thời gian phục vụ}
\le
\text{budget_hours}.
$$

### 2.3. Ma trận di chuyển

Hai file được sử dụng:

- distance_matrix_km.csv: khoảng cách giữa chi nhánh và các khách hàng.
- travel_time_matrix_hours.csv: thời gian di chuyển tương ứng.

Hàng và cột đầu tiên là chi nhánh ngân hàng. Các hàng và cột còn lại theo thứ
tự khách hàng trong customers.csv.

Pipeline ưu tiên lấy ma trận tuyến nhanh nhất từ OSRM. Nếu OSRM không truy cập
được, code dùng:

$$
d_{ij}=1.3\times \operatorname{Haversine}(i,j),
$$

và:

$$
\tau_{ij}=\frac{d_{ij}}{25}.
$$

Nguồn thực tế được ghi trong data/generated/metadata.txt.

### 2.4. Chuyển dữ liệu vào mô hình

data_processing/load_data.jl kiểm tra các file rồi tạo DebtRoutingData gồm:

$$
(n,K,H,w,p,d,\tau,s,B,R).
$$

Trong đó n là số khách hàng, K là số cán bộ và H là số ngày. Mọi thuật toán
trong benchmark nhận đúng cùng một đối tượng này.

## 3. Biểu diễn nghiệm dùng chung

### 3.1. Biểu diễn trong MILP

Mô hình chính xác dùng:

- x(i,j,k,t): cán bộ k đi từ i đến j trong ngày t.
- y(i,k,t): cán bộ k thăm khách hàng i trong ngày t.
- z(k,t): cán bộ k có tuyến trong ngày t.
- lambda(i,S): khách hàng i chọn lịch thăm S.
- u(i,k,t): thứ tự MTZ để loại chu trình con.

### 3.2. Biểu diễn trong heuristic

GA, Tabu, SA, ALNS, Hill Climbing và Q-learning ALNS dùng ma trận gene:

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

## 4. Branch-and-Bound tự cài đặt

File: core/branch_and_bound.jl.

Đây là bản minh họa rõ từng bước của thuật toán, không có cutting plane và các
tăng tốc mạnh của solver.

### Các bước

1. Dựng LP relaxation bằng cách thay biến nhị phân bởi:

   $$
   0\le x,y,z,\lambda\le1.
   $$

2. Giải LP bằng HiGHS để lấy cận trên cho bài toán cực đại.
3. Nếu LP không khả thi, loại nút.
4. Nếu cận trên không tốt hơn nghiệm nguyên tốt nhất, loại nút.
5. Nếu mọi biến logic đã nguyên, cập nhật incumbent.
6. Nếu còn biến phân số, chọn biến có giá trị gần 0,5 nhất.
7. Tạo hai nút con, một nút cố định biến bằng 0 và một nút bằng 1.
8. Lặp đến khi hết nút hoặc chạm giới hạn thời gian/số nút.

Ví dụ, nếu LP trả về y(i,k,t)=0,4 thì thuật toán tạo hai nhánh:

$$
y_{ikt}=0
\qquad\text{và}\qquad
y_{ikt}=1.
$$

### Gắn với bài toán

Mỗi nút cây là một tập quyết định đã được cố định, chẳng hạn khách hàng 3 chắc
chắn được hoặc không được cán bộ 1 thăm trong ngày 2. LP relaxation cho biết
giá trị kỳ vọng tốt nhất mà mọi kế hoạch trong nhánh đó có thể đạt.

### Kết quả

- OPTIMAL: đã duyệt hoặc loại toàn bộ nút và chứng minh tối ưu.
- LIMIT_REACHED: có nghiệm nhưng chưa chứng minh tối ưu.
- NO_INTEGER_SOLUTION: chưa tìm được nghiệm nguyên.

Bản này chỉ nên chạy instance nhỏ trong run_comparison.jl.

## 5. Branch-and-Cut của HiGHS

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

## 6. Genetic Algorithm

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

## 7. Tabu Search

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

## 7A. Simulated Annealing độc lập

SA bắt đầu từ cùng nghiệm tham lam với Tabu Search. Mỗi vòng chọn ngẫu nhiên một
cặp khách hàng-ngày `(i,t)`, đổi gene sang `0` hoặc một cán bộ khác, sau đó dùng
`repair!` để đưa nghiệm về miền khả thi. Nếu repair hủy đúng thay đổi vừa đề xuất,
move đó bị bỏ qua.

Điểm dùng cho xác suất chấp nhận được chuẩn hóa theo tổng dư nợ:

```text
score(S) = expected_recovery(S) / total_debt - 0.0001 * distance(S)
```

Nghiệm tốt hơn luôn được nhận. Với nghiệm kém hơn, đặt
`delta = score(S') - score(S) < 0` và chấp nhận với xác suất:

```text
P(accept) = exp(delta / T)
```

Nhiệt độ giảm hình học sau mỗi vòng: `T <- 0.995 * T`, bắt đầu từ `T=0.05`.
SA lưu riêng nghiệm tốt nhất từng gặp, nên việc tạm nhận nghiệm xấu không làm mất
kết quả tốt nhất. Khác ALNS, SA độc lập chỉ đổi một gene mỗi vòng và không có các
toán tử destroy-repair theo cụm.

## 8. Adaptive Large Neighborhood Search

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

## 9. Hill Climbing

File: core/hill_climbing.jl.

### Một lần leo đồi

1. Bắt đầu từ nghiệm rỗng hoặc nghiệm ngẫu nhiên đã repair.
2. Với từng gene, thử mọi giá trị từ 0 đến K.
3. Repair và đánh giá từng láng giềng.
4. Chọn láng giềng tốt nhất trong toàn bộ lân cận.
5. Chỉ di chuyển nếu láng giềng tốt hơn nghiệm hiện tại.
6. Dừng khi không còn cải thiện.

Để giảm phụ thuộc điểm xuất phát, code dùng multi-start:

- 8 lần khởi động trong profile chuẩn.
- 2 lần khởi động trong profile large.
- 1 lần khởi động, tối đa 30 vòng trong profile xlarge.

Hill Climbing dễ hiểu nhưng thường chậm vì duyệt toàn bộ lân cận và dễ kẹt ở
cực trị địa phương. Nó được dùng làm baseline.

## 10. Q-learning assisted ALNS

File: core/rl_alns.jl.

Đây là RL dạng bảng, chưa phải mạng neural. RL không trực tiếp tạo tuyến mà học
cách chọn toán tử ALNS.

### State

State rời rạc gồm ba thành phần:

1. Giai đoạn đầu, giữa hoặc cuối episode.
2. Mức stagnation: thấp, vừa hoặc cao.
3. Khoảng cách giữa nghiệm hiện tại và nghiệm tốt nhất: gần, vừa hoặc xa.

### Action

Có:

$$
4\text{ destroy}\times2\text{ repair}=8\text{ action}.
$$

Mỗi action chọn một cặp destroy-repair cụ thể.

### Reward

- +10 nếu tạo nghiệm tốt nhất toàn cục.
- Khoảng +3 nếu cải thiện nghiệm hiện tại.
- +0,5 nếu nghiệm kém hơn nhưng được chấp nhận để đa dạng hóa.
- -1 nếu nghiệm bị từ chối.

### Cập nhật Q-value

$$
Q(s,a)
\leftarrow
Q(s,a)+\alpha
\left[
r+\gamma\max_{a'}Q(s',a')-Q(s,a)
\right].
$$

Agent chọn action bằng epsilon-greedy. Epsilon giảm từ 0,90 xuống 0,05 qua các
episode.

Profile chuẩn dùng 12 episode, mỗi episode 100 bước. Profile large dùng 6
episode, mỗi episode 60 bước.
Profile xlarge dùng 4 episode, mỗi episode 50 bước.

Thời gian benchmark hiện bao gồm cả huấn luyện. Muốn đánh giá RL công bằng
trong nghiên cứu lớn hơn cần huấn luyện trên nhiều instance, lưu policy rồi đo
inference trên các instance chưa thấy.

## 11. Quy trình benchmark

File core/run_metaheuristic_comparison.jl thực hiện:

1. Đọc data/generated bằng load_data.jl.
2. Chạy GA.
3. Chạy Tabu Search.
4. Chạy Simulated Annealing độc lập.
5. Chạy ALNS.
6. Chạy Hill Climbing.
7. Huấn luyện và chạy Q-learning ALNS.
7. Chạy Branch-and-Cut với time limit.
8. Dùng cận trên của HiGHS làm mốc tính gap.
9. In bảng và lưu results/comparison.csv.

Tất cả phương pháp dùng cùng debt, probability, distance, travel_time,
service_time và daily_budget. Vì vậy khác biệt kết quả đến từ thuật toán chứ
không phải do dùng dữ liệu khác nhau.

## 12. Cách đọc kết quả

### Objective

Objective là tổng tiền thu hồi kỳ vọng, không phải số tiền chắc chắn thu được.
Hai kế hoạch có cùng objective vẫn có thể có tuyến khác nhau.

### Status

- OPTIMAL: solver đã chứng minh tối ưu.
- TIME_LIMIT hoặc LIMIT_REACHED: có thể có nghiệm tốt nhưng chưa chứng minh.
- HEURISTIC: phương pháp không cung cấp chứng minh tối ưu.

### Gap

Benchmark dùng:

$$
\operatorname{gap}
=
\frac{\text{HiGHS upper bound}-\text{heuristic objective}}
{\text{HiGHS upper bound}}\times100\%.
$$

Gap nhỏ cho thấy nghiệm heuristic gần cận lý thuyết. Nếu HiGHS đã OPTIMAL thì
cận trên chính là nghiệm tối ưu. Nếu solver chưa chứng minh tối ưu, gap vẫn là
một đánh giá bảo thủ dựa trên cận.

### Time

Thời gian chỉ tính phần solve của từng phương pháp, không tính đọc CSV. Với
Q-learning ALNS, thời gian bao gồm huấn luyện online.

## 13. Phạm vi và hạn chế hiện tại

1. Hồ sơ nợ và xác suất là dữ liệu mô phỏng, chưa được hiệu chỉnh từ ngân hàng.
2. Nếu OSRM lỗi, ma trận di chuyển là Haversine fallback.
3. Xác suất các lần thăm được giả định độc lập có điều kiện.
4. MILP hiện tối ưu một pha theo giá trị kỳ vọng; pha tối thiểu quãng đường
   chưa được cài trong solver.
5. Heuristic dùng nearest-neighbor và 2-opt, chưa tối ưu chính xác từng tuyến.
6. Q-learning mới học trên instance đang giải, chưa đánh giá tổng quát hóa.
7. Instance nhỏ và ít bị giới hạn có thể khiến mọi heuristic đạt gap 0, che
   khuất khác biệt chất lượng thực sự.

## 14. Khuyến nghị thực nghiệm

Nên tạo nhiều nhóm instance:

- Nhỏ: 10-20 khách hàng để Branch-and-Bound minh họa.
- Vừa: 30-50 khách hàng để so chất lượng và thời gian.
- Lớn: 75 khách hàng với profile large và time limit cho HiGHS.

Mỗi heuristic nên chạy nhiều seed. Báo cáo trung bình, độ lệch chuẩn, nghiệm
tốt nhất, thời gian và gap. Không nên kết luận một phương pháp tốt hơn chỉ từ
một instance hoặc một lần chạy.
