# -*- coding: utf-8 -*-
"""Bước 6: ghi SHA256SUMS.txt cho mọi tệp của gói (trừ SHA256SUMS.txt và validation_report.txt). Chạy trước bước 5."""
import hashlib, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = []
for d, _, fs in os.walk(ROOT):
    if "__pycache__" in d:
        continue
    for f in fs:
        p = os.path.relpath(os.path.join(d, f), ROOT).replace(os.sep, "/")
        if p in ("SHA256SUMS.txt", "validation_report.txt"):
            continue
        out.append((p, hashlib.sha256(open(os.path.join(ROOT, p), "rb").read()).hexdigest()))
open(os.path.join(ROOT, "SHA256SUMS.txt"), "w", encoding="utf-8").write("".join(f"{h}  {p}\n" for p, h in sorted(out)))
print(len(out), "tệp")
