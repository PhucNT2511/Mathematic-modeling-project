// ============================================================================================
// Bước 0 (đã chạy ngày 20/10/2026): mã JavaScript đã dùng trong trình duyệt để lấy dữ liệu nguồn.
// Lý do chạy trong trình duyệt: môi trường xử lý không truy cập được OSM/HuggingFace trực tiếp.
//
// A. OSM: mở https://download.geofabrik.de/asia/vietnam.html, chạy phần A trong console.
//    Tải vietnam-latest.osm.pbf (331 MB, dữ liệu OSM đến 2026-10-18T20:25:06Z), đọc PBF bằng trình đọc
//    tự viết (DenseNodes / Ways / Relations, giải nén zlib bằng DecompressionStream), giữ:
//      - nút trong khung đệm lat 20.965–21.065, lon 105.760–105.885
//      - way có thẻ highway chạm khung (kèm các thẻ quyền đi, một chiều, tốc độ, tên)
//      - tâm công trình (way có thẻ building) trong khung
//      - POI amenity=bank trong khung
//      - relation phường 2025 (boundary=administrative, admin_level=6) và 6 quận cũ (boundary=historic,
//        was:admin_level=6) chạm khung, kèm toạ độ đầy đủ của các way thành viên
//    Kết quả: osm_hanoi_extract.json.gz (raw/).
//
// B. Nemotron: mở https://datasets-server.huggingface.co/info?dataset=nvidia/Nemotron-Personas-Vietnam,
//    chạy phần B. Đọc 257 trang × 100 dòng ở vị trí ngẫu nhiên không lặp (seed 20261020), giữ hồ sơ
//    region = 'Đồng bằng sông Hồng', zone = 'Đô Thị' và có chuỗi 'Hà Nội' trong persona /
//    cultural_background / professional_persona. Kết quả: nemotron_hanoi_urban_v3.json (raw/).
// ============================================================================================

// ------------------------------------------------------------------ A. OSM
async function fetchPbf() {
  const r = await fetch("/asia/vietnam-latest.osm.pbf");
  const reader = r.body.getReader(); const chunks = []; let n = 0;
  for (;;) { const { done, value } = await reader.read(); if (done) break; chunks.push(value); n += value.length; }
  const buf = new Uint8Array(n); let o = 0; for (const c of chunks) { buf.set(c, o); o += c.length; }
  return { buf, lastModified: r.headers.get("last-modified") };
}

const PB = (function () {
  function R(buf, pos, end) { this.b = buf; this.p = pos || 0; this.e = (end === undefined) ? buf.length : end; }
  R.prototype.varint = function () { let r = 0, m = 1, b; do { b = this.b[this.p++]; r += (b & 0x7f) * m; m *= 128; } while (b & 0x80); return r; };
  R.prototype.svarint = function () { const n = this.varint(); return (n % 2 === 0) ? n / 2 : -(n + 1) / 2; };
  R.prototype.bytes = function () { const l = this.varint(); const s = this.p; this.p += l; return [s, this.p]; };
  R.prototype.skip = function (wt) { if (wt === 0) this.varint(); else if (wt === 2) { const l = this.varint(); this.p += l; } else if (wt === 1) this.p += 8; else if (wt === 5) this.p += 4; else throw new Error("wt " + wt); };
  R.prototype.done = function () { return this.p >= this.e; };
  const packedS = (b, s, e) => { const r = new R(b, s, e), o = []; while (!r.done()) o.push(r.svarint()); return o; };
  const packedU = (b, s, e) => { const r = new R(b, s, e), o = []; while (!r.done()) o.push(r.varint()); return o; };
  const td = new TextDecoder();
  async function inflate(u8) { const ds = new DecompressionStream("deflate"); const w = ds.writable.getWriter(); w.write(u8); w.close(); return new Uint8Array(await new Response(ds.readable).arrayBuffer()); }
  function blobs(buf) {
    const out = []; let p = 0; const dv = new DataView(buf.buffer, buf.byteOffset);
    while (p < buf.length) {
      const hl = dv.getUint32(p); p += 4; const r = new R(buf, p, p + hl); let type = "", size = 0;
      while (!r.done()) { const k = r.varint(), f = k >> 3, wt = k & 7; if (f === 1) { const [s, e] = r.bytes(); type = td.decode(buf.subarray(s, e)); } else if (f === 3) size = r.varint(); else r.skip(wt); }
      p += hl; out.push([type, p, p + size]); p += size;
    }
    return out;
  }
  async function blockData(buf, s, e) {
    const r = new R(buf, s, e); let raw = null, z = null;
    while (!r.done()) { const k = r.varint(), f = k >> 3, wt = k & 7; if (f === 1) { const [a, b] = r.bytes(); raw = buf.subarray(a, b); } else if (f === 3) { const [a, b] = r.bytes(); z = buf.subarray(a, b); } else r.skip(wt); }
    return raw || await inflate(z);
  }
  function prim(b, cb) {
    const r = new R(b); const st = []; let gran = 100, lato = 0, lono = 0; const groups = [];
    while (!r.done()) {
      const k = r.varint(), f = k >> 3, wt = k & 7;
      if (f === 1) { const [s, e] = r.bytes(); const rr = new R(b, s, e); while (!rr.done()) { const kk = rr.varint(); if ((kk >> 3) === 1) { const [a, c] = rr.bytes(); st.push(td.decode(b.subarray(a, c))); } else rr.skip(kk & 7); } }
      else if (f === 2) groups.push(r.bytes()); else if (f === 17) gran = r.varint(); else if (f === 19) lato = r.varint(); else if (f === 20) lono = r.varint(); else r.skip(wt);
    }
    for (const [gs, ge] of groups) {
      const g = new R(b, gs, ge);
      while (!g.done()) {
        const k = g.varint(), f = k >> 3, wt = k & 7;
        if (f === 2) { // DenseNodes
          const [s, e] = g.bytes(); if (!cb.want.nodes) continue; const d = new R(b, s, e); let ids = null, lats = null, lons = null, kv = null;
          while (!d.done()) { const kk = d.varint(), ff = kk >> 3, ww = kk & 7; if (ff === 1) { const [a, c] = d.bytes(); ids = packedS(b, a, c); } else if (ff === 8) { const [a, c] = d.bytes(); lats = packedS(b, a, c); } else if (ff === 9) { const [a, c] = d.bytes(); lons = packedS(b, a, c); } else if (ff === 10) { const [a, c] = d.bytes(); kv = packedU(b, a, c); } else d.skip(ww); }
          let id = 0, la = 0, lo = 0, ki = 0;
          for (let i = 0; i < ids.length; i++) { id += ids[i]; la += lats[i]; lo += lons[i]; let tags = null; if (kv) { while (kv[ki] !== 0) { if (!tags) tags = {}; tags[st[kv[ki]]] = st[kv[ki + 1]]; ki += 2; } ki++; } cb.node(id, 1e-9 * (lato + gran * la), 1e-9 * (lono + gran * lo), tags); }
        } else if (f === 3) { // Way
          const [s, e] = g.bytes(); if (!cb.want.ways) continue; const w = new R(b, s, e); let id = 0, keys = [], vals = [], refs = [];
          while (!w.done()) { const kk = w.varint(), ff = kk >> 3, ww = kk & 7; if (ff === 1) id = w.varint(); else if (ff === 2) { const [a, c] = w.bytes(); keys = packedU(b, a, c); } else if (ff === 3) { const [a, c] = w.bytes(); vals = packedU(b, a, c); } else if (ff === 8) { const [a, c] = w.bytes(); refs = packedS(b, a, c); } else w.skip(ww); }
          for (let i = 1; i < refs.length; i++) refs[i] += refs[i - 1]; const tags = {}; for (let i = 0; i < keys.length; i++) tags[st[keys[i]]] = st[vals[i]]; cb.way(id, refs, tags);
        } else if (f === 4) { // Relation
          const [s, e] = g.bytes(); if (!cb.want.rels) continue; const w = new R(b, s, e); let id = 0, keys = [], vals = [], roles = [], mem = [], types = [];
          while (!w.done()) { const kk = w.varint(), ff = kk >> 3, ww = kk & 7; if (ff === 1) id = w.varint(); else if (ff === 2) { const [a, c] = w.bytes(); keys = packedU(b, a, c); } else if (ff === 3) { const [a, c] = w.bytes(); vals = packedU(b, a, c); } else if (ff === 8) { const [a, c] = w.bytes(); roles = packedU(b, a, c); } else if (ff === 9) { const [a, c] = w.bytes(); mem = packedS(b, a, c); } else if (ff === 10) { const [a, c] = w.bytes(); types = packedU(b, a, c); } else w.skip(ww); }
          for (let i = 1; i < mem.length; i++) mem[i] += mem[i - 1]; const tags = {}; for (let i = 0; i < keys.length; i++) tags[st[keys[i]]] = st[vals[i]]; cb.rel(id, tags, mem, types, roles.map(x => st[x]));
        } else if (f === 1) { // Node (không nén)
          const [s, e] = g.bytes(); if (!cb.want.nodes) continue; const w = new R(b, s, e); let id = 0, keys = [], vals = [], la = 0, lo = 0;
          while (!w.done()) { const kk = w.varint(), ff = kk >> 3, ww = kk & 7; if (ff === 1) id = w.svarint(); else if (ff === 2) { const [a, c] = w.bytes(); keys = packedU(b, a, c); } else if (ff === 3) { const [a, c] = w.bytes(); vals = packedU(b, a, c); } else if (ff === 8) la = w.svarint(); else if (ff === 9) lo = w.svarint(); else w.skip(ww); }
          let tags = null; if (keys.length) { tags = {}; for (let i = 0; i < keys.length; i++) tags[st[keys[i]]] = st[vals[i]]; } cb.node(id, 1e-9 * (lato + gran * la), 1e-9 * (lono + gran * lo), tags);
        } else g.skip(wt);
      }
    }
  }
  async function run(buf, cb) { for (const [t, s, e] of blobs(buf)) { if (t !== "OSMData") continue; prim(await blockData(buf, s, e), cb); } }
  return { run };
})();

async function extractOSM() {
  const { buf, lastModified } = await fetchPbf();
  const E = { la0: 20.965, la1: 21.065, lo0: 105.760, lo1: 105.885 };
  const N = new Map(), ways = [], bld = [], banks = [];
  const KEEP = ["highway", "name", "oneway", "junction", "access", "motorcycle", "motor_vehicle", "vehicle", "oneway:motorcycle", "maxspeed", "service", "area", "bridge", "tunnel", "layer", "ref"];
  // lượt 1: nút trong khung, way highway/building, POI ngân hàng
  await PB.run(buf, { want: { nodes: true, ways: true, rels: false },
    node(id, la, lo, t) { if (la >= E.la0 && la <= E.la1 && lo >= E.lo0 && lo <= E.lo1) { N.set(id, [la, lo]); if (t && t.amenity === "bank") banks.push({ type: "node", id, lat: la, lon: lo, name: t.name || "", brand: t.brand || "", street: t["addr:street"] || "", hn: t["addr:housenumber"] || "" }); } },
    way(id, refs, t) { let inb = 0; for (const r of refs) if (N.has(r)) inb++; if (!inb) return;
      if (t.highway) { const tt = {}; for (const k of KEEP) if (t[k] !== undefined) tt[k] = t[k]; ways.push([id, refs, tt]); }
      else if (t.building && inb * 2 >= refs.length) { let a = 0, o = 0, c = 0; for (const r of refs) { const p = N.get(r); if (p) { a += p[0]; o += p[1]; c++; } } bld.push([+(a / c).toFixed(6), +(o / c).toFixed(6), t.building, t["building:levels"] || ""]); }
      if (t.amenity === "bank") { const p = N.get(refs[0]); if (p) banks.push({ type: "way", id, lat: p[0], lon: p[1], name: t.name || "", brand: t.brand || "", street: t["addr:street"] || "", hn: t["addr:housenumber"] || "" }); } },
    rel() {} });
  // lượt 2–4: ranh giới phường 2025 và 6 quận cũ
  const rels = [];
  await PB.run(buf, { want: { nodes: false, ways: false, rels: true }, node() {}, way() {},
    rel(id, t, mem, types, roles) { const ward = t.boundary === "administrative" && t.admin_level === "6";
      const old = t.boundary === "historic" && t["was:admin_level"] === "6" && /Hoàn Kiếm|Ba Đình|Đống Đa|Hai Bà Trưng|Cầu Giấy|Thanh Xuân/.test(t.name || "");
      if (ward || old) rels.push({ id, tags: t, kind: ward ? "ward2025" : "district_old", ways: mem.filter((m, i) => types[i] === 1), roles: roles.filter((r, i) => types[i] === 1) }); } });
  const want = new Set(rels.flatMap(r => r.ways)), wayRefs = new Map();
  await PB.run(buf, { want: { nodes: false, ways: true, rels: false }, node() {}, rel() {}, way(id, refs) { if (want.has(id)) wayRefs.set(id, refs); } });
  const touch = rels.filter(r => r.ways.some(w => (wayRefs.get(w) || []).some(x => N.has(x))));
  const needN = new Set(touch.flatMap(r => r.ways.flatMap(w => wayRefs.get(w) || []))), loc = new Map();
  await PB.run(buf, { want: { nodes: true, ways: false, rels: false }, way() {}, rel() {}, node(id, la, lo) { if (needN.has(id)) loc.set(id, [+la.toFixed(7), +lo.toFixed(7)]); } });
  // xuất
  const used = new Set(); for (const [, refs] of ways) for (const r of refs) if (N.has(r)) used.add(r);
  const TK = ["name", "admin_level", "boundary", "was:admin_level", "end_date", "start_date", "population", "source:population", "population:date", "ref", "type", "official_name", "old_name", "is_in"];
  const out = { meta: { source: "Geofabrik vietnam-latest.osm.pbf (© OpenStreetMap contributors, ODbL 1.0)", last_modified_http: lastModified, osm_data_until: "2026-10-18T20:25:06Z (theo trang Geofabrik)", file_bytes: buf.length, extracted_at: new Date().toISOString(), extended_bbox: E },
    nodes: [...used].map(id => { const p = N.get(id); return [id, +p[0].toFixed(7), +p[1].toFixed(7)]; }),
    ways: ways.map(([id, refs, t]) => [id, refs.filter(r => N.has(r)), t]), bld, banks,
    areas: touch.map(r => { const tags = {}; for (const k of TK) if (r.tags[k] !== undefined) tags[k] = r.tags[k];
      return { id: r.id, kind: r.kind, tags, members: r.ways.map((w, i) => ({ way: w, role: r.roles[i], coords: (wayRefs.get(w) || []).map(x => loc.get(x)).filter(Boolean) })) }; }) };
  const gz = await new Response(new Blob([JSON.stringify(out)]).stream().pipeThrough(new CompressionStream("gzip"))).blob();
  const a = document.createElement("a"); a.href = URL.createObjectURL(gz); a.download = "osm_hanoi_extract.json.gz"; a.click();
}

// ------------------------------------------------------------------ B. Nemotron-Personas-Vietnam
async function extractPersonas() {
  let s = 20261020; const rnd = () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
  const used = new Set(), rows = [], pages = []; let scanned = 0, dbsh = 0, urban = 0;
  for (let k = 0; k < 700 && rows.length < 950; k++) {
    let pg; do { pg = Math.floor(rnd() * 10000); } while (used.has(pg)); used.add(pg);
    const r = await fetch(`/rows?dataset=nvidia/Nemotron-Personas-Vietnam&config=default&split=train&offset=${pg * 100}&length=100`);
    if (r.status !== 200) { used.delete(pg); await new Promise(z => setTimeout(z, r.status === 429 ? 15000 : 3000)); continue; }
    const j = await r.json(); pages.push(pg * 100);
    for (const x of j.rows) { const w = x.row; scanned++;
      if (w.region !== "Đồng bằng sông Hồng") continue; dbsh++; if (w.zone !== "Đô Thị") continue; urban++;
      const f = [["persona", w.persona], ["cultural_background", w.cultural_background], ["professional_persona", w.professional_persona]].filter(([, t]) => /Hà Nội/.test(t || "")).map(x => x[0]);
      if (f.length) rows.push({ row_idx: x.row_idx, uuid: w.uuid, sex: w.sex, age: w.age, marital_status: w.marital_status, education_level: w.education_level, occupation: w.occupation, zone: w.zone, region: w.region, country: w.country, matched_fields: f.join("|") }); }
    await new Promise(z => setTimeout(z, 600));
  }
  const meta = { dataset: "nvidia/Nemotron-Personas-Vietnam", hf_sha_at_access: "950724d49b7b41eee7925ae035a2059286c890ff", rows_scanned: scanned, region_DBSH: dbsh, region_DBSH_urban: urban, kept: rows.length, page_offsets: pages };
  const a = document.createElement("a"); a.href = URL.createObjectURL(new Blob([JSON.stringify({ meta, rows })])); a.download = "nemotron_hanoi_urban_v3.json"; a.click();
}
