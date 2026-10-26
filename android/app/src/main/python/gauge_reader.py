"""Analog gauge reader.

Give it a photo of any round analog gauge (pressure, temperature, vacuum,
voltage, ...) and it works out the reading on its own:

  1. finds the dial and the needle pivot (OpenCV),
  2. reads the numbers and the unit printed on the dial (RapidOCR),
  3. fits the scale from those numbers (which angle = which value),
  4. reads where the needle points and converts it to the gauge's unit.

Usage:
    python gauge_reader.py photo.jpg                     # fully automatic
    python gauge_reader.py photos/*.jpg                  # many images / a folder
    python gauge_reader.py photo.jpg --debug out.png     # save a marked-up image
    python gauge_reader.py photo.jpg --unit psi          # if the unit isn't printed/readable
    python gauge_reader.py photo.jpg --range 0 10        # if the numbers can't be read
    python gauge_reader.py photo.jpg --gauge boiler_pressure   # use a gauges.yaml entry
    python gauge_reader.py photo.jpg --json               # label, value, unit, confidence,
                                                         # needle_angle, gauge_bounds, processing_time_ms
    python gauge_reader.py photo.jpg --label "Main Air Pressure"   # set the label yourself
    python gauge_reader.py photo.jpg --no-label          # skip reading the name plate (faster)

Angle convention used everywhere: degrees measured CLOCKWISE starting from
straight DOWN (6 o'clock).  So 6 o'clock = 0, 9 o'clock = 90,
12 o'clock = 180, 3 o'clock = 270.  A typical gauge has its zero at the
bottom-left (~45) and its maximum at the bottom-right (~315).
"""

if __name__ == "__main__":  # run with the project's .venv Python if there is one
    import use_venv

    use_venv.ensure()

import argparse
import glob
import itertools
import json
import math
import sys
import time
from dataclasses import dataclass, field, replace
from pathlib import Path

import cv2
import numpy as np
import yaml

from units import GAUGE_TYPES, convert, display_unit, normalize_unit

DEFAULT_CONFIG = Path(__file__).with_name("gauges.yaml")
# Below this confidence a reading is flagged in its status as possibly wrong.
# On the test photos, every reading below it was wrong and every one above right.
LOW_CONFIDENCE = 0.35
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff", ".webp"}

# Extra units shown next to the reading, per gauge type
DEFAULT_SHOW_ALSO = {
    "pressure": ["bar", "psi", "kPa"],
    "vacuum": ["kPa", "inHg"],
    "temperature": ["C", "F"],
}


@dataclass
class GaugeSpec:
    name: str
    type: str
    unit: str
    min_value: float
    max_value: float
    min_angle: float = 45.0
    max_angle: float = 315.0
    show_also: list = field(default_factory=list)  # extra units to convert to
    decimals: int = 2
    center: tuple | None = None  # (x, y) px, optional: skips circle detection
    radius: float | None = None  # px, optional
    warn_below: float | None = None
    warn_above: float | None = None

    @classmethod
    def from_dict(cls, name, d):
        gtype = d["type"].lower()
        if gtype not in GAUGE_TYPES:
            raise ValueError(f"[{name}] unknown type '{gtype}'. Known: {', '.join(GAUGE_TYPES)}")
        spec = cls(
            name=name,
            type=gtype,
            unit=normalize_unit(gtype, str(d["unit"])),
            min_value=float(d["min_value"]),
            max_value=float(d["max_value"]),
            min_angle=float(d.get("min_angle", 45)),
            max_angle=float(d.get("max_angle", 315)),
            show_also=[normalize_unit(gtype, str(u)) for u in d.get("show_also", [])],
            decimals=int(d.get("decimals", 2)),
            center=tuple(d["center"]) if d.get("center") else None,
            radius=float(d["radius"]) if d.get("radius") else None,
            warn_below=d.get("warn_below"),
            warn_above=d.get("warn_above"),
        )
        if spec.max_value == spec.min_value:
            raise ValueError(f"[{name}] min_value and max_value must differ")
        return spec


def load_config(path):
    if not Path(path).exists():
        return {}
    with open(path, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    gauges = data.get("gauges", {}) or {}
    return {name: GaugeSpec.from_dict(name, d) for name, d in gauges.items()}


# ---------------------------------------------------------------- vision ----

def prepare(image):
    """Bring every photo to a similar size so the thresholds below fit."""
    h, w = image.shape[:2]
    s = 1000.0 / max(h, w)
    if s < 1 or max(h, w) < 600:
        image = cv2.resize(image, None, fx=s, fy=s, interpolation=cv2.INTER_AREA if s < 1 else cv2.INTER_CUBIC)
    return image


def find_dial(gray, center=None, radius=None):
    """Return (cx, cy, r) of the gauge face."""
    h, w = gray.shape
    if center and radius:
        return float(center[0]), float(center[1]), float(radius)

    blurred = cv2.medianBlur(gray, 5)
    edges = cv2.Canny(blurred, 40, 120)
    fams = _circle_families(blurred, edges, min_frac=0.15, per_pass=60, enough=20)
    if fams:
        _, cx, cy, r = fams[0]
    else:  # assume the gauge fills the picture
        cx, cy, r = w / 2, h / 2, min(h, w) / 2 * 0.95

    if center:
        cx, cy = center
    else:
        cx, cy = find_pivot(gray, edges, cx, cy, r)
    if radius:
        r = radius
    return float(cx), float(cy), float(r)


def _circle_families(blurred, edges, min_frac, per_pass, enough):
    """Candidate gauges, best first, as [(score, cx, cy, r)].

    A gauge is a family of concentric circles (bezel, glass ring, dial edge)
    around the pivot, so each circle is scored by the edge support of its
    whole family."""
    h, w = blurred.shape
    cands = []
    for p2 in (50, 35, 25):  # strict first, then more forgiving
        found = cv2.HoughCircles(
            blurred, cv2.HOUGH_GRADIENT, dp=1.2, minDist=8, param1=120, param2=p2,
            minRadius=int(min(h, w) * min_frac), maxRadius=int(max(h, w) * 0.6),
        )
        if found is not None:
            cands += [tuple(map(float, c)) for c in found[0][:per_pass]]
        if len(cands) >= enough:
            break

    # how much of each circle is backed by a real edge, and is it in the photo?
    scored = []
    for x, y, rr in cands:
        sup, inside = circle_support(edges, x, y, rr)
        if inside >= 0.75 and sup >= 0.25:
            scored.append((x, y, rr, sup))

    fams = []
    for x, y, rr, sup in scored:
        fam = [c for c in scored if math.hypot(c[0] - x, c[1] - y) < 0.06 * max(rr, c[2])]
        radii, total = [], 0.0
        for c in sorted(fam, key=lambda c: -c[3]):
            if all(abs(c[2] - q) > 0.04 * c[2] for q in radii):  # count each ring once
                radii.append(c[2])
                total += c[3]
        wts = np.array([c[3] for c in fam])
        fx = float(np.average([c[0] for c in fam], weights=wts))
        fy = float(np.average([c[1] for c in fam], weights=wts))
        fr = max(fam, key=lambda c: c[3])[2]  # the dial face: best-supported ring
        fams.append((total, fx, fy, fr))
    fams.sort(key=lambda f: -f[0])
    return fams


def _rim_outlines(edges, max_n=30):
    """Round outlines traced from the edge map (bezels, dial edges), as
    [(cx, cy, r)].  Catches rims the circle search misses, including ones
    seen slightly from the side (oval)."""
    h, w = edges.shape
    closed = cv2.dilate(edges, np.ones((3, 3), np.uint8))
    contours, _ = cv2.findContours(closed, cv2.RETR_LIST, cv2.CHAIN_APPROX_NONE)
    out = []
    for c in contours:
        if len(c) < 60:
            continue
        (x, y), (a, b), _ = cv2.fitEllipse(c)
        r = (a + b) / 4
        if not (0.06 * min(h, w) <= r <= 0.6 * max(h, w)) or min(a, b) / max(a, b) < 0.75:
            continue
        sup, inside = circle_support(edges, x, y, r)
        if sup >= 0.5 and inside >= 0.75:
            out.append((sup * r, float(x), float(y), float(r)))
    out.sort(key=lambda o: -o[0])
    # drop near-duplicates (inner and outer edge of the same rim)
    kept = []
    for _, x, y, r in out:
        if all(math.hypot(x - kx, y - ky) > 0.1 * r or abs(r - kr) > 0.08 * r for kx, ky, kr in kept):
            kept.append((x, y, r))
        if len(kept) >= max_n:
            break
    return kept


def _arc_candidates(labels, h, w, max_n=6):
    """Gauges found from their printed numbers alone, as [(cx, cy, r)].

    A scale's numbers sit on an arc around the pivot, so a circle through
    them gives the pivot even where there is no round rim to find - a square
    panel meter whose pivot hides under a corner cover, say.  r is the dial
    radius estimated from the numbers' ring (numbers sit at ~3/4 of it)."""
    from scale_fit import fit_scale

    pts = [lb for lb in labels if lb.conf >= 0.3]
    if len(pts) < 4:
        return []
    found = []
    for a, b, c in itertools.combinations(pts, 3):
        if len({a.value, b.value, c.value}) < 3:
            continue
        # circle through the three numbers
        ax, ay, bx, by, cx_, cy_ = a.x, a.y, b.x, b.y, c.x, c.y
        d = 2 * (ax * (by - cy_) + bx * (cy_ - ay) + cx_ * (ay - by))
        if abs(d) < 1e-6:
            continue
        ux = ((ax * ax + ay * ay) * (by - cy_) + (bx * bx + by * by) * (cy_ - ay) + (cx_ * cx_ + cy_ * cy_) * (ay - by)) / d
        uy = ((ax * ax + ay * ay) * (cx_ - bx) + (bx * bx + by * by) * (ax - cx_) + (cx_ * cx_ + cy_ * cy_) * (bx - ax)) / d
        rl = math.hypot(ax - ux, ay - uy)
        if not 0.04 * min(h, w) < rl < 0.6 * max(h, w):
            continue
        ring = [lb for lb in pts if abs(math.hypot(lb.x - ux, lb.y - uy) - rl) < 0.07 * rl]
        if len({lb.value for lb in ring}) < 4:
            continue
        if any(math.hypot(ux - fx, uy - fy) < 0.1 * fr for _, fx, fy, fr in found):
            continue  # already have this one
        s = fit_scale(ring, ux, uy, rl / 0.75)
        if s is not None and len(s.labels) >= 4:
            found.append((len(s.labels), ux, uy, rl / 0.75))
    found.sort(key=lambda f: -f[0])
    return [(x, y, r) for _, x, y, r in found[:max_n]]


def find_gauges(color, gray, max_gauges=6, return_text=False):
    """Every gauge in the photo, as [(cx, cy, r)], in reading order (top to
    bottom, left to right).

    Circles are only candidates (screws, flanges and pipes are round too).
    One quick OCR pass over the whole photo finds the printed numbers; a
    circle counts as a gauge when the numbers around it form a proper scale
    centred on it."""
    from dial_ocr import read_dial_text, read_ring_text
    from scale_fit import fit_scale, fit_two

    h, w = gray.shape
    blurred = cv2.medianBlur(gray, 5)
    edges = cv2.Canny(blurred, 40, 120)
    first = find_dial(gray)
    rims = _rim_outlines(edges)
    cands = [first] + [(x, y, r) for _, x, y, r in
                       _circle_families(blurred, edges, min_frac=0.06, per_pass=200, enough=200)[:30]] + rims

    def scale_around(labels, x, y, r):
        near = [lb for lb in labels if 0.2 * r <= math.hypot(lb.x - x, lb.y - y) <= 1.1 * r]
        s = fit_scale(near, x, y, r) or fit_two(near, x, y, r)
        # a real scale wraps round its own centre; numbers borrowed from a
        # neighbouring gauge all sit off to one side
        if s is None or s.radius < 0.35 or s.u_max - s.u_min < 90:
            return None
        return s

    # 1) quick: one OCR pass over the whole photo
    text = read_dial_text(color, w / 2, h / 2, max(h, w) / 2 / 1.15, size=1300)
    valid = []
    for i, (x, y, r) in enumerate(cands):
        s = scale_around(text.labels, x, y, r)
        if s is None:
            continue
        sup, _ = circle_support(edges, x, y, r)
        # The dial find_dial() picks gets priority, so single-gauge photos
        # read exactly as before - unless it rests on just 2 numbers, when a
        # better-supported candidate may take its place.
        bonus = (100 if len(s.labels) >= 3 else 1.5) if i == 0 else 0
        valid.append((len(s.labels) + sup + bonus, x, y, r))

    # 1b) gauges found from their numbers' arc (pivot hidden or off-centre,
    #     e.g. square panel meters); already checked against their scale
    arcs = _arc_candidates(text.labels, h, w)
    for x, y, r in arcs:
        near = [lb for lb in text.labels if 0.2 * r <= math.hypot(lb.x - x, lb.y - y) <= 1.1 * r]
        s = fit_scale(near, x, y, r)
        if s is not None:
            valid.append((len(s.labels) + 1.0, x, y, r))

    # 2) small gauges' numbers are too small for that pass: OCR each strong
    #    round rim not confirmed yet on its own, enlarged
    for x, y, r in rims[:6]:
        if any(math.hypot(x - vx, y - vy) < 0.7 * (r + vr) for _, vx, vy, vr in valid):
            continue
        close_up = read_dial_text(color, x, y, r, size=800)
        # keep what the close-up saw (units, words) for reading this gauge later
        text.units.extend(close_up.units)
        text.words = (text.words or []) + (close_up.words or [])
        s = scale_around(close_up.labels, x, y, r)
        if s is None and valid and any(lb.conf >= 0.9 and 0.3 * r <= math.hypot(lb.x - x, lb.y - y) <= r
                                       for lb in close_up.labels):
            # A number was read clearly, but no scale: the numbers may be
            # turned to follow the circle - read their ring unrolled.  Only to
            # find further gauges: with none found yet, read_auto() reads the
            # photo as one gauge, and unrolls the ring itself if it must.
            px, py = find_pivot(gray, edges, x, y, r)
            rho = _number_ring(close_up.labels, px, py, r)
            if rho:
                ring = read_ring_text(color, px, py, rho)
                text.rings = (text.rings or []) + [(px, py, ring)]
                s = scale_around(close_up.labels + ring.labels, px, py, r)
        if s is not None:
            sup, _ = circle_support(edges, x, y, r)
            valid.append((len(s.labels) + sup, x, y, r))

    chosen = []
    for _, x, y, r in sorted(valid, key=lambda v: -v[0]):
        if len(chosen) >= max_gauges:
            break
        if any(math.hypot(x - cx, y - cy) < 0.7 * (r + cr) for cx, cy, cr in chosen):
            continue  # same gauge (another of its rings) or overlapping
        chosen.append((x, y, r))
    out = []
    for x, y, r in chosen:
        if (x, y, r) == first or (x, y, r) in arcs:
            out.append((float(x), float(y), float(r)))  # already at the pivot
        else:
            px, py = find_pivot(gray, edges, x, y, r)
            out.append((float(px), float(py), float(r)))
    # reading order: rows top to bottom, left to right within a row
    if out:
        row = 0.8 * max(d[2] for d in out)
        out.sort(key=lambda d: (round(d[1] / row), d[0]))
    return (out, text) if return_text else out


def _number_ring(labels, cx, cy, r):
    """Distance (px) of the scale numbers from the pivot, judged from the
    numbers OCR could read (the surest ones if there are any), or None."""
    pts = [(lb.conf, math.hypot(lb.x - cx, lb.y - cy)) for lb in labels]
    pts = [(c, d) for c, d in pts if 0.18 * r <= d <= 1.15 * r]
    dists = [d for c, d in pts if c >= 0.9] or [d for _, d in pts]
    return float(np.median(dists)) if dists else None


def _temperature_nearby(words, cx, cy, r):
    """Is a temperature word ("THERMOMETER", "temperature" ...) printed on
    the gauge or on a plate right next to it?"""
    from units import TEMPERATURE_WORDS
    return any(any(t in w.lower() for t in TEMPERATURE_WORDS) and math.hypot(x - cx, y - cy) < 2.6 * r
               for w, x, y in words or [])


def circle_support(edges, x, y, r, n=180):
    """Fraction of a circle's samples (inside the photo) that sit on an edge,
    and the fraction of the circle that is inside the photo at all."""
    h, w = edges.shape
    t = np.linspace(0, 2 * np.pi, n, endpoint=False)
    xs = (x + r * np.cos(t)).astype(int)
    ys = (y + r * np.sin(t)).astype(int)
    ok = (xs >= 2) & (ys >= 2) & (xs < w - 2) & (ys < h - 2)
    inside = ok.mean()
    xs, ys = xs[ok], ys[ok]
    if len(xs) == 0:
        return 0.0, 0.0
    # an edge within +-2 px counts
    hit = np.zeros(len(xs), bool)
    for ox in (-2, 0, 2):
        for oy in (-2, 0, 2):
            hit |= edges[ys + oy, xs + ox] > 0
    return float(hit.mean()), float(inside)


def find_pivot(gray, edges, cx, cy, r):
    """The needle turns on a small round cap near the dial centre.  Find that
    circle; it is a better centre than the rim (which may be slightly off or
    seen at an angle)."""
    win = int(r * 0.35)
    x0, y0 = max(int(cx) - win, 0), max(int(cy) - win, 0)
    roi = cv2.medianBlur(gray[y0:int(cy) + win, x0:int(cx) + win], 3)
    if roi.size == 0:
        return cx, cy
    found = cv2.HoughCircles(roi, cv2.HOUGH_GRADIENT, dp=1, minDist=3, param1=100, param2=12,
                             minRadius=max(3, int(r * 0.025)), maxRadius=int(r * 0.12))
    caps = []
    if found is not None:
        for x, y, rr in found[0][:40]:
            gx, gy = x + x0, y + y0
            off = math.hypot(gx - cx, gy - cy) / r
            if off > 0.25:
                continue
            sup, _ = circle_support(edges, gx, gy, rr, n=72)
            if sup >= 0.45:
                caps.append((gx, gy, sup, off))
    if not caps:
        return cx, cy

    # Several round caps can sit near the middle (a decorative boss, a screw).
    # The pivot is the one the needle turns on: a straight dark bar runs
    # through it both ways (pointer one way, counterweight the other).
    ngray, _ = needle_view(gray, cx, cy, r)
    inv = _needle_contrast(ngray, cx, cy, r)
    coarse = np.arange(0, 360, 1.0)

    def bar(px, py):
        s = _line_score(inv, px, py, r, coarse, r0=0.12, n=30)
        # the counterweight is short: look for it close to the pivot only (with
        # long rays, the round end of the counterweight itself scores well, as
        # the needle runs on from it through the real pivot)
        back = _line_score(inv, px, py, r, coarse, r0=0.04, r1=0.15, n=15)
        return float((s + 0.5 * np.roll(back, 180)).max())

    bars = [bar(gx, gy) for gx, gy, _, _ in caps]
    top = max(bars) or 1.0
    best = max(zip(caps, bars), key=lambda cb: cb[1] / top + 0.5 * cb[0][2] - cb[0][3])
    return best[0][0], best[0][1]


def needle_view(gray, cx, cy, r):
    """Grey image in which the needle is darker than the face, whatever the
    gauge's colours (black dial with white needle -> inverted)."""
    mask = np.zeros_like(gray)
    cv2.circle(mask, (int(cx), int(cy)), int(r * 0.7), 255, -1)
    cv2.circle(mask, (int(cx), int(cy)), int(r * 0.3), 0, -1)
    if not mask.any():
        return gray, False
    # Decide by contrast, not brightness (a white dial in a dim photo is
    # grey): on a light face the printing is the dark minority of pixels, on a
    # dark face it is the bright minority.
    px = gray[mask > 0]
    p5, med, p95 = np.percentile(px, (5, 50, 95))
    dark_face = (p95 - med) > (med - p5)
    return (255 - gray) if dark_face else gray, dark_face


def _needle_contrast(gray, cx, cy, r):
    """Float image where the needle is bright: darkness above the dial
    face's typical level.  The level comes from the inner face only, so a
    black bezel or recess around the gauge can't raise it."""
    inv = 255 - cv2.GaussianBlur(gray, (5, 5), 0)
    mask = np.zeros(gray.shape, np.uint8)
    cv2.circle(mask, (int(cx), int(cy)), max(int(0.6 * r), 2), 255, -1)
    face = inv[mask > 0]
    thr = np.percentile(face, 60) if face.size else 0
    return np.clip(inv.astype(np.float32) - thr, 0, None)


def _major_ticks(inv, cx, cy, r, u_lo, u_hi, needle=None):
    """Unwrapped angles of the long (major) tick marks between u_lo and u_hi.
    A major tick is a dark radial stroke clearly longer than the small ones.
    The needle (at dial angle `needle`) is a long dark stroke too: skip it."""
    us = np.arange(u_lo, u_hi, 0.25)
    if needle is not None:
        us = us[np.abs((us - needle + 180) % 360 - 180) > 3]
    s = _rays(inv, cx, cy, us % 360, np.linspace(0.7 * r, 1.08 * r, 60))
    dark = s > max(10.0, 0.35 * float(np.percentile(s, 99.5)))
    # longest unbroken dark run along each ray = the tick's length there
    run = np.zeros(len(us))
    for i, row in enumerate(dark):
        best = cur = 0
        for d in row:
            cur = cur + 1 if d else 0
            best = max(best, cur)
        run[i] = best / len(row)
    if run.max() < 0.08:
        return []
    peaks = []
    for i in range(1, len(us) - 1):
        if us[i + 1] - us[i - 1] > 0.6:  # neighbours across the skipped needle
            continue
        if run[i] >= 0.7 * run.max() and run[i] >= run[i - 1] and run[i] >= run[i + 1]:
            if peaks and us[i] - peaks[-1][0] < 2.0:  # same tick
                if run[i] > peaks[-1][1]:
                    peaks[-1] = (us[i], run[i])
                continue
            peaks.append((us[i], run[i]))
    return [p[0] for p in peaks]


def _fill_from_ticks(scale, inv, cx, cy, r, needle=None):
    """On an uneven scale, add the numbers OCR missed (e.g. hidden under the
    needle): the major ticks carry the numbers in order, so a major tick
    between two read numbers gets the value in between."""
    from scale_fit import nice_step

    us, vs = scale._points()
    step = nice_step(set(vs))
    ticks = _major_ticks(inv, cx, cy, r, us[0] - 3, us[-1] + 3, needle)
    if step is None or len(ticks) < 3:
        return
    # each read number sits next to its major tick
    anchors = []
    for u, v in zip(us, vs):
        t = min(ticks, key=lambda t: abs(t - u))
        if abs(t - u) <= 5:
            anchors.append((t, v))
    u_needle = scale.unwrap(needle) if needle is not None else None
    added = []
    for (ta, va), (tb, vb) in zip(anchors, anchors[1:]):
        between = [t for t in ticks if ta + 1 < t < tb - 1]
        n = round(abs(vb - va) / step) - 1
        # one major tick short, and the needle lies in that gap: the missing
        # tick is hidden under the needle
        if n >= 1 and len(between) == n - 1 and u_needle is not None and ta + 1 < u_needle < tb - 1:
            between = sorted(between + [u_needle])
        if n >= 1 and len(between) == n:  # the ticks agree with the numbers' step
            for k, t in enumerate(between, 1):
                added.append((t, va + (vb - va) * k / (n + 1)))
    if not added:
        return
    from dial_ocr import Label
    for t, v in added:
        scale.angles.append(float(t))
        scale.labels.append(Label(float(v), 0.0, 0.0, 0.0, f"{v:g} (tick)"))


def _rays(img, cx, cy, angles, radii):
    """Sample `img` along rays from (cx, cy): array [angle, radius]."""
    a = np.deg2rad(angles)[:, None]
    # our convention: 0 = down, clockwise on screen  ->  dx = -sin, dy = cos
    xs = np.clip(cx - np.sin(a) * radii[None, :], 0, img.shape[1] - 1).astype(np.float32)
    ys = np.clip(cy + np.cos(a) * radii[None, :], 0, img.shape[0] - 1).astype(np.float32)
    return cv2.remap(img, xs, ys, cv2.INTER_LINEAR)


def _line_score(inv, cx, cy, r, angles, r0=0.3, r1=0.75, n=70):
    """How needle-like each ray is: dark over most of its length (30th
    percentile), plus a little of its overall darkness.  Numbers, ticks and
    printing are dark only in short stretches."""
    s = _rays(inv, cx, cy, angles, np.linspace(r0 * r, r1 * r, n))
    return np.percentile(s, 30, axis=1) + 0.25 * s.mean(axis=1)


def find_needle(gray, cx, cy, r):
    """Find the needle around the pivot (cx, cy).  Returns (angle,
    confidence, cx, cy): the pointer's angle (our convention), how clearly it
    stands out, and the pivot used."""
    inv = _needle_contrast(gray, cx, cy, r)

    # 1) The direction of the needle (either end)
    angles = np.arange(0, 360, 0.5)
    score = _line_score(inv, cx, cy, r, angles)
    k = np.ones(5) / 5
    score = np.convolve(np.r_[score[-2:], score, score[:2]], k, mode="valid")  # smooth circularly
    i = int(np.argmax(score))

    # 2) Which end is the pointer?  The one that reaches further out from the
    #    pivot without a break (the counterweight is short).
    j = (i + 360 + np.argmax([score[(i + 360 + d) % 720] for d in range(-16, 17)]) - 16) % 720  # opposite end
    radii = np.linspace(0.2 * r, 0.95 * r, 90)
    samples = _rays(inv, cx, cy, angles, radii)
    dark = samples > max(10.0, 0.35 * float(np.percentile(samples, 99.5)))
    dark = dark | np.roll(dark, 1, axis=0) | np.roll(dark, -1, axis=0)  # thin needle between two rays
    run = np.cumsum(dark, axis=1) / np.arange(1, len(radii) + 1)
    ok = (run >= 0.8) & dark
    reach = np.where(ok.any(axis=1), len(radii) - 1 - np.argmax(ok[:, ::-1], axis=1), 0) / (len(radii) - 1)
    near = lambda m: reach[np.arange(m - 4, m + 5) % 720].max()
    if near(j) > near(i) + 0.1:
        i = j

    # refine the peak with a weighted average
    idx = np.arange(i - 4, i + 5) % len(angles)
    w = score[idx] - score.min()
    offs = np.arange(-4, 5) * 0.5
    refined = angles[i] + (np.sum(w * offs) / np.sum(w) if w.sum() > 0 else 0)
    confidence = float((score[i] - np.median(score)) / (score.std() + 1e-6))
    return refined % 360, confidence, float(cx), float(cy)


def find_needle_angle(gray, cx, cy, r):
    """(angle, confidence) of the needle; see find_needle()."""
    angle, conf, _, _ = find_needle(gray, cx, cy, r)
    return angle, conf


def angle_to_value(angle, spec):
    sweep = (spec.max_angle - spec.min_angle) % 360 or 360
    rel = (angle - spec.min_angle) % 360
    if rel > sweep:  # needle in the dead zone: snap to the nearer end stop
        rel = sweep if (rel - sweep) < (360 - rel) else 0.0
    frac = rel / sweep
    return spec.min_value + frac * (spec.max_value - spec.min_value)


# --------------------------------------------------------------- reading ----

@dataclass
class Reading:
    source: str
    type: str | None  # pressure, temperature, ... or None if unknown
    value: float | None
    unit: str  # "" if unknown
    scale_min: float | None = None
    scale_max: float | None = None
    labels_read: int = 0
    conversions: dict = field(default_factory=dict)
    second_scale: dict | None = None  # {"value":..., "unit":...} on dual gauges
    needle_angle: float | None = None
    needle_confidence: float = 0.0
    mode: str = "auto"
    status: str = "OK"
    notes: list = field(default_factory=list)
    decimals: int = 2
    label: str = ""  # name plate text ("PI-40 FUEL OIL PRESSURE") or the gauge type
    confidence: float = 0.0  # 0..1, how much to trust this reading
    gauge_bounds: dict | None = None  # {"x","y","w","h"} of the dial, in the original photo's pixels
    processing_time_ms: int = 0
    gauge_index: int = 1  # which gauge in the photo (reading order), when there are several
    gauge_count: int = 1

    def to_json(self):
        """The result as a JSON-ready dict: the main fields first, details after."""
        out = {
            "label": self.label,
            "value": None if self.value is None else f"{self.value:.{self.decimals}f}",
            "unit": self.unit,
            "confidence": self.confidence,
            "needle_angle": self.needle_angle,
            "gauge_bounds": self.gauge_bounds,
            "processing_time_ms": self.processing_time_ms,
            "file": self.source,
            "gauge_index": self.gauge_index,
            "gauge_count": self.gauge_count,
            "type": self.type,
            "status": self.status,
            "scale_min": self.scale_min,
            "scale_max": self.scale_max,
            "conversions": {u: round(v, 4) for u, v in self.conversions.items()},
            "notes": self.notes,
        }
        if self.second_scale:
            out["second_scale"] = {"value": round(self.second_scale["value"], 4), "unit": self.second_scale["unit"]}
        return out

    def fmt(self, v, unit, decimals=None):
        d = self.decimals if decimals is None else decimals
        return f"{round(v, d) + 0.0:.{d}f} {display_unit(unit)}".strip()  # + 0.0: no "-0.00"

    def fmt_converted(self, v, unit):
        """Converted values get ~4 significant digits of their own."""
        mag = math.floor(math.log10(abs(v))) if v else 0
        return self.fmt(v, unit, min(3, max(0, 3 - mag)))

    def __str__(self):
        kind = GAUGE_TYPES[self.type]["label"] if self.type else "Unknown type"
        head = self.source + (f"  (gauge {self.gauge_index} of {self.gauge_count})" if self.gauge_count > 1 else "")
        lines = [head]
        if self.label:
            lines.append(f"  Label      : {self.label}")
        if self.value is None:
            lines.append(f"  Result     : could not read gauge")
        else:
            lines.append(f"  Gauge type : {kind}")
            lines.append(f"  Reading    : {self.fmt(self.value, self.unit)}")
            lines.append(f"  Confidence : {self.confidence:.2f}")
            if self.second_scale:
                lines.append(f"  2nd scale  : {self.fmt_converted(self.second_scale['value'], self.second_scale['unit'])}")
            if self.conversions:
                lines.append("  Also       : " + ", ".join(self.fmt_converted(v, u) for u, v in self.conversions.items()))
            if self.scale_min is not None:
                src = f"{self.labels_read} numbers read" if self.mode == "auto" else self.mode
                lines.append(f"  Scale      : {self.scale_min:g} to {self.scale_max:g} {display_unit(self.unit)}  ({src})")
        if self.needle_angle is not None:
            lines.append(f"  Needle     : {self.needle_angle:.1f} deg (clockwise from 6 o'clock)")
        if self.gauge_bounds:
            b = self.gauge_bounds
            lines.append(f"  Gauge at   : x={b['x']} y={b['y']} w={b['w']} h={b['h']} px")
        lines.append(f"  Time       : {self.processing_time_ms} ms")
        lines.append(f"  Status     : {self.status}")
        for n in self.notes:
            lines.append(f"  Note       : {n}")
        return "\n".join(lines)


def _bounds(cx, cy, r, factor, orig_shape):
    """Dial box in the ORIGINAL photo's pixels (we work on a resized copy)."""
    h, w = orig_shape[:2]
    x0, y0 = max((cx - r) / factor, 0), max((cy - r) / factor, 0)
    x1, y1 = min((cx + r) / factor, w), min((cy + r) / factor, h)
    return {"x": int(round(x0)), "y": int(round(y0)), "w": int(round(x1 - x0)), "h": int(round(y1 - y0))}


def _confidence(needle_conf, labels_read, rms_deg=0.0, has_unit=True, extrapolated=False, known_scale=False):
    """0..1 trust in a reading, from how clearly the needle stands out, how
    well the scale was established, and whether the unit is known."""
    c_needle = min(1.0, max(0.0, (needle_conf - 2) / 8))
    if known_scale:
        c_scale = 1.0
    else:
        c_scale = {0: 0.0, 1: 0.0, 2: 0.55, 3: 0.75, 4: 0.85}.get(labels_read, 0.95)
        c_scale *= max(0.5, 1 - rms_deg / 8)
    c = math.sqrt(c_needle) * c_scale * (1.0 if has_unit else 0.75) * (0.85 if extrapolated else 1.0)
    return round(c, 2)


def _default_label(gtype):
    return f"{GAUGE_TYPES[gtype]['label']} Gauge" if gtype else "Gauge"


def _decimals(lo, hi):
    span = abs(hi - lo) or 1
    return max(0, math.ceil(-math.log10(span / 200)))


def _conversions(value, gtype, unit, extra=None):
    if not gtype or not unit:
        return {}
    wanted = extra if extra is not None else DEFAULT_SHOW_ALSO.get(gtype, [])
    out = {}
    for u in wanted:
        if u != unit and u in GAUGE_TYPES[gtype]["units"]:
            out[u] = convert(value, gtype, unit, u)
    return out


def _scales_agree(s1, u1, s2, u2, gtype):
    """Do two scales read the same quantity in units u1 / u2?"""
    try:
        errs = []
        for ang in np.linspace(s1.start_angle, s1.start_angle + ((s1.end_angle - s1.start_angle) % 360), 5):
            v1, ok1 = s1.read(ang % 360)
            v2, ok2 = s2.read(ang % 360)
            if ok1 and ok2:
                errs.append(abs(convert(v1, gtype, u1, u2) - v2))
        span2 = (s2.v_max - s2.v_min) or 1
        return len(errs) >= 2 and max(errs) / span2 < 0.06
    except ValueError:
        return False


def _units_from_other_ring(dial, main, cands, votes, center):
    """Find (main_unit, other_unit) for a dual-unit dial, or None.

    Every number that is not part of the main scale is checked: if it equals
    the main scale's value at that angle converted from unit A to unit B,
    it supports "main ring is A, other ring is B"."""
    from scale_fit import dial_angle

    cx, cy = center
    used = {id(lb) for lb in main.labels}
    strays = [lb for lb in dial.labels if id(lb) not in used]
    types = {c[0] for c in cands if c[0]} or set()
    if dial.temperature_word:
        types.add("temperature")
    seen = {c[1] for c in cands}
    best = None
    for t in types:
        units = list(GAUGE_TYPES[t]["units"])
        for ua in units:
            for ub in units:
                if ua == ub or (ua not in seen and ub not in seen):
                    continue  # at least one of the two must be printed on the dial
                lo, hi = convert(main.v_min, t, ua, ub), convert(main.v_max, t, ua, ub)
                tol = 0.03 * abs(hi - lo)
                hits = {}
                for lb in strays:
                    v, on = main.read(dial_angle(lb.x, lb.y, cx, cy))
                    if on and abs(convert(v, t, ua, ub) - lb.value) <= tol:
                        hits[lb.value] = max(hits.get(lb.value, 0), lb.conf)
                if not hits:
                    continue
                support = sum(hits.values())  # confident readings count more
                score = support + 0.5 * (ua in seen) + 0.5 * (ub in seen) + 0.1 * votes.get((t, ua), 0)
                if best is None or score > best[0]:
                    best = (score, (t, ua), (t, ub), support)
    # one matching number is enough only if both units are printed on the dial
    if best and (best[3] >= 1.5 or (best[1][1] in seen and best[2][1] in seen and best[3] >= 0.5)):
        return best[1], best[2]
    return None


def _pick_units(dial, scales, unit_override=None, type_override=None, center=(0, 0)):
    """Return [(type, unit)] for each scale (unit may be "")."""
    # sum the evidence for every unit seen on the dial
    votes = {}
    for h in dial.units:
        votes[(h.type, h.unit)] = votes.get((h.type, h.unit), 0) + h.score
    cands = sorted(votes, key=lambda k: -votes[k])
    if unit_override:
        gtype = type_override or next((t for t in GAUGE_TYPES if unit_override in GAUGE_TYPES[t]["units"]
                                       or _try_norm(t, unit_override)), None)
        if gtype is None:
            raise SystemExit(f"--unit '{unit_override}' is not a known unit")
        cands = [(gtype, normalize_unit(gtype, unit_override))] + [c for c in cands if c[0] == gtype]
    elif type_override:
        cands = [c for c in cands if c[0] == type_override] or [(type_override, "")]

    # drop weak single-letter guesses when a stronger unit exists
    if cands and votes.get(cands[0], 99) >= 1.5:
        cands = [c for c in cands if votes.get(c, 99) >= 0.6]

    if scales and not unit_override:
        # 1) Dual-unit dials (°C + °F, bar + MPa): numbers of the other ring
        #    sit where the main scale's value, converted, would be.  Try each
        #    unit pair and keep the one those stray numbers agree with.
        pair = _units_from_other_ring(dial, scales[0], cands, votes, center)
        if pair:
            main, other = pair
            if len(scales) == 2:
                return [main, other if _scales_agree(scales[0], main[1], scales[1], other[1], main[0]) else (main[0], "")]
            return [main]
        # 2) Otherwise, among similarly likely units, the one printed in the
        #    same colour as the main scale's numbers wins.
        if cands:
            inks = {}
            for h in dial.units:
                k = (h.type, h.unit)
                if k not in inks or h.score > inks[k][0]:
                    inks[k] = (h.score, h.ink)
            si = tuple(np.median([lb.ink[i] for lb in scales[0].labels]) for i in range(3))

            def chroma(c):  # colour difference to the main scale's numbers
                ink = inks[c][1]
                return math.hypot(ink[1] - si[1], ink[2] - si[2])

            top = votes.get(cands[0], 0)
            close = [c for c in cands if c[0] == cands[0][0] and votes.get(c, 0) >= top / 3 and c in inks]
            if close:
                best = min(close, key=chroma)
                cands = [best] + [c for c in cands if c != best]
                # 3) Thermometers often carry a red °F ring around a black °C
                #    one.  If the only unit found is °C/°F printed in another
                #    colour than the main numbers, it labels the other ring.
                #    (Not for other units: an aged, yellowed dial shifts colours
                #    a little, and a lone "MPa" or "bar" is the gauge's unit.)
                t, u = best
                if t == "temperature" and u in ("C", "F") and chroma(best) > 6:
                    cands = [(t, "F" if u == "C" else "C")]

    if len(scales) == 2 and cands:
        gtype = cands[0][0]
        same = [c[1] for c in cands if c[0] == gtype and c[1]]
        all_units = list(GAUGE_TYPES[gtype]["units"]) if gtype else []
        # 1) both units printed: which goes with which ring?
        for ua in same:
            for ub in same:
                if ua != ub and _scales_agree(scales[0], ua, scales[1], ub, gtype):
                    return [(gtype, ua), (gtype, ub)]
        # 2) one unit printed: infer the other ring's unit from the ratio
        for known in same[:1]:
            for other in all_units:
                if other == known:
                    continue
                if _scales_agree(scales[0], known, scales[1], other, gtype):
                    return [(gtype, known), (gtype, other)]
                if _scales_agree(scales[1], known, scales[0], other, gtype):
                    return [(gtype, other), (gtype, known)]
        return [cands[0], (gtype, "")]

    first = cands[0] if cands else (type_override, "")
    return [first] + [(first[0], "")] * (len(scales) - 1)


def _try_norm(t, u):
    try:
        normalize_unit(t, u)
        return True
    except ValueError:
        return False


def _center_from_labels(labels, cx, cy, r):
    """Circle through the label positions (needs >= 4 labels spread over at
    least half the dial).  Returns the new centre, or None if not trustworthy."""
    if len(labels) < 4:
        return None
    pts = np.array([(lb.x, lb.y) for lb in labels], float)
    angs = np.sort(np.degrees(np.arctan2(pts[:, 1] - cy, pts[:, 0] - cx)) % 360)
    gaps = np.diff(np.r_[angs, angs[0] + 360])
    if 360 - gaps.max() < 150:  # labels too bunched together
        return None
    # algebraic (Kasa) circle fit: x^2 + y^2 + D x + E y + F = 0
    A = np.c_[pts, np.ones(len(pts))]
    b = -(pts ** 2).sum(axis=1)
    (D, E, F), *_ = np.linalg.lstsq(A, b, rcond=None)
    nx, ny = -D / 2, -E / 2
    rad = math.sqrt(max(nx * nx + ny * ny - F, 0))
    resid = np.abs(np.hypot(pts[:, 0] - nx, pts[:, 1] - ny) - rad)
    # The circle may be a fair way from the rim's centre (a recess or bezel
    # mistaken for the dial, a photo taken a little from the side), as long
    # as the numbers sit cleanly on it.
    if math.hypot(nx - cx, ny - cy) > 0.25 * r or resid.max() > 0.06 * r or not 0.2 * r < rad < 1.2 * r:
        return None
    return float(nx), float(ny)


def read_all(image, source="", debug_path=None, **kw):
    """Read every gauge in the photo.  Returns a list of Readings in reading
    order (top to bottom, left to right); one entry if there is one gauge."""
    t_start = time.perf_counter()
    prepared = prepare(image)
    gray = cv2.cvtColor(prepared, cv2.COLOR_BGR2GRAY) if prepared.ndim == 3 else prepared
    color = prepared if prepared.ndim == 3 else cv2.cvtColor(prepared, cv2.COLOR_GRAY2BGR)
    dials, text = find_gauges(color, gray, return_text=True)
    hint = lambda d: _temperature_nearby(text.words, *d)
    # units the whole-photo pass saw on each gauge (a tiny "MPa" is sometimes
    # read there but not in the gauge's own passes)
    units_on = lambda d: [u for u in text.units if math.hypot(u.x - d[0], u.y - d[1]) < 0.8 * d[2]]
    # a gauge's number ring, if it was already read unrolled while finding the gauges
    ring_of = lambda d: next((rg for x, y, rg in text.rings or [] if math.hypot(x - d[0], y - d[1]) < 0.1 * d[2]), None)
    if len(dials) <= 1:
        d = dials[0] if dials else None
        rd = read_auto(image, source, debug_path, at=d, temperature_hint=bool(d) and hint(d),
                       extra_units=units_on(d) if d else [], ring_text=ring_of(d) if d else None, **kw)
        rd.processing_time_ms = int(round((time.perf_counter() - t_start) * 1000))
        return [rd]

    readings = [read_auto(image, source, None, at=d, temperature_hint=hint(d), extra_units=units_on(d),
                          ring_text=ring_of(d), **kw)
                for d in dials]
    good = [rd for rd in readings if rd.value is not None] or readings[:1]
    for i, rd in enumerate(good, 1):
        rd.gauge_index, rd.gauge_count = i, len(good)
    if debug_path:
        canvas = color.copy()
        for rd in good:
            _draw_debug(color, None, *rd._debug, rd, canvas=canvas)
        cv2.imwrite(str(debug_path), canvas)
    total = int(round((time.perf_counter() - t_start) * 1000))
    for rd in good:
        rd.processing_time_ms = total  # the whole photo; the gauges share the work
    return good


def read_auto(image, source="", debug_path=None, unit=None, gtype=None, value_range=None, angles=None,
              label=None, read_label=True, at=None, temperature_hint=False, extra_units=(), ring_text=None):
    """Read one gauge with no prior knowledge of it: the most prominent one,
    or the one at `at` = (cx, cy, r) in prepare()d-image pixels.  `label`
    sets the label; otherwise it is read off the name plate (unless
    read_label=False).  `temperature_hint`: a temperature word was seen next
    to the gauge (e.g. on its plate).  `extra_units`: unit words another OCR
    pass found on this gauge.  `ring_text`: its number ring, already read
    unrolled (see find_gauges)."""
    from dial_ocr import PASSES as OCR_PASSES
    from dial_ocr import merge as merge_text
    from dial_ocr import read_dial_text, read_plate_label, read_ring_text
    from scale_fit import fit_scales

    t_start = time.perf_counter()
    orig_shape = image.shape
    image = prepare(image)
    factor = image.shape[1] / orig_shape[1]
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if image.ndim == 3 else image
    cx, cy, r = at if at else find_dial(gray)
    ngray, _ = needle_view(gray, cx, cy, r)

    color = image if image.ndim == 3 else cv2.cvtColor(image, cv2.COLOR_GRAY2BGR)
    notes = []
    # Read the dial; if the scale isn't clear yet, read it again larger and
    # contrast-boosted, and pool what all the passes found.
    dial, scales = None, []
    for size, enhanced in OCR_PASSES:
        text = read_dial_text(color, cx, cy, r, size=size, enhanced=enhanced)
        dial = text if dial is None else merge_text(dial, text, r)
        scales = fit_scales(dial.labels, cx, cy, r)
        if scales and len(scales[0].labels) >= 5 and (dial.units or unit):
            break
    # Still unclear - few numbers, or the needle points away from all of
    # them (then even which end to extend the scale from is a guess): the
    # numbers may be printed turned to follow the circle (refrigerant gauges,
    # say), which OCR mostly misses.  Read their ring again, unrolled so they
    # stand upright.
    if not (scales and len(scales[0].labels) >= 5
            and scales[0].read(find_needle_angle(ngray, cx, cy, r)[0])[1]):
        if ring_text is None:
            rho = _number_ring(dial.labels, cx, cy, r)
            ring_text = read_ring_text(color, cx, cy, rho) if rho else None
        if ring_text is not None:
            # numbers only: a unit out in that band may belong to an outer
            # second ring (the red °F round a thermometer's °C, say)
            dial = merge_text(dial, replace(ring_text, units=[]), r)
            scales = fit_scales(dial.labels, cx, cy, r)
    # The scale numbers sit on a ring around the pivot: fitting a circle
    # through them pins the pivot down better than the rim does.
    for _ in range(2):
        new = _center_from_labels(scales[0].labels, cx, cy, r) if scales else None
        if new is None:
            break
        cx, cy = new
        scales = fit_scales(dial.labels, cx, cy, r)
    for u in extra_units:  # add units another pass saw, unless already found here
        if not any(h.unit == u.unit and math.hypot(h.x - u.x, h.y - u.y) < 0.1 * r for h in dial.units):
            dial.units.append(u)
    ngray, _ = needle_view(gray, cx, cy, r)  # judged around the final pivot
    angle, conf = find_needle_angle(ngray, cx, cy, r)
    if scales and scales[0].piecewise:  # uneven scale: fill gaps from the ticks
        _fill_from_ticks(scales[0], _needle_contrast(ngray, cx, cy, r), cx, cy, r, needle=angle)
        from_ticks = [lb.value for lb in scales[0].labels if lb.text.endswith("(tick)")]
        notes.append("uneven scale: read between neighbouring marks"
                     + (f"; {', '.join(f'{v:g}' for v in from_ticks)} worked out from the tick marks" if from_ticks else ""))

    if dial.multiplier != 1 and scales:
        for s in scales[:1]:
            s.slope *= dial.multiplier
            s.offset *= dial.multiplier
        notes.append(f"scale multiplier x{dial.multiplier:g} applied")

    reading = Reading(source=source, type=None, value=None, unit="", needle_angle=round(angle, 2),
                      needle_confidence=round(conf, 2), notes=notes)

    if value_range:  # user told us the range: trust it over OCR
        lo, hi = value_range
        a0, a1 = angles or ((scales[0].start_angle, scales[0].end_angle) if scales else (45, 315))
        spec = GaugeSpec("manual", "level", "%", lo, hi, a0, a1)
        val = angle_to_value(angle, spec)
        units_ = _pick_units(dial, [], unit, gtype)
        reading.type, reading.unit = units_[0]
        reading.value, reading.scale_min, reading.scale_max = val, lo, hi
        reading.mode = "range given on command line"
        reading.decimals = _decimals(lo, hi)
    elif scales:
        units_ = _pick_units(dial, scales, unit, gtype, center=(cx, cy))
        main = scales[0]
        val, on_scale = main.read(angle)
        reading.type, reading.unit = units_[0]
        reading.value = val
        # report the numbers actually printed on the dial, not the fitted line
        printed = [lb.value * dial.multiplier for lb in main.labels]
        reading.scale_min, reading.scale_max = min(printed), max(printed)
        reading.labels_read = len(main.labels)
        reading.decimals = _decimals(main.v_min, main.v_max)
        if not on_scale:
            # either the needle is past the end stop, or OCR missed the end numbers
            notes.append("needle is beyond the numbers that could be read (value extrapolated)")
        if len(scales) > 1:
            v2, _ = scales[1].read(angle)
            reading.second_scale = {"value": v2, "unit": units_[1][1]}
        if main.rms_deg > 3:
            notes.append(f"scale numbers fit loosely ({main.rms_deg:.1f} deg) - check the debug image")
        if len(main.labels) == 2:
            notes.append("scale worked out from only 2 numbers (" + " and ".join(f"{lb.value:g}" for lb in main.labels)
                         + ") - check the debug image")
    else:
        reading.status = "could not read the scale numbers"
        notes.append("try a sharper, straight-on photo, or pass --range MIN MAX (and --unit)")
        found = ", ".join(t for t, _ in dial.raw[:12]) or "nothing"
        notes.append(f"text found on dial: {found}")

    # vacuum gauges: pressure units with a scale at or below zero, or the word "vacuum"
    if reading.type == "pressure" and (dial.vacuum_word or (reading.scale_max is not None and reading.scale_max <= 0)):
        if reading.unit in GAUGE_TYPES["vacuum"]["units"] or not reading.unit:
            reading.type = "vacuum"
    is_thermometer = dial.temperature_word or temperature_hint
    if reading.type is None and is_thermometer:
        reading.type = "temperature"

    # No unit readable on a thermometer (the °C is often tiny): assume °C,
    # unless some non-temperature unit was seen on the dial.
    other_units = {h.type for h in dial.units} - {"temperature"}
    if (reading.value is not None and not reading.unit and not unit and reading.type == "temperature"
            and is_thermometer and not other_units):
        reading.unit = "C"
        why = "dial says THERMOMETER" if dial.temperature_word else "a temperature label is next to the gauge"
        notes.append(f"unit not readable - °C assumed ({why})")

    if reading.value is not None:
        if not reading.unit:
            notes.append("unit not found on the dial - pass --unit (e.g. --unit bar)")
        reading.conversions = _conversions(reading.value, reading.type, reading.unit)
        if reading.second_scale:  # already shown, read straight off its own scale
            reading.conversions.pop(reading.second_scale["unit"], None)
    if conf < 2.0:
        msg = "needle unclear - check the debug image"
        reading.status = msg if reading.status == "OK" else f"{reading.status} / {msg}"

    if reading.value is not None:
        extrapolated = any("extrapolated" in n for n in notes)
        known = bool(value_range)
        reading.confidence = _confidence(conf, reading.labels_read, scales[0].rms_deg if scales else 0.0,
                                         bool(reading.unit), extrapolated, known_scale=known)
        if reading.confidence < LOW_CONFIDENCE:
            msg = "LOW CONFIDENCE - reading may be wrong, check the debug image"
            reading.status = msg if reading.status == "OK" else f"{reading.status} / {msg}"
    reading.gauge_bounds = _bounds(cx, cy, r, factor, orig_shape)
    plate = label or (read_plate_label(color, cx, cy, r) if read_label else "")
    reading.label = plate or _default_label(reading.type)

    reading._debug = (cx, cy, r, angle, dial, scales)
    if debug_path:
        _draw_debug(color, debug_path, cx, cy, r, angle, dial, scales, reading)
    reading.processing_time_ms = int(round((time.perf_counter() - t_start) * 1000))
    return reading


def read_gauge(image, spec, debug_path=None, source="", label=None):
    """Read a gauge described by a gauges.yaml entry (no OCR needed)."""
    t_start = time.perf_counter()
    orig_shape = image.shape
    image = prepare(image) if spec.center is None else image
    factor = image.shape[1] / orig_shape[1]
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if image.ndim == 3 else image
    cx, cy, r = find_dial(gray, spec.center, spec.radius)
    ngray, _ = needle_view(gray, cx, cy, r)
    angle, conf = find_needle_angle(ngray, cx, cy, r)
    value = angle_to_value(angle, spec)

    status = "OK"
    if spec.warn_below is not None and value < spec.warn_below:
        status = "LOW"
    if spec.warn_above is not None and value > spec.warn_above:
        status = "HIGH"
    if conf < 2.0:
        status += " / needle unclear - check the debug image"

    reading = Reading(
        source=source or spec.name, type=spec.type, value=value, unit=spec.unit,
        scale_min=spec.min_value, scale_max=spec.max_value,
        conversions=_conversions(value, spec.type, spec.unit, spec.show_also or None),
        needle_angle=round(angle, 2), needle_confidence=round(conf, 2),
        mode=f"from gauges.yaml '{spec.name}'", status=status, decimals=spec.decimals,
        label=label or spec.name.replace("_", " ").title(),
        confidence=_confidence(conf, 0, known_scale=True),
        gauge_bounds=_bounds(cx, cy, r, factor, orig_shape),
    )
    if debug_path:
        color = image if image.ndim == 3 else cv2.cvtColor(image, cv2.COLOR_GRAY2BGR)
        _draw_debug(color, debug_path, cx, cy, r, angle, None, [], reading,
                    end_angles=(spec.min_angle, spec.max_angle))
    reading.processing_time_ms = int(round((time.perf_counter() - t_start) * 1000))
    return reading


def _ray(cx, cy, ang, rad):
    t = math.radians(ang)
    return int(cx - math.sin(t) * rad), int(cy + math.cos(t) * rad)


def _draw_debug(image, path, cx, cy, r, angle, dial, scales, reading, end_angles=None, canvas=None):
    """Mark up what was found.  With `canvas`, draw onto it (several gauges in
    one photo) and label the value beside the gauge instead of writing a file."""
    dbg = image.copy() if canvas is None else canvas
    cv2.circle(dbg, (int(cx), int(cy)), int(r), (0, 200, 0), 2)
    cv2.circle(dbg, (int(cx), int(cy)), 4, (0, 200, 0), -1)
    if dial:
        used = {id(lb) for s in scales for lb in s.labels}
        for (x0, y0, x1, y1) in dial.boxes:
            cv2.rectangle(dbg, (int(x0), int(y0)), (int(x1), int(y1)), (200, 200, 200), 1)
        for lb in dial.labels:
            col = (0, 170, 0) if id(lb) in used else (0, 0, 255)  # green = used, red = ignored
            cv2.circle(dbg, (int(lb.x), int(lb.y)), 5, col, -1)
    if scales:
        end_angles = (scales[0].start_angle, scales[0].end_angle)
    if end_angles:
        cv2.line(dbg, (int(cx), int(cy)), _ray(cx, cy, end_angles[0], r), (255, 0, 0), 1)
        cv2.line(dbg, (int(cx), int(cy)), _ray(cx, cy, end_angles[1], r), (0, 0, 255), 1)
    cv2.line(dbg, (int(cx), int(cy)), _ray(cx, cy, angle, r * 0.9), (0, 255, 255), 3)
    txt = "?" if reading.value is None else reading.fmt(reading.value, reading.unit).replace("°", "deg ")
    if canvas is not None:
        txt = f"{reading.gauge_index}: {txt}"
        org = (max(int(cx - r), 5), max(int(cy - r) - 10, 30))
    else:
        org = (10, 34)
    cv2.putText(dbg, txt, org, cv2.FONT_HERSHEY_SIMPLEX, 1.0, (255, 255, 255), 5)
    cv2.putText(dbg, txt, org, cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 0, 200), 2)
    if canvas is None:
        cv2.imwrite(str(path), dbg)


# ------------------------------------------------------------------- CLI ----

def _expand(paths):
    out = []
    for p in paths:
        pp = Path(p)
        if pp.is_dir():
            out += sorted(str(f) for f in pp.iterdir() if f.suffix.lower() in IMAGE_EXTS)
        elif any(c in p for c in "*?["):
            out += sorted(glob.glob(p))
        else:
            out.append(p)
    return out


def main(argv=None):
    p = argparse.ArgumentParser(description="Read any analog gauge from a photo.")
    p.add_argument("images", nargs="*", help="photo(s), folder(s) or wildcards")
    p.add_argument("--gauge", "-g", help="use this gauges.yaml entry instead of reading the dial")
    p.add_argument("--config", "-c", default=str(DEFAULT_CONFIG))
    p.add_argument("--unit", "-u", help="unit, if it isn't printed on the dial (bar, psi, C, ...)")
    p.add_argument("--type", "-t", choices=list(GAUGE_TYPES), help="gauge type, if it can't be told from the unit")
    p.add_argument("--range", nargs=2, type=float, metavar=("MIN", "MAX"), help="scale range, if numbers can't be read")
    p.add_argument("--angles", nargs=2, type=float, metavar=("MIN_ANGLE", "MAX_ANGLE"),
                   help="needle angles at MIN and MAX (with --range; default 45 315)")
    p.add_argument("--label", "-l", help="label for the result(s), instead of reading the name plate")
    p.add_argument("--no-label", action="store_true", help="don't read the name plate (faster)")
    p.add_argument("--debug", "-d", help="write a marked-up image (a folder when reading several images)")
    p.add_argument("--json", action="store_true", help="print JSON instead of text")
    p.add_argument("--list", action="store_true", help="list gauges in gauges.yaml")
    args = p.parse_args(argv)

    gauges = load_config(args.config)
    if args.list:
        for name, s in gauges.items():
            print(f"{name:20s} {s.type:12s} {s.min_value:g}..{s.max_value:g} {display_unit(s.unit)}")
        return 0
    files = _expand(args.images)
    if not files:
        p.error("give at least one image (or --list)")
    if args.gauge and args.gauge not in gauges:
        p.error(f"unknown gauge '{args.gauge}' (use --list)")

    results, failed = [], 0
    for f in files:
        img = cv2.imread(f)
        if img is None:
            print(f"{f}\n  Status     : cannot open this file as an image", file=sys.stderr)
            failed += 1
            continue
        dbg = None
        if args.debug:
            if len(files) > 1:
                Path(args.debug).mkdir(parents=True, exist_ok=True)
                dbg = Path(args.debug) / f"{Path(f).stem}_debug.png"
            else:
                dbg = args.debug
        try:
            if args.gauge:
                found = [read_gauge(img, gauges[args.gauge], dbg, source=f, label=args.label)]
            else:  # every gauge in the photo
                found = read_all(img, f, dbg, unit=args.unit, gtype=args.type,
                                 value_range=args.range, angles=args.angles,
                                 label=args.label, read_label=not args.no_label)
        except Exception as e:  # keep going with the other images
            print(f"{f}\n  Status     : error: {e}", file=sys.stderr)
            failed += 1
            continue
        for rd in found:
            failed += rd.value is None
            results.append(rd)
            if not args.json:
                print(rd, end="\n\n")

    if args.json:
        print(json.dumps([r.to_json() for r in results], indent=2, ensure_ascii=False))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
