package com.logbridge.logbridge;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Point;
import android.graphics.Rect;

import com.google.android.gms.tasks.Tasks;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.text.Text;
import com.google.mlkit.vision.text.TextRecognition;
import com.google.mlkit.vision.text.TextRecognizer;
import com.google.mlkit.vision.text.latin.TextRecognizerOptions;

import org.json.JSONArray;
import org.json.JSONObject;

/**
 * On-device text recognition (ML Kit, bundled model, no network) for gauge-reader's dial_ocr,
 * which on a PC uses RapidOCR. Called from Python (app_gauge.py) on a worker thread.
 * Returns JSON [{box: [[x,y] x4], text, conf}], the same shape as RapidOCR's results.
 */
public final class MlKitText {
    private static TextRecognizer recognizer;

    private MlKitText() { }

    private static synchronized TextRecognizer get() {
        if (recognizer == null) recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS);
        return recognizer;
    }

    public static String recognize(byte[] png) throws Exception {
        Bitmap bmp = BitmapFactory.decodeByteArray(png, 0, png.length);
        if (bmp == null) return "[]";
        Text text = Tasks.await(get().process(InputImage.fromBitmap(bmp, 0)));
        JSONArray out = new JSONArray();
        for (Text.TextBlock block : text.getTextBlocks()) {
            for (Text.Line line : block.getLines()) {
                // Scale numbers sit apart on a dial; ML Kit sometimes joins a few into one line
                // ("0 2 4"), which RapidOCR keeps apart. Such lines are given word by word.
                boolean split = line.getElements().size() > 1 && line.getText().matches(".*\\d.*");
                if (split) {
                    for (Text.Element e : line.getElements()) add(out, e.getText(), e.getCornerPoints(), e.getBoundingBox(), e.getConfidence());
                } else {
                    add(out, line.getText(), line.getCornerPoints(), line.getBoundingBox(), line.getConfidence());
                }
            }
        }
        bmp.recycle();
        return out.toString();
    }

    private static void add(JSONArray out, String text, Point[] corners, Rect box, float conf) throws Exception {
        JSONArray pts = new JSONArray();
        if (corners != null && corners.length == 4) {
            for (Point p : corners) pts.put(new JSONArray().put(p.x).put(p.y));
        } else if (box != null) {
            pts.put(new JSONArray().put(box.left).put(box.top)).put(new JSONArray().put(box.right).put(box.top))
               .put(new JSONArray().put(box.right).put(box.bottom)).put(new JSONArray().put(box.left).put(box.bottom));
        } else {
            return;
        }
        out.put(new JSONObject().put("box", pts).put("text", text).put("conf", (double) conf));
    }
}
