# -*- coding: utf-8 -*-
"""
Bước 2: sinh bộ dữ liệu mô phỏng (phiên bản 3) cho đề tài
"Tối ưu lộ trình thu hồi nợ cho cán bộ ngân hàng tại Hà Nội".

Đầu vào: build/ (từ bước 1), raw/nemotron_hanoi_urban_v3.json, raw/uci_default_of_credit_card_clients.xls
Đầu ra : csv/*.csv (UTF-8 có BOM), build/meta_v3.json

Nhãn nguồn dùng trong tham_so_mo_hinh / data_dictionary:
  [OSM]  OpenStreetMap (Geofabrik 18/10/2026)        [NVIDIA] Nemotron-Personas-Vietnam
  [UCI]  UCI Default of Credit Card Clients            [CK] số liệu công bố khác (ghi rõ trong nguon_du_lieu)
  [GĐ]   giả định của tác giả                          [TT] tính toán từ các thành phần trên
"""
import itertools, json, math, os
from datetime import date, timedelta
import numpy as np
import pandas as pd
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import dijkstra
from scipy.spatial import cKDTree
from matplotlib.path import Path

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW, BUILD, CSV = (os.path.join(ROOT, x) for x in ("raw", "build", "csv"))
os.makedirs(CSV, exist_ok=True)

SEED = 20261020
START = date(2026, 11, 2)            # Thứ Hai; kỳ 5 ngày làm việc [GĐ]
DAYS = [1, 2, 3, 4, 5]
WORK_MIN = 480
M_MAX = 3
N_MC = 100
CUSTOMER_SETS = [  # (mã bộ, số KH, seed, mô tả)
    ("MAIN", 500, SEED + 0, "Bộ chính, dùng cho các thể hiện lồng nhau INS_XS ⊂ INS_S ⊂ INS_M ⊂ INS_L"),
    ("REP1", 200, SEED + 101, "Bộ lặp độc lập 1 (seed khác) để kiểm tra độ vững của kết luận"),
    ("REP2", 200, SEED + 202, "Bộ lặp độc lập 2"),
    ("REP3", 200, SEED + 303, "Bộ lặp độc lập 3"),
    ("REP4", 200, SEED + 404, "Bộ lặp độc lập 4"),
]
OLD_DISTRICTS = ["Hoàn Kiếm", "Ba Đình", "Đống Đa", "Hai Bà Trưng", "Cầu Giấy", "Thanh Xuân"]
STUDY = dict(lat0=20.980, lat1=21.050, lon0=105.775, lon1=105.870)
BRANCH_OSM_NODE = 11283340462      # POI VPBank, Phố Láng Hạ trong OSM; dùng làm vị trí chi nhánh giả định
MIN_SEP_M = 40.0                  # khoảng cách tối thiểu giữa hai khách hàng trong một bộ [GĐ]
RES_EDGE = {"residential", "living_street", "service", "unclassified", "tertiary", "tertiary_link"}

# ---------------- nhóm nợ: cơ cấu tham chiếu công khai [CK], DPD theo TT 11/2021 ----------------
# Cơ cấu nhóm 2 / nợ xấu: VPBank hợp nhất Q1/2025 (nhóm 2 = 4,3% dư nợ, nợ xấu = 4,7%); trong nợ xấu nhóm 5 = 24%
# (8.383/34.610 tỷ); nhóm 3 : nhóm 4 = 43,8 : 53,5 (27 NH niêm yết 2024). Đây là cơ cấu toàn danh mục, dùng làm
# tham chiếu cho danh mục thu hồi thực địa (giả định chúng tương tự) [GĐ].
DEBT = pd.DataFrame([
    # nhom, ten, dpd_min, dpd_max, ty_trong, p_co_so, ty_le_giam_ngay, phut_pv_min, phut_pv_max
    (2, "Nợ cần chú ý", 31, 90, 0.478, 0.35, 0.06, 15, 20),
    (3, "Nợ dưới tiêu chuẩn", 91, 180, 0.178, 0.22, 0.05, 18, 25),
    (4, "Nợ nghi ngờ", 181, 360, 0.218, 0.12, 0.04, 22, 30),
    (5, "Nợ có khả năng mất vốn", 361, 720, 0.126, 0.06, 0.03, 22, 30),
], columns=["nhom_no", "ten_nhom", "dpd_min", "dpd_max", "ty_trong", "p_co_so", "ty_le_giam_ngay",
            "phut_phuc_vu_min", "phut_phuc_vu_max"])
ALPHA_DPD = 0.30
P_SCEN = [("THAP", 0.5, "Kịch bản thấp: p cơ sở × 0,5"), ("CO_SO", 1.0, "Kịch bản cơ sở (giả định)"),
          ("CAO", 1.5, "Kịch bản cao: p cơ sở × 1,5, chặn trên 0,95")]

# ---------------- sản phẩm [GĐ] (trừ thẻ: hạn mức & tỷ lệ sử dụng theo hình dạng phân bố UCI) ----------------
PRODUCTS = {
    # tên: (trọng số, lãi suất/năm, kỳ hạn các lựa chọn, có tài sản bảo đảm, trung vị gốc (VND), sigma log, trần)
    "Thẻ tín dụng": (0.30, 0.30, None, False, None, None, 200_000_000),
    "Vay tiêu dùng tín chấp": (0.35, 0.20, [24, 36, 48, 60], False, 60_000_000, 0.60, 500_000_000),
    "Vay mua xe": (0.12, 0.10, [48, 60, 72], True, 350_000_000, 0.45, 1_500_000_000),
    "Vay thế chấp nhà": (0.08, 0.09, [120, 180, 240], True, 1_500_000_000, 0.50, 6_000_000_000),
    "Vay kinh doanh hộ cá thể": (0.15, 0.11, [24, 36, 60], True, 300_000_000, 0.70, 3_000_000_000),
}
CARD_MEDIAN_LIMIT = 30_000_000   # trung vị hạn mức thẻ [GĐ]; hình dạng phân bố lấy từ UCI
MIN_PAY = 0.05                   # thanh toán tối thiểu thẻ [GĐ]
OVERDUE_MULT = 1.5               # lãi quá hạn = 150% lãi trong hạn (TT 39/2016) [CK]
ACCELERATE = {4, 5}              # nhóm 4–5 + sản phẩm không bảo đảm: toàn bộ dư nợ đến hạn [GĐ]

BUSINESS_KW = ["Tiểu thương", "Kinh doanh", "Chủ ", "Đại lý", "Bán hàng online", "Buôn bán"]
NOINC_KW = ["Đang tìm việc", "Vừa nghỉ việc", "Sinh viên", "Nội trợ", "Thất nghiệp"]
FREE_KW = ["Bán hàng rong", "Lao động phổ thông", "Lái xe ôm", "Tài xế công nghệ", "Thợ", "tự do", "Phụ hồ"]


def nhom_nghe(o):
    if o.startswith("Nghỉ hưu"): return "Hưu trí"
    if any(k in o for k in NOINC_KW): return "Không có thu nhập thường xuyên"
    if any(k in o for k in BUSINESS_KW): return "Kinh doanh"
    if any(k in o for k in FREE_KW): return "Lao động tự do"
    return "Làm công ăn lương"


def write(df, name):
    df.to_csv(os.path.join(CSV, name + ".csv"), index=False, encoding="utf-8-sig", lineterminator="\n")


def annuity(P, r, n):
    i = r / 12
    return P * i / (1 - (1 + i) ** -n)


def balance(P, r, n, k):
    i = r / 12
    return P * (1 + i) ** k - annuity(P, r, n) * ((1 + i) ** k - 1) / i


def r1000(x):
    return int(round(x / 1000.0)) * 1000


# ======================================================================= main
def main():
    rng_master = np.random.default_rng(SEED)
    meta_net = json.load(open(os.path.join(BUILD, "network_meta.json"), encoding="utf-8"))
    nodes = pd.read_csv(os.path.join(BUILD, "graph_nodes.csv"))
    edges = pd.read_csv(os.path.join(BUILD, "graph_edges.csv"))
    areas = json.load(open(os.path.join(BUILD, "areas.json"), encoding="utf-8"))
    bld = pd.read_csv(os.path.join(BUILD, "buildings.csv"))
    per_src = json.load(open(os.path.join(RAW, "nemotron_hanoi_urban_v3.json"), encoding="utf-8"))

    # ---------------------------------------------------------- 1. ranh giới & gán vùng cho nút
    lat0 = 21.015
    kx, ky = 111320 * math.cos(math.radians(lat0)), 110574

    def xy(lat, lon):
        return np.c_[(np.asarray(lon) - 105.82) * kx, (np.asarray(lat) - lat0) * ky]

    polys = []
    for a in areas:
        rings = [r["coords"] for r in a["rings"]["outer"] if r["closed"]]
        holes = [r["coords"] for r in a["rings"]["inner"] if r["closed"]]
        paths = [Path(xy([c[0] for c in rg], [c[1] for c in rg])) for rg in rings]
        hpaths = [Path(xy([c[0] for c in rg], [c[1] for c in rg])) for rg in holes]
        polys.append(dict(id=a["id"], kind=a["kind"], name=a["tags"].get("name", ""), tags=a["tags"], paths=paths, holes=hpaths))

    def inside(poly, P):
        m = np.zeros(len(P), bool)
        for p in poly["paths"]:
            m |= p.contains_points(P)
        for h in poly["holes"]:
            m &= ~h.contains_points(P)
        return m

    NP = xy(nodes.lat.values, nodes.lon.values)
    nodes["quan_cu"] = ""
    nodes["phuong_2025"] = ""
    for p in polys:
        m = inside(p, NP)
        if p["kind"] == "district_old":
            nodes.loc[m, "quan_cu"] = p["name"].replace("Quận ", "")
        else:
            nodes.loc[m & (nodes.phuong_2025 == ""), "phuong_2025"] = p["name"]

    # ---------------------------------------------------------- 2. đồ thị & chi nhánh
    nid = nodes.node_id.values
    idx = {n: i for i, n in enumerate(nid)}
    ui = edges.u.map(idx).values; vi = edges.v.map(idx).values
    Gt = csr_matrix((edges.travel_time_s.values, (ui, vi)), shape=(len(nid), len(nid)))
    NN = len(nid)
    ekey = ui.astype(np.int64) * NN + vi
    eord = np.argsort(ekey); ekey_s = ekey[eord]; elen_s = edges.length_m.values[eord]

    def edge_len(a, b):
        k = a.astype(np.int64) * NN + b
        pos = np.clip(np.searchsorted(ekey_s, k), 0, len(ekey_s) - 1)
        out = np.where(ekey_s[pos] == k, elen_s[pos], 0.0)
        return out
    banks = json.load(open(os.path.join(BUILD, "banks.json"), encoding="utf-8"))
    bpoi = [b for b in banks if b["type"] == "node" and b["id"] == BRANCH_OSM_NODE][0]
    bxy = xy([bpoi["lat"]], [bpoi["lon"]])[0]
    tree_nodes = cKDTree(NP)
    dist_b, bi = tree_nodes.query(bxy)
    branch_node = int(nid[bi])

    # ---------------------------------------------------------- 3. ứng viên vị trí khách hàng (có chủ đích)
    inc_res = set(edges.loc[edges.highway.isin(RES_EDGE), "u"]) | set(edges.loc[edges.highway.isin(RES_EDGE), "v"])
    in_study = nodes.trong_vung_nghien_cuu.eq(1)
    cand = nodes[in_study & nodes.quan_cu.isin(OLD_DISTRICTS) & (nodes.phuong_2025 != "") &
                 nodes.node_id.isin(inc_res) & (nodes.node_id != branch_node)].copy()
    BP = xy(bld.lat.values, bld.lon.values)
    tb = cKDTree(BP)
    cand["so_cong_trinh_100m"] = [len(x) for x in tb.query_ball_point(xy(cand.lat.values, cand.lon.values), r=100)]
    cand = cand[cand.so_cong_trinh_100m > 0]

    # Hạn ngạch theo phường 2025: dân số phường (tag population OSM, nguồn gis.vn 01/07/2025) × tỷ lệ diện tích phường
    # nằm trong vùng lấy mẫu (giao của 6 quận cũ và khung nghiên cứu). Diện tích ước bằng lưới điểm 50 m.
    gx = np.arange((STUDY["lon0"] - 105.82) * kx - 20000, (STUDY["lon1"] - 105.82) * kx + 20000, 50.0)
    gy = np.arange((20.90 - lat0) * ky, (21.12 - lat0) * ky, 50.0)
    GX, GY = np.meshgrid(gx, gy); GP = np.c_[GX.ravel(), GY.ravel()]
    glon = GP[:, 0] / kx + 105.82; glat = GP[:, 1] / ky + lat0
    g_study = (glat >= STUDY["lat0"]) & (glat <= STUDY["lat1"]) & (glon >= STUDY["lon0"]) & (glon <= STUDY["lon1"])
    g_old = np.zeros(len(GP), bool)
    for p in polys:
        if p["kind"] == "district_old" and p["name"].replace("Quận ", "") in OLD_DISTRICTS:
            g_old |= inside(p, GP)
    ward_rows = []
    for p in polys:
        if p["kind"] != "ward2025":
            continue
        m = inside(p, GP)
        a_tot = m.sum() * 0.0025          # km² (ô 50 m)
        a_in = (m & g_study & g_old).sum() * 0.0025
        if a_in <= 0:
            continue
        pop = float(p["tags"].get("population", "nan"))
        ward_rows.append(dict(phuong_2025=p["name"], osm_relation_id=p["id"], dan_so_2025=int(pop),
                              nguon_dan_so=p["tags"].get("source:population", ""), ngay_dan_so=p["tags"].get("population:date", ""),
                              dien_tich_km2=round(a_tot, 3), dien_tich_trong_vung_km2=round(a_in, 3),
                              dan_so_uoc_trong_vung=round(pop * a_in / a_tot, 1)))
    wards = pd.DataFrame(ward_rows)
    wards = wards[wards.phuong_2025.isin(cand.phuong_2025.unique())].copy()
    wards["ty_trong_mau"] = wards.dan_so_uoc_trong_vung / wards.dan_so_uoc_trong_vung.sum()
    wards = wards.sort_values("dan_so_uoc_trong_vung", ascending=False).reset_index(drop=True)

    def quotas(n, rng):
        q = wards.ty_trong_mau.values * n
        base = np.floor(q).astype(int)
        rem = n - base.sum()
        order = np.argsort(-(q - base) + rng.uniform(0, 1e-9, len(q)))
        base[order[:rem]] += 1
        return dict(zip(wards.phuong_2025, base))

    # ---------------------------------------------------------- 4. hồ sơ NVIDIA
    pool = pd.DataFrame(per_src["rows"])
    pool = pool[(pool.age >= 20) & (pool.age <= 65)].drop_duplicates("uuid").sort_values("row_idx").reset_index(drop=True)
    pool["nhom_nghe"] = pool.occupation.map(nhom_nghe)

    # UCI: hình dạng phân bố hạn mức và tỷ lệ sử dụng của khách thẻ trễ hạn ≥ 2 tháng
    uci = pd.read_excel(os.path.join(RAW, "uci_default_of_credit_card_clients.xls"), header=1)
    dl = uci[uci.PAY_0 >= 2]
    lim_rel = np.sort(dl.LIMIT_BAL.values / np.median(dl.LIMIT_BAL.values))
    util = np.sort(np.clip(dl.BILL_AMT1.values / dl.LIMIT_BAL.values, 0, 1.2))
    uci_info = dict(n_tre_han=int(len(dl)), median_limit_ntd=float(np.median(dl.LIMIT_BAL)),
                    limit_rel_q=[round(float(x), 4) for x in np.quantile(lim_rel, [.1, .25, .5, .75, .9])],
                    util_q=[round(float(x), 4) for x in np.quantile(util, [.1, .25, .5, .75, .9])])

    def eligible(row):
        g, age = row.nhom_nghe, row.age
        el = []
        if g in ("Làm công ăn lương", "Kinh doanh", "Lao động tự do", "Hưu trí", "Không có thu nhập thường xuyên"):
            el.append("Thẻ tín dụng")
        if g in ("Làm công ăn lương", "Lao động tự do") and age <= 60:
            el.append("Vay tiêu dùng tín chấp")
        if g in ("Làm công ăn lương", "Kinh doanh", "Lao động tự do") and 21 <= age <= 60:
            el.append("Vay mua xe")
        if g in ("Làm công ăn lương", "Kinh doanh") and 25 <= age <= 60:
            el.append("Vay thế chấp nhà")
        if g == "Kinh doanh" and age <= 62:
            el.append("Vay kinh doanh hộ cá thể")
        return el

    # ---------------------------------------------------------- 5. sinh từng bộ khách hàng
    period_dates = [START + timedelta(days=d - 1) for d in DAYS]
    cust_rows, prob_rows, sched_rows, mc_rows, mat_rows, set_rows = [], [], [], [], [], []
    subsets = [s for k in range(1, 6) for s in itertools.combinations(DAYS, k)]
    gshare = DEBT.ty_trong.values / DEBT.ty_trong.sum()

    for set_id, n, seed, desc in CUSTOMER_SETS:
        rng = np.random.default_rng(seed)
        rng_mc = np.random.default_rng(seed + 9_000_000)        # luồng ngẫu nhiên riêng cho Monte Carlo
        # vị trí
        q = quotas(n, rng)
        chosen, taken = [], np.empty((0, 2))
        for w, k in q.items():
            if k == 0:
                continue
            cw = cand[cand.phuong_2025 == w]
            pr = cw.so_cong_trinh_100m.values.astype(float); pr /= pr.sum()
            order = rng.choice(len(cw), size=len(cw), replace=False, p=pr)   # thứ tự rút ∝ mật độ công trình
            got = []
            for o in order:                                                  # khoảng cách tối thiểu MIN_SEP_M
                pxy = xy([cw.lat.values[o]], [cw.lon.values[o]])
                if len(taken) and np.min(np.hypot(*(taken - pxy).T)) < MIN_SEP_M:
                    continue
                got.append(o); taken = np.vstack([taken, pxy])
                if len(got) == k:
                    break
            chosen.append(cw.iloc[got])
        loc = pd.concat(chosen).sample(frac=1, random_state=seed % 2**32).reset_index(drop=True)
        # hồ sơ (không lặp trong bộ)
        prs = pool.iloc[rng.choice(len(pool), size=n, replace=False)].reset_index(drop=True)
        # nhóm nợ (đúng cơ cấu, làm tròn theo phần dư lớn nhất)
        cnt = np.floor(gshare * n).astype(int); cnt[np.argsort(-(gshare * n - cnt))[: n - cnt.sum()]] += 1
        groups = np.repeat(DEBT.nhom_no.values, cnt); rng.shuffle(groups)

        ids = []
        for j in range(n):
            cid = f"{set_id}_KH{j + 1:04d}"; ids.append(cid)
            ps, lc, g = prs.iloc[j], loc.iloc[j], int(groups[j])
            D = DEBT.set_index("nhom_no").loc[g]
            dpd = int(round(rng.triangular(D.dpd_min, D.dpd_min, D.dpd_max)))
            k_miss = math.ceil(dpd / 30)
            el = eligible(ps)
            wts = np.array([PRODUCTS[p][0] for p in el]); prod = el[rng.choice(len(el), p=wts / wts.sum())]
            w_, rate, terms, secured, med, sig, cap = PRODUCTS[prod]
            if prod == "Thẻ tín dụng":
                limit = min(cap, max(5_000_000, int(round(CARD_MEDIAN_LIMIT * lim_rel[rng.integers(len(lim_rel))] / 1e6)) * 1_000_000))
                u_ = max(0.30, util[rng.integers(len(util))])
                outstanding = r1000(limit * min(u_, 1.10)); principal = limit; term = None; paid = None
                inst = max(MIN_PAY * outstanding, 200_000)
            else:
                principal = min(cap, med * math.exp(rng.normal(0, sig)))
                principal = r1000(max(principal, 10_000_000))
                tok = [x for x in terms if x >= k_miss + 6] or [max(terms)]           # khoản vay chưa đáo hạn khi bắt đầu quá hạn
                term = int(rng.choice(tok)); paid = int(rng.integers(3, term - k_miss + 1))
                inst = annuity(principal, rate, term)
                outstanding = r1000(balance(principal, rate, term, paid))
            r_od = OVERDUE_MULT * rate
            if g in ACCELERATE and not secured:
                overdue = outstanding * (1 + r_od * dpd / 365); kieu = "Toàn bộ dư nợ đến hạn (thu hồi trước hạn)"
            else:
                due = min(k_miss * inst, outstanding * (1 + rate * k_miss / 12))
                overdue = due * (1 + r_od * (dpd / 2) / 365); kieu = "Các kỳ quá hạn + lãi quá hạn"
            overdue = r1000(overdue)
            target = overdue                                   # mục tiêu của một lần thu thành công [GĐ-TIEN]
            svc = int(rng.integers(D.phut_phuc_vu_min, D.phut_phuc_vu_max + 1))
            cust_rows.append(dict(
                khach_hang_id=cid, bo_khach_hang_id=set_id, persona_uuid=ps.uuid, persona_row_idx=int(ps.row_idx),
                gioi_tinh=ps.sex, tuoi=int(ps.age), tinh_trang_hon_nhan=ps.marital_status,
                trinh_do_hoc_van=ps.education_level, nghe_nghiep=ps.occupation, nhom_nghe=ps.nhom_nghe,
                quan_cu=lc.quan_cu, phuong_2025=lc.phuong_2025, node_id=int(lc.node_id), lat=lc.lat, lon=lc.lon,
                so_cong_trinh_100m=int(lc.so_cong_trinh_100m), chi_nhanh_id="CN01",
                loai_san_pham=prod, co_tai_san_bao_dam=int(secured), lai_suat_nam=rate,
                ky_han_thang=term, so_ky_da_tra=paid, goc_hoac_han_muc_vnd=int(principal),
                tra_gop_hoac_toi_thieu_vnd=r1000(inst), tong_du_no_vnd=int(outstanding),
                nhom_no=g, so_ngay_qua_han=dpd, so_ky_qua_han=k_miss, cach_tinh_qua_han=kieu,
                so_tien_qua_han_vnd=int(overdue), so_tien_muc_tieu_vnd=int(target),
                thoi_gian_phuc_vu_phut=svc))
            # p(i,t) theo kịch bản – chỉ phụ thuộc nhóm nợ, DPD, ngày [GĐ-P]
            f = (dpd - D.dpd_min) / (D.dpd_max - D.dpd_min)
            base = [D.p_co_so * (1 - ALPHA_DPD * f) * (1 - D.ty_le_giam_ngay) ** (t - 1) for t in DAYS]
            pv = {}
            for sc, mult, _ in P_SCEN:
                pv[sc] = [round(min(0.95, b * mult), 4) for b in base]
                for t in DAYS:
                    prob_rows.append(dict(khach_hang_id=cid, kich_ban_p=sc, ngay_thu=t,
                                          ngay=period_dates[t - 1].isoformat(), p_thu_hoi=pv[sc][t - 1]))
            for si, S in enumerate(subsets, 1):
                row = dict(lich_id=f"{cid}_S{si:02d}", khach_hang_id=cid, tap_ngay="-".join(map(str, S)), so_lan=len(S))
                for sc, _, _ in P_SCEN:
                    row[f"v_vnd_{sc.lower()}"] = int(round(target * (1 - np.prod([1 - pv[sc][t - 1] for t in S]))))
                sched_rows.append(row)
            U = rng_mc.random((N_MC, len(DAYS)))
            for s in range(N_MC):
                for t in DAYS:
                    mc_rows.append((s + 1, cid, t, round(float(U[s, t - 1]), 6)))
        set_rows.append(dict(bo_khach_hang_id=set_id, so_khach_hang=n, seed=seed, seed_monte_carlo=seed + 9_000_000, mo_ta=desc))

        # ma trận thời gian / quãng đường trên cùng tuyến nhanh nhất
        pts = [branch_node] + [int(c["node_id"]) for c in cust_rows[-n:]]
        pid = ["CN01"] + ids
        src = np.array([idx[p] for p in pts])
        dt, pred = dijkstra(Gt, directed=True, indices=src, return_predecessors=True)
        for a, s in enumerate(src):
            ptr = pred[a].astype(np.int64); ptr[s] = s
            allv = np.arange(len(ptr))
            acc = edge_len(ptr, allv); acc[s] = 0.0
            for _ in range(64):            # nhân đôi con trỏ: cộng độ dài dọc cây đường đi nhanh nhất
                if np.all(ptr == s):
                    break
                acc = acc + acc[ptr]; ptr = ptr[ptr]
            for b, t_ in enumerate(src):
                mat_rows.append((set_id, pid[a], pid[b], round(acc[t_] / 1000, 3), round(dt[a, t_] / 60, 2)))

    cust = pd.DataFrame(cust_rows)
    cust["ky_han_thang"] = cust.ky_han_thang.astype("Int64"); cust["so_ky_da_tra"] = cust.so_ky_da_tra.astype("Int64")

    # ---------------------------------------------------------- 6. thể hiện, thiết kế thí nghiệm
    inst_rows, ic_rows, ib_rows = [], [], []
    main_ids = cust[cust.bo_khach_hang_id == "MAIN"].khach_hang_id.values
    perm = rng_master.permutation(main_ids)
    INST = [("INS_XS", "MAIN", 30, 2, 3, "Nhỏ, kiểm tra định tuyến và MILP chính xác"),
            ("INS_S", "MAIN", 80, 2, 2, "Nhỏ-vừa, MILP"),
            ("INS_M", "MAIN", 200, 3, 2, "Vừa, MILP có giới hạn thời gian, có thể cần heuristic"),
            ("INS_L", "MAIN", 500, 4, 2, "Lớn, heuristic và so sánh với cận tốt nhất")]
    for r in ["REP1", "REP2", "REP3", "REP4"]:
        INST += [(f"{r}_S", r, 80, 2, 2, f"Lặp độc lập trên bộ {r}, cỡ như INS_S"),
                 (f"{r}_M", r, 200, 3, 2, f"Lặp độc lập trên bộ {r}, cỡ như INS_M")]
    perms = {"MAIN": perm}
    for r in ["REP1", "REP2", "REP3", "REP4"]:
        perms[r] = np.random.default_rng(dict((c[0], c[2]) for c in CUSTOMER_SETS)[r] + 55).permutation(
            cust[cust.bo_khach_hang_id == r].khach_hang_id.values)
    officers = ["CB01", "CB02", "CB03", "CB04"]
    for iid, bset, n, K, m, desc in INST:
        members = sorted(perms[bset][:n])
        inst_rows.append(dict(thuc_the_id=iid, bo_khach_hang_id=bset, so_khach_hang=n, so_can_bo=K, so_ngay=5,
                              phut_lam_viec_ngay=WORK_MIN, m_mac_dinh=m, mo_ta=desc))
        ic_rows += [dict(thuc_the_id=iid, khach_hang_id=c) for c in members]
        ib_rows += [dict(thuc_the_id=iid, can_bo_id=o) for o in officers[:K]]
    inst = pd.DataFrame(inst_rows)
    # tải năng lực (cận dưới)
    mat = pd.DataFrame(mat_rows, columns=["bo_khach_hang_id", "tu_id", "den_id", "khoang_cach_km", "thoi_gian_phut"])
    exp_rows, eid = [], 0
    base_cfg = dict(phut=480, m=2, kb="CO_SO")
    for _, r in inst.iterrows():
        for K in (2, 3, 4):
            for H in (360, 420, 480):
                for m in (1, 2, 3):
                    for kb, _, _ in P_SCEN:
                        eid += 1
                        core = (H == 480 and m == 2 and kb == "CO_SO" and K == r.so_can_bo)
                        oat = sum([H != 480, m != 2, kb != "CO_SO", K != r.so_can_bo]) == 1
                        exp_rows.append(dict(thi_nghiem_id=f"TN{eid:04d}", thuc_the_id=r.thuc_the_id, so_can_bo=K,
                                             phut_lam_viec_ngay=H, m=m, kich_ban_p=kb, so_kich_ban_mc=N_MC,
                                             muc_uu_tien=1 if core else (2 if oat else 3)))
    exp = pd.DataFrame(exp_rows)

    # ---------------------------------------------------------- 7. bảng tham số & mô tả
    nd_out = nodes.rename(columns={"trong_vung_nghien_cuu": "trong_vung_nghien_cuu"})[
        ["node_id", "lat", "lon", "quan_cu", "phuong_2025", "trong_vung_nghien_cuu"]]
    ed_out = edges[["edge_id", "u", "v", "osm_way_id", "highway", "ten_duong", "oneway", "length_m", "toc_do_kmh", "travel_time_s"]].copy()
    ed_out["ten_duong"] = ed_out.ten_duong.fillna("")
    speed = pd.DataFrame([dict(highway=h, ten_loai_duong=meta_net["highway_name_vi"][h], toc_do_kmh=v,
                               so_canh=int((edges.highway == h).sum())) for h, v in meta_net["speed_kmh"].items()])
    branch = pd.DataFrame([dict(chi_nhanh_id="CN01", ten_chi_nhanh="Chi nhánh giả định (vị trí POI VPBank trên OSM)",
                                osm_poi_id=BRANCH_OSM_NODE, ten_poi_osm=bpoi["name"],
                                dia_chi_osm=f"{bpoi['hn']} {bpoi['street']}".strip(),
                                quan_cu=nodes.loc[bi, "quan_cu"], phuong_2025=nodes.loc[bi, "phuong_2025"],
                                node_id=branch_node, lat=nodes.loc[bi, "lat"], lon=nodes.loc[bi, "lon"],
                                khoang_cach_poi_den_nut_m=round(float(dist_b), 1), gio_mo_cua="08:00", gio_dong_cua="17:00")])
    officer = pd.DataFrame([dict(can_bo_id=o, chi_nhanh_id="CN01", phuong_tien="Xe máy", gio_bat_dau="08:00",
                                 gio_ket_thuc="17:00", phut_nghi_trua=60, phut_lam_viec_ngay=WORK_MIN, so_ngay_san_sang=5)
                            for o in officers])
    ngay = pd.DataFrame([dict(ngay_thu=t, ngay=d.isoformat(), thu=["Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu"][t - 1])
                         for t, d in zip(DAYS, period_dates)])
    kbp = pd.DataFrame([dict(kich_ban_p=s, he_so_nhan=mlt, chan_tren=0.95, mo_ta=d, nguon="Giả định") for s, mlt, d in P_SCEN])
    debt = DEBT.copy()
    debt["so_khach_hang_main"] = [int((cust[(cust.bo_khach_hang_id == "MAIN")].nhom_no == g).sum()) for g in debt.nhom_no]
    debt["alpha_dpd"] = ALPHA_DPD
    debt["nguon_ty_trong"] = "Tham chiếu công bố (VPBank Q1/2025; 27 NH niêm yết 2024)"
    debt["nguon_p"] = "Giả định (chưa có dữ liệu kết quả tiếp cận)"
    prod_tab = pd.DataFrame([dict(loai_san_pham=k, trong_so=v[0], lai_suat_nam=v[1],
                                  ky_han_thang=";".join(map(str, v[2])) if v[2] else "", co_tai_san_bao_dam=int(v[3]),
                                  trung_vi_goc_vnd=v[4] if v[4] else CARD_MEDIAN_LIMIT, sigma_log=v[5] if v[5] else "",
                                  tran_vnd=v[6],
                                  nguon_phan_bo=("Hình dạng phân bố hạn mức và tỷ lệ sử dụng: UCI (khách trễ ≥ 2 tháng); "
                                                 "trung vị hạn mức 30 triệu: giả định") if k == "Thẻ tín dụng" else "Giả định (log-chuẩn)")
                             for k, v in PRODUCTS.items()])
    params = [
        ("seed", SEED, "", "Seed gốc (mỗi bộ khách hàng có seed riêng, xem bo_khach_hang)", "Giả định"),
        ("ngay_bat_dau", START.isoformat(), "ngày", "Ngày đầu kỳ thu hồi (Thứ Hai)", "Giả định"),
        ("so_ngay_ky", 5, "ngày", "|T|", "Tài liệu"),
        ("phut_lam_viec_ngay", WORK_MIN, "phút", "Giờ làm việc tối đa của một cán bộ mỗi ngày", "Tài liệu"),
        ("m_toi_da_trong_lich", M_MAX, "lần", "Lịch được tính sẵn tới |S| = 5; mô hình lọc so_lan ≤ m (m = 1, 2, 3)", "Tài liệu"),
        ("mo_hinh_thu_tien", "TOAN_BO_HOAC_KHONG", "", "Một lần tiếp cận thành công thu đủ so_tien_muc_tieu_vnd; thất bại thu 0; khách đã trả không tiếp cận nữa", "Giả định [GĐ-TIEN]"),
        ("phuong_tien", "Xe máy", "", "Mạng đường lọc theo quyền đi của xe máy (motorway, motorcycle=no bị loại)", "Giả định + OSM"),
        ("nguon_mang_duong", "Geofabrik vietnam-latest.osm.pbf", "", f"Dữ liệu OSM đến {meta_net['source'].get('osm_data_until','')}; tải {meta_net['source'].get('extracted_at','')}", "OSM"),
        ("vung_nghien_cuu", "lat 20.980–21.050; lon 105.775–105.870", "độ", "Khung lấy mẫu khách hàng; mạng định tuyến có vùng đệm ~1,5 km", "Giả định"),
        ("quan_lay_mau", ";".join(OLD_DISTRICTS), "", "Khách hàng chỉ nằm trong 6 quận cũ (ranh giới OSM boundary=historic, hết hiệu lực 30/6/2025)", "OSM"),
        ("phan_bo_khach_hang", "Hạn ngạch theo dân số phường 2025 × tỷ lệ diện tích trong vùng; trong phường chọn nút ∝ số công trình trong 100 m; cách nhau ≥ 40 m", "", "Lấy mẫu có chủ đích, không chọn đều các nút đường", "OSM + Giả định"),
        ("so_kich_ban_monte_carlo", N_MC, "kịch bản", "Số ngẫu nhiên chung cho mọi chính sách (common random numbers)", "Giả định"),
        ("alpha_dpd", ALPHA_DPD, "", "Hệ số giảm p theo vị trí DPD trong nhóm", "Giả định"),
        ("lai_qua_han_he_so", OVERDUE_MULT, "", "Lãi trên gốc quá hạn = 150% lãi trong hạn", "TT 39/2016/TT-NHNN"),
        ("thanh_toan_toi_thieu_the", MIN_PAY, "", "Tỷ lệ thanh toán tối thiểu thẻ tín dụng mỗi kỳ", "Giả định"),
        ("trung_vi_han_muc_the_vnd", CARD_MEDIAN_LIMIT, "VND", "Trung vị hạn mức thẻ (hình dạng phân bố lấy từ UCI)", "Giả định + UCI"),
    ]
    tham_so = pd.DataFrame(params, columns=["tham_so", "gia_tri", "don_vi", "mo_ta", "nguon"])

    # ---------------------------------------------------------- 8. ghi CSV
    write(tham_so, "tham_so_mo_hinh"); write(ngay, "ngay_ky"); write(debt, "tham_so_nhom_no")
    write(prod_tab, "tham_so_san_pham"); write(kbp, "kich_ban_xac_suat"); write(speed, "toc_do_loai_duong")
    write(nd_out, "nut_duong"); write(ed_out, "canh_duong"); write(wards, "phuong_lay_mau")
    write(branch, "chi_nhanh"); write(officer, "can_bo"); write(pd.DataFrame(set_rows), "bo_khach_hang")
    write(cust, "khach_hang"); write(pd.DataFrame(prob_rows), "xac_suat_thu_hoi")
    write(pd.DataFrame(sched_rows), "lich_tiep_can"); write(mat, "ma_tran_di_chuyen")
    write(inst, "thuc_the"); write(pd.DataFrame(ic_rows), "thuc_the_khach_hang"); write(pd.DataFrame(ib_rows), "thuc_the_can_bo")
    write(exp, "thiet_ke_thi_nghiem")
    write(pd.DataFrame(mc_rows, columns=["kich_ban_id", "khach_hang_id", "ngay_thu", "u"]), "kich_ban_monte_carlo")
    json.dump(dict(uci=uci_info, persona_meta={k: v for k, v in per_src["meta"].items() if k != "page_offsets"},
                   persona_pool_20_65=int(len(pool)), network=meta_net, branch_node=branch_node),
              open(os.path.join(BUILD, "meta_v3.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1, default=str)
    print("customers", len(cust), "matrix rows", len(mat), "mc rows", len(mc_rows), "wards", len(wards))


if __name__ == "__main__":
    main()
