# LogBridge — How It's Built (read this to actually understand it)

This is the MVP described in the brief: operator fills a form (remote + local
engine parameters), optionally attaches a photo/PDF, signs on screen, and the
whole entry is saved to a local SQLite database — fully offline.

## The mental model: one-way data flow

```
User types/draws/taps
        |
        v
Riverpod provider (in-memory draft state)
        |  (only on Submit)
        v
Repository (translates draft -> SQL)
        |
        v
SQLite (sqflite) — the only source of truth once saved
        |
        v
History screen reads it back via another provider
```

Nothing writes to SQLite until "Submit Entry" is pressed. Until then, everything
the operator has typed lives in `EntryFormState`, held by Riverpod. This means:
navigating away and back mid-form doesn't lose data (Riverpod holds it), but a
half-finished entry is never accidentally saved.

## Why Riverpod, and what a "provider" actually is

A **provider** is just a global, observable variable. Instead of passing data
down through 5 constructors (`prop drilling`), any widget can do:

```dart
final formState = ref.watch(entryFormProvider);
```

`ref.watch` subscribes that widget to changes — when the state changes, only
the widgets that watched it rebuild. Compare to `ref.read`, which grabs the
current value once without subscribing (used inside callbacks like
`onPressed`, where you don't want a rebuild every time you read).

Two kinds of provider are used here:

- **`Provider` / `FutureProvider`** — read-only. `parameterConfigProvider`
  loads the JSON schema once; `recentEntriesProvider` re-runs its query
  whenever `ref.invalidate(...)` is called on it (we do this right after a
  successful save, so the history list updates itself).
- **`StateNotifierProvider`** — read/write. `entryFormProvider` wraps an
  `EntryFormNotifier`, which is the *only* thing allowed to mutate
  `EntryFormState`. Widgets call `notifier.setValue(...)`; nothing reaches
  into the state object directly. This is the same discipline Redux/BLoC
  enforce, just with far less boilerplate.

## Why the form is "schema-driven" (JSON, not hardcoded widgets)

[assets/config/engine_parameters.json](assets/config/engine_parameters.json)
lists every remote and local parameter: key, label, unit, input type, min/max.
[lib/data/parameter_config.dart](lib/data/parameter_config.dart) loads and
parses it; [lib/widgets/dynamic_param_field.dart](lib/widgets/dynamic_param_field.dart)
renders **one widget type** that adapts itself per definition (number field,
text field, or dropdown).

Consequence: to add "Turbocharger Exhaust Temp" as a new local parameter,
you edit the JSON file — no Dart code changes, no rebuild of the form logic.
This matters a lot in a real vessel-logging app because the exact parameter
list varies by engine make/model, and a chief engineer, not a developer,
should be able to adjust it later.

## The database shape

Two tables, deliberately not "one column per parameter":

```sql
logbook_entries(id, engine_id, entry_timestamp, notes,
                 signature_path, photo_path, pdf_path, synced, created_at)

parameter_values(entry_id, param_key, param_category, value)
```

If parameters lived as columns on `logbook_entries`, every time the JSON
schema changed you'd need a SQL migration too. Storing them as
`(entry_id, key, value)` rows instead means the schema and the data are
decoupled — same reasoning as the JSON-driven form above, just one layer
down. The tradeoff: querying "average RPM across entries" needs a
`WHERE param_key = 'rpm'` filter instead of `AVG(rpm)`; fine for an MVP,
worth revisiting if you ever need heavy analytics on this data.

`signature_path` / `photo_path` / `pdf_path` store **file paths**, not
bytes. The PNG/JPEG/PDF itself lives under the app's private documents
directory (`getApplicationDocumentsDirectory()`), organized into
`signatures/`, `photos/`, `pdfs/` subfolders. SQLite is for structured data
you'll query; the filesystem is for blobs you'll just display or upload —
mixing them (storing images as BLOBs in SQLite) works but bloats the DB
file and makes it slower to back up/sync.

## Signature capture

[lib/widgets/signature_pad_field.dart](lib/widgets/signature_pad_field.dart)
uses the `signature` package's `SignatureController`, which tracks pen
strokes internally. "Save Signature" calls `controller.toPngBytes()` (an
async render of the strokes to a PNG), writes that to
`.../signatures/<entryId>.png`, and stores the path in `EntryFormState`.
Submit is blocked until a signature path exists — see the check in
[lib/screens/entry_form_screen.dart](lib/screens/entry_form_screen.dart).

This is what makes the entry "legally defensible": the signature is
captured as an image tied to that specific timestamped entry, not a
generic "signed: yes" checkbox.

## Photo / PDF capture

[lib/widgets/photo_upload_field.dart](lib/widgets/photo_upload_field.dart)
offers a bottom sheet (Take Photo / Choose from Gallery) via `image_picker`,
and a PDF picker via `file_picker`. Both copy the picked file into app
storage immediately — the original source (camera cache, Downloads folder)
can be cleared later without breaking the reference. Right now these paths
just sit in the local DB; per the brief, Saturday's work is wiring them into
Shreya's upload API, which only requires reading `photoPath`/`pdfPath` off
the saved entry — nothing in this layer needs to change for that.

## Offline-first, by construction

There's no network call anywhere in this codebase. `sqflite` is a local,
on-device database (not a client for a remote one), so "offline first" isn't
a special mode — it's just what happens when you never introduce an HTTP
call. Cloud sync later means: add a `synced` flag check (already a column,
defaulted to 0), and a background job that POSTs unsynced rows and flips it
to 1. Nothing about today's screens needs to change for that to slot in.

## File map

```
lib/
  main.dart                        — app entry point, wraps everything in ProviderScope
  models/
    param_definition.dart          — one form field's shape (key, label, type, min/max)
    logbook_entry.dart             — one saved entry's shape
  data/
    app_database.dart              — sqflite open/create-table logic (singleton)
    parameter_config.dart          — loads+parses the JSON parameter schema
    logbook_repository.dart        — all SQL lives here; screens never touch sqflite directly
  providers/
    repository_providers.dart      — exposes the repository + parameter config to the UI
    entry_form_provider.dart       — in-progress draft state (StateNotifier)
    history_provider.dart          — "last 5 entries" query, invalidated after each save
  widgets/
    dynamic_param_field.dart       — one field, rendered per ParamDefinition
    signature_pad_field.dart       — signature canvas + save/clear
    photo_upload_field.dart        — photo (camera/gallery) + PDF pickers
  screens/
    home_screen.dart               — history list + "New Entry" FAB
    entry_form_screen.dart         — the actual data entry form, wires everything together
    entry_detail_screen.dart       — read-only view of one past entry
assets/config/engine_parameters.json — the editable parameter schema
```

## Navigation (added after the section above was first written)

The app now opens on a login screen (name + PIN against a small demo operator
list — a real check, not an always-pass gate), then Department (Engine Room /
Cargo Control / Navigation) → Engine Room's Auxiliary Engine holds Generator
1-4, each with its own Daily Logs / Records / New Entry. Only Generator 1 has
real data flowing into it so far; 2-4 use the exact same screens, just
filtered to entries tagged with their own `generator_number`. Main Engine
sits alongside Auxiliary Engine as a placeholder for when that's built out
the same way. `lib/screens/home_screen.dart` mentioned below no longer
exists — its old "history + FAB" role is now split across
`department_screen.dart`, `engine_room_screen.dart`, and
`generator_screen.dart`.

## Things intentionally left out of this MVP (and why)

- **No cloud sync** — the brief explicitly defers this; the `synced` column
  is the only hook needed later.
- **PDF/photo "upload"** — buttons exist and files are stored, but nothing
  is transmitted anywhere yet; that's for when the backend exists.
- **No unit tests yet** — worth adding once the parameter schema and DB
  shape settle; testing `LogbookRepository` against an in-memory sqflite DB
  is the highest-value first test to write.
