package com.logbridge.logbridge

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, not FlutterActivity — the local_auth plugin's
// BiometricPrompt integration requires a FragmentActivity host.
class MainActivity : FlutterFragmentActivity()
