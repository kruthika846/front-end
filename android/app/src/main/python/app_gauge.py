"""What the Android app calls: read the needle gauge in one photo, on the tablet.

gauge-reader's own code does the work; only its text recognition is swapped for
ML Kit (com.logbridge.logbridge.MlKitText), because RapidOCR's ONNX runtime is not
available on Android.
"""

import json

import cv2
import numpy as np

import dial_ocr
from gauge_reader import read_all
from units import convert


def _ml_kit(img):
    from java import jclass

    ok, png = cv2.imencode(".png", img)
    if not ok:
        return []
    found = json.loads(str(jclass("com.logbridge.logbridge.MlKitText").recognize(png.tobytes())))
    return [(np.array(r["box"], np.float32), r["text"], r["conf"]) for r in found]


dial_ocr.set_ocr_backend(_ml_kit)


def read(path, wanted_unit=""):
    """Returns JSON: the most trustworthy gauge in the photo (Reading.to_json()),
    plus the value in `wanted_unit` (the log's unit) when the dial shows another."""
    img = cv2.imread(path)
    if img is None:
        return json.dumps({"error": "The photo could not be opened"})
    found = [r for r in read_all(img, "photo") if r.value is not None]
    if not found:
        return json.dumps({"error": "No gauge could be read in this photo"})
    best = max(found, key=lambda r: r.confidence)
    out = best.to_json()
    out["gauges_found"] = len(found)
    if wanted_unit and best.type and best.unit:
        try:
            out["value_in_wanted_unit"] = convert(best.value, best.type, best.unit, wanted_unit)
            out["wanted_unit"] = wanted_unit
        except (ValueError, KeyError) as e:
            out["unit_note"] = str(e)
    return json.dumps(out)
