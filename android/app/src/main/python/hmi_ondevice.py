"""Reads an HMI / monitoring screen photo on the tablet, for when DSR Extract
(the PC/ship OCR server) can't be reached.

Text comes from ML Kit (app_gauge._ml_kit). Each number is paired with the
label text just left of it on the same row, and tagged with the
"Generator no.N" block it sits under. The answer has the same shape as DSR
Extract's (extracted_values: label, value, unit, confidence), so the app maps
both the same way. It is simpler than DSR Extract: expect fewer values.
"""

import json
import re

import cv2

from app_gauge import _ml_kit

NUMBER = re.compile(r"^[-−]?\d+(?:[.,]\d+)?$")
UNIT_AFTER = re.compile(r"^([-−]?\d+(?:[.,]\d+)?)\s*(°?\s?C|MPa|kPa|bar|kW|%|A|V|rpm)$", re.I)
UNIT_ONLY = re.compile(r"^(°?\s?C|•C|MPa|kPa|bar|kW|%|A|V|rpm)$", re.I)
TITLE = re.compile(r"generator\s*no\.?\s*(\d+)", re.I)


def _box(b):
    xs = [p[0] for p in b]
    ys = [p[1] for p in b]
    return min(xs), min(ys), max(xs), max(ys)


def read(path):
    img = cv2.imread(path)
    if img is None:
        return json.dumps({"error": "The photo could not be opened"})
    h, w = img.shape[:2]
    scale = 2000 / max(h, w)
    if scale < 1:
        img = cv2.resize(img, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)

    items = []
    for box, text, conf in _ml_kit(img):
        x0, y0, x1, y1 = _box(box)
        items.append({"text": text.strip(), "conf": float(conf), "x0": x0, "y0": y0, "x1": x1, "y1": y1,
                      "yc": (y0 + y1) / 2, "h": max(1.0, y1 - y0)})

    titles = []  # (y, generator number)
    for it in items:
        m = TITLE.search(it["text"])
        if m:
            titles.append((it["yc"], int(m.group(1))))
    titles.sort()

    numbers, texts, units = [], [], []
    for it in items:
        t = it["text"].replace(",", ".")
        m = UNIT_AFTER.match(t)
        if m:
            numbers.append({**it, "value": m.group(1).replace("−", "-"), "unit": m.group(2).replace(" ", "")})
        elif NUMBER.match(t):
            numbers.append({**it, "value": t.replace("−", "-"), "unit": ""})
        elif UNIT_ONLY.match(t):
            units.append(it)
        elif re.search(r"[A-Za-z]", t):
            texts.append(it)

    def same_row(a, b):
        return abs(a["yc"] - b["yc"]) <= 0.6 * max(a["h"], b["h"])

    # "CYL no.  1  2  3 ..." gives each column of the cylinder rows its number.
    cyl_head = next((t for t in texts if re.search(r"cyl", t["text"], re.I)), None)
    cyl_cols = []
    if cyl_head:
        cyl_cols = sorted((n["x0"] + n["x1"]) / 2 for n in numbers
                          if same_row(n, cyl_head) and re.fullmatch(r"\d", n["value"]))

    out = []
    for n in numbers:
        if cyl_head and same_row(n, cyl_head):
            continue  # the cylinder numbers themselves
        unit = n["unit"]
        if not unit:
            right = [u for u in units if same_row(u, n) and 0 <= u["x0"] - n["x1"] <= 3 * n["h"]]
            if right:
                unit = right[0]["text"].replace(" ", "").replace("•", "°")
        left = [t for t in texts if same_row(t, n) and t["x1"] <= n["x0"] + 0.5 * n["h"]]
        if not left:
            continue
        label = max(left, key=lambda t: t["x1"])["text"]
        if TITLE.search(label):
            label = "Generator no."
        # a row of per-cylinder values (several numbers right of one label, under "CYL no.")
        if cyl_cols and n["y0"] > cyl_head["y0"]:
            row = [m for m in numbers if same_row(m, n)]
            if len(row) >= 3:
                cx = (n["x0"] + n["x1"]) / 2
                k = min(range(len(cyl_cols)), key=lambda i: abs(cyl_cols[i] - cx)) + 1
                label = f"{label} (CYL {k})"
        group = None
        for ty, g in titles:
            if ty <= n["yc"] + n["h"]:
                group = g
        if group is not None:
            label = f"Gen {group} - {label}"
        out.append({"label": label, "value": n["value"], "unit": unit or None, "confidence": round(n["conf"], 3)})
    return json.dumps({"extracted_values": out, "tables": [], "source": "on-device"})
