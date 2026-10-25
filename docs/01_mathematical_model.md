# Mô hình toán học cho bài toán tối ưu lộ trình thu hồi nợ

## 1. Vấn đề

Ngân hàng cần xây dựng kế hoạch thu hồi nợ cho nhiều cán bộ trong một số ngày làm việc. Mỗi ngày, mỗi cán bộ xuất phát từ chi nhánh ngân hàng, thăm một số khách hàng và quay lại chi nhánh trước khi hết thời gian làm việc.

Do nguồn lực có hạn, ngân hàng không nhất thiết thăm tất cả khách hàng. Một khách hàng có thể được thăm nhiều lần vào các ngày khác nhau nếu lần thăm trước không thành công. Bài toán cần xác định:

- khách hàng nào được lựa chọn;
- khách hàng được thăm vào những ngày nào;
- cán bộ nào phụ trách từng lần thăm;
- thứ tự thăm khách hàng của từng cán bộ trong từng ngày.

Mục tiêu chính là tối đa hóa tổng giá trị khoản nợ thu hồi kỳ vọng. Nếu nhiều phương án có cùng giá trị kỳ vọng, ngân hàng chọn phương án có tổng quãng đường di chuyển nhỏ nhất.

## 2. Ký hiệu

### 2.1. Tập chỉ số

- $V=\{0,1,\ldots,n\}$: tập các địa điểm, trong đó $0$ là chi nhánh ngân hàng.
- $N=V\setminus\{0\}$: tập khách hàng cần thu hồi nợ.
- $K=\{1,\ldots,m\}$: tập cán bộ thu hồi nợ.
- $T=\{1,\ldots,H\}$: tập ngày trong kỳ lập kế hoạch.
- $A=\{(i,j):i,j\in V,\ i\ne j\}$: tập cung di chuyển có thể sử dụng.
- $\mathcal S_i$: tập các lịch thăm khả thi của khách hàng $i$.

Mỗi $S\in\mathcal S_i$ là một tập các ngày mà khách hàng $i$ được dự kiến thăm. Nếu khách hàng được thăm tối đa $R_i$ lần thì:

$$
\mathcal S_i=\{S\subseteq T:1\le |S|\le R_i\}.
$$

Ví dụ, với ba ngày làm việc và tối đa hai lần thăm:

$$
\mathcal S_i=
\big\{\{1\},\{2\},\{3\},\{1,2\},\{1,3\},\{2,3\}\big\}.
$$

### 2.2. Tham số

- $w_i$: giá trị khoản nợ có thể thu hồi từ khách hàng $i$.
- $p_{it}$: xác suất thu hồi thành công khi thăm khách hàng $i$ vào ngày $t$, với điều kiện khoản nợ chưa được thu hồi trước đó.
- $d_{ij}$: khoảng cách từ địa điểm $i$ đến địa điểm $j$.
- $\tau_{ij}$: thời gian di chuyển từ địa điểm $i$ đến địa điểm $j$.
- $s_i$: thời gian làm việc với khách hàng $i$.
- $B_{kt}$: tổng thời gian làm việc tối đa của cán bộ $k$ trong ngày $t$.
- $R_i$: số lần tối đa được phép thăm khách hàng $i$.
- $a_{tS}$: tham số nhận giá trị 1 nếu $t\in S$, ngược lại nhận giá trị 0.
- $v_{iS}$: giá trị thu hồi kỳ vọng khi chọn lịch thăm $S$ cho khách hàng $i$.

Giả sử các lần thăm độc lập có điều kiện và khách hàng chỉ trả khoản nợ một lần. Xác suất thu hồi thành công ít nhất một lần theo lịch $S$ là:

$$
1-\prod_{t\in S}(1-p_{it}).
$$

Do đó:

$$
v_{iS}
=
w_i\left[1-\prod_{t\in S}(1-p_{it})\right].
$$

Giá trị $v_{iS}$ được tính trước khi giải mô hình nên không làm xuất hiện tích giữa các biến quyết định.

### 2.3. Biến quyết định

Biến lựa chọn cung di chuyển:

$$
x_{ijkt}=
\begin{cases}
1, & \text{nếu cán bộ }k\text{ đi trực tiếp từ }i\text{ đến }j\text{ trong ngày }t,\\
0, & \text{ngược lại.}
\end{cases}
$$

Biến phân công khách hàng:

$$
y_{ikt}=
\begin{cases}
1, & \text{nếu cán bộ }k\text{ thăm khách hàng }i\text{ trong ngày }t,\\
0, & \text{ngược lại.}
\end{cases}
$$

Biến lựa chọn lịch thăm:

$$
\lambda_{iS}=
\begin{cases}
1, & \text{nếu lịch }S\text{ được chọn cho khách hàng }i,\\
0, & \text{ngược lại.}
\end{cases}
$$

Biến sử dụng cán bộ:

$$
z_{kt}=
\begin{cases}
1, & \text{nếu cán bộ }k\text{ thực hiện một tuyến trong ngày }t,\\
0, & \text{ngược lại.}
\end{cases}
$$

Biến $u_{ikt}\ge 0$ biểu diễn thứ tự của khách hàng $i$ trong tuyến của cán bộ $k$ vào ngày $t$. Biến này được dùng để loại chu trình con.

## 3. Mô hình toán học

### 3.1. Hàm mục tiêu

$$
\max Z=
\sum_{i\in N}\sum_{S\in\mathcal S_i}
v_{iS}\lambda_{iS}.
\tag{1}
$$

Với các ràng buộc:

$$
\sum_{S\in\mathcal S_i}\lambda_{iS}\le 1,
\qquad \forall i\in N.
\tag{2}
$$

$$
\sum_{k\in K}y_{ikt}
=
\sum_{S\in\mathcal S_i}a_{tS}\lambda_{iS},
\qquad \forall i\in N,\ t\in T.
\tag{3}
$$

$$
\sum_{j\in N}x_{0jkt}=z_{kt},
\qquad \forall k\in K,\ t\in T.
\tag{4}
$$

$$
\sum_{i\in N}x_{i0kt}=z_{kt},
\qquad \forall k\in K,\ t\in T.
\tag{5}
$$

$$
\sum_{\substack{j\in V\\j\ne i}}x_{ijkt}=y_{ikt},
\qquad \forall i\in N,\ k\in K,\ t\in T.
\tag{6}
$$

$$
\sum_{\substack{j\in V\\j\ne i}}x_{jikt}=y_{ikt},
\qquad \forall i\in N,\ k\in K,\ t\in T.
\tag{7}
$$

$$
\sum_{(i,j)\in A}\tau_{ij}x_{ijkt}
+
\sum_{i\in N}s_i y_{ikt}
\le B_{kt}z_{kt},
\qquad \forall k\in K,\ t\in T.
\tag{8}
$$

$$
u_{ikt}-u_{jkt}+n x_{ijkt}
\le n-1+n(1-y_{jkt}),
\qquad
\forall i,j\in N,\ i\ne j,\ k\in K,\ t\in T.
\tag{9}
$$

$$
y_{ikt}\le u_{ikt}\le n y_{ikt},
\qquad
\forall i\in N,\ k\in K,\ t\in T.
\tag{10}
$$

$$
x_{ijkt},y_{ikt},z_{kt},\lambda_{iS}\in\{0,1\}.
\tag{11}
$$

$$
u_{ikt}\ge 0.
\tag{12}
$$

## 4. Giải thích mô hình

### Hàm mục tiêu (1)

Hàm mục tiêu tối đa hóa tổng giá trị thu hồi kỳ vọng. Nếu $\lambda_{iS}=1$, khách hàng $i$ được thực hiện theo lịch $S$ và đóng góp một lượng kỳ vọng $v_{iS}$ vào hàm mục tiêu. Khách hàng không được chọn có tất cả các biến $\lambda_{iS}$ bằng 0 nên không đóng góp giá trị.

### Ràng buộc (2): chọn lịch thăm

Mỗi khách hàng được chọn nhiều nhất một lịch thăm. Dấu nhỏ hơn hoặc bằng cho phép ngân hàng không thăm khách hàng $i$ nếu việc thăm khách hàng đó không đủ hiệu quả hoặc không thể bố trí trong giới hạn thời gian.

Số lần tái viếng thăm đã được kiểm soát khi xây dựng tập $\mathcal S_i$, vì mọi lịch $S\in\mathcal S_i$ đều thỏa mãn $|S|\le R_i$.

### Ràng buộc (3): liên kết lịch thăm và cán bộ

Vế phải bằng 1 nếu lịch được chọn cho khách hàng $i$ có chứa ngày $t$. Khi đó, vế trái buộc đúng một cán bộ thực hiện lần thăm này.

Nếu ngày $t$ không nằm trong lịch được chọn, vế phải bằng 0 và không cán bộ nào được phép thăm khách hàng $i$ trong ngày đó. Ràng buộc này đồng thời bảo đảm một khách hàng không được hai cán bộ cùng thăm trong một ngày.

### Ràng buộc (4): xuất phát từ chi nhánh

Nếu $z_{kt}=1$, cán bộ $k$ phải rời chi nhánh đúng một lần trong ngày $t$. Nếu $z_{kt}=0$, không có cung nào được phép đi từ chi nhánh cho cán bộ này.

### Ràng buộc (5): quay về chi nhánh

Nếu cán bộ $k$ có làm việc ngoài hiện trường trong ngày $t$, cán bộ phải quay lại chi nhánh đúng một lần. Kết hợp (4) và (5), mỗi tuyến đều bắt đầu và kết thúc tại chi nhánh.

### Ràng buộc (6): cung đi ra khỏi khách hàng

Nếu $y_{ikt}=1$, phải có đúng một cung đi ra khỏi khách hàng $i$ trên tuyến của cán bộ $k$ trong ngày $t$. Nếu khách hàng không được cán bộ này thăm thì không được có cung đi ra.

### Ràng buộc (7): cung đi vào khách hàng

Nếu $y_{ikt}=1$, phải có đúng một cung đi vào khách hàng $i$. Kết hợp (6) và (7), mỗi khách hàng được thăm có một điểm đến trước đó và một điểm đến tiếp theo trên tuyến.

### Ràng buộc (8): giới hạn thời gian làm việc

Thành phần đầu tiên là tổng thời gian di chuyển của cán bộ $k$ trong ngày $t$. Thành phần thứ hai là tổng thời gian làm việc trực tiếp với khách hàng.

Tổng hai thành phần không được vượt quá $B_{kt}$. Khi $z_{kt}=0$, vế phải bằng 0 nên cán bộ không thể có hoạt động di chuyển hoặc phục vụ khách hàng trong ngày đó.

### Ràng buộc (9): loại chu trình con

Các ràng buộc trước có thể tạo ra một chu trình giữa một số khách hàng nhưng không nối với chi nhánh, ví dụ $i\rightarrow j\rightarrow i$. Ràng buộc MTZ sử dụng thứ tự $u_{ikt}$ để loại các chu trình như vậy. Hạng tử $n(1-y_{jkt})$ làm ràng buộc mất tác dụng khi khách hàng $j$ không được chọn.

Nếu cung $(i,j)$ được chọn, tức $x_{ijkt}=1$, ràng buộc (9) suy ra:

$$
u_{jkt}\ge u_{ikt}+1.
$$

Vì thứ tự phải tăng dọc theo các cung được chọn, một chu trình giữa các khách hàng là không thể tồn tại.

### Ràng buộc (10): miền của biến thứ tự

Nếu khách hàng $i$ không được thăm, $y_{ikt}=0$ và ràng buộc buộc $u_{ikt}=0$. Nếu khách hàng được thăm, thứ tự của khách hàng nằm trong khoảng từ 1 đến $n$.

### Ràng buộc (11): biến nhị phân

Các biến $x$, $y$, $z$ và $\lambda$ chỉ được nhận giá trị 0 hoặc 1. Điều kiện này bảo đảm nghiệm biểu diễn các quyết định thực tế thay vì các quyết định phân số.

### Ràng buộc (12): tính không âm

Biến thứ tự $u_{ikt}$ không được nhận giá trị âm. Kết hợp với (10), biến này chỉ có giá trị dương đối với khách hàng thực sự xuất hiện trên tuyến.

### Ràng buộc (15): phá đối xứng giữa các cán bộ

Các cán bộ có cùng ngân sách thời gian là hoán đổi được: đổi nhãn hai cán bộ
cho một nghiệm khác nhưng cùng giá trị, làm cây Branch-and-Bound phải duyệt
lặp lại. Với hai cán bộ liên tiếp có $B_{kt}=B_{k+1,t}$, thêm

$$
z_{kt}\ \ge\ z_{k+1,t},\qquad k=1,\ldots,K-1,\ t\in T.
	ag{15}
$$

Ràng buộc chỉ loại các nghiệm trùng lặp, không làm mất giá trị tối ưu
(bật bằng `symmetry_breaking = true` trong cấu hình thí nghiệm).

## 5. Mục tiêu phụ về quãng đường

Sau khi giải mô hình trên và thu được giá trị thu hồi kỳ vọng tối ưu $Z^\star$, có thể giữ nguyên mức thu hồi bằng ràng buộc:

$$
\sum_{i\in N}\sum_{S\in\mathcal S_i}
v_{iS}\lambda_{iS}
\ge Z^\star-\varepsilon,
\tag{13}
$$

trong đó $\varepsilon$ là sai số số học nhỏ. Sau đó thay hàm mục tiêu bằng:

$$
\min
\sum_{t\in T}\sum_{k\in K}\sum_{(i,j)\in A}
d_{ij}x_{ijkt}.
\tag{14}
$$

Ràng buộc (13) bảo đảm mục tiêu thu hồi không bị giảm. Hàm mục tiêu (14) chọn phương án có tổng quãng đường nhỏ nhất trong số các phương án có giá trị thu hồi kỳ vọng tối ưu.

## 6. Từ dữ liệu đến nghiệm và mô phỏng động

Có hai tầng: (1) giải bài toán định tuyến
cho *những ngày còn lại* bằng tiền thu **kỳ vọng**; (2) chỉ đi tuyến hôm nay,
quan sát khách nào thực sự trả, cập nhật dữ liệu và giải lại sáng hôm sau.
Không thuật toán nào được biết trước kết quả trả tiền của các ngày tương lai.

### 6.1. Ánh xạ dữ liệu

Chọn một `instance`, ví dụ `INS_S`. [load_v3_data.jl](../data_processing/load_v3_data.jl)
đọc các bảng dưới `collection_routing_dataset_v3/csv/`:

| File | Đưa vào mô hình |
|---|---|
| `thuc_the.csv` | Số ngày `H`, phút làm việc/ngày, giới hạn lượt ghé `R_i`, mã bộ khách. |
| `thuc_the_khach_hang.csv` | Danh sách `n` khách thuộc instance. |
| `thuc_the_can_bo.csv` | Danh sách cán bộ, từ đó có số cán bộ `K`. |
| `khach_hang.csv` | Tiền mục tiêu `w_i`, thời gian phục vụ `s_i`. |
| `xac_suat_thu_hoi.csv` | Xác suất `p(i,t)` của **CO_SO** cho khách `i`, ngày `t`. |
| `ma_tran_di_chuyen.csv` | Quãng đường `d(i,j)` và thời gian đi `tau(i,j)` theo **chiều** `i -> j`; điểm 0 là chi nhánh `CN01`. |
| `kich_ban_monte_carlo.csv` | Số ngẫu nhiên cho mô phỏng kết quả; **không** đưa cho solver khi lập tuyến. |

Tiền được đổi từ VND sang **triệu VND**; phút đổi sang **giờ**. Ma trận
di chuyển được cắt theo đúng khách của instance, giữ cả chiều đi và về.
`lich_tiep_can.csv` có giá trị lịch tính sẵn nhưng code hiện tại **không đọc**;
nó tự liệt kê lịch và tự tính giá trị. `can_bo.csv` là thông tin nguồn, còn
ngân sách ngày hiện tại lấy chung từ `thuc_the.csv`, không cá thể hóa cán bộ.

### 6.2. Mã hóa một kế hoạch

Gọi `N = {1,...,n}` là tập khách, `k = 1..K` là cán bộ, `t = 1..H` là
ngày. Khách `i` có tiền mục tiêu `w_i`; `p(i,t)` là xác suất thu thành
công khi ghé vào ngày `t`, **với điều kiện khách chưa trả trước đó**.
Một kế hoạch cần trả lời ba câu: ghé
**ngày nào**, **ai** ghé, và đi theo **thứ tự nào**.

Ví dụ 2 khách, 1 cán bộ, 2 ngày: ngày 1 đi `0 -> 1 -> 2 -> 0`, ngày 2
định đi `0 -> 1 -> 0`. Khi ấy tập ngày thăm là `S_1 = {1,2}`,
`S_2 = {1}`. Nếu `w_1=10`, `p(1,1)=0.5`, `p(1,2)=0.4`,
`w_2=8`, `p(2,1)=0.25`, thì:

$$
v_1(S_1)=10[1-(1-0.5)(1-0.4)]=7,\quad
v_2(S_2)=8(0.25)=2,\quad Z=9\text{ triệu VND}.
$$

Đây là **kỳ vọng trước khi đi**, không phải chắc chắn thu 9 triệu.
Nếu khách không được ghé, `S_i` rỗng và `v_i(S_i)=0`.
Công thức giả định các lần tiếp cận độc lập có điều kiện theo `p(i,t)`.

Cùng kế hoạch đó dưới dạng ma trận heuristic (hàng = khách, cột = ngày):

```text
             ngày 1   ngày 2
khách 1         1        1
khách 2         1        0
```

Số `1` là cán bộ số 1; số `0` là không ghé. Đây **chưa phải tuyến**:
ô `G[1,1]=1` và `G[2,1]=1` chỉ nói hai khách cùng được giao trong ngày 1.
Vector `0 -> 1 -> 2 -> 0` mới cho biết thứ tự. Tuyến ngày 1 hợp lệ khi
`tau(0,1)+tau(1,2)+tau(2,0)+s_1+s_2 <= B(1,1)`. Đi theo thứ tự
`0 -> 2 -> 1 -> 0` có thể tốn thời gian khác vì ma trận có hướng.

Trong [model.jl](../core/model.jl), BnC dùng biến nhị phân:

| Biến | Ý nghĩa |
|---|---|
| `lambda(i,S)` | Chọn tập ngày thăm `S` cho khách `i`. |
| `y(i,k,t)` | Cán bộ `k` ghé khách `i` ngày `t`. |
| `x(i,j,k,t)` | Đi trực tiếp từ `i` tới `j` trên tuyến `k,t`. |
| `z(k,t)` | Cán bộ `k` có đi tuyến ngày `t`. |
| `u(i,k,t)` | Thứ tự MTZ trên tuyến, dùng loại chu trình con. |

Trong ví dụ: `lambda(1,{1,2})=1`, `lambda(2,{1})=1`;
`y(1,1,1)=y(1,1,2)=y(2,1,1)=1`; các cung ngày 1 có
`x(0,1,1,1)=x(1,2,1,1)=x(2,0,1,1)=1`, và `z(1,1)=1`.
Những biến không chọn bằng 0. MTZ chỉ ngăn một vòng riêng kiểu
`1 -> 2 -> 1` tách khỏi chi nhánh.

Hàm mục tiêu BnC là tối đa hóa tổng `v_i(S)` của các lịch được chọn.
Liên kết cốt lõi:

$$
\sum_S\lambda_{iS}\le1,\qquad
\sum_k y_{ikt}=\sum_{S:\,t\in S}\lambda_{iS}.
$$

Mỗi khách chọn tối đa một lịch; nếu lịch chứa ngày `t`, đúng một cán bộ
ghé ngày đó. Các ràng buộc còn lại buộc tuyến đi từ chi nhánh rồi về,
mỗi khách trong tuyến có một cung vào và một cung ra, không có chu trình
con, số lần ghé không vượt `R_i`, và:

$$
\sum_{i,j}\tau_{ij}x_{ijkt}+\sum_i s_i y_{ikt}\le B_{kt}z_{kt}.
$$

`B(k,t)` là số giờ làm việc của cán bộ `k` ngày `t`. BnC dùng JuMP
và HiGHS để giải MILP này. **Code BnC hiện chỉ tối đa hóa kỳ vọng**;
chưa có lượt giải thứ hai để tối thiểu quãng đường khi hòa mục tiêu.
Quãng đường vẫn được tính để báo cáo.

Trong runner **cuốn chiếu**, trước mỗi lần gọi BnC, code dựng một nghiệm
ALNS khả thi làm MIP start. Nếu BnC hết giới hạn thời gian mà chưa cải thiện
được nghiệm đó, runner giữ lại nghiệm ALNS và báo
`TIME_LIMIT_HEURISTIC_FALLBACK`. Đây là cơ chế dự phòng, **không** được gọi
là nghiệm tốt nhất *do BnC tìm ra*. Giới hạn giây chỉ áp dụng cho HiGHS;
thời gian khởi tạo ALNS và dựng mô hình được ghi trong thời gian tổng.

GA, Tabu và ALNS trong [genetic_algorithm.jl](../core/genetic_algorithm.jl)
không thao tác trực tiếp trên `x`, `y`, `lambda`. Chúng dùng ma trận
`G` kích thước `n x H`, mỗi ô thuộc `{0,1,...,K}`: `G[i,t]=0` nghĩa
là không ghé, `G[i,t]=k` nghĩa là cán bộ `k` ghé. Từ mỗi cột ngày, code gom khách
theo cán bộ, dựng vector tuyến `0 -> ... -> 0` bằng nearest-neighbor và
2-opt, rồi tính lại giờ, quãng đường và `v_i(S_i)`. `repair!` bỏ các
lượt vượt giới hạn hoặc làm tuyến quá giờ. GA lai/đột biến các ô của `G`;
Tabu đổi một ô và nhớ các bước bị cấm; ALNS xóa một nhóm lượt rồi chèn
lại. `ga_decisions` chuyển nghiệm heuristic về `x,y,z` để kiểm tra và
in cùng định dạng BnC. Vì là heuristic, chúng không có chứng nhận tối ưu.

### 6.3. Quan sát và cập nhật theo ngày

Với kịch bản Monte Carlo `s`, file lưu một số `u(s,i,t)` trong `[0,1]`
cho **mỗi khách-ngày** (tên cột CSV là `u`). Chỉ khi thật sự ghé khách,
ta mới thử: nếu `u(s,i,t) < p(i,t)`, thu được `w_i`; nếu không,
thu 0. Chẳng hạn `p(1,1)=0.5`, `u=0.3` thì khách 1 trả vào ngày 1;
chuyến dự kiến ghé lại khách 1 ngày 2 không còn cần thiết. Cột `u` này
**khác hẳn** biến `u(i,k,t)` MTZ của MILP. Cả hai đều không phải biến
quyết định về việc khách trả tiền.

Với **cuốn chiếu**, đầu ngày `t` giữ `A_t`: khách chưa trả và số lượt
đã ghé `a_i < R_i`. [remaining_v3_data](../data_processing/dynamic_v3_data.jl)
cắt dữ liệu còn lại: chỉ khách trong `A_t`, ngày `t..H`,
xác suất `p(i,t..H)`, ngân sách `B(k,t..H)`, giới hạn còn lại
`R_i - a_i`, và ma trận di chuyển con gồm chi nhánh với khách còn lại.
Solver lập lịch cho **toàn bộ phần kỳ còn lại**, nhưng
[run_v3_dynamic.jl](../core/run_v3_dynamic.jl) chỉ thực hiện tuyến hôm nay.
Cuối ngày cập nhật khách đã trả và `a_i`, rồi bỏ phần lịch tương lai
vừa tính và giải lại. Trong ví dụ trên, nếu khách 1 trả ngày 1 thì sáng
ngày 2 khách 1 bị loại; chỗ trống có thể giao cho khách 2 hoặc khách khác.

Một kịch bản Monte Carlo là **một đường diễn biến để chấm điểm**, không
phải thông tin đầu vào mà thuật toán được nhìn trước. Cùng một kịch bản
`u(s,i,t)` được dùng cho mọi phương pháp. `planned_expected` là kỳ vọng
khi lập kế hoạch; `collected_million_vnd` là tiền mô phỏng **thực thu**.
Cận BnC chỉ chứng nhận bài toán MILP *còn lại tại lần giải đó*, không
chứng nhận chính sách động tối ưu trên tất cả kịch bản.

### 6.4. Ba chính sách so sánh

GA, Tabu, ALNS, BnC **không học** từ các kịch bản Monte Carlo; chúng chỉ giải
lại khi trạng thái thay đổi. Ba chính sách khác nhau ở *khi nào* lập kế hoạch
và *nhìn trước bao nhiêu ngày*:

| Chính sách | Lập kế hoạch | Nhìn trước |
|---|---|---|
| Tĩnh | Một lần đầu kỳ cho cả H ngày, sau đó chỉ thực hiện | H ngày |
| Cuốn chiếu | Đầu mỗi ngày t, cho các ngày t..H; chỉ thực hiện tuyến ngày t | H − t + 1 ngày |
| Tham lam | Đầu mỗi ngày t, chỉ cho ngày t | 1 ngày |

Ở chính sách tĩnh, khách đã trả bị bỏ qua khi tới lượt (đi thẳng tới khách
kế tiếp) nhưng không chèn thêm khách mới. Cả ba dùng **cùng** dãy số ngẫu
nhiên `u(s,i,t)` của kịch bản s (common random numbers), nên chênh lệch
ghép cặp chỉ đến từ chính sách. Runner: `core/run_v3_static_vs_rolling.jl`.

### 6.5. Bài toán động và phép đo chất lượng

Ký hiệu trạng thái **được biết đầu ngày** $t$ là
$X_t=(P_t,a_t)$, với $P_t$ là tập khách đã trả và $a_{it}$ là số lần đã
ghé khách $i$ trước ngày $t$. Tập khách còn đủ điều kiện là

$$
A_t=\{i\in N:i\notin P_t,\ a_{it}<R_i\}.
$$

Từ $X_t$, tạo bài toán còn lại bằng cách chỉ giữ $A_t$, các ngày
$t,\ldots,H$ và giới hạn thăm mới $R_i-a_{it}$. Gọi $Q_t$ là lời giải
cho **cả kỳ còn lại**; hành động thực hiện là *chỉ tuyến ngày $t$* của
$Q_t$. Tập khách đã ghé thật trong ngày đó là $E_t$.

Trong kịch bản Monte Carlo $s$, đặt $\xi^{(s)}_{it}$ là cột `u` của CSV.
Với khách $i\in E_t$, kết quả thu nợ là

$$
Y^{(s)}_{it}=\mathbf{1}\{\xi^{(s)}_{it}<p_{it}\},\qquad
C^{(s)}_t=\sum_{i\in E_t}w_iY^{(s)}_{it}.
$$

Cuối ngày chuyển trạng thái: $a_{i,t+1}=a_{it}+1$ nếu $i\in E_t$,
ngược lại giữ nguyên; $P_{t+1}=P_t\cup\{i\in E_t:Y^{(s)}_{it}=1\}$.
Ngày hôm sau giải lại trên $X_{t+1}$. Vì thế một **chính sách** $\pi$
là quy tắc ánh xạ trạng thái quan sát được sang tuyến ngày hiện tại,
không phải một lịch cố định biết trước toàn bộ kết quả.

Tiền thu cả kỳ dưới kịch bản $s$ là
$C^{(s)}(\pi)=\sum_{t=1}^{H}C_t^{(s)}$. Với tập ID test $S_{\rm test}$,
đánh giá bằng trung bình mẫu

$$
\widehat{C}(\pi)=\frac{1}{|S_{\rm test}|}
\sum_{s\in S_{\rm test}} C^{(s)}(\pi).
$$

Để so hai phương pháp $\pi_A,\pi_B$, dùng *cùng ID kịch bản* và lấy trung
bình chênh lệch ghép cặp
$\frac{1}{|S_{\rm test}|}\sum_s[C^{(s)}(\pi_A)-C^{(s)}(\pi_B)]$.
Không dùng $\xi^{(s)}_{it}$ của tương lai để chọn tuyến; chỉ dùng nó
**sau khi** tuyến đã chọn để sinh kết quả. Cận trên của BnC cho một
bài toán $Q_t$ không phải cận trên cho $\widehat{C}(\pi)$ hay chính
sách động tối ưu.

## 7. Kết luận

Mô hình MILP mã hóa lịch thăm bằng $\lambda$, phân công bằng $y$, tuyến
bằng $x$ và loại chu trình con bằng biến thứ tự MTZ $u$. Ở mỗi ngày của
quy trình cuốn chiếu, mô hình tối đa hóa tiền thu **kỳ vọng của phần kỳ
còn lại**; tiền thực thu chỉ xuất hiện sau khi mô phỏng kết quả tiếp cận.
Mục 5 trình bày cách tối thiểu hóa quãng đường theo thứ tự từ điển; BnC
thực hiện lượt giải thứ hai này khi bật `minimize_distance`, còn heuristic
dùng quãng đường để phá hòa giữa hai nghiệm có giá trị kỳ vọng bằng nhau.
