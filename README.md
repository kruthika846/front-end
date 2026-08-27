# LogBridge

A Flutter Android app for digitizing paper engine-room logbooks on shipboard tablets.
An operator signs in, fills in remote (control-room) and local (walk-around gauge)
readings for a generator, signs the entry on-screen, and it's saved to an on-device
SQLite database — no network connection required at any point.

## Features

- **Operator sign-in** with a name + PIN check (Chief Engineer / 2nd Engineer / 3rd Engineer demo accounts)
- **Engine Room → Auxiliary Engine → Generator 1-4** navigation, each generator with its own Daily Logs, Records, and entries
- **Remote parameter panel** — generator load, turbocharger, cylinder exhaust temps, alternator, lubrication/cooling, status indicators
- **Local parameter panel** — ~35 manually-read gauge values (JCW/exhaust outlet temps, lubrication, cooling water, charge air, fuel, running data), each with its own photo-evidence capture button
- **Per-field numeric validation** — every number field is checked against its configured min/max range and rejects non-numeric input, with the error shown inline
- **Per-panel comments** and a per-reading correction ("edit") option, available only on the live entry form — never on a saved entry, to keep submitted records tamper-proof
- **HMI screen photo capture** — one photo of the whole remote monitoring screen as evidence (values are still typed by hand; nothing is auto-read from the photo)
- **On-screen signature capture**, required before an entry can be submitted
- **Time / Noon reading selector** — required on every entry, drives which column it lands in on the Daily Log
- **Daily Log report** — a curated 14-row view matching the paper "Diesel Alternator" log sheet, computed from the saved remote + local readings (max/min across cylinders, unit conversions, Time/Noon columns per day)
- **Read-only entry detail screen** — once submitted, an entry cannot be edited or commented on, only viewed
- **Fully offline** — all data is stored locally with `sqflite`; there is no server call anywhere in the app

## Tech stack

- Flutter / Dart, Material 3
- Riverpod (`flutter_riverpod`) for state management
- `sqflite` for local persistence
- `image_picker` for camera capture (gauge photos, HMI photo)
- `signature` for on-screen signature capture
- `file_picker` for PDF attachments

## Setup & running it

See [SETUP.md](SETUP.md) for full first-time setup (Flutter SDK, Android toolchain,
generating the native `android/` project). Once set up:

```bash
flutter pub get
flutter run
```

To build a standalone APK you can install on any Android phone without a PC:

```bash
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk` — copy it to a
phone and install it directly; no server or network connection is needed to run it.

## Project structure

See [ARCHITECTURE.md](ARCHITECTURE.md) for a full walkthrough of the data flow,
why the form is schema-driven, and the database shape.

```
lib/
  models/          — ParamDefinition (one form field), LogbookEntry (one saved entry)
  data/            — sqflite setup + migrations, JSON parameter-schema loader, repository
  providers/       — Riverpod providers (session, entry-form draft state, history)
  widgets/         — reusable field widgets (gauge dial, signature pad, photo upload, ...)
  screens/         — login, department picker, engine room, generator, entry form, entry detail
assets/config/engine_parameters.json — the editable remote/local parameter schema
```

## Known limitations (by design, for this stage of the project)

- No backend/cloud sync yet — entries live only in the local SQLite database (a `synced`
  column already exists as the hook for wiring this in later)
- Cargo Control, Navigation, and Main Engine are placeholder sections — only Engine Room
  → Auxiliary Engine is fully built out
- No automated test suite yet
