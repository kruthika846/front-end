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

// DSR Extract runs on the tablet too (python/dsr_device.py), so HMI photos read with no server or
// Wi-Fi give the server's results. Its code and RapidOCR (code + models) are copied in at build
// time from a DSR Extract checkout set up with its setup (dsrExtractDir=... in local.properties,
// e.g. C:/Users/kruth/LogBridge-DSR/dsr-extract); nothing is duplicated in this repository.
val dsrDir = localProps.getProperty("dsrExtractDir")
    ?: error("Set dsrExtractDir=<path to dsr-extract> in android/local.properties (DSR Extract, set up with setup.bat)")
val dsrSitePackages = "$dsrDir/.venv/Lib/site-packages"
val dsrPython = layout.buildDirectory.dir("generated/dsr-python").get().asFile

val copyDsrPython by tasks.registering(Sync::class) {
    into(dsrPython)
    from("$dsrDir/dsr_extract") {
        into("dsr_extract")
        exclude("**/__pycache__/**", "api.py", "cli.py", "__main__.py")
    }
    from("$dsrSitePackages/rapidocr_onnxruntime") {
        into("rapidocr_onnxruntime")
        exclude("**/__pycache__/**")
    }
    // rapidfuzz's own pure-Python implementation (its compiled one has no Android build)
    from("$dsrSitePackages/rapidfuzz") {
        into("rapidfuzz")
        include("**/*.py")
        exclude("**/__pycache__/**", "__pyinstaller/**")
    }
    // wordninja as a package, so its word list can be unpacked next to it (extractPackages)
    from("$dsrSitePackages/wordninja.py") {
        into("wordninja")
        rename { "__init__.py" }
        filter { it.replace(",'wordninja','wordninja_words.txt.gz'", ",'wordninja_words.txt.gz'") }
    }
    from("$dsrSitePackages/wordninja/wordninja_words.txt.gz") { into("wordninja") }
}

chaquopy {
    defaultConfig {
        version = "3.10"
        localProps.getProperty("buildPython")?.let { buildPython(it) }
        pip {
            install("numpy==1.26.2")
            install("opencv-python==4.5.1.48")
            install("PyYAML")
            // DSR Extract's remaining dependencies (pure Python, or built for Android)
            install("Pillow")
            install("Pint==0.24.4")
            install("python-dateutil")
        }
        // these read data files next to their code (lexicon, OCR models, word list, unit table)
        extractPackages("dsr_extract", "rapidocr_onnxruntime", "wordninja", "pint")
    }
    sourceSets {
        getByName("main") {
            srcDir(dsrPython)
        }
    }
}

tasks.named("preBuild") { dependsOn(copyDsrPython) }
tasks.configureEach {
    if (name.startsWith("merge") && name.endsWith("PythonSources")) dependsOn(copyDsrPython)
}

dependencies {
    // On-device text recognition (bundled model, works offline): reads dial numbers for
    // gauge-reader (in place of RapidOCR) and HMI screens when DSR Extract can't be reached.
    implementation("com.google.mlkit:text-recognition:16.0.1")
    // Runs RapidOCR's ONNX models for DSR Extract on the tablet (OrtBridge.java)
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.20.0")
}
