"""DSR Extract on the tablet: reads an HMI screen photo with DSR Extract's own
pipeline, offline, so a photo read without Wi-Fi gives what the server gives.

On the PC, DSR Extract turns a photo into a one-page PDF (PyMuPDF) and OCRs the
rendered page with RapidOCR. Neither PyMuPDF nor onnxruntime's Python package
exists for Android, so this does the same steps on the picture directly:

  straighten the photo  ->  the page render (1.2x, as 250-DPI image at 300 DPI)
  ->  RapidOCR (same models; run by onnxruntime for Android, see onnxruntime/)
  ->  minus-sign recovery  ->  DSR Extract's layout, readings and result

Everything after the OCR is DSR Extract's own code (dsr_extract/, unchanged).
"""

import json
import os
import time

# rapidfuzz has no Android build: its own pure-Python implementation is used (same results).
os.environ.setdefault("RAPIDFUZZ_IMPLEMENTATION", "python")

import cv2  # noqa: E402

_NOMINAL_DPI = 250.0  # dsr_extract/image_input.py
_MAX_SIDE = 2800


def _analyze(bgr, config):
    from dsr_extract.backends import ocr_local as ol
    from dsr_extract.backends._photo import prepare_photo

    bgr, info = prepare_photo(bgr)
    h, w = bgr.shape[:2]
    if max(h, w) > _MAX_SIDE:
        s = _MAX_SIDE / max(h, w)
        bgr = cv2.resize(bgr, (max(1, round(w * s)), max(1, round(h * s))), interpolation=cv2.INTER_AREA)
        h, w = bgr.shape[:2]

    backend = ol.LocalOcrBackend(config)
    zoom = backend.dpi / 72.0                       # the PDF page is rendered at this zoom
    page_w, page_h = w / _NOMINAL_DPI * 72.0, h / _NOMINAL_DPI * 72.0
    base = cv2.resize(bgr, (round(page_w * zoom), round(page_h * zoom)), interpolation=cv2.INTER_LINEAR)
    H, W = base.shape[:2]

    # whole-page pass, as LocalOcrBackend.analyze_document
    if max(H, W) * 1.5 <= 4096:
        work = cv2.resize(base, None, fx=1.5, fy=1.5, interpolation=cv2.INTER_CUBIC)
        up = 1.5
    else:
        work, up = base, 1.0
    raw = ol._ocr_page_with_fallback(work, backend.page_timeout_s, page_num=1)
    dets = [(ol._bbox_to_poly([c / up for c in ol._poly_to_bbox(p)]), t, s) for p, t, s in raw]
    # a photographed screen skips the panel re-read (PyMuPDF-only anyway); a flat screenshot
    # would get it on the PC - the one step not repeated here
    if backend.restore_minus:
        from dsr_extract.backends._minus import restore_minus
        dets = restore_minus(cv2.cvtColor(base, cv2.COLOR_BGR2GRAY), dets)

    layout = ol._build_layout(1, float(W), float(H), dets, panels=[], strict_labels=False,
                              strip_cjk=backend.strip_stray_cjk)
    ol._scale_layout(layout, 1.0 / zoom)
    layout.width, layout.height = page_w, page_h
    return layout, info


def extract_image(path):
    """DSR Extract's result dict for the photo at `path` (same shape as the server's)."""
    from dsr_extract.config import CONFIG
    from dsr_extract.enrich import enrich
    from dsr_extract.extract import _document_to_result
    from dsr_extract.extract_scanned import layout_to_blocks
    from dsr_extract.model import Page
    from dsr_extract.normalize import build_document

    started = time.time()
    bgr = cv2.imread(path)          # applies the photo's EXIF rotation
    if bgr is None:
        raise ValueError("The photo could not be opened")
    layout, _info = _analyze(bgr, CONFIG)
    page = Page(number=1, kind="SCANNED", width=layout.width, height=layout.height)
    page.blocks = list(layout_to_blocks(layout))
    doc = enrich(build_document(os.path.basename(path), [page], started), CONFIG)
    return _document_to_result(doc, CONFIG)


def read(path):
    """JSON for the app: {"extracted_values": [...], "tables": [...], "source": "dsr-on-device"}.
    If DSR Extract fails here or finds nothing, the simpler ML Kit reader (hmi_ondevice) is
    tried, and the reason is passed on."""
    try:
        out = extract_image(path)
        if out.get("document_type") == "error":
            raise RuntimeError(out.get("raw_text") or "DSR Extract could not read the photo")
        if out.get("extracted_values"):
            out.pop("_traceback", None)
            out.pop("raw_text", None)
            out["source"] = "dsr-on-device"
            return json.dumps(out)
        why = "DSR Extract found no values"
    except Exception as e:  # noqa: BLE001
        why = f"DSR Extract failed: {type(e).__name__}: {e}"
    try:
        from hmi_ondevice import read as mlkit_read
        out = json.loads(mlkit_read(path))
    except Exception as e:  # noqa: BLE001
        # both readers failed: keep DSR Extract's reason as well as ML Kit's
        return json.dumps({"error": f"{why}; the simpler reader failed too: {type(e).__name__}: {e}"})
    out["dsr_note"] = why
    return json.dumps(out)


def warm():
    """Load DSR Extract and RapidOCR's models now, so the first photo isn't slowed by it."""
    from dsr_extract.backends import ocr_local
    ocr_local._engine()
    import dsr_extract.enrich, dsr_extract.extract  # noqa: F401,E401
