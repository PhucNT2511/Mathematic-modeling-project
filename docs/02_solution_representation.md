# Biểu diễn nghiệm và biến đổi toán học

Tài liệu này nối mô tả bài toán với các thuật toán. Ta xét **kế hoạch tĩnh**:
chọn lịch cho cả kỳ trước khi biết kết quả thu hồi.

## 1. Dữ liệu và chỉ số

- \(N=\{1,\ldots,n\}\): khách hàng; \(0\): chi nhánh.
- \(\mathcal K=\{1,\ldots,K\}\): cán bộ; \(T=\{1,\ldots,H\}\): ngày.
- \(w_i\): tiền mục tiêu; \(p_{it}\): xác suất thu nếu thăm khách \(i\) ngày
  \(t\), với điều kiện chưa thu được trước đó.
- \(d_{ij}\), \(\tau_{ij}\): quãng đường và thời gian đi từ \(i\) đến \(j\).
  Có thể \(d_{ij}\ne d_{ji}\) và \(\tau_{ij}\ne\tau_{ji}\).
- \(s_i\): thời gian phục vụ; \(B_{kt}\): thời gian làm việc tối đa của cán
  bộ \(k\) ngày \(t\); \(R_i\): số lượt thăm tối đa.

Một instance của bộ dữ liệu xác định khách, cán bộ, ngày, \(B_{kt}\) và
\(R_i\). Ta lấy \(w_i,s_i,p_{it}\) đúng khách, rồi cắt ma trận di chuyển
theo các điểm của instance. Tiền và thời gian phải cùng hệ đơn vị trước
khi tính.

## 2. Một nghiệm gồm ma trận và các vector tuyến

### Ma trận phân công

Đặt \(G=(g_{it})\in\{0,1,\ldots,K\}^{n\times H}\):

\[
g_{it}=\begin{cases}
0,&\text{không thăm khách }i\text{ ngày }t,\\
k,&\text{cán bộ }k\text{ thăm khách }i\text{ ngày }t.
\end{cases}
\]

Một ô có đúng một giá trị nên không thể giao cùng khách cho hai cán bộ
trong cùng ngày. Từ \(G\), suy ra

\[
S_i(G)=\{t:g_{it}>0\},\qquad C_{kt}(G)=\{i:g_{it}=k\}.
\]

\(S_i\) là **tập ngày** của khách \(i\); \(C_{kt}\) là **tập khách** giao
cho cán bộ \(k\) ngày \(t\). Cả hai chưa chứa thứ tự đi.

### Vector tuyến có thứ tự

Với **mỗi cặp cán bộ-ngày** \((k,t)\), đặt

\[
r_{kt}=(0,i_1,i_2,\ldots,i_q,0),\qquad
\{i_1,\ldots,i_q\}=C_{kt}(G).
\]

Tuyến rỗng ký hiệu \(r_{kt}=(0,0)\): cán bộ không ra tuyến ngày đó.
Một cán bộ có **một vector riêng cho mỗi ngày**; cả kế hoạch có tối đa
\(KH\) vector. Nhiều thứ tự tuyến khác nhau có thể cùng tương ứng với
một ma trận \(G\).

## 3. Ví dụ chuyển ma trận thành vector

Giả sử \(n=4,K=2,H=2\):

| Khách | \(g_{i1}\) | \(g_{i2}\) | \(S_i\) |
|---|---:|---:|---|
| 1 | 1 | 0 | \(\{1\}\) |
| 2 | 1 | 2 | \(\{1,2\}\) |
| 3 | 0 | 2 | \(\{2\}\) |
| 4 | 2 | 0 | \(\{1\}\) |

Suy ra \(C_{1,1}=\{1,2\}\), \(C_{2,1}=\{4\}\),
\(C_{1,2}=\varnothing\), \(C_{2,2}=\{2,3\}\). Một họ tuyến **có thể** là

\[
r_{1,1}=(0,1,2,0),\quad r_{2,1}=(0,4,0),\quad
r_{1,2}=(0,0),\quad r_{2,2}=(0,3,2,0).
\]

Thứ tự \(3\to2\) ở tuyến cuối chỉ là một lựa chọn; phải so chi phí với
\(2\to3\). Khách 2 được thăm hai ngày bởi hai cán bộ khác nhau, điều
mà mô hình hiện tại cho phép.

## 4. Giá trị và ràng buộc

Tiền thu hồi kỳ vọng nếu thăm khách \(i\) vào tập ngày \(S_i\) là

\[
v_i(S_i)=w_i\left[1-\prod_{t\in S_i}(1-p_{it})\right],
\qquad v_i(\varnothing)=0.
\]

Mục tiêu chính là \(\max F(G)=\sum_i v_i(S_i(G))\). Với
\(r_{kt}=(r_0,\ldots,r_{q+1})\), \(r_0=r_{q+1}=0\), đặt

\[
D(r_{kt})=\sum_{a=0}^{q}d_{r_a,r_{a+1}},\qquad
L(r_{kt})=\sum_{a=0}^{q}\tau_{r_a,r_{a+1}}+
\sum_{i\in C_{kt}(G)}s_i.
\]

Nghiệm khả thi phải thỏa

\[
|S_i(G)|\le R_i\quad(\forall i),\qquad
L(r_{kt})\le B_{kt}\quad(\forall k,t),
\]

và mỗi vector tuyến đi từ 0 về 0, chứa đúng một lần mỗi khách trong
\(C_{kt}\). Khi hai nghiệm có cùng tiền kỳ vọng trong ngưỡng so sánh,
ưu tiên tổng quãng đường \(\sum_{k,t}D(r_{kt})\) nhỏ hơn.

**Điểm cần nhớ:** \(F\) phụ thuộc trực tiếp vào *ngày thăm* \(S_i\), còn
phân công cán bộ và thứ tự đi quyết định tính khả thi về thời gian.
Tuyến tốt có thể tạo chỗ để thêm khách có giá trị.

## 5. Dựng thứ tự tuyến từ tập khách

Với \(G\) cho trước, thuật toán phải biến từng tập \(C_{kt}\) thành vector
\(r_{kt}\). Heuristic hiện tại đi từ 0 tới khách chưa thăm gần nhất theo
\(d_{ij}\), về 0, rồi thử đảo đoạn bằng 2-opt. Mỗi phép đảo được chấm bằng
**toàn bộ** quãng đường vì ma trận có thể bất đối xứng. Sau đó tính
\(L(r_{kt})\) bằng ma trận **thời gian** trên chính thứ tự vừa chọn.

Đây là quy tắc dựng tuyến từ \(G\), không bảo đảm thứ tự ngắn nhất có thể.
Mỗi khi \(C_{kt}\) thay đổi, phải dựng lại vector tuyến liên quan.

## 6. Biến đổi giữa các nghiệm

### Đổi một ô: thêm, bỏ, chuyển cán bộ

Chọn \((i,t)\), thay \(g_{it}=a\) bằng \(b\ne a\):

| Phép đổi | Tập nào thay đổi? |
|---|---|
| \(0\to k\) | Thêm \(t\) vào \(S_i\), thêm \(i\) vào \(C_{kt}\). |
| \(k\to0\) | Bỏ \(t\) khỏi \(S_i\), bỏ \(i\) khỏi \(C_{kt}\). |
| \(k\to k'\) | Chuyển \(i\) từ \(C_{kt}\) sang \(C_{k't}\); \(S_i\) không đổi. |

Trong ví dụ ở mục 3, đổi \(g_{3,1}:0\to1\) làm

\[
S_3:\{2\}\to\{1,2\},\qquad
C_{1,1}:\{1,2\}\to\{1,2,3\}.
\]

Phải dựng lại \(r_{1,1}\), kiểm tra \(|S_3|\le R_3\),
\(L(r_{1,1})\le B_{1,1}\) và tính lại \(v_3(S_3)\). Không thể mặc
định đặt khách 3 cuối tuyến. Tabu dùng phép đổi một ô này.

### Lai ghép và đột biến GA

Cho hai ma trận \(G^A,G^B\). Ma trận con \(G^C\) lấy từng ô từ một trong
hai bố mẹ: \(g^C_{it}\in\{g^A_{it},g^B_{it}\}\). Đột biến thay một số ô
bằng giá trị trong \(\{0,1,\ldots,K\}\). Ma trận con có thể vượt lượt
thăm hoặc quá giờ, nên phải sửa và dựng lại các vector tuyến. GA hiện
tại lai **ma trận phân công**, không lai trực tiếp các vector tuyến.

### Phá và xây lại ALNS

Chọn một tập lượt đang có

\[
Q\subseteq\{(i,t):g_{it}>0\},
\]

rồi đặt \(g_{it}=0\) với \((i,t)\in Q\). Có thể phá ngẫu nhiên, bỏ lượt
giá trị thấp, bỏ cụm khách gần nhau hoặc bỏ một số lượt của một tuyến.
Toán tử phá tuyến hiện tại xóa tối đa \(q\) lượt trong tuyến được chọn,
**không bắt buộc xóa toàn bộ**.

Từ ma trận đã phá \(G^-\), toán tử sửa lần lượt chèn bộ ba \((i,t,k)\)
còn khả thi. Greedy ưu tiên mức tăng \(v_i(S_i)\); regret-2 ưu tiên khách
sẽ mất nhiều lợi ích nếu bỏ lỡ chỗ chèn tốt nhất. Có thể chèn cả khách
trước đó chưa nằm trong kế hoạch. Mỗi phép chèn cần dựng lại tuyến và
kiểm tra thời gian.

## 7. Sửa nghiệm không khả thi

Ký hiệu phép sửa tham lam \(\mathcal R(G)=\widehat G\):

1. Nếu \(|S_i|>R_i\), chỉ giữ \(R_i\) ngày có \(p_{it}\) lớn nhất.
2. Nếu tuyến \((k,t)\) quá giờ, tính tổn thất biên khi bỏ một lượt:

   \[
   \Delta_{it}=v_i(S_i)-v_i(S_i\setminus\{t\}).
   \]

   Bỏ lượt có \(\Delta_{it}\) nhỏ nhất, dựng lại tuyến và kiểm tra giờ;
   lặp tới khi \(L(r_{kt})\le B_{kt}\).

Phép sửa không bảo đảm giữ tập lượt thăm có giá trị tối ưu. Nếu nó hủy
đúng thay đổi vừa đề xuất, Tabu bỏ qua đề xuất. ALNS kiểm tra tính
khả thi trước mỗi phép chèn.

## 8. Branch-and-Cut diễn tả cùng kế hoạch ra sao?

MILP quyết định đồng thời:

- \(y_{ikt}=1\): cán bộ \(k\) thăm khách \(i\) ngày \(t\); từ đó suy ra
  \(g_{it}=k\).
- \(x_{ijkt}=1\): cán bộ \(k\) đi trực tiếp \(i\to j\) ngày \(t\); nối
  các cung từ 0 để đọc vector \(r_{kt}\).
- \(\lambda_{iS}=1\): chọn tập ngày \(S\) cho khách \(i\).
- \(z_{kt}=1\): tuyến cán bộ-ngày được sử dụng; \(u_{ikt}\) là biến thứ
  tự để loại chu trình con.

Ràng buộc nối \(x,y,\lambda\) để lịch ngày, phân công và tuyến khớp
nhau. Branch-and-Cut **tối ưu thứ tự tuyến như một quyết định**. Heuristic
hiện tại chọn \(G\), sau đó dựng thứ tự bằng quy tắc ở mục 5; do đó có
thể bỏ qua một tuyến khả thi/tốt mà MILP có thể tìm ra.

## 9. Kích thước không gian nghiệm

Một khách có

\[
1+\sum_{r=1}^{R_i}\binom{H}{r}K^r
\]

cách chọn ngày và cán bộ, kể cả không thăm, **chưa tính thứ tự đi**.
Với \(H=5,R_i=2,K=2\), số đó bằng
\(1+\binom51 2+\binom52 2^2=51\) cách/khách. Với \(n\) khách,
cận trên thô là \(51^n\) cách phân công, rồi còn phải xếp thứ tự tuyến.
Ràng buộc thời gian loại nhiều phương án nhưng không làm phép liệt kê
toàn bộ khả thi ở quy mô lớn.

## 10. "Động" trong tìm kiếm và khi thực hiện

Trong **tìm kiếm**, \(G\) và \(r_{kt}\) đổi qua các vòng GA/Tabu/ALNS;
đầu ra cuối vẫn là kế hoạch tĩnh. Trong **thực hiện cuốn chiếu**, sau
ngày \(t\), loại khách đã trả, trừ số lượt đã tiếp cận khỏi giới hạn
\(R_i\), chỉ giữ ngày \(t+1,\ldots,H\), rồi giải lại để tạo các tuyến
tương lai. Không đổi tuyến đã thực hiện. Runner heuristic v3 hiện chưa
cập nhật trạng thái theo ngày.

## 11. Đối chiếu ký hiệu với code

| Ký hiệu | Trong code |
|---|---|
| \(G=(g_{it})\) | `genes::Matrix{Int}` |
| \(S_i\) | `findall(genes[i, :] .> 0)` |
| \(C_{kt}\) | `findall(genes[:, t] .== k)` |
| \(r_{kt}\) | `routes[(k,t)]` từ `build_route` |
| \(v_i(S_i)\) | `expected_value` / `customer_value` |
| \(\mathcal R(G)\) | `repair!` |
| \(F(G)\), \(\sum D\) | `evaluate_ga`, `is_better` |
| \(x,y,\lambda,z,u\) | `build_model` trong `core/model.jl` |
