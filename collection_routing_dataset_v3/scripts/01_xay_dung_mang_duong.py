# -*- coding: utf-8 -*-
"""
Bước 1: dựng mạng đường xe máy nội thành Hà Nội từ dữ liệu OpenStreetMap thật.

Đầu vào : raw/osm_hanoi_extract.json.gz
          (trích từ Geofabrik vietnam-latest.osm.pbf, xem raw/README_raw.md)
Đầu ra  : build/graph_nodes.csv, build/graph_edges.csv   (mạng đã rút gọn, liên thông mạnh)
          build/buildings.csv, build/areas.json (đa giác đã ghép vòng), build/banks.json, build/network_meta.json

Quy tắc (ghi trong tham_so_mo_hinh / data_dictionary):
  * Phương tiện: xe máy. Loại bỏ motorway/motorway_link (cấm xe máy), đường đi bộ, đường mòn, bậc thang,
    đường đang xây; loại bỏ way có motorcycle=no, hoặc motor_vehicle/vehicle=no, access=no/private
    (trừ khi motorcycle=yes/designated/permissive/destination); loại service=parking_aisle/drive-through.
  * Một chiều: oneway=yes/1/true (thuận), -1 (ngược), junction=roundabout/circular (thuận),
    oneway:motorcycle=no -> hai chiều cho xe máy.
  * Tốc độ: theo loại đường (bảng SPEED, giả định cho xe máy giờ hành chính); nếu maxspeed nhỏ hơn thì lấy maxspeed.
  * Giữ thành phần liên thông mạnh lớn nhất -> mọi nút đi được tới và về chi nhánh.
  * Rút gọn: chỉ giữ nút giao, nút cụt và nút đổi thuộc tính; cạnh = chuỗi đoạn liên tiếp (cộng độ dài, thời gian).
"""
import gzip, json, math, os, sys
import numpy as np
import pandas as pd
import networkx as nx

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW, BUILD = os.path.join(ROOT, "raw"), os.path.join(ROOT, "build")
os.makedirs(BUILD, exist_ok=True)

# Vùng nghiên cứu (lõi) và vùng đệm dùng để định tuyến
STUDY = dict(lat0=20.980, lat1=21.050, lon0=105.775, lon1=105.870)

ALLOWED = {"trunk", "trunk_link", "primary", "primary_link", "secondary", "secondary_link", "tertiary",
           "tertiary_link", "unclassified", "residential", "living_street", "service", "road"}
# km/h, xe máy trong giờ hành chính – giả định [GĐ-05]
SPEED = {"trunk": 30, "trunk_link": 25, "primary": 28, "primary_link": 22, "secondary": 25, "secondary_link": 20,
         "tertiary": 22, "tertiary_link": 18, "unclassified": 18, "residential": 15, "road": 15,
         "living_street": 10, "service": 10}
NAME_VI = {"trunk": "Đường trục chính", "trunk_link": "Nhánh nối đường trục", "primary": "Đường chính",
           "primary_link": "Nhánh nối đường chính", "secondary": "Đường cấp 2", "secondary_link": "Nhánh nối cấp 2",
           "tertiary": "Đường cấp 3", "tertiary_link": "Nhánh nối cấp 3", "unclassified": "Đường không phân cấp",
           "residential": "Đường khu dân cư/ngõ", "road": "Đường chưa phân loại", "living_street": "Ngõ nhỏ/đường nội bộ dân cư",
           "service": "Đường phục vụ/ngách"}
YES_MC = {"yes", "designated", "permissive", "destination"}


def hav(la1, lo1, la2, lo2):
    R = 6371008.8
    p1, p2 = math.radians(la1), math.radians(la2)
    dp, dl = p2 - p1, math.radians(lo2 - lo1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))


def motorbike_ok(t):
    hw = t.get("highway")
    if hw not in ALLOWED or t.get("area") == "yes":
        return False, "highway"
    if t.get("service") in ("parking_aisle", "drive-through"):
        return False, "service"
    mc = t.get("motorcycle")
    if mc == "no":
        return False, "motorcycle=no"
    if mc in YES_MC:
        return True, ""
    if t.get("motor_vehicle") == "no" or t.get("vehicle") == "no" or t.get("access") in ("no", "private"):
        return False, "access"
    return True, ""


def direction(t):
    ow = t.get("oneway", "")
    if t.get("oneway:motorcycle") == "no":
        return 0
    if ow in ("yes", "1", "true"):
        return 1
    if ow == "-1":
        return -1
    if t.get("junction") in ("roundabout", "circular") and ow != "no":
        return 1
    return 0


def speed_of(t):
    s = SPEED[t["highway"]]
    ms = t.get("maxspeed", "")
    try:
        v = float(ms.split()[0])
        if 5 <= v < s:
            s = v
    except Exception:
        pass
    return s


def assemble(area):
    """Ghép các way thành vòng khép kín (outer/inner) cho một relation ranh giới."""
    segs = {"outer": [], "inner": []}
    for m in area["members"]:
        if len(m["coords"]) >= 2:
            segs["inner" if m["role"] == "inner" else "outer"].append([tuple(c) for c in m["coords"]])
    rings = {}
    for role, parts in segs.items():
        parts = [p[:] for p in parts]
        out = []
        while parts:
            ring = parts.pop(0)
            changed = True
            while ring[0] != ring[-1] and changed:
                changed = False
                for i, p in enumerate(parts):
                    if p[0] == ring[-1]:
                        ring += p[1:]
                    elif p[-1] == ring[-1]:
                        ring += p[::-1][1:]
                    elif p[-1] == ring[0]:
                        ring = p[:-1] + ring
                    elif p[0] == ring[0]:
                        ring = p[::-1][:-1] + ring
                    else:
                        continue
                    parts.pop(i); changed = True
                    break
            out.append({"closed": ring[0] == ring[-1], "coords": ring})
        rings[role] = out
    return {"id": area["id"], "kind": area["kind"], "tags": area["tags"], "rings": rings}


def main():
    d = json.load(gzip.open(os.path.join(RAW, "osm_hanoi_extract.json.gz"), "rt", encoding="utf-8"))
    nodes = {int(i): (la, lo) for i, la, lo in d["nodes"]}
    stats = {"ways_in": len(d["ways"]), "excluded": {}}

    G = nx.MultiDiGraph()
    for wid, refs, t in d["ways"]:
        ok, why = motorbike_ok(t)
        if not ok:
            stats["excluded"][why] = stats["excluded"].get(why, 0) + 1
            continue
        dr, sp = direction(t), speed_of(t)
        attrs = dict(osm_way_id=int(wid), highway=t["highway"], ten_duong=t.get("name", ""), toc_do_kmh=sp,
                     oneway=int(dr != 0))
        for a, b in zip(refs[:-1], refs[1:]):
            if a not in nodes or b not in nodes or a == b:
                continue
            L = hav(*nodes[a], *nodes[b])
            tt = L / (sp / 3.6)
            if dr >= 0:
                G.add_edge(a, b, length_m=L, travel_time_s=tt, **attrs)
            if dr <= 0:
                G.add_edge(b, a, length_m=L, travel_time_s=tt, **attrs)
    for n in G.nodes:
        G.nodes[n]["lat"], G.nodes[n]["lon"] = nodes[n]
    stats["raw_nodes"], stats["raw_edges"] = G.number_of_nodes(), G.number_of_edges()

    scc = max(nx.strongly_connected_components(G), key=len)
    G = G.subgraph(scc).copy()
    stats["scc_nodes"], stats["scc_edges"] = G.number_of_nodes(), G.number_of_edges()

    # ---- rút gọn kiểu OSMnx: giữ nút giao / nút cụt / nút đổi thuộc tính ----
    def is_endpoint(n):
        preds, succs = set(G.predecessors(n)), set(G.successors(n))
        nb = preds | succs
        if n in nb:
            return True
        if len(nb) != 2:
            return True
        if not ((len(preds) == 2 and len(succs) == 2) or (len(preds) == 1 and len(succs) == 1)):
            return True
        # đổi way/loại đường tại nút -> giữ để không trộn thuộc tính
        keys = {(e[2]["highway"], e[2]["osm_way_id"]) for e in list(G.in_edges(n, data=True)) + list(G.out_edges(n, data=True))}
        return len(keys) > 1

    ends = {n for n in G.nodes if is_endpoint(n)}
    S = {}
    for u in ends:
        for _, v, k, a in G.out_edges(u, keys=True, data=True):
            path_len, path_t, cur, prev = a["length_m"], a["travel_time_s"], v, u
            seen = {u}
            while cur not in ends and cur not in seen:
                seen.add(cur)
                nxt = [(w, dd) for _, w, dd in G.out_edges(cur, data=True) if w != prev]
                if not nxt:
                    break
                w, dd = nxt[0]
                path_len += dd["length_m"]; path_t += dd["travel_time_s"]
                prev, cur = cur, w
            if cur not in ends:
                ends.add(cur)
            key = (u, cur)
            rec = dict(length_m=path_len, travel_time_s=path_t, osm_way_id=a["osm_way_id"], highway=a["highway"],
                       ten_duong=a["ten_duong"], toc_do_kmh=a["toc_do_kmh"], oneway=a["oneway"])
            if u != cur and (key not in S or S[key]["travel_time_s"] > path_t):
                S[key] = rec
    H = nx.DiGraph()
    for (u, v), a in S.items():
        H.add_edge(u, v, **a)
    # an toàn: lấy lại SCC sau rút gọn
    scc2 = max(nx.strongly_connected_components(H), key=len)
    H = H.subgraph(scc2).copy()
    stats["simplified_nodes"], stats["simplified_edges"] = H.number_of_nodes(), H.number_of_edges()

    nd = pd.DataFrame([{"node_id": int(n), "lat": round(G.nodes[n]["lat"], 7), "lon": round(G.nodes[n]["lon"], 7)} for n in H.nodes])
    nd["trong_vung_nghien_cuu"] = ((nd.lat >= STUDY["lat0"]) & (nd.lat <= STUDY["lat1"]) &
                                   (nd.lon >= STUDY["lon0"]) & (nd.lon <= STUDY["lon1"])).astype(int)
    ed = pd.DataFrame([{"u": int(u), "v": int(v), **a} for u, v, a in H.edges(data=True)])
    ed["length_m"] = ed.length_m.round(1)
    ed["travel_time_s"] = ed.travel_time_s.round(2)
    ed = ed.sort_values(["u", "v"]).reset_index(drop=True)
    ed.insert(0, "edge_id", np.arange(1, len(ed) + 1))
    nd.sort_values("node_id").to_csv(os.path.join(BUILD, "graph_nodes.csv"), index=False, encoding="utf-8-sig")
    ed.to_csv(os.path.join(BUILD, "graph_edges.csv"), index=False, encoding="utf-8-sig")

    pd.DataFrame(d["bld"], columns=["lat", "lon", "building", "levels"]).to_csv(os.path.join(BUILD, "buildings.csv"), index=False, encoding="utf-8-sig")
    json.dump([assemble(a) for a in d["areas"]], open(os.path.join(BUILD, "areas.json"), "w", encoding="utf-8"), ensure_ascii=False)
    json.dump(d["banks"], open(os.path.join(BUILD, "banks.json"), "w", encoding="utf-8"), ensure_ascii=False)
    meta = {"source": d["meta"], "study_area": STUDY, "speed_kmh": SPEED, "highway_name_vi": NAME_VI, "stats": stats}
    json.dump(meta, open(os.path.join(BUILD, "network_meta.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(json.dumps(stats, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
