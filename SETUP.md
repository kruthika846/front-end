# LogBridge — Setup & Run

The Dart/Flutter source code (everything in `lib/`, `assets/`, `pubspec.yaml`) is already written.
What's missing is the native Android project scaffold, which only the Flutter CLI can generate —
it wasn't safe to hand-write. Follow these steps once, then `flutter run` works like any normal
Flutter project from here on.

## 1. Install Flutter SDK (skip if `flutter --version` already works)

- Download from https://docs.flutter.dev/get-started/install/windows
- Extract somewhere like `C:\src\flutter`, add `C:\src\flutter\bin` to your PATH
- Install Android Studio (for the Android SDK + an emulator), or plug in a physical
  Android phone with USB debugging enabled
- Run:
  ```bash
  flutter doctor
  ```
  Fix anything it flags with a red ✗ (Android licenses: `flutter doctor --android-licenses`)

## 2. Generate the native Android project

From inside this folder (`C:\Users\kruth\front end app`):

```bash
flutter create . --platforms=android --org com.logbridge --project-name logbridge
```

Because `lib/` and `pubspec.yaml` already exist, this command **adds** the missing
`android/` folder (and `.metadata`, `analysis_options.yaml`) without touching your code.

## 3. Install dependencies

```bash
flutter pub get
```

## 4. Add Android permissions

Open `android/app/src/main/AndroidManifest.xml`. Inside the `<manifest>` tag, above
`<application>`, add:

```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
```

Inside the `<application>` tag add (marks the camera as optional, so the app still
installs on devices/emulators without one):

```xml
<uses-feature android:name="android.hardware.camera" android:required="false"/>
```

## 5. Run it

Connect a device (`adb devices` should list it) or start an emulator from Android Studio, then:

```bash
flutter run
```

## Troubleshooting

- **"minSdkVersion too low"** — open `android/app/build.gradle`, set `minSdkVersion` to at
  least `21` (sqflite requires it; recent Flutter templates already default to 21+).
- **Camera permission denial on first launch** — Android asks at runtime the first time
  "Take Photo" is tapped; if you accidentally deny it, clear it back on via
  Settings → Apps → LogBridge → Permissions.
- **`file_picker` build errors on Android** — run `flutter clean` then `flutter pub get`
  again; this package occasionally needs a clean build after first install.
