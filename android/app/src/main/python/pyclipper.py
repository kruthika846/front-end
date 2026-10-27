"""The one pyclipper call RapidOCR makes (pyclipper has no Android build): growing a
detected text box outward by `distance` with round corners before its minimum
rectangle is taken (ch_ppocr_det/utils.py DBPostProcess.unclip).

A round-cornered offset of a convex polygon is the convex hull of a circle of radius
`distance` around each corner - computed here with OpenCV. RapidOCR then takes the
minimum-area rectangle of the result, which is the box grown by `distance` on every
side, the same as with pyclipper.
"""

import math

import cv2
import numpy as np

JT_SQUARE, JT_ROUND, JT_MITER = 0, 1, 2
ET_CLOSEDPOLYGON = 0

_STEPS = 64
_CIRCLE = np.array([[math.cos(2 * math.pi * k / _STEPS), math.sin(2 * math.pi * k / _STEPS)] for k in range(_STEPS)])


class PyclipperOffset:
    def __init__(self):
        self._paths = []

    def AddPath(self, path, join_type=JT_ROUND, end_type=ET_CLOSEDPOLYGON):  # noqa: N802 - pyclipper's names
        self._paths.append(np.asarray(path, dtype=np.float64).reshape(-1, 2))

    def Execute(self, distance):  # noqa: N802
        out = []
        for p in self._paths:
            pts = (p[:, None, :] + distance * _CIRCLE[None, :, :]).reshape(-1, 2)
            hull = cv2.convexHull(np.round(pts).astype(np.int32)).reshape(-1, 2)
            out.append(hull.astype(np.int32))
        return out
