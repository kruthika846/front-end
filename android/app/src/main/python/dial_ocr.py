"""Read the text printed on a gauge face with RapidOCR (PaddleOCR models
running on ONNX: accurate on photos of dials, and fast on a normal CPU).

Splits what it finds into
  * numbers (scale labels) with their position on the dial,
  * units (bar, psi, °C, ...),
  * a scale multiplier such as "x100" or "×1000",
  * the boxes of all text, so the needle finder can ignore them.

A dial can be read in several passes (different sizes, contrast-boosted);
merge() combines them.
"""

import math
import re
from dataclasses import dataclass

import cv2
import numpy as np

from units import TEMPERATURE_WORDS, VACUUM_WORDS, units_in_text

# OCR passes tried in turn until the scale is clear: (dial size in px, enhanced)
PASSES = [(800, False), (1300, False), (1000, True)]

_reader = None
_backend = None  # another OCR engine with the same result format (the Android app sets one)


def set_ocr_backend(fn):
    """Use `fn(img) -> [(box, text, conf)]` instead of RapidOCR: on Android,
    where RapidOCR's ONNX runtime is not available, the app passes its
    on-device text recognizer."""
    global _backend
    _backend = fn


def get_reader():
    """Loading the OCR models takes a moment, so do it once and reuse them."""
    global _reader
    if _reader is None:
        from rapidocr_onnxruntime import RapidOCR  # imported here so config-only use doesn't need it
        _warn_if_old_ocr()
        _reader = RapidOCR()
    return _reader


def _warn_if_old_ocr():
    """On Python 3.13+ pip can only install RapidOCR 1.2.x, which reads dials
    noticeably worse.  Say so instead of silently giving worse readings."""
    import sys
    from importlib.metadata import version

    try:
        major, minor = (int(p) for p in version("rapidocr_onnxruntime").split(".")[:2])
    except Exception:
        return
    if (major, minor) < (1, 4):
        print(f"WARNING: RapidOCR {major}.{minor} is too old and reads dials less reliably. "
              f"Use Python 3.11 or 3.12 (this is {sys.version.split()[0]}) - see requirements.txt.",
              file=sys.stderr)


@dataclass
class Label:
    value: float
    x: float
    y: float
    conf: float
    text: str
    ink: tuple = (0.0, 0.0, 0.0)  # Lab colour of the printed text


@dataclass
class UnitHit:
    type: str
    unit: str
    score: float
    x: float
    y: float
    text: str
    ink: tuple = (0.0, 0.0, 0.0)


def ink_color(image, box):
    """Lab colour of the text inside a box: the darkest third of its pixels.
    Dual-scale gauges print each scale in its own colour (black / red /
    green), which tells which unit goes with which ring of numbers."""
    x0, y0, x1, y1 = (int(round(v)) for v in box)
    patch = image[max(y0, 0):max(y1, 0), max(x0, 0):max(x1, 0)]
    if patch.size == 0 or patch.ndim != 3:
        return (0.0, 0.0, 0.0)
    lab = cv2.cvtColor(patch, cv2.COLOR_BGR2LAB).reshape(-1, 3).astype(float)
    dark = lab[lab[:, 0] <= np.percentile(lab[:, 0], 33)]
    L, a, b = dark.mean(axis=0)
    return (L * 100 / 255, a - 128, b - 128)


def ink_distance(c1, c2):
    """Colour difference that cares mostly about hue (red vs black vs green),
    less about brightness, which varies with lighting."""
    return math.hypot(c1[1] - c2[1], c1[2] - c2[2]) + 0.3 * abs(c1[0] - c2[0])


@dataclass
class DialText:
    labels: list
    units: list
    multiplier: float
    vacuum_word: bool
    temperature_word: bool
    boxes: list  # [(x0, y0, x1, y1)] in image coordinates
    raw: list  # [(text, conf)] for debugging
    words: list = None  # [(text, x, y)] of all confident text, in image coordinates
    rings: list = None  # [(cx, cy, DialText)]: number rings read unrolled while finding the gauges


# OCR often mixes up these characters inside numbers
_DIGIT_FIX = str.maketrans({"O": "0", "o": "0", "D": "0", "Q": "0", "l": "1", "I": "1", "|": "1", "i": "1",
                            "S": "5", "s": "5", "B": "8", "Z": "2", "z": "2", "G": "6", "−": "-", "–": "-",
                            "—": "-", ",": "."})
_NUMBER = re.compile(r"^[-+]?\d+(\.\d+)?$")
_NUMBER_IN = re.compile(r"[-+−–]?\d+(?:[.,]\d+)?")
_MULT = re.compile(r"[x×*]\s*(1[0oO]{1,4})(?![0-9])|(?<![0-9])(1[0oO]{1,4})\s*[x×]", re.I)


def parse_number(text):
    t = text.strip().replace(" ", "")
    if not t:
        return None
    # Only "repair" tokens that are mostly digits already, so words stay words
    digits = sum(c.isdigit() for c in t)
    if digits == 0 or digits < len(t) / 2:
        return None
    # tick marks next to a number are often read as a dash: "100 -", "200-"
    t = t.translate(_DIGIT_FIX).rstrip("-_~'.").lstrip("_~'.")
    # "02", "06": the decimal point of 0.2 / 0.6 is often lost
    if re.fullmatch(r"0\d+", t):
        t = "0." + t[1:]
    if _NUMBER.match(t):
        try:
            return float(t)
        except ValueError:
            return None
    return None


def _ocr(img):
    """Returns [(box, text, conf)].  Loose detection settings, because dial
    numbers are often single thin digits."""
    if _backend is not None:
        return [(np.array(box, np.float32), str(txt), float(c)) for box, txt, c in _backend(img)]
    result, _ = get_reader()(img, text_score=0.3, box_thresh=0.3, unclip_ratio=1.8)
    return [(np.array(box, np.float32), str(txt), float(c)) for box, txt, c in (result or [])]


def read_plate_label(image, cx, cy, r):
    """Text of the name plate next to the gauge ("PI-50 NOZZLE COOL OIL
    PRESS"), or "" if there is none.  Looks outside the dial, above and
    below it, and takes the plate nearest to the gauge."""
    h, w = image.shape[:2]
    best = None
    for side in ("above", "below"):
        # the strip above or below the dial
        y0, y1 = (cy - 2.6 * r, cy - 1.0 * r) if side == "above" else (cy + 1.0 * r, cy + 2.6 * r)
        x0, x1 = max(int(cx - 1.6 * r), 0), min(int(cx + 1.6 * r), w)
        y0, y1 = max(int(y0), 0), min(int(y1), h)
        if y1 - y0 < 20 or x1 - x0 < 20:
            continue
        crop = image[y0:y1, x0:x1]
        s = 1000 / crop.shape[1]
        big = cv2.resize(crop, None, fx=s, fy=s, interpolation=cv2.INTER_CUBIC)
        plate = _plate_in(big, s, x0, y0, cx, cy, r)
        if 0 < _plate_score(plate) < 15:
            # a plate, but worn, scratched or shiny: try again contrast-boosted
            gray = cv2.createCLAHE(clipLimit=2.5, tileGridSize=(8, 8)).apply(cv2.cvtColor(big, cv2.COLOR_BGR2GRAY))
            other = _plate_in(cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR), s, x0, y0, cx, cy, r)
            if _plate_score(other) > _plate_score(plate):
                plate = other
        if not plate:
            continue
        near = min(it[0] for it in plate) / r - (0.2 if side == "below" else 0.0)  # plates usually sit below
        if best is None or near < best[0]:
            best = (near, plate)
    if best is None:
        return ""

    # put the pieces in reading order: lines top to bottom, words left to right
    pieces = sorted(best[1], key=lambda it: it[1])
    lines, line = [], [pieces[0]]
    for it in pieces[1:]:
        if it[1] - line[-1][1] > 0.06 * r:
            lines.append(line)
            line = []
        line.append(it)
    lines.append(line)
    words = [it[3] for ln in lines for it in sorted(ln, key=lambda it: it[2])]
    return clean_tag(" ".join(words))


def _plate_in(img, s, x0, y0, cx, cy, r):
    """Text lines of the plate nearest the dial in one strip image."""
    items = []
    for box, txt, conf in _ocr(img):
        txt = txt.strip()
        x, y = box.mean(axis=0) / s + [x0, y0]
        if conf < 0.5 or sum(ch.isalpha() for ch in txt) < 2:  # a plate has words, not just numbers
            continue
        if math.hypot(x - cx, y - cy) < 1.15 * r:  # on the dial or its bezel
            continue
        items.append((abs(y - cy), y, x, txt, conf))
    if not items:
        return []
    items.sort()
    # the nearest line and the ones right after it make up one plate
    plate = [items[0]]
    for it in items[1:]:
        if it[0] - plate[-1][0] <= 0.6 * r and len(plate) < 6:
            plate.append(it)
    return plate


def _plate_score(plate):
    return sum(it[4] * sum(ch.isalnum() for ch in it[3]) for it in plate)


def clean_tag(text):
    """Tidy common OCR slips on instrument tags: "P1-50", "PL-10", "PT-23",
    "PPI-01" -> "PI-..", and drop stray characters stuck in front ("3:PI-10")."""
    text = re.sub(r"(?<![A-Za-z])[^A-Za-z\s]*P{1,2}[1lLI|iT]?\s*-\s*(\d)", r"PI-\1", text)
    return re.sub(r"\s+", " ", text).strip()


def merge(a, b, r):
    """Combine two OCR passes over the same dial.  If the passes read
    different numbers at the same spot ("6" vs "9"), keep both: the scale fit
    picks the one that lines up with the rest."""
    def near(p, q):
        return math.hypot(p.x - q.x, p.y - q.y) < 0.05 * r

    labels = list(a.labels)
    for lb in b.labels:
        twin = next((q for q in labels if near(q, lb) and q.value == lb.value), None)
        if twin is None:
            labels.append(lb)
        elif lb.conf > twin.conf:
            labels[labels.index(twin)] = lb
    units = a.units + [u for u in b.units if not any(near(u, q) and u.unit == q.unit for q in a.units)]
    return DialText(labels, units, a.multiplier if a.multiplier != 1 else b.multiplier,
                    a.vacuum_word or b.vacuum_word, a.temperature_word or b.temperature_word,
                    a.boxes + b.boxes, a.raw + b.raw, (a.words or []) + (b.words or []))


def read_dial_text(image, cx, cy, r, size=PASSES[0][0], enhanced=False, min_conf=0.3):
    """OCR the dial area of a BGR image, scaled to `size` px.  `enhanced`:
    contrast-boosted and sharpened, for dull or blurry photos."""
    h, w = image.shape[:2]
    pad = int(r * 1.15)
    x0, y0 = max(int(cx) - pad, 0), max(int(cy) - pad, 0)
    x1, y1 = min(int(cx) + pad, w), min(int(cy) + pad, h)
    crop = image[y0:y1, x0:x1]
    scale = size / max(crop.shape[:2])
    big = cv2.resize(crop, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC if scale > 1 else cv2.INTER_AREA)
    if enhanced:
        gray = cv2.cvtColor(big, cv2.COLOR_BGR2GRAY)
        gray = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8)).apply(gray)
        gray = cv2.addWeighted(gray, 1.8, cv2.GaussianBlur(gray, (0, 0), 3), -0.8, 0)
        big = cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)
    results = [(np.array(p, np.float32) / scale + [x0, y0], t, c) for p, t, c in _ocr(big)]
    return _dial_text(image, results, min_conf)


def read_ring_text(image, cx, cy, radius, min_conf=0.3):
    """OCR the ring of numbers `radius` px from the pivot, unrolled into
    straight strips.

    Many dials print their numbers turned to follow the circle (each one's
    top pointing outwards), and OCR misses most of those.  Unrolled, they all
    stand upright.  The ring is read in four overlapping 140-degree pieces,
    each with a margin round it (OCR finds far more of the numbers that way)."""
    r_out, r_in = 1.15 * radius, 0.82 * radius
    rows = 140  # the band is drawn 140 px tall, whatever the dial's size
    radii = np.linspace(r_out, r_in, rows)  # top row = outside
    step = 180 / math.pi * (r_out - r_in) / (rows * radius)  # degrees per strip column
    pad_y, pad_x = 60, 20
    found = None
    for a0 in (0, 90, 180, 270):
        angs = np.arange(a0 - 25, a0 + 115, step)
        a = np.deg2rad(angs)[None, :]
        xs = (cx - np.sin(a) * radii[:, None]).astype(np.float32)
        ys = (cy + np.cos(a) * radii[:, None]).astype(np.float32)
        strip = cv2.remap(image, xs, ys, cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)
        strip = cv2.copyMakeBorder(strip, pad_y, pad_y, pad_x, pad_x, cv2.BORDER_REPLICATE)

        def to_image(pts, angs=angs):  # strip px -> image px
            ang = np.deg2rad(np.interp(pts[:, 0] - pad_x, np.arange(len(angs)), angs))
            rad = np.interp(pts[:, 1] - pad_y, np.arange(rows), radii)
            return np.c_[cx - np.sin(ang) * rad, cy + np.cos(ang) * rad].astype(np.float32)

        part = _dial_text(image, [(to_image(p), t, c) for p, t, c in _ocr(strip)], min_conf)
        found = part if found is None else merge(found, part, radius)
    return found


def _dial_text(image, results, min_conf):
    """Sort OCR results [(corners in image px, text, conf)] into a DialText."""
    labels, units, boxes, raw, words = [], [], [], [], []
    multiplier, vac, temp = 1.0, False, False
    for pts, text, conf in results:
        bx0, by0 = pts.min(axis=0)
        bx1, by1 = pts.max(axis=0)
        mx, my = pts.mean(axis=0)
        raw.append((text, round(float(conf), 2)))
        if conf >= min_conf:
            words.append((text, float(mx), float(my)))
        ink = ink_color(image, (bx0, by0, bx1, by1))
        # unit words are matched strictly, so even unsure OCR is useful for them
        for tp, unit, score in units_in_text(text):
            units.append(UnitHit(tp, unit, score * (0.5 + 0.5 * conf), mx, my, text, ink))
        v = parse_number(text)
        if conf < min_conf:
            continue
        boxes.append((bx0, by0, bx1, by1))
        low = text.lower()

        m = _MULT.search(text)
        if m:
            multiplier = float((m.group(1) or m.group(2)).lower().replace("o", "0"))
        if any(wd in low for wd in VACUUM_WORDS):
            vac = True
        if any(wd in low for wd in TEMPERATURE_WORDS):
            temp = True

        # a token may be a plain number, or a number glued to a unit ("10bar")
        if v is None and not m:
            nums = _NUMBER_IN.findall(text)
            if len(nums) == 1 and units_in_text(text):
                v = parse_number(nums[0])
        if v is not None:
            parts = split_run_together(text.strip())
            if parts:  # "200250" -> 200 and 250, spread across the box
                k = len(parts)
                for j, pv in enumerate(parts):
                    px = bx0 + (j + 0.5) * (bx1 - bx0) / k
                    labels.append(Label(pv, float(px), float(my), float(conf), str(pv), ink))
            else:
                labels.append(Label(v, float(mx), float(my), float(conf), text, ink))

    return DialText(labels, units, multiplier, vac, temp, boxes, raw, words)


def split_run_together(text):
    """Two or three neighbouring scale numbers read as one ("200250" ->
    [200, 250]).  Only split when the pieces are equally long and go up in an
    even step, so ordinary numbers ("2015", "4190569") stay whole."""
    if not text.isdigit() or len(text) < 4:
        return None
    for k in (2, 3):
        if len(text) % k:
            continue
        n = len(text) // k
        pieces = [text[i * n:(i + 1) * n] for i in range(k)]
        if any(p.startswith("0") and p != "0" for p in pieces):
            continue
        vals = [int(p) for p in pieces]
        steps = {b - a for a, b in zip(vals, vals[1:])}
        if len(steps) == 1 and steps.pop() > 0 and vals[1] - vals[0] <= vals[0]:
            return [float(v) for v in vals]
    return None
