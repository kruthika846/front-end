package com.logbridge.logbridge

import android.content.pm.ApplicationInfo
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

// FlutterFragmentActivity, not FlutterActivity — the local_auth plugin's
// BiometricPrompt integration requires a FragmentActivity host.
class MainActivity : FlutterFragmentActivity() {
    // One photo at a time: the readers are heavy and Python runs one thing at a time anyway.
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private companion object { const val TAG = "LogBridgeOCR" }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!Python.isStarted()) Python.start(AndroidPlatform(this))
        // Load Python, OpenCV and the readers in the background now, so the first photo isn't slowed by it.
        worker.execute {
            val t0 = System.currentTimeMillis()
            runCatching { Python.getInstance().getModule("hmi_ondevice") }
                .onSuccess { Log.i(TAG, "on-tablet readers loaded in ${System.currentTimeMillis() - t0} ms") }
                .onFailure { Log.e(TAG, "on-tablet readers failed to load", it) }
            // Debug builds only: `adb shell am start -n com.logbridge.logbridge/.MainActivity
            //   --es selftest /data/local/tmp/photo.jpg --es kind gauge|hmi [--es unit MPa]` reads that
            // photo and logs the result, so the readers can be checked on an emulator without the UI.
            val debuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            val photo = intent?.getStringExtra("selftest")
            if (debuggable && photo != null) {
                val t1 = System.currentTimeMillis()
                runCatching {
                    if (intent.getStringExtra("kind") == "hmi") Python.getInstance().getModule("hmi_ondevice").callAttr("read", photo).toString()
                    else Python.getInstance().getModule("app_gauge").callAttr("read", photo, intent.getStringExtra("unit") ?: "").toString()
                }.onSuccess { Log.i(TAG, "selftest ${System.currentTimeMillis() - t1} ms: $it") }
                    .onFailure { Log.e(TAG, "selftest failed", it) }
            }
        }

        // "logbridge/ocr": photo readers that run on this tablet (lib/services/device_ocr.dart).
        //   readGauge(path, unit) -> gauge-reader's reading of a needle gauge, as JSON
        //   readHmi(path)         -> an HMI screen's labelled values, as JSON (DSR Extract's shape)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "logbridge/ocr").setMethodCallHandler { call, result ->
            val path = call.argument<String>("path")
            if (path == null) {
                result.error("bad_args", "No photo path", null)
                return@setMethodCallHandler
            }
            val run: (() -> String)? = when (call.method) {
                "readGauge" -> { { Python.getInstance().getModule("app_gauge").callAttr("read", path, call.argument<String>("unit") ?: "").toString() } }
                "readHmi" -> { { Python.getInstance().getModule("hmi_ondevice").callAttr("read", path).toString() } }
                else -> null
            }
            if (run == null) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            worker.execute {
                try {
                    val json = run()
                    main.post { result.success(json) }
                } catch (t: Throwable) {
                    Log.e(TAG, "${call.method} failed", t)
                    main.post { result.error("reader_failed", t.message ?: t.toString(), null) }
                }
            }
        }
    }
}
