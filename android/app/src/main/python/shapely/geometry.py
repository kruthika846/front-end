import numpy as np


class Polygon:
    """A simple polygon's area (shoelace) and perimeter - all RapidOCR asks of it."""

    def __init__(self, points):
        self._p = np.asarray(points, dtype=np.float64).reshape(-1, 2)

    @property
    def area(self):
        x, y = self._p[:, 0], self._p[:, 1]
        return float(abs(np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1))) / 2)

    @property
    def length(self):
        d = np.diff(np.vstack([self._p, self._p[:1]]), axis=0)
        return float(np.sqrt((d ** 2).sum(axis=1)).sum())
