# Called only from Python (app_gauge.py via Chaquopy's jclass), so the release shrinker can't see
# it is used and would remove it: every on-tablet read would then fail.
-keep class com.logbridge.logbridge.MlKitText { public static *; }
