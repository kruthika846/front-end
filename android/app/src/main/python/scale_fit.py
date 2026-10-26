"""Work out a gauge's scale from the numbers printed on it.

Every scale label gives one (angle, value) pair.  A robust (RANSAC) fit finds
the straight line  value = slope * angle + offset  that most labels agree on,
so stray numbers (brand names, "EN 837-1", "Class 1.6") are ignored.  It
works whether the scale runs clockwise or anticlockwise, and finds a second
ring of numbers on dual-scale gauges (e.g. bar inside, psi outside).

Angles use the same convention as gauge_reader: degrees clockwise from 6 o'clock.
"""

import itertools
import math
from dataclasses import dataclass

import numpy as np


def dial_angle(x, y, cx, cy):
    return math.degrees(math.atan2(-(x - cx), (y - cy))) % 360


def wrap180(a):
    return (a + 180) % 360 - 180


@dataclass
class Scale:
    slope: float  # value per degree (unwrapped)
    offset: float
    u_min: float  # unwrapped angle range covered by the labels
    u_max: float
    labels: list  # inlier Label objects
    angles: list  # their unwrapped angles
    radius: float  # mean label distance from centre / r
    rms_deg: float
    # Uneven scales (AC moving-iron meters squeeze the low end): read
    # between the two nearest printed numbers instead of along one line.
    piecewise: bool = False

    @property
    def v_min(self):
        return min(self.value_at(self.u_min), self.value_at(self.u_max))

    @property
    def v_max(self):
        return max(self.value_at(self.u_min), self.value_at(self.u_max))

    @property
    def start_angle(self):
        """Dial angle of the lowest value on the scale."""
        u = self.u_min if self.slope > 0 else self.u_max
        return u % 360

    @property
    def end_angle(self):
        u = self.u_max if self.slope > 0 else self.u_min
        return u % 360

    def value_at(self, u):
        return self.slope * u + self.offset

    def unwrap(self, angle):
        """Pick the turn of `angle` (±360) that lies on, or nearest, the scale."""
        best, dist = None, None
        for k in range(-2, 3):
            u = angle + 360 * k
            d = 0.0 if self.u_min <= u <= self.u_max else min(abs(u - self.u_min), abs(u - self.u_max))
            if dist is None or d < dist:
                best, dist = u, d
        return best

    def read(self, needle_angle):
        u = self.unwrap(needle_angle)
        on = self.u_min - 3 <= u <= self.u_max + 3
        if not self.piecewise:
            return self.value_at(u), on
        us, vs = self._points()
        if us[0] <= u <= us[-1]:
            return float(np.interp(u, us, vs)), on
        # beyond the printed numbers: carry on from the nearest end at the
        # average slope
        end = 0 if u < us[0] else -1
        return float(vs[end] + self.slope * (u - us[end])), on

    def _points(self):
        """(angle, value) of the printed numbers, in angle order."""
        pts = sorted(zip(self.angles, (lb.value for lb in self.labels)))
        return np.array([p[0] for p in pts]), np.array([p[1] for p in pts])


def nice_step(values):
    """Largest 'nice' step (1, 2, 2.5 or 5 x 10^k) that every value is a
    multiple of, or None."""
    vals = sorted(values)
    span = vals[-1] - vals[0]
    if span <= 0:
        return None
    for k in range(int(math.floor(math.log10(span))), -4, -1):
        for m in (5, 2.5, 2, 1):
            s = m * 10 ** k
            if s > span:
                continue
            if all(abs(v / s - round(v / s)) < 0.02 for v in vals):
                return s
    return None


def plausible_values(values):
    """Printed scale numbers go up in even steps (0 2 4 6, or 20 40 60 ...).
    Reject sets like {0.3, 3, 8} that only line up by accident."""
    vals = sorted(values)
    s = nice_step(vals)
    # a dial carries roughly 4-16 numbered marks over its range
    return s is not None and s >= (vals[-1] - vals[0]) / 20


def _one_per_spot(inl, r):
    """OCR passes may offer several readings for one printed number ("6",
    "9"); use only the best-fitting one."""
    kept = []
    for p in sorted(inl, key=lambda p: abs(p[4])):
        if all(math.hypot(p[3].x - q[3].x, p[3].y - q[3].y) > 0.05 * r for q in kept):
            kept.append(p)
    return kept


def _same_ring(inl, max_dr=0.1, max_chroma=30):
    """Numbers of one scale are printed at the same distance from the centre
    and in the same colour.  Drop those that aren't (they belong to another
    scale on a dual-scale gauge, or are stray numbers)."""
    d_med = np.median([p[2] for p in inl])
    a_med = np.median([p[3].ink[1] for p in inl])
    b_med = np.median([p[3].ink[2] for p in inl])
    return [p for p in inl
            if abs(p[2] - d_med) <= max_dr and math.hypot(p[3].ink[1] - a_med, p[3].ink[2] - b_med) <= max_chroma]


def fit_scale(labels, cx, cy, r, tol_deg=6.0, min_inliers=3):
    """Best single scale through `labels`, or None."""
    pts = []
    for lb in labels:
        d = math.hypot(lb.x - cx, lb.y - cy) / r
        if 0.18 <= d <= 1.15:
            pts.append((dial_angle(lb.x, lb.y, cx, cy), lb.value, d, lb))
    if len(pts) < min_inliers:
        return None

    best = None
    for (t1, v1, _, _), (t2, v2, _, _) in itertools.combinations(pts, 2):
        if v1 == v2:
            continue
        cw = (t2 - t1) % 360
        for d in (cw, cw - 360):  # clockwise or anticlockwise between them
            if abs(d) < 8:
                continue
            a = (v2 - v1) / d
            inl = []
            for t, v, dist, lb in pts:
                u_pred = t1 + (v - v1) / a
                err = wrap180(t - u_pred)
                if abs(err) <= tol_deg:
                    inl.append((u_pred + err, v, dist, lb, err))
            if len(inl) < min_inliers:
                continue
            inl = _same_ring(_one_per_spot(inl, r))
            if len(inl) < min_inliers:
                continue
            us = [p[0] for p in inl]
            if max(us) - min(us) > 355:  # a scale can't wrap all the way round
                continue
            # one label per value: keep the closest if OCR read a number twice
            vals = [p[1] for p in inl]
            if len(set(vals)) < min_inliers or not plausible_values(set(vals)):
                continue
            score = (len(set(vals)), -sum(e * e for *_, e in inl))
            if best is None or score > best[0]:
                best = (score, inl)

    if best is None:
        return None
    inl = best[1]
    u = np.array([p[0] for p in inl])
    v = np.array([p[1] for p in inl])
    slope, offset = np.polyfit(u, v, 1)
    resid = (v - (slope * u + offset)) / slope
    rms = float(np.sqrt(np.mean(resid ** 2)))
    scale = Scale(
        slope=float(slope), offset=float(offset), u_min=float(u.min()), u_max=float(u.max()),
        labels=[p[3] for p in inl], angles=list(map(float, u)),
        radius=float(np.mean([p[2] for p in inl])), rms_deg=rms,
    )
    # Numbers clearly off a straight line, but still in order along the
    # scale: an uneven scale, read point to point.
    if len(inl) >= 4 and rms > 1.5:
        us, vs = scale._points()
        dv = np.diff(vs)
        if np.all(np.diff(us) > 0) and (np.all(dv > 0) or np.all(dv < 0)):
            scale.piecewise = True
    return scale


def _chroma_gap(s1, s2):
    a1, b1 = (np.median([lb.ink[i] for lb in s1.labels]) for i in (1, 2))
    a2, b2 = (np.median([lb.ink[i] for lb in s2.labels]) for i in (1, 2))
    return math.hypot(a1 - a2, b1 - b2)


def fit_two(labels, cx, cy, r, min_conf=0.5):
    """Last resort when only two numbers could be read (e.g. the middle ones
    hide behind glare or the fill-level line): accept a "0" and one other
    number on the same ring if they span a normal gauge sweep (180-320 deg)."""
    pts = []
    for lb in labels:
        d = math.hypot(lb.x - cx, lb.y - cy) / r
        if 0.18 <= d <= 1.15 and lb.conf >= min_conf:
            pts.append((dial_angle(lb.x, lb.y, cx, cy), lb.value, d, lb))
    best = None
    for ta, va, da, la in pts:
        if va != 0:
            continue
        for tb, vb, db, lbb in pts:
            if vb <= 0 or abs(da - db) > 0.1 or nice_step([0, vb]) is None:
                continue
            if math.hypot(la.ink[1] - lbb.ink[1], la.ink[2] - lbb.ink[2]) > 30:
                continue
            cw = (tb - ta) % 360
            for sweep in (cw, cw - 360):  # values rising clockwise, or anticlockwise
                if 180 <= abs(sweep) <= 320:
                    score = la.conf * lbb.conf - abs(abs(sweep) - 270) / 1000
                    if best is None or score > best[0]:
                        best = (score, ta, sweep, vb, (da + db) / 2, la, lbb)
    if best is None:
        return None
    _, ta, sweep, vb, rad, la, lbb = best
    slope = vb / sweep
    u0, u1 = sorted((ta, ta + sweep))
    return Scale(slope=slope, offset=-ta * slope, u_min=u0, u_max=u1, labels=[la, lbb],
                 angles=[ta, ta + sweep], radius=rad, rms_deg=0.0)


def fit_scales(labels, cx, cy, r):
    """Primary scale plus an optional second ring (dual-scale gauges)."""
    first = fit_scale(labels, cx, cy, r)
    if first is None:
        two = fit_two(labels, cx, cy, r)
        return [two] if two else []
    used = {id(lb) for lb in first.labels}
    rest = [lb for lb in labels if id(lb) not in used]
    second = fit_scale(rest, cx, cy, r)
    # a real second ring sits at a clearly different radius (or is printed in
    # a different colour) and isn't tiny
    if second and len(second.labels) >= 3 and (abs(second.radius - first.radius) > 0.08
                                               or _chroma_gap(first, second) > 30):
        # the scale with more labels is the main one
        return sorted([first, second], key=lambda s: -len(s.labels))
    return [first]
