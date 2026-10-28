"""What the Android app calls: read the needle gauge in one photo, on the tablet.

gauge-reader's own code does the work, with the same text recognition as on the PC
(RapidOCR, whose models run on onnxruntime for Android - see onnxruntime/). If RapidOCR
can't start, ML Kit (com.logbridge.logbridge.MlKitText) reads the dial numbers instead.
"""

import json
import math

import cv2
import numpy as np

import dial_ocr
from gauge_reader import read_all
from units import GAUGE_TYPES, convert, display_unit


def _ml_kit(img):
    from java import jclass

    ok, png = cv2.imencode(".png", img)
    if not ok:
        return []
    found = json.loads(str(jclass("com.logbridge.logbridge.MlKitText").recognize(png.tobytes())))
    return [(np.array(r["box"], np.float32), r["text"], r["conf"]) for r in found]


_ocr_chosen = False


def _choose_ocr():
    """RapidOCR (gauge-reader's own engine; its tests pass with it) when it starts here,
    else ML Kit. Its own instance: RapidOCR keeps per-call settings, and gauge-reader's
    (looser, for thin dial digits) must not change DSR Extract's."""
    global _ocr_chosen
    if _ocr_chosen:
        return
    _ocr_chosen = True
    try:
        dial_ocr.set_ocr_backend(None)
        dial_ocr.get_reader()
    except Exception:  # noqa: BLE001
        dial_ocr.set_ocr_backend(_ml_kit)


def _display(rd):
    """The reading's lines as gauge-reader prints them (Reading.__str__), for the app's card."""
    d = {
        "label": rd.label or (GAUGE_TYPES[rd.type]["label"] if rd.type else "Gauge"),
        "type": GAUGE_TYPES[rd.type]["label"] if rd.type else "Unknown type",
        "reading": rd.fmt(rd.value, rd.unit),
        "confidence": f"{rd.confidence:.2f}",
    }
    if rd.second_scale:
        d["second_scale"] = rd.fmt_converted(rd.second_scale["value"], rd.second_scale["unit"])
    if rd.conversions:
        d["also"] = ", ".join(rd.fmt_converted(v, u) for u, v in rd.conversions.items())
    if rd.scale_min is not None:
        src = f"{rd.labels_read} numbers read" if rd.mode == "auto" else rd.mode
        d["scale"] = f"{rd.scale_min:g} to {rd.scale_max:g} {display_unit(rd.unit)}  ({src})"
    if rd.needle_angle is not None:
        d["needle"] = f"{rd.needle_angle:.1f} deg (clockwise from 6 o'clock)"
    if rd.gauge_bounds:
        b = rd.gauge_bounds
        d["gauge_at"] = f"x={b['x']} y={b['y']} w={b['w']} h={b['h']} px"
    d["time"] = f"{rd.processing_time_ms} ms"
    d["status"] = rd.status
    d["unit"] = display_unit(rd.unit)
    return d


def read(path, wanted_unit="", debug_path=""):
    """Returns JSON: the most trustworthy gauge in the photo (Reading.to_json()) with its
    display lines, the marked-up picture at `debug_path` when given (needle, dial, the
    numbers read), and the value in `wanted_unit` when the dial shows another unit."""
    _choose_ocr()
    img = cv2.imread(path)
    if img is None:
        return json.dumps({"error": "The photo could not be opened"})
    found = [r for r in read_all(img, "photo", debug_path or None) if r.value is not None]
    if not found:
        return json.dumps({"error": "No gauge could be read in this photo",
                           "debug_image": debug_path or None})
    best = max(found, key=lambda r: r.confidence)
    out = best.to_json()
    out["gauges_found"] = len(found)
    out["labels_read"] = best.labels_read
    out["display"] = _display(best)
    out["debug_image"] = debug_path or None
    if wanted_unit and best.type and best.unit:
        try:
            # the app's own spellings the converter doesn't know ("Amps" is A)
            to = {"amps": "A", "amp": "A"}.get(wanted_unit.strip().lower(), wanted_unit)
            out["value_in_wanted_unit"] = convert(best.value, best.type, best.unit, to)
            out["wanted_unit"] = wanted_unit
        except (ValueError, KeyError) as e:
            out["unit_note"] = str(e)   # e.g. a temperature gauge photographed for a pressure
    elif wanted_unit:
        out["unit_note"] = "The dial's unit could not be read"
    return json.dumps(_finite(out), default=str)


def _finite(o):
    """NaN / infinity (e.g. a needle angle it could not fix) are not JSON the app can read: null."""
    if isinstance(o, float) and not math.isfinite(o):
        return None
    if isinstance(o, dict):
        return {k: _finite(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)):
        return [_finite(v) for v in o]
    return o
