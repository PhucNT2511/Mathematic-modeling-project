# -*- coding: utf-8 -*-
"""
Bước 3: kiểm tra sơ bộ bằng HEURISTIC (không thay thế MILP của đề tài)
  (a) so sánh chính sách TĨNH và CUỐN CHIẾU trên cùng số ngẫu nhiên Monte Carlo (common random numbers);
  (b) độ nhạy theo kịch bản xác suất THAP / CO_SO / CAO.

Quy định hai chính sách (giống README §8):
  TĨNH      : lập kế hoạch 5 ngày một lần ở đầu kỳ. Khi thực hiện, khách đã trả bị bỏ qua: cán bộ đi thẳng từ
              điểm vừa rời tới khách kế tiếp chưa trả trong tuyến; thời gian rảnh không được dùng thêm.
  CUỐN CHIẾU: đầu mỗi ngày t lập lại kế hoạch cho ngày t..5 với khách chưa trả; số lần đã tiếp cận được
              giữ lại (m_còn = m − đã tiếp cận); chỉ thực hiện tuyến của ngày t.
  Chung     : thành công khi u(s,i,t) < p(i,t) (cùng bảng u cho mọi chính sách và mọi kịch bản p);
              thành công thu đủ so_tien_muc_tieu_vnd, thất bại thu 0; không thu trùng một khoản nợ.

Heuristic lập kế hoạch: chèn tham lam theo tỷ số (tăng giá trị kỳ vọng) / (thời gian tăng thêm), rồi 2-opt
từng tuyến và chèn lại. Mục tiêu phụ (quãng đường) không được tối ưu riêng.
Kết quả: ket_qua/mo_phong_chi_tiet.csv, ket_qua/mo_phong_tom_tat.csv, ket_qua/do_nhay_ke_hoach.csv
"""
import os, sys, time, math
import numpy as np
import pandas as pd

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV, OUT = os.path.join(ROOT, "csv"), os.path.join(ROOT, "ket_qua")
os.makedirs(OUT, exist_ok=True)
DAYS = 5


def load():
    rd = lambda n: pd.read_csv(os.path.join(CSV, n + ".csv"))
    return dict(kh=rd("khach_hang"), mat=rd("ma_tran_di_chuyen"), p=rd("xac_suat_thu_hoi"), inst=rd("thuc_the"),
                ik=rd("thuc_the_khach_hang"), mc=rd("kich_ban_monte_carlo"))


class Instance:
    def __init__(self, D, iid, K=None, H=None, m=None):
        r = D["inst"].set_index("thuc_the_id").loc[iid]
        self.iid, self.K, self.H, self.m = iid, int(K or r.so_can_bo), float(H or r.phut_lam_viec_ngay), int(m or r.m_mac_dinh)
        ids = sorted(D["ik"][D["ik"].thuc_the_id == iid].khach_hang_id)
        self.ids = ids; n = len(ids); pts = ["CN01"] + ids; pos = {p: i for i, p in enumerate(pts)}
        mm = D["mat"][(D["mat"].bo_khach_hang_id == r.bo_khach_hang_id) & D["mat"].tu_id.isin(pts) & D["mat"].den_id.isin(pts)]
        self.T = np.zeros((n + 1, n + 1)); self.Dk = np.zeros((n + 1, n + 1))
        self.T[mm.tu_id.map(pos), mm.den_id.map(pos)] = mm.thoi_gian_phut.values
        self.Dk[mm.tu_id.map(pos), mm.den_id.map(pos)] = mm.khoang_cach_km.values
        kh = D["kh"].set_index("khach_hang_id").loc[ids]
        self.s = np.r_[0, kh.thoi_gian_phuc_vu_phut.values].astype(float)
        self.w = np.r_[0, kh.so_tien_muc_tieu_vnd.values].astype(float)
        self.group = np.r_[0, kh.nhom_no.values]
        pp = D["p"][D["p"].khach_hang_id.isin(ids)]
        self.p = {}
        for sc, g in pp.groupby("kich_ban_p"):
            P = np.zeros((n + 1, DAYS + 1))
            P[g.khach_hang_id.map(pos), g.ngay_thu] = g.p_thu_hoi.values
            self.p[sc] = P
        mc = D["mc"][D["mc"].khach_hang_id.isin(ids)]
        self.nsc = int(mc.kich_ban_id.max())
        U = np.ones((self.nsc + 1, n + 1, DAYS + 1))
        U[mc.kich_ban_id, mc.khach_hang_id.map(pos), mc.ngay_thu] = mc.u.values
        self.U = U; self.n = n


def plan(I, P, avail, days, used, m, H, K):
    """Trả về dict (k,t) -> danh sách chỉ số khách theo thứ tự thăm."""
    n = I.n; T, s, w = I.T, I.s, I.w
    routes = {(k, t): [0, 0] for k in range(K) for t in days}
    tused = {r: 0.0 for r in routes}
    S = {i: set() for i in range(1, n + 1)}
    cap_left = np.array([0] + [max(0, m - used[i]) if avail[i] else 0 for i in range(1, n + 1)])

    def vS(i, Sset):
        return w[i] * (1 - np.prod([1 - P[i, t] for t in Sset])) if Sset else 0.0

    gain = np.zeros((n + 1, DAYS + 1))
    def upd_gain(i):
        base = vS(i, S[i])
        for t in days:
            gain[i, t] = (vS(i, S[i] | {t}) - base) if (cap_left[i] > len(S[i]) and t not in S[i]) else 0.0
    for i in range(1, n + 1):
        upd_gain(i)

    def best_ins(seq):
        a = np.array(seq[:-1]); b = np.array(seq[1:])
        d = T[a, :] + T[:, b].T - T[a, b][:, None]          # vị trí j x khách i
        j = np.argmin(d, axis=0)
        return d[j, np.arange(d.shape[1])], j
    cache = {r: best_ins(routes[r]) for r in routes}

    def two_opt(seq):
        best = seq; improved = True
        while improved:
            improved = False
            for a in range(1, len(best) - 2):
                for b in range(a + 1, len(best) - 1):
                    new = best[:a] + best[a:b + 1][::-1] + best[b + 1:]
                    if route_time(new) + 1e-9 < route_time(best):
                        best = new; improved = True
        return best

    def route_time(seq):
        return float(sum(T[seq[x], seq[x + 1]] for x in range(len(seq) - 1)) + s[seq].sum())

    for rnd in range(2):
        while True:
            best = (0.0, None)
            for r, (dlt, pos) in cache.items():
                t = r[1]
                g = gain[:, t]
                cost = dlt + s
                feas = (g > 0) & (tused[r] + cost <= H)
                feas[0] = False
                if not feas.any():
                    continue
                ratio = np.where(feas, g / np.maximum(cost, 1e-6), -1)
                i = int(np.argmax(ratio))
                if ratio[i] > best[0]:
                    best = (ratio[i], (r, i, int(pos[i]), cost[i]))
            if best[1] is None:
                break
            r, i, j, c = best[1]
            routes[r].insert(j + 1, i); tused[r] += c
            S[i].add(r[1]); upd_gain(i)
            cache[r] = best_ins(routes[r])
        if rnd == 0:
            for r in routes:
                routes[r] = two_opt(routes[r]); tused[r] = route_time(routes[r]); cache[r] = best_ins(routes[r])
    return routes


def execute_day(I, routes, t, paid, used, P, U_s):
    coll, km, visits = 0.0, 0.0, 0
    for (k, tt), seq in routes.items():
        if tt != t:
            continue
        cur = 0
        for i in seq[1:-1]:
            if paid[i]:
                continue
            km += I.Dk[cur, i]; cur = i; visits += 1; used[i] += 1
            if U_s[i, t] < P[i, t]:
                paid[i] = True; coll += I.w[i]
        km += I.Dk[cur, 0]
    return coll, km, visits


def expected_value(I, routes, P):
    S = {}
    for (k, t), seq in routes.items():
        for i in seq[1:-1]:
            S.setdefault(i, set()).add(t)
    return sum(I.w[i] * (1 - np.prod([1 - P[i, t] for t in ts])) for i, ts in S.items()), S


def run(I, sc, n_mc):
    P = I.p[sc]; rows = []
    avail = np.ones(I.n + 1, bool); used0 = np.zeros(I.n + 1, int)
    t0 = time.time(); stat_routes = plan(I, P, avail, list(range(1, DAYS + 1)), used0, I.m, I.H, I.K); t_stat = time.time() - t0
    ev, Ssel = expected_value(I, stat_routes, P)
    for sidx in range(1, n_mc + 1):
        U_s = I.U[sidx]
        # tĩnh
        paid = np.zeros(I.n + 1, bool); used = np.zeros(I.n + 1, int); C = K_ = V = 0.0
        for t in range(1, DAYS + 1):
            c, k, v = execute_day(I, stat_routes, t, paid, used, P, U_s); C += c; K_ += k; V += v
        rows.append(dict(thuc_the_id=I.iid, kich_ban_p=sc, chinh_sach="TINH", kich_ban_mc=sidx, thu_hoi_vnd=C,
                         quang_duong_km=K_, so_lan_tiep_can=V, thoi_gian_tinh_s=t_stat if sidx == 1 else 0.0))
        # cuốn chiếu
        paid = np.zeros(I.n + 1, bool); used = np.zeros(I.n + 1, int); C = K_ = V = 0.0; tc = 0.0
        for t in range(1, DAYS + 1):
            t0 = time.time()
            r_t = plan(I, P, ~paid, list(range(t, DAYS + 1)), used, I.m, I.H, I.K); tc += time.time() - t0
            c, k, v = execute_day(I, r_t, t, paid, used, P, U_s); C += c; K_ += k; V += v
        rows.append(dict(thuc_the_id=I.iid, kich_ban_p=sc, chinh_sach="CUON_CHIEU", kich_ban_mc=sidx, thu_hoi_vnd=C,
                         quang_duong_km=K_, so_lan_tiep_can=V, thoi_gian_tinh_s=tc))
    return rows, ev, Ssel, stat_routes


def summarize(det):
    out = []
    for (iid, sc), g in det.groupby(["thuc_the_id", "kich_ban_p"]):
        a = g[g.chinh_sach == "TINH"].set_index("kich_ban_mc"); b = g[g.chinh_sach == "CUON_CHIEU"].set_index("kich_ban_mc")
        for col in ["thu_hoi_vnd", "quang_duong_km"]:
            d = (b[col] - a[col]).values; n = len(d)
            se = d.std(ddof=1) / math.sqrt(n); tq = 1.984 if n >= 100 else 2.0
            out.append(dict(thuc_the_id=iid, kich_ban_p=sc, chi_tieu=col, n_kich_ban_mc=n,
                            tb_tinh=a[col].mean(), tb_cuon_chieu=b[col].mean(), chenh_lech_tb=d.mean(),
                            ci95_duoi=d.mean() - tq * se, ci95_tren=d.mean() + tq * se,
                            ty_le_cuon_chieu_tot_hon=(d > 0).mean() if col == "thu_hoi_vnd" else (d < 0).mean()))
        out.append(dict(thuc_the_id=iid, kich_ban_p=sc, chi_tieu="thoi_gian_tinh_s_moi_kich_ban",
                        n_kich_ban_mc=len(b), tb_tinh=a.thoi_gian_tinh_s.sum(), tb_cuon_chieu=b.thoi_gian_tinh_s.mean()))
    return pd.DataFrame(out)


if __name__ == "__main__":
    targets = sys.argv[1].split(",") if len(sys.argv) > 1 else ["INS_M", "REP1_M", "REP2_M", "REP3_M", "REP4_M"]
    scens = sys.argv[2].split(",") if len(sys.argv) > 2 else ["THAP", "CO_SO", "CAO"]
    n_mc = int(sys.argv[3]) if len(sys.argv) > 3 else 100
    D = load(); det, sens = [], []
    for iid in targets:
        I = Instance(D, iid)
        plans = {}
        for sc in scens:
            t0 = time.time()
            rows, ev, Ssel, rts = run(I, sc, n_mc); det += rows; plans[sc] = Ssel
            vis = [i for i, ts in Ssel.items() for _ in ts]
            sens.append(dict(thuc_the_id=iid, kich_ban_p=sc, gia_tri_ky_vong_ke_hoach_tinh_vnd=round(ev),
                             so_khach_duoc_chon=len(Ssel), so_lan_tiep_can_ke_hoach=len(vis),
                             **{f"ty_trong_luot_nhom_{g}": round(np.mean([I.group[i] == g for i in vis]), 3) for g in (2, 3, 4, 5)}))
            print(iid, sc, f"{time.time() - t0:.0f}s", flush=True)
        for a in scens:
            for b in scens:
                if a < b:
                    A, B = set(plans[a]), set(plans[b])
                    sens.append(dict(thuc_the_id=iid, kich_ban_p=f"{a}~{b}", jaccard_khach_chon=round(len(A & B) / len(A | B), 3)))
    det = pd.DataFrame(det)
    tag = "_".join(targets) if len(targets) == 1 else "tat_ca"
    det.to_csv(os.path.join(OUT, f"mo_phong_chi_tiet_{tag}.csv"), index=False, encoding="utf-8-sig")
    summarize(det).to_csv(os.path.join(OUT, f"mo_phong_tom_tat_{tag}.csv"), index=False, encoding="utf-8-sig")
    pd.DataFrame(sens).to_csv(os.path.join(OUT, f"do_nhay_ke_hoach_{tag}.csv"), index=False, encoding="utf-8-sig")
