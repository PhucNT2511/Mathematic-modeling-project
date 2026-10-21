# -*- coding: utf-8 -*-
"""
Bước 4: đóng gói – bảng nguồn, từ điển dữ liệu, Excel, bản đồ, SHA256SUMS.
(README.md viết tay; bước 5 kiểm tra toàn bộ.)
"""
import hashlib, json, os
import pandas as pd

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV = os.path.join(ROOT, "csv")
meta = json.load(open(os.path.join(ROOT, "build", "meta_v3.json"), encoding="utf-8"))
pm = meta["persona_meta"]; net = meta["network"]

NGUON = [
    ("OSM", "Dữ liệu thật (công khai)", "OpenStreetMap qua Geofabrik: vietnam-latest.osm.pbf",
     "https://download.geofabrik.de/asia/vietnam-latest.osm.pbf",
     f"Dữ liệu OSM đến 2026-10-18T20:25:06Z; HTTP Last-Modified {net['source'].get('last_modified_http','')}; trích xuất {net['source'].get('extracted_at','')[:10]}",
     "ODbL 1.0 – ghi nguồn \"© OpenStreetMap contributors\"",
     "Mạng đường xe máy (nut_duong, canh_duong), ma trận Dijkstra, vị trí chi nhánh (POI VPBank Láng Hạ), ranh giới 6 quận cũ (boundary=historic), ranh giới và dân số phường 2025, mật độ công trình",
     f"Khung đệm lat {net['source']['extended_bbox']['la0']}–{net['source']['extended_bbox']['la1']}, lon {net['source']['extended_bbox']['lo0']}–{net['source']['extended_bbox']['lo1']}; vùng lấy mẫu lat 20.980–21.050, lon 105.775–105.870"),
    ("DAN_SO_PHUONG", "Dữ liệu thật (công khai)", "Thẻ population trên relation phường 2025 trong OSM (source:population = gis.vn, population:date = 2025-07-01)",
     "https://www.openstreetmap.org/relation/19331657 (ví dụ Phường Bạch Mai)", "Giá trị ngày 01/07/2025", "ODbL 1.0",
     "Hạn ngạch số khách hàng theo phường (phuong_lay_mau)", "27 phường giao với vùng lấy mẫu"),
    ("NVIDIA", "Dữ liệu thật (công khai, tổng hợp)", "NVIDIA Nemotron-Personas-Vietnam",
     "https://huggingface.co/datasets/nvidia/Nemotron-Personas-Vietnam",
     f"Commit {pm['hf_sha_at_access']} (lastModified {pm['hf_last_modified']}); đọc qua datasets-server ngày {pm['accessed_at'][:10]}",
     "CC BY 4.0", "Giới tính, tuổi, hôn nhân, học vấn, nghề nghiệp của khách hàng (lấy nguyên từng hồ sơ)",
     f"Quét {pm['rows_scanned']:,} / 1.000.000 dòng (257 trang ngẫu nhiên); ĐBSH {pm['region_DBSH']:,}; ĐBSH đô thị {pm['region_DBSH_urban']:,}; có 'Hà Nội' trong mô tả {pm['kept']}; tuổi 20–65 còn {meta['persona_pool_20_65']}".replace(",", ".")),
    ("UCI", "Dữ liệu thật (công khai, nước ngoài)", "UCI Default of Credit Card Clients (Yeh, 2009)",
     "https://archive.ics.uci.edu/dataset/350/default+of+credit+card+clients", "DOI 10.24432/C55S3H", "CC BY 4.0",
     "Chỉ dùng HÌNH DẠNG phân bố hạn mức thẻ (chia cho trung vị) và tỷ lệ sử dụng hạn mức (BILL_AMT1/LIMIT_BAL) của khách trễ ≥ 2 tháng; KHÔNG coi số tiền sao kê là khoản quá hạn và KHÔNG dùng xác suất vỡ nợ làm xác suất thu hồi",
     f"{meta['uci']['n_tre_han']} khách trễ ≥ 2 tháng (PAY_0 ≥ 2)"),
    ("CO_CAU_NHOM_NO", "Số liệu công bố", "Cơ cấu nhóm nợ: VPBank hợp nhất Q1/2025 (DSC), Tuổi Trẻ 23/4/2025, DNSE (27 NH niêm yết 2024)",
     "https://extgw.dsc.com.vn/eback/uploads/BC_VPB_2025_Q1_5d161668e8.pdf ; https://tuoitre.vn/no-xau-nhieu-ngan-hang-tiep-tuc-tang-nhanh-20250423190639834.htm ; https://www.dnse.com.vn/senses/tin-tuc/nhan-dien-buc-tranh-no-xau-co-kha-nang-mat-von-cua-cac-ngan-hang-34109426",
     "Q1/2025 và 31/12/2024", "Trích dẫn số liệu",
     "Tỷ trọng nhóm 2–5 (tham_so_nhom_no.ty_trong). Đây là cơ cấu toàn danh mục, giả định áp dụng cho danh sách thu hồi thực địa", ""),
    ("PHAP_LY", "Văn bản pháp luật", "TT 11/2021/TT-NHNN (phân loại nợ theo DPD); TT 39/2016/TT-NHNN (lãi quá hạn 150%)",
     "https://luatvietnam.vn/tai-chinh/thong-tu-11-2021-tt-nhnn-ngan-hang-nha-nuoc-viet-nam-206806-d1.html", "Cần kiểm tra văn bản đang có hiệu lực", "",
     "Khoảng DPD của nhóm nợ; cách tính lãi quá hạn", ""),
    ("GIA_DINH", "Giả định của tác giả", "Không có nguồn ngoài", "", "", "",
     "Xác suất thu hồi p(i,t) và 3 kịch bản; phân bố gốc vay các sản phẩm không phải thẻ; trung vị hạn mức thẻ; lãi suất, kỳ hạn; quy tắc thu hồi trước hạn; tốc độ theo loại đường; thời gian phục vụ; ngưỡng DPD 31 ngày cho thu hồi thực địa; kỳ 02–06/11/2026",
     "Chưa có dữ liệu kết quả tiếp cận hay tỷ lệ thu hồi của ngân hàng Việt Nam; không được viết là đã hiệu chỉnh từ ngân hàng"),
]
nguon = pd.DataFrame(NGUON, columns=["nguon_id", "loai", "ten_nguon", "url", "phien_ban_thoi_diem", "giay_phep", "dung_cho", "ghi_chu"])
nguon.to_csv(os.path.join(CSV, "nguon_du_lieu.csv"), index=False, encoding="utf-8-sig", lineterminator="\n")

# ------------------------------------------------------------------ từ điển dữ liệu
D = {
 "tham_so_mo_hinh": {"tham_so": ("text", "PK", "Tên tham số"), "gia_tri": ("text", "", "Giá trị"), "don_vi": ("text", "", "Đơn vị"),
                     "mo_ta": ("text", "", "Ý nghĩa"), "nguon": ("text", "", "Tài liệu / Giả định / OSM / UCI / văn bản")},
 "ngay_ky": {"ngay_thu": ("int", "PK", "Chỉ số ngày t ∈ T = {1..5}"), "ngay": ("date", "", "Ngày dương lịch"), "thu": ("text", "", "Thứ trong tuần")},
 "tham_so_nhom_no": {"nhom_no": ("int", "PK", "Nhóm nợ 2–5"), "ten_nhom": ("text", "", "Tên nhóm theo TT 11/2021"),
                     "dpd_min": ("int", "", "DPD nhỏ nhất của nhóm trong danh sách thu hồi thực địa"), "dpd_max": ("int", "", "DPD lớn nhất"),
                     "ty_trong": ("float", "", "Tỷ trọng nhóm trong danh sách (tham chiếu công bố, xem nguon_du_lieu CO_CAU_NHOM_NO)"),
                     "p_co_so": ("float", "", "p ngày 1 tại DPD nhỏ nhất, kịch bản CO_SO (giả định)"),
                     "ty_le_giam_ngay": ("float", "", "Tỷ lệ giảm p mỗi ngày (giả định)"),
                     "phut_phuc_vu_min": ("int", "", "Thời gian phục vụ tối thiểu (phút)"), "phut_phuc_vu_max": ("int", "", "Thời gian phục vụ tối đa (phút)"),
                     "so_khach_hang_main": ("int", "", "Số khách của nhóm trong bộ MAIN"), "alpha_dpd": ("float", "", "Hệ số giảm p theo vị trí DPD trong nhóm"),
                     "nguon_ty_trong": ("text", "", "Nguồn của ty_trong"), "nguon_p": ("text", "", "Nguồn của p (giả định)")},
 "tham_so_san_pham": {"loai_san_pham": ("text", "PK", "Sản phẩm"), "trong_so": ("float", "", "Trọng số chọn sản phẩm trong các sản phẩm đủ điều kiện (giả định)"),
                      "lai_suat_nam": ("float", "", "Lãi suất trong hạn/năm (giả định)"), "ky_han_thang": ("text", "", "Các kỳ hạn được chọn (tháng), rỗng với thẻ"),
                      "co_tai_san_bao_dam": ("int 0/1", "", "1 nếu có tài sản bảo đảm"), "trung_vi_goc_vnd": ("int", "", "Trung vị số tiền giải ngân, hoặc hạn mức với thẻ"),
                      "sigma_log": ("float", "", "Độ lệch chuẩn log của phân phối log-chuẩn (rỗng với thẻ: dùng phân bố UCI)"),
                      "tran_vnd": ("int", "", "Trần số tiền"), "nguon_phan_bo": ("text", "", "Nguồn phân bố số tiền")},
 "kich_ban_xac_suat": {"kich_ban_p": ("text", "PK", "THAP / CO_SO / CAO"), "he_so_nhan": ("float", "", "Nhân với p cơ sở"),
                       "chan_tren": ("float", "", "Chặn trên của p"), "mo_ta": ("text", "", "Mô tả"), "nguon": ("text", "", "Giả định")},
 "toc_do_loai_duong": {"highway": ("text", "PK", "Giá trị thẻ highway của OSM"), "ten_loai_duong": ("text", "", "Tên tiếng Việt"),
                       "toc_do_kmh": ("int", "", "Tốc độ xe máy mặc định (giả định); dùng maxspeed nếu nhỏ hơn"), "so_canh": ("int", "", "Số cung của loại này")},
 "nut_duong": {"node_id": ("int64", "PK", "ID nút OSM (đã rút gọn: nút giao, nút cụt, nút đổi thuộc tính)"), "lat": ("float", "", "Vĩ độ WGS84"),
               "lon": ("float", "", "Kinh độ WGS84"), "quan_cu": ("text", "", "Quận trước 01/07/2025 (ranh giới OSM boundary=historic), rỗng nếu ngoài 6 quận"),
               "phuong_2025": ("text", "", "Phường từ 01/07/2025 (ranh giới OSM admin_level=6)"), "trong_vung_nghien_cuu": ("int 0/1", "", "1 nếu trong khung lấy mẫu; 0 là vùng đệm định tuyến")},
 "canh_duong": {"edge_id": ("int", "PK", "Mã cung"), "u": ("int64", "FK nut_duong", "Nút đầu"), "v": ("int64", "FK nut_duong", "Nút cuối"),
                "osm_way_id": ("int64", "", "Way OSM của đoạn đầu chuỗi"), "highway": ("text", "FK toc_do_loai_duong", "Loại đường"),
                "ten_duong": ("text", "", "Tên đường trong OSM (có thể rỗng)"), "oneway": ("int 0/1", "", "1 nếu đường một chiều với xe máy"),
                "length_m": ("float", "", "Độ dài (m)"), "toc_do_kmh": ("float", "", "Tốc độ áp dụng"), "travel_time_s": ("float", "", "Thời gian đi (giây)")},
 "phuong_lay_mau": {"phuong_2025": ("text", "PK", "Phường 2025"), "osm_relation_id": ("int64", "", "Relation OSM"), "dan_so_2025": ("int", "", "Dân số phường (thẻ OSM population)"),
                    "nguon_dan_so": ("text", "", "source:population"), "ngay_dan_so": ("date", "", "population:date"),
                    "dien_tich_km2": ("float", "", "Diện tích phường (lưới 50 m)"), "dien_tich_trong_vung_km2": ("float", "", "Phần diện tích nằm trong 6 quận cũ ∩ khung lấy mẫu"),
                    "dan_so_uoc_trong_vung": ("float", "", "Dân số × tỷ lệ diện tích trong vùng"), "ty_trong_mau": ("float", "", "Tỷ trọng hạn ngạch khách hàng")},
 "chi_nhanh": {"chi_nhanh_id": ("text", "PK", "CN01"), "ten_chi_nhanh": ("text", "", "Tên (giả định)"), "osm_poi_id": ("int64", "", "Node POI ngân hàng trong OSM"),
               "ten_poi_osm": ("text", "", "Tên POI trong OSM"), "dia_chi_osm": ("text", "", "addr:housenumber + addr:street của POI trong OSM"),
               "quan_cu": ("text", "", "Quận cũ"), "phuong_2025": ("text", "", "Phường 2025"), "node_id": ("int64", "FK nut_duong", "Nút mạng gần POI nhất"),
               "lat": ("float", "", "Vĩ độ nút"), "lon": ("float", "", "Kinh độ nút"), "khoang_cach_poi_den_nut_m": ("float", "", "Khoảng cách POI → nút (m)"),
               "gio_mo_cua": ("time", "", "Giờ mở cửa"), "gio_dong_cua": ("time", "", "Giờ đóng cửa")},
 "can_bo": {"can_bo_id": ("text", "PK", "Mã cán bộ (không dùng tên người)"), "chi_nhanh_id": ("text", "FK chi_nhanh", "Chi nhánh"),
            "phuong_tien": ("text", "", "Xe máy"), "gio_bat_dau": ("time", "", "Giờ bắt đầu"), "gio_ket_thuc": ("time", "", "Giờ kết thúc"),
            "phut_nghi_trua": ("int", "", "Nghỉ trưa"), "phut_lam_viec_ngay": ("int", "", "480 phút"), "so_ngay_san_sang": ("int", "", "Số ngày làm việc trong kỳ")},
 "bo_khach_hang": {"bo_khach_hang_id": ("text", "PK", "MAIN, REP1..REP4"), "so_khach_hang": ("int", "", "Số khách"), "seed": ("int", "", "Seed sinh vị trí, hồ sơ, khoản nợ"),
                   "seed_monte_carlo": ("int", "", "Seed của luồng số ngẫu nhiên Monte Carlo (tách khỏi bộ sinh dữ liệu và bộ giải)"), "mo_ta": ("text", "", "Mục đích")},
 "khach_hang": {"khach_hang_id": ("text", "PK", "<bộ>_KHxxxx"), "bo_khach_hang_id": ("text", "FK bo_khach_hang", "Bộ khách hàng"),
                "persona_uuid": ("text", "", "uuid hồ sơ Nemotron"), "persona_row_idx": ("int", "", "Chỉ số dòng trong split train"),
                "gioi_tinh": ("text", "", "Từ Nemotron"), "tuoi": ("int", "", "Từ Nemotron (lọc 20–65)"), "tinh_trang_hon_nhan": ("text", "", "Từ Nemotron"),
                "trinh_do_hoc_van": ("text", "", "Từ Nemotron"), "nghe_nghiep": ("text", "", "Từ Nemotron"),
                "nhom_nghe": ("text", "", "Gộp nghề để xét điều kiện sản phẩm (không dùng cho p)"),
                "quan_cu": ("text", "", "Quận cũ của nút"), "phuong_2025": ("text", "FK phuong_lay_mau", "Phường 2025 của nút"),
                "node_id": ("int64", "FK nut_duong", "Nút mạng đặt khách hàng (vị trí xấp xỉ, không phải địa chỉ đã xác minh)"),
                "lat": ("float", "", "Vĩ độ nút"), "lon": ("float", "", "Kinh độ nút"), "so_cong_trinh_100m": ("int", "", "Số công trình OSM trong 100 m (trọng số chọn nút)"),
                "chi_nhanh_id": ("text", "FK chi_nhanh", "Chi nhánh quản lý"), "loai_san_pham": ("text", "FK tham_so_san_pham", "Sản phẩm"),
                "co_tai_san_bao_dam": ("int 0/1", "", "Có tài sản bảo đảm"), "lai_suat_nam": ("float", "", "Lãi suất/năm"),
                "ky_han_thang": ("int", "", "Kỳ hạn (rỗng với thẻ)"), "so_ky_da_tra": ("int", "", "Số kỳ đã trả trước khi quá hạn (rỗng với thẻ)"),
                "goc_hoac_han_muc_vnd": ("int", "", "Số tiền giải ngân, hoặc hạn mức thẻ"), "tra_gop_hoac_toi_thieu_vnd": ("int", "", "Kỳ trả góp, hoặc thanh toán tối thiểu thẻ"),
                "tong_du_no_vnd": ("int", "", "TỔNG DƯ NỢ gốc còn lại (thẻ: dư nợ sao kê)"), "nhom_no": ("int", "FK tham_so_nhom_no", "Nhóm nợ"),
                "so_ngay_qua_han": ("int", "", "DPD đầu kỳ"), "so_ky_qua_han": ("int", "", "⌈DPD/30⌉"), "cach_tinh_qua_han": ("text", "", "Quy tắc tính khoản quá hạn"),
                "so_tien_qua_han_vnd": ("int", "", "KHOẢN QUÁ HẠN: các kỳ quá hạn + lãi quá hạn; nhóm 4–5 không bảo đảm: toàn bộ dư nợ + lãi quá hạn"),
                "so_tien_muc_tieu_vnd": ("int", "", "w(i) – MỤC TIÊU THU HỒI của một lần tiếp cận thành công (= khoản quá hạn); thất bại thu 0"),
                "thoi_gian_phuc_vu_phut": ("int", "", "Thời gian làm việc tại khách mỗi lần (15–30 phút)")},
 "xac_suat_thu_hoi": {"khach_hang_id": ("text", "FK khach_hang", "Khách"), "kich_ban_p": ("text", "FK kich_ban_xac_suat", "Kịch bản"),
                      "ngay_thu": ("int", "FK ngay_ky", "t"), "ngay": ("date", "", "Ngày"), "p_thu_hoi": ("float", "", "p(i,t) – GIẢ ĐỊNH")},
 "lich_tiep_can": {"lich_id": ("text", "PK", "<khách>_Sxx"), "khach_hang_id": ("text", "FK khach_hang", "Khách"), "tap_ngay": ("text", "", "S, các ngày nối bằng '-'"),
                   "so_lan": ("int", "", "|S|; mô hình lọc so_lan ≤ m"), "v_vnd_thap": ("int", "", "v(i,S) kịch bản THAP"),
                   "v_vnd_co_so": ("int", "", "v(i,S) kịch bản CO_SO"), "v_vnd_cao": ("int", "", "v(i,S) kịch bản CAO")},
 "ma_tran_di_chuyen": {"bo_khach_hang_id": ("text", "PK, FK bo_khach_hang", "Bộ"), "tu_id": ("text", "PK", "CN01 hoặc khách"), "den_id": ("text", "PK", "CN01 hoặc khách"),
                       "khoang_cach_km": ("float", "", "Quãng đường trên tuyến nhanh nhất"), "thoi_gian_phut": ("float", "", "Thời gian tuyến nhanh nhất (Dijkstra)")},
 "thuc_the": {"thuc_the_id": ("text", "PK", "Mã thể hiện"), "bo_khach_hang_id": ("text", "FK bo_khach_hang", "Bộ khách hàng nguồn"), "so_khach_hang": ("int", "", "Số khách"),
              "so_can_bo": ("int", "", "Số cán bộ mặc định"), "so_ngay": ("int", "", "5"), "phut_lam_viec_ngay": ("int", "", "Mặc định 480"),
              "m_mac_dinh": ("int", "", "m mặc định"), "mo_ta": ("text", "", "Mục đích")},
 "thuc_the_khach_hang": {"thuc_the_id": ("text", "PK, FK thuc_the", "Thể hiện"), "khach_hang_id": ("text", "PK, FK khach_hang", "Khách")},
 "thuc_the_can_bo": {"thuc_the_id": ("text", "PK, FK thuc_the", "Thể hiện"), "can_bo_id": ("text", "PK, FK can_bo", "Cán bộ")},
 "thiet_ke_thi_nghiem": {"thi_nghiem_id": ("text", "PK", "Mã cấu hình"), "thuc_the_id": ("text", "FK thuc_the", "Thể hiện"), "so_can_bo": ("int", "", "2/3/4"),
                         "phut_lam_viec_ngay": ("int", "", "360/420/480"), "m": ("int", "", "1/2/3"), "kich_ban_p": ("text", "FK kich_ban_xac_suat", "THAP/CO_SO/CAO"),
                         "so_kich_ban_mc": ("int", "", "Số kịch bản Monte Carlo dùng"),
                         "muc_uu_tien": ("int", "", "1 = cấu hình cơ sở; 2 = đổi đúng một yếu tố so với cơ sở; 3 = tổ hợp đầy đủ")},
 "kich_ban_monte_carlo": {"kich_ban_id": ("int", "PK", "s = 1..100"), "khach_hang_id": ("text", "PK, FK khach_hang", "Khách"), "ngay_thu": ("int", "PK, FK ngay_ky", "t"),
                          "u": ("float", "", "Số ngẫu nhiên chung; lần tiếp cận (i,t) thành công nếu u < p(i,t) của kịch bản p đang xét")},
 "nguon_du_lieu": {"nguon_id": ("text", "PK", "Mã nguồn"), "loai": ("text", "", "Dữ liệu thật / số liệu công bố / giả định"), "ten_nguon": ("text", "", "Tên"),
                   "url": ("text", "", "Đường dẫn"), "phien_ban_thoi_diem": ("text", "", "Phiên bản, ngày trích xuất"), "giay_phep": ("text", "", "Giấy phép"),
                   "dung_cho": ("text", "", "Dùng cho bảng/cột nào"), "ghi_chu": ("text", "", "Phạm vi, số lượng, giới hạn")},
}
ORDER = ["tham_so_mo_hinh", "ngay_ky", "tham_so_nhom_no", "tham_so_san_pham", "kich_ban_xac_suat", "toc_do_loai_duong",
         "nut_duong", "canh_duong", "phuong_lay_mau", "chi_nhanh", "can_bo", "bo_khach_hang", "khach_hang",
         "xac_suat_thu_hoi", "lich_tiep_can", "ma_tran_di_chuyen", "thuc_the", "thuc_the_khach_hang", "thuc_the_can_bo",
         "thiet_ke_thi_nghiem", "kich_ban_monte_carlo", "nguon_du_lieu"]
rows = []
for t in ORDER:
    cols = list(pd.read_csv(os.path.join(CSV, t + ".csv"), nrows=0).columns)
    for c in cols:
        k, key, desc = D[t][c]
        rows.append(dict(bang=t, cot=c, kieu=k, khoa=key, mo_ta=desc))
dd = pd.DataFrame(rows)
dd.to_csv(os.path.join(CSV, "data_dictionary.csv"), index=False, encoding="utf-8-sig", lineterminator="\n")

# ------------------------------------------------------------------ Excel (write-only, nhanh)
from openpyxl import Workbook
wb = Workbook(write_only=True)
for t in ["data_dictionary"] + ORDER:
    df = pd.read_csv(os.path.join(CSV, t + ".csv"), low_memory=False)
    ws = wb.create_sheet(t[:31])
    ws.append(list(df.columns))
    for row in df.itertuples(index=False):
        ws.append([None if (isinstance(v, float) and v != v) else v for v in row])
wb.save(os.path.join(ROOT, "collection_routing_dataset_v3.xlsx"))
print("xlsx ok")
