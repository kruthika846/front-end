import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-progress state for the entry currently being filled out.
/// Nothing here touches the database — this is pure UI state.
class EntryFormState {
  final Map<String, String> values;

  /// One evidence photo per parameter (mainly used by local/manual gauge
  /// readings) — key is the ParamDefinition.key, value is the saved file
  /// path. Separate from the single whole-entry `photoPath` below.
  final Map<String, String> paramPhotos;

  final String notes;
  final String? photoPath;
  final String? pdfPath;

  /// True once the operator has passed a real device biometric check
  /// (fingerprint/face) for this draft — required before submit, in place
  /// of the drawn signature this form used to require.
  final bool biometricVerified;

  /// Which of the day's two paper-log columns this entry is for — 'time' or
  /// 'noon' — picked explicitly by the operator rather than guessed from
  /// the clock. Null until they choose one.
  final String? readingSlot;

  /// One photo of the whole remote HMI/monitoring screen — evidence of what
  /// the display showed, same idea as paramPhotos but for the single shared
  /// panel instead of per-parameter. Not auto-read; the operator still
  /// types each remote value in by hand.
  final String? hmiPhotoPath;

  /// One comment per parameter group/panel (e.g. "remote::Turbocharger"),
  /// not per individual reading.
  final Map<String, String> groupComments;

  const EntryFormState({
    this.values = const {},
    this.paramPhotos = const {},
    this.notes = '',
    this.photoPath,
    this.pdfPath,
    this.biometricVerified = false,
    this.hmiPhotoPath,
    this.groupComments = const {},
    this.readingSlot,
  });

  EntryFormState copyWith({
    Map<String, String>? values,
    Map<String, String>? paramPhotos,
    String? notes,
    String? photoPath,
    String? pdfPath,
    bool? biometricVerified,
    String? hmiPhotoPath,
    Map<String, String>? groupComments,
    String? readingSlot,
    bool clearPhotoPath = false,
    bool clearHmiPhotoPath = false,
  }) {
    return EntryFormState(
      values: values ?? this.values,
      paramPhotos: paramPhotos ?? this.paramPhotos,
      notes: notes ?? this.notes,
      photoPath: clearPhotoPath ? null : (photoPath ?? this.photoPath),
      pdfPath: pdfPath ?? this.pdfPath,
      biometricVerified: biometricVerified ?? this.biometricVerified,
      hmiPhotoPath: clearHmiPhotoPath ? null : (hmiPhotoPath ?? this.hmiPhotoPath),
      groupComments: groupComments ?? this.groupComments,
      readingSlot: readingSlot ?? this.readingSlot,
    );
  }
}

class EntryFormNotifier extends StateNotifier<EntryFormState> {
  EntryFormNotifier() : super(const EntryFormState());

  void setValue(String key, String value) {
    final updated = Map<String, String>.from(state.values)..[key] = value;
    state = state.copyWith(values: updated);
  }

  /// Attach (or clear, by passing null) a gauge photo to one specific
  /// parameter — this is the evidence photo of the physical dial, not an
  /// automatic reading; the operator still types the value themselves.
  void setParamPhoto(String key, String? path) {
    final updated = Map<String, String>.from(state.paramPhotos);
    if (path == null) {
      updated.remove(key);
    } else {
      updated[key] = path;
    }
    state = state.copyWith(paramPhotos: updated);
  }

  void setNotes(String notes) => state = state.copyWith(notes: notes);
  void setPhotoPath(String? path) =>
      state = state.copyWith(photoPath: path, clearPhotoPath: path == null);
  void setPdfPath(String? path) => state = state.copyWith(pdfPath: path);
  void setBiometricVerified(bool verified) => state = state.copyWith(biometricVerified: verified);
  void setHmiPhotoPath(String? path) =>
      state = state.copyWith(hmiPhotoPath: path, clearHmiPhotoPath: path == null);
  void setReadingSlot(String slot) => state = state.copyWith(readingSlot: slot);

  /// Sets the one comment for a whole parameter group/panel, e.g.
  /// setGroupComment('remote::Turbocharger', 'IN sensor reads a bit high').
  void setGroupComment(String groupKey, String comment) {
    final updated = Map<String, String>.from(state.groupComments)..[groupKey] = comment;
    state = state.copyWith(groupComments: updated);
  }

  void reset() => state = const EntryFormState();
}

final entryFormProvider = StateNotifierProvider.autoDispose<EntryFormNotifier, EntryFormState>((ref) {
  return EntryFormNotifier();
});
