import java.util.Properties

plugins {
    id("com.android.application")
    id("com.chaquo.python")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.logbridge.logbridge"
    compileSdk = flutter.compileSdkVersion
    // Must match Flutter's expected NDK version — Flutter ships a
    // PREBUILT native library (libdartjni.so) built for this exact NDK.
    // Without it, Gradle tries to recompile that library from source via
    // CMake instead of using the prebuilt one, which hit an unrelated
    // Windows file-locking bug. The real fix for the sdkmanager crash is
    // `android.builder.sdkDownload=false` in gradle.properties instead.
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.logbridge.logbridge"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Tablets (arm64) and the PC emulator (x86_64): the embedded Python/OpenCV build is 64-bit here.
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // No code shrinking: R8 removed MlKitText (only the embedded Python calls it) and broke ML Kit's
            // own internals (NullPointerException inside ML Kit on the tablet). A few MB more, and the
            // release runs exactly the code that was tested.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles("proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// gauge-reader (from LogBridge-DSR/gauge-reader) runs on the tablet inside the app. OpenCV for
// Android is published for Python 3.10 (OpenCV 4.5.1), and gauge-reader passes its tests on it.
// The build PC needs a Python 3.10 too: set buildPython=... in local.properties.
val localProps = Properties()
rootProject.file("local.properties").takeIf { it.exists() }?.inputStream()?.use { localProps.load(it) }

chaquopy {
    defaultConfig {
        version = "3.10"
        localProps.getProperty("buildPython")?.let { buildPython(it) }
        pip {
            install("numpy==1.26.2")
            install("opencv-python==4.5.1.48")
            install("PyYAML")
        }
    }
}

dependencies {
    // On-device text recognition (bundled model, works offline): reads dial numbers for
    // gauge-reader (in place of RapidOCR) and HMI screens when DSR Extract can't be reached.
    implementation("com.google.mlkit:text-recognition:16.0.1")
}
