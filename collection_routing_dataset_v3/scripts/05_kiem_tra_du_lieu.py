# -*- coding: utf-8 -*-
"""
Bước 5: kiểm tra toàn bộ gói dữ liệu, ghi validation_report.txt (mã thoát 0 = đạt).
Các phép tính lại (Dijkstra, p, v, hạn ngạch) được viết độc lập với bước 2.
"""
import hashlib, json, math, os, sys, zipfile, re
from datetime import datetime
import numpy as np
import pandas as pd
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import dijkstra, connected_components

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV = os.path.join(ROOT, "csv")
TABLES = ["tham_so_mo_hinh", "ngay_ky", "tham_so_nhom_no", "tham_so_san_pham", "kich_ban_xac_suat", "toc_do_loai_duong",
          "nut_duong", "canh_duong", "phuong_lay_mau", "chi_nhanh", "can_bo", "bo_khach_hang", "khach_hang",
          "xac_suat_thu_hoi", "lich_tiep_can", "ma_tran_di_chuyen", "thuc_the", "thuc_the_khach_hang", "thuc_the_can_bo",
          "thiet_ke_thi_nghiem", "kich_ban_monte_carlo", "nguon_du_lieu", "data_dictionary"]
PK = {"tham_so_mo_hinh": ["tham_so"], "ngay_ky": ["ngay_thu"], "tham_so_nhom_no": ["nhom_no"], "tham_so_san_pham": ["loai_san_pham"],
      "kich_ban_xac_suat": ["kich_ban_p"], "toc_do_loai_duong": ["highway"], "nut_duong": ["node_id"], "canh_duong": ["edge_id"],
      "phuong_lay_mau": ["phuong_2025"], "chi_nhanh": ["chi_nhanh_id"], "can_bo": ["can_bo_id"], "bo_khach_hang": ["bo_khach_hang_id"],
      "khach_hang": ["khach_hang_id"], "xac_suat_thu_hoi": ["khach_hang_id", "kich_ban_p", "ngay_thu"], "lich_tiep_can": ["lich_id"],
      "ma_tran_di_chuyen": ["bo_khach_hang_id", "tu_id", "den_id"], "thuc_the": ["thuc_the_id"],
      "thuc_the_khach_hang": ["thuc_the_id", "khach_hang_id"], "thuc_the_can_bo": ["thuc_the_id", "can_bo_id"],
      "thiet_ke_thi_nghiem": ["thi_nghiem_id"], "kich_ban_monte_carlo": ["kich_ban_id", "khach_hang_id", "ngay_thu"],
      "nguon_du_lieu": ["nguon_id"], "data_dictionary": ["bang", "cot"]}
OLD = {"Hoàn Kiếm", "Ba Đình", "Đống Đa", "Hai Bà Trưng", "Cầu Giấy", "Thanh Xuân"}
RES = []


def check(code, name, ok, detail=""):
    RES.append((code, name, bool(ok), detail))


def hav(la1, lo1, la2, lo2):
    la1, lo1, la2, lo2 = map(np.radians, (la1, lo1, la2, lo2))
    a = np.sin((la2 - la1) / 2) ** 2 + np.cos(la1) * np.cos(la2) * np.sin((lo2 - lo1) / 2) ** 2
    return 2 * 6371008.8 * np.arcsin(np.sqrt(a))


def main():
    # 01 tệp & BOM
    miss = [t for t in TABLES if not os.path.exists(os.path.join(CSV, t + ".csv"))]
    check("01", f"Đủ {len(TABLES)} bảng CSV", not miss, "thiếu: " + ",".join(miss) if miss else "")
    nobom = [t for t in TABLES if t not in miss and open(os.path.join(CSV, t + ".csv"), "rb").read(3) != b"\xef\xbb\xbf"]
    check("01b", "Mọi CSV có BOM UTF-8", not nobom, ",".join(nobom))
    import glob
    allcsv = glob.glob(os.path.join(ROOT, "**", "*.csv"), recursive=True)
    nob2 = [os.path.relpath(f, ROOT) for f in allcsv if open(f, "rb").read(3) != b"\xef\xbb\xbf"]
    moj = re.compile("Ã.|á»|áº|Ä‘|Æ°|â€|\ufffd")
    bad_txt = [os.path.relpath(f, ROOT) for f in allcsv if moj.search(open(f, encoding="utf-8-sig").read())]
    check("01c", f"Mọi tệp CSV trong gói ({len(allcsv)} tệp, kể cả build/ và ket_qua/) có BOM và không có chữ lỗi mã hóa",
          not nob2 and not bad_txt, ",".join(nob2 + bad_txt))
    T = {t: pd.read_csv(os.path.join(CSV, t + ".csv"), low_memory=False) for t in TABLES if t not in miss}
    # 02 khóa chính
    bad = [t for t, k in PK.items() if t in T and T[t].duplicated(k).any()]
    check("02", "Khóa chính duy nhất (kể cả khóa ghép)", not bad, ",".join(bad))
    # 03 từ điển dữ liệu phủ mọi cột
    dd = T["data_dictionary"]; gaps = []
    for t in TABLES:
        if t in ("data_dictionary",) or t not in T:
            continue
        cols = list(T[t].columns); dcols = list(dd[dd.bang == t].cot)
        if cols != dcols:
            gaps.append(t)
    check("03", "data_dictionary mô tả đúng và đủ mọi cột, đúng thứ tự", not gaps, ",".join(gaps))
    nd, ed, kh = T["nut_duong"], T["canh_duong"], T["khach_hang"]
    # 04 khóa ngoại
    nset = set(nd.node_id); kset = set(kh.khach_hang_id)
    fk = {
        "canh_duong.u/v": ed.u.isin(nset).all() and ed.v.isin(nset).all(),
        "chi_nhanh.node_id": T["chi_nhanh"].node_id.isin(nset).all(),
        "khach_hang.node_id": kh.node_id.isin(nset).all(),
        "khach_hang.bo": kh.bo_khach_hang_id.isin(T["bo_khach_hang"].bo_khach_hang_id).all(),
        "khach_hang.nhom_no": kh.nhom_no.isin(T["tham_so_nhom_no"].nhom_no).all(),
        "khach_hang.san_pham": kh.loai_san_pham.isin(T["tham_so_san_pham"].loai_san_pham).all(),
        "khach_hang.phuong": kh.phuong_2025.isin(T["phuong_lay_mau"].phuong_2025).all(),
        "canh_duong.highway": ed.highway.isin(T["toc_do_loai_duong"].highway).all(),
        "xac_suat": T["xac_suat_thu_hoi"].khach_hang_id.isin(kset).all() and T["xac_suat_thu_hoi"].kich_ban_p.isin(T["kich_ban_xac_suat"].kich_ban_p).all(),
        "lich": T["lich_tiep_can"].khach_hang_id.isin(kset).all(),
        "mc": T["kich_ban_monte_carlo"].khach_hang_id.isin(kset).all(),
        "thuc_the_kh": T["thuc_the_khach_hang"].khach_hang_id.isin(kset).all() and T["thuc_the_khach_hang"].thuc_the_id.isin(T["thuc_the"].thuc_the_id).all(),
        "thuc_the_cb": T["thuc_the_can_bo"].can_bo_id.isin(T["can_bo"].can_bo_id).all(),
        "thiet_ke": T["thiet_ke_thi_nghiem"].thuc_the_id.isin(T["thuc_the"].thuc_the_id).all() and T["thiet_ke_thi_nghiem"].kich_ban_p.isin(T["kich_ban_xac_suat"].kich_ban_p).all(),
        "ngay": T["xac_suat_thu_hoi"].ngay_thu.isin(T["ngay_ky"].ngay_thu).all(),
    }
    check("04", "Khóa ngoại tham chiếu đúng", all(fk.values()), ",".join(k for k, v in fk.items() if not v))
    # 05 mạng đường
    idx = {n: i for i, n in enumerate(nd.node_id)}; N = len(nd)
    G = csr_matrix((ed.travel_time_s, (ed.u.map(idx), ed.v.map(idx))), shape=(N, N))
    nc, _ = connected_components(G, directed=True, connection="strong")
    check("05", "Mạng đường liên thông mạnh (đi được tới và về chi nhánh từ mọi nút)", nc == 1, f"{nc} thành phần; {N} nút, {len(ed)} cung")
    check("05b", "Không có motorway/đường đi bộ trong mạng xe máy",
          not ed.highway.isin(["motorway", "motorway_link", "footway", "pedestrian", "path", "steps", "cycleway"]).any())
    sp = T["toc_do_loai_duong"].set_index("highway").toc_do_kmh
    tt = ed.length_m / (ed.toc_do_kmh / 3.6)
    check("05c", "travel_time_s = length_m / tốc độ; tốc độ ≤ mức theo loại đường",
          (abs(tt - ed.travel_time_s) <= 0.05 + 1e-6 * tt).all() and (ed.toc_do_kmh <= ed.highway.map(sp) + 1e-9).all())
    pair = set(zip(ed.u, ed.v)); ow = ed[ed.oneway == 1]
    rev = np.mean([(v, u) in pair for u, v in zip(ow.u, ow.v)]) if len(ow) else 1
    check("05d", "Đường một chiều được giữ (cung một chiều phần lớn không có cung ngược)", len(ow) > 0 and rev < 0.2,
          f"{len(ow)} cung một chiều ({len(ow) / len(ed):.1%}); {rev:.1%} có cung ngược (đoạn đôi song song)")
    # 06 chi nhánh & khách hàng trên mạng
    br = T["chi_nhanh"].iloc[0]
    check("06", "Chi nhánh gắn vào nút mạng cách POI OSM ≤ 50 m", br.khoang_cach_poi_den_nut_m <= 50, f"{br.khoang_cach_poi_den_nut_m} m")
    ndi = nd.set_index("node_id")
    k_ok = (kh.node_id.map(ndi.trong_vung_nghien_cuu) == 1).all() and kh.quan_cu.isin(OLD).all() and \
           (kh.quan_cu.values == kh.node_id.map(ndi.quan_cu).values).all() and (kh.phuong_2025.values == kh.node_id.map(ndi.phuong_2025).values).all()
    check("07", "Khách hàng ở nút trong vùng nghiên cứu, thuộc 6 quận cũ; quận/phường khớp nút", k_ok)
    sep, uniq = [], True
    for b, g in kh.groupby("bo_khach_hang_id"):
        uniq &= g.node_id.is_unique and g.persona_uuid.is_unique
        la, lo = g.lat.values, g.lon.values
        dmin = min(np.sort(hav(la[i], lo[i], la, lo))[1] for i in range(len(g)))
        sep.append((b, dmin))
    check("07b", "Trong mỗi bộ: nút và hồ sơ không lặp; hai khách cách nhau ≥ 40 m", uniq and all(d >= 39.5 for _, d in sep),
          "; ".join(f"{b} {d:.0f} m" for b, d in sep))
    w = T["phuong_lay_mau"]; dev = []
    for b, g in kh.groupby("bo_khach_hang_id"):
        n = len(g); exp = (w.set_index("phuong_2025").ty_trong_mau * n)
        got = g.phuong_2025.value_counts().reindex(exp.index, fill_value=0)
        dev.append(float((got - exp).abs().max()))
    check("08", "Số khách mỗi phường bám hạn ngạch dân số (lệch ≤ 1 do làm tròn)", max(dev) <= 1.0, f"lệch lớn nhất {max(dev):.2f}")
    check("08b", "Tỷ trọng mẫu theo phường = dân số ước trong vùng / tổng",
          abs(w.ty_trong_mau.sum() - 1) < 1e-9 and np.allclose(w.ty_trong_mau, w.dan_so_uoc_trong_vung / w.dan_so_uoc_trong_vung.sum()))
    # 09 ma trận
    M = T["ma_tran_di_chuyen"]; okfull = True
    for b, g in kh.groupby("bo_khach_hang_id"):
        n = len(g) + 1
        mm = M[M.bo_khach_hang_id == b]
        okfull &= len(mm) == n * n and set(mm.tu_id) == set(["CN01"] + list(g.khach_hang_id))
    diag = M[M.tu_id == M.den_id]; off = M[M.tu_id != M.den_id]
    check("09", "Ma trận đủ mọi cặp trong từng bộ; đường chéo 0, ngoài đường chéo > 0",
          okfull and (diag[["khoang_cach_km", "thoi_gian_phut"]] == 0).all().all() and (off.thoi_gian_phut > 0).all() and (off.khoang_cach_km > 0).all())
    # Dijkstra độc lập từ 3 nguồn + quãng đường theo cùng tuyến
    Lmat = {(u, v): (l, t) for u, v, l, t in zip(ed.u, ed.v, ed.length_m, ed.travel_time_s)}
    node_of = dict(zip(kh.khach_hang_id, kh.node_id)); node_of["CN01"] = int(br.node_id)
    mx_t = mx_d = 0.0
    for b, src in [("MAIN", "CN01"), ("MAIN", kh[kh.bo_khach_hang_id == "MAIN"].khach_hang_id.iloc[123]),
                   ("REP3", kh[kh.bo_khach_hang_id == "REP3"].khach_hang_id.iloc[7])]:
        s = idx[node_of[src]]
        dist, pred = dijkstra(G, indices=s, return_predecessors=True)
        sub = M[(M.bo_khach_hang_id == b) & (M.tu_id == src)]
        for den, km, mins in zip(sub.den_id, sub.khoang_cach_km, sub.thoi_gian_phut):
            j = idx[node_of[den]]
            mx_t = max(mx_t, abs(dist[j] / 60 - mins))
            L, cur = 0.0, j
            while cur != s:
                p = pred[cur]; L += Lmat[(nd.node_id.iat[p], nd.node_id.iat[cur])][0]; cur = p
            mx_d = max(mx_d, abs(L / 1000 - km))
    check("10", "Tính lại Dijkstra (3 nguồn) khớp ma trận; quãng đường lấy trên đúng tuyến nhanh nhất",
          mx_t <= 0.006 and mx_d <= 0.0015, f"lệch thời gian {mx_t:.4f} phút, quãng đường {mx_d:.4f} km")
    rng = np.random.default_rng(1); viol = 0
    for b, g in kh.groupby("bo_khach_hang_id"):
        mm = M[M.bo_khach_hang_id == b].set_index(["tu_id", "den_id"]).thoi_gian_phut
        ids = ["CN01"] + list(g.khach_hang_id)
        for _ in range(400):
            a, c, d = rng.choice(ids, 3, replace=False)
            viol += mm[(a, d)] > mm[(a, c)] + mm[(c, d)] + 0.02
    check("11", "Bất đẳng thức tam giác về thời gian (2.000 bộ ba)", viol == 0, f"{viol} vi phạm")
    asym = (off.merge(off, left_on=["bo_khach_hang_id", "tu_id", "den_id"], right_on=["bo_khach_hang_id", "den_id", "tu_id"])
            .pipe(lambda x: (abs(x.thoi_gian_phut_x - x.thoi_gian_phut_y) > 0.01).mean()))
    check("11b", "Ma trận bất đối xứng ở phần lớn cặp (do đường một chiều)", asym > 0.3, f"{asym:.1%} cặp bất đối xứng")
    dep = M[(M.tu_id == "CN01") & (M.den_id != "CN01")].set_index(["bo_khach_hang_id", "den_id"]).thoi_gian_phut
    back = M[(M.den_id == "CN01") & (M.tu_id != "CN01")].set_index(["bo_khach_hang_id", "tu_id"]).thoi_gian_phut
    svc = kh.set_index(["bo_khach_hang_id", "khach_hang_id"]).thoi_gian_phuc_vu_phut
    rt = dep.values + back.reindex(dep.index).values + svc.reindex(dep.index).values
    check("12", "Mọi khách phục vụ được trong một ngày: t(CN01,i) + phục vụ + t(i,CN01) ≤ 480", (rt <= 480).all(), f"lớn nhất {rt.max():.1f} phút")
    # 13 hồ sơ NVIDIA khớp nguồn
    src = pd.DataFrame(json.load(open(os.path.join(ROOT, "raw", "nemotron_hanoi_urban_v3.json"), encoding="utf-8"))["rows"]).set_index("uuid")
    j = kh.join(src, on="persona_uuid", rsuffix="_src")
    same = (j.gioi_tinh == j.sex) & (j.tuoi == j.age) & (j.trinh_do_hoc_van == j.education_level) & (j.nghe_nghiep == j.occupation) & \
           (j.tinh_trang_hon_nhan == j.marital_status) & (j.persona_row_idx == j.row_idx) & (j.region == "Đồng bằng sông Hồng") & (j.zone == "Đô Thị")
    check("13", "Hồ sơ lấy nguyên từ Nemotron (uuid, row_idx, giới, tuổi, học vấn, nghề, hôn nhân khớp tệp nguồn; vùng ĐBSH, đô thị)",
          same.all() and kh.tuoi.between(20, 65).all(), f"{(~same).sum()} dòng lệch")
    # 14 sản phẩm hợp nghiệp vụ
    rules = {
        "Vay kinh doanh hộ cá thể": lambda r: r.nhom_nghe == "Kinh doanh",
        "Vay tiêu dùng tín chấp": lambda r: r.nhom_nghe in ("Làm công ăn lương", "Lao động tự do") and r.tuoi <= 60,
        "Vay mua xe": lambda r: r.nhom_nghe in ("Làm công ăn lương", "Kinh doanh", "Lao động tự do") and 21 <= r.tuoi <= 60,
        "Vay thế chấp nhà": lambda r: r.nhom_nghe in ("Làm công ăn lương", "Kinh doanh") and 25 <= r.tuoi <= 60,
        "Thẻ tín dụng": lambda r: True}
    badp = sum(not rules[r.loai_san_pham](r) for r in kh.itertuples())
    check("14", "Sản phẩm phù hợp nhóm nghề và tuổi (hộ kinh doanh chỉ cho người kinh doanh, ...)", badp == 0, f"{badp} vi phạm")
    # 15 khoản tiền
    inst = kh[kh.loai_san_pham != "Thẻ tín dụng"]; card = kh[kh.loai_san_pham == "Thẻ tín dụng"]
    acc = kh.cach_tinh_qua_han.str.startswith("Toàn bộ")
    cond = {
        "mục tiêu = quá hạn": (kh.so_tien_muc_tieu_vnd == kh.so_tien_qua_han_vnd).all(),
        "bội số 1.000": (kh[["tong_du_no_vnd", "so_tien_qua_han_vnd", "goc_hoac_han_muc_vnd"]] % 1000 == 0).all().all(),
        "dương": (kh[["tong_du_no_vnd", "so_tien_qua_han_vnd"]] > 0).all().all(),
        "đã trả + kỳ trễ ≤ kỳ hạn": ((inst.so_ky_da_tra + inst.so_ky_qua_han) <= inst.ky_han_thang).all(),
        "dư nợ ≤ gốc": (inst.tong_du_no_vnd <= inst.goc_hoac_han_muc_vnd).all(),
        "thẻ: dư nợ ≤ 110% hạn mức": (card.tong_du_no_vnd <= 1.1 * card.goc_hoac_han_muc_vnd + 1000).all(),
        "thu hồi trước hạn chỉ nhóm 4–5 không bảo đảm": (kh[acc].nhom_no.isin([4, 5]) & (kh[acc].co_tai_san_bao_dam == 0)).all(),
        "nhóm 4–5 không bảo đảm: quá hạn = dư nợ × (1 + 1,5·r·DPD/365)": (abs(kh[acc].so_tien_qua_han_vnd - (kh[acc].tong_du_no_vnd * (1 + 1.5 * kh[acc].lai_suat_nam * kh[acc].so_ngay_qua_han / 365)).round(-3)) <= 1000).all(),
        "còn lại: quá hạn ≤ dư nợ × (1 + r·kỳ trễ/12) × (1 + 1,5·r·DPD/730)": (kh[~acc].so_tien_qua_han_vnd <= kh[~acc].tong_du_no_vnd * (1 + kh[~acc].lai_suat_nam * kh[~acc].so_ky_qua_han / 12) * (1 + 1.5 * kh[~acc].lai_suat_nam * kh[~acc].so_ngay_qua_han / 730) + 1000).all(),
        "kỳ trễ = ⌈DPD/30⌉": (kh.so_ky_qua_han == np.ceil(kh.so_ngay_qua_han / 30)).all(),
    }
    check("15", "Khoản tiền nhất quán (tổng dư nợ, khoản quá hạn, mục tiêu thu hồi tách bạch)", all(cond.values()),
          ",".join(k for k, v in cond.items() if not v))
    gq = T["tham_so_nhom_no"].set_index("nhom_no")
    okg = True
    for b, g in kh.groupby("bo_khach_hang_id"):
        n = len(g); share = gq.ty_trong / gq.ty_trong.sum()
        okg &= ((g.nhom_no.value_counts().reindex(share.index, fill_value=0) - share * n).abs() <= 1).all()
    okd = kh.apply(lambda r: gq.dpd_min[r.nhom_no] <= r.so_ngay_qua_han <= gq.dpd_max[r.nhom_no], axis=1).all()
    check("16", "Cơ cấu nhóm nợ đúng tỷ trọng trong từng bộ; DPD trong khoảng của nhóm", okg and okd)
    svc_ok = kh.apply(lambda r: gq.phut_phuc_vu_min[r.nhom_no] <= r.thoi_gian_phuc_vu_phut <= gq.phut_phuc_vu_max[r.nhom_no], axis=1).all() \
             and kh.thoi_gian_phuc_vu_phut.between(15, 30).all()
    check("16b", "Thời gian phục vụ 15–30 phút, theo khoảng của nhóm nợ", svc_ok)
    # 17 p(i,t)
    P = T["xac_suat_thu_hoi"]; kb = T["kich_ban_xac_suat"].set_index("kich_ban_p")
    a = float(T["tham_so_mo_hinh"].set_index("tham_so").gia_tri["alpha_dpd"])
    k2 = kh.set_index("khach_hang_id")
    Pj = P.join(k2[["nhom_no", "so_ngay_qua_han"]], on="khach_hang_id").join(gq, on="nhom_no").join(kb, on="kich_ban_p")
    f = (Pj.so_ngay_qua_han - Pj.dpd_min) / (Pj.dpd_max - Pj.dpd_min)
    pexp = np.minimum(Pj.chan_tren, Pj.he_so_nhan * Pj.p_co_so * (1 - a * f) * (1 - Pj.ty_le_giam_ngay) ** (Pj.ngay_thu - 1))
    check("17", "p(i,t) đúng công thức giả định (chỉ phụ thuộc nhóm nợ, DPD, ngày, kịch bản; không dùng nhân khẩu học)",
          (abs(pexp.round(4) - Pj.p_thu_hoi) <= 1e-4).all() and len(P) == len(kh) * 15)
    pv = P.pivot_table(index=["khach_hang_id", "ngay_thu"], columns="kich_ban_p", values="p_thu_hoi")
    dec = P.sort_values(["khach_hang_id", "kich_ban_p", "ngay_thu"]).groupby(["khach_hang_id", "kich_ban_p"]).p_thu_hoi.apply(lambda s: (s.diff().dropna() < 0).all())
    check("17b", "p giảm ngặt theo ngày; THAP < CO_SO < CAO", dec.all() and (pv.THAP < pv.CO_SO).all() and (pv.CO_SO < pv.CAO).all())
    # 18 v(i,S)
    L = T["lich_tiep_can"]; pp = {(c, s): g.sort_values("ngay_thu").p_thu_hoi.values for (c, s), g in P.groupby(["khach_hang_id", "kich_ban_p"])}
    wv = k2.so_tien_muc_tieu_vnd; mx = 0
    for r in L.itertuples():
        S = [int(x) for x in r.tap_ngay.split("-")]
        for sc, col in (("THAP", r.v_vnd_thap), ("CO_SO", r.v_vnd_co_so), ("CAO", r.v_vnd_cao)):
            v = wv[r.khach_hang_id] * (1 - np.prod([1 - pp[(r.khach_hang_id, sc)][t - 1] for t in S]))
            mx = max(mx, abs(v - col))
    check("18", "31 lịch/khách; so_lan = |S|; v(i,S) = w·[1 − Π(1 − p)] cho cả 3 kịch bản",
          (L.groupby("khach_hang_id").size() == 31).all() and (L.so_lan == L.tap_ngay.str.count("-") + 1).all() and mx <= 1.0,
          f"lệch lớn nhất {mx:.2f} VND")
    # 19 Monte Carlo
    MC = T["kich_ban_monte_carlo"]
    check("19", "Monte Carlo: 100 kịch bản × 5 ngày × mọi khách; u ∈ [0,1), trung bình ≈ 0,5",
          len(MC) == 100 * 5 * len(kh) and MC.u.between(0, 1, inclusive="left").all() and abs(MC.u.mean() - 0.5) < 0.005,
          f"TB u = {MC.u.mean():.4f}")
    # 20 thể hiện
    ik = T["thuc_the_khach_hang"].groupby("thuc_the_id").khach_hang_id.apply(set); th = T["thuc_the"].set_index("thuc_the_id")
    nest = ik["INS_XS"] <= ik["INS_S"] <= ik["INS_M"] <= ik["INS_L"] and all(ik[f"REP{i}_S"] <= ik[f"REP{i}_M"] for i in range(1, 5))
    sizes = all(len(ik[i]) == th.so_khach_hang[i] for i in th.index)
    sameset = all(set(kh.set_index("khach_hang_id").bo_khach_hang_id[list(ik[i])]) == {th.bo_khach_hang_id[i]} for i in th.index)
    cb = T["thuc_the_can_bo"].groupby("thuc_the_id").size()
    check("20", "Thể hiện lồng nhau, đúng cỡ, khách thuộc đúng bộ; 2–4 cán bộ", nest and sizes and sameset and (cb.reindex(th.index) == th.so_can_bo).all() and cb.between(2, 4).all())
    tk = T["thiet_ke_thi_nghiem"]
    check("21", "Thiết kế thí nghiệm: mỗi thể hiện có đúng 1 cấu hình cơ sở (ưu tiên 1) và các biến thể một yếu tố (ưu tiên 2)",
          (tk[tk.muc_uu_tien == 1].groupby("thuc_the_id").size() == 1).all() and (tk[tk.muc_uu_tien == 2].groupby("thuc_the_id").size() == 8).all())
    ts = T["tham_so_mo_hinh"].set_index("tham_so").gia_tri
    check("22", "Mô hình tiền thu được khai báo rõ: TOAN_BO_HOAC_KHONG", ts.get("mo_hinh_thu_tien") == "TOAN_BO_HOAC_KHONG")
    nguon = T["nguon_du_lieu"]
    check("23", "Bảng nguồn có OSM, NVIDIA, UCI, dân số phường và đánh dấu xác suất là giả định",
          nguon.nguon_id.isin(["OSM", "NVIDIA", "UCI", "DAN_SO_PHUONG"]).sum() == 4 and nguon.loai.str.contains("Giả định").any())
    # 24 Excel
    xl = os.path.join(ROOT, "collection_routing_dataset_v3.xlsx")
    if os.path.exists(xl):
        z = zipfile.ZipFile(xl); wb = z.read("xl/workbook.xml").decode()
        names = re.findall(r'<sheet [^>]*?name="([^"]+)"', wb)
        expect = ["data_dictionary"] + [t for t in TABLES if t != "data_dictionary"]
        okx = [n[:31] for n in expect] == names
        dims = []
        rels = z.read("xl/_rels/workbook.xml.rels").decode()
        for i, n in enumerate(names, 1):
            cnt = z.read(f"xl/worksheets/sheet{i}.xml").count(b"<row")
            dims.append(cnt - 1)
        full = {t[:31]: len(T[t]) for t in TABLES}
        okr = all(dims[i] == full[names[i]] for i in range(len(names)))
        check("24", f"Excel: {len(names)} sheet đúng tên/thứ tự, số dòng khớp CSV", okx and okr)
    else:
        check("24", "Excel tồn tại", False)
    # 25 mã kiểm tra tệp
    sums = os.path.join(ROOT, "SHA256SUMS.txt")
    okh, nbad = os.path.exists(sums), 0
    if okh:
        for line in open(sums, encoding="utf-8"):
            h, f = line.strip().split("  ", 1)
            if f == "validation_report.txt":
                continue
            if hashlib.sha256(open(os.path.join(ROOT, f), "rb").read()).hexdigest() != h:
                nbad += 1
    check("25", "SHA256SUMS khớp mọi tệp (trừ chính báo cáo này)", okh and nbad == 0, f"{nbad} tệp lệch")

    lines = ["BÁO CÁO KIỂM TRA BỘ DỮ LIỆU v3 – Tối ưu lộ trình thu hồi nợ (Hà Nội)",
             f"Thời điểm chạy: {datetime.now():%Y-%m-%d %H:%M:%S}", ""]
    for c, n, ok, d in RES:
        lines.append(f"[{'PASS' if ok else 'FAIL'}] {c} {n}" + (f" – {d}" if d else ""))
    npass = sum(r[2] for r in RES)
    lines += ["", f"TỔNG KẾT: {npass}/{len(RES)} kiểm tra ĐẠT -> {'PASS' if npass == len(RES) else 'FAIL'}"]
    open(os.path.join(ROOT, "validation_report.txt"), "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print("\n".join(lines))
    sys.exit(0 if npass == len(RES) else 1)


if __name__ == "__main__":
    main()
