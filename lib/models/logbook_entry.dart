class LogbookEntry {
  final String id;
  final String engineId;

  /// Which physical generator (1-4) this entry belongs to. Null on legacy
  /// entries saved before this existed — treat as Generator 1 when reading.
  final int? generatorNumber;

  /// Which of the day's two paper-log columns this entry belongs to —
  /// 'time' or 'noon' — chosen explicitly by the operator on the form.
  /// Null on legacy entries saved before this existed; the daily log table
  /// falls back to guessing from the timestamp's hour for those.
  final String? readingSlot;

  final DateTime timestamp;
  final String? notes;

  /// Legacy proof-of-submission — a drawn signature image. Only ever set on
  /// entries saved before biometric authentication replaced it; new entries
  /// use [biometricVerified] + [operatorName] instead.
  final String? signaturePath;

  final String? photoPath;
  final String? pdfPath;
  final String? hmiPhotoPath;

  /// The signed-in operator who authenticated this submission, captured
  /// from the session at submit time.
  final String? operatorName;

  /// True if this entry was submitted via a real device fingerprint/face
  /// check (see BiometricAuth) rather than the old drawn signature.
  final bool biometricVerified;

  final bool synced;

  /// Remote + local parameter values keyed by ParamDefinition.key.
  final Map<String, String> paramValues;

  /// Evidence photo of the physical gauge for a parameter, keyed the same
  /// way. Not every parameter has one — mainly used for local readings.
  final Map<String, String> paramPhotos;

  /// One comment per parameter group/panel (e.g. "remote::Turbocharger"),
  /// not per individual reading.
  final Map<String, String> groupComments;

  /// Every non-empty group comment on this entry, combined into one
  /// readable line (e.g. "Turbocharger: bearing noise  •  Alternator:
  /// vibration slightly high") — this is what makes a comment actually
  /// visible in Watch Keeping and the Daily Log, not just buried behind a
  /// tap into the detail screen. Empty string when there are none.
  String get combinedComments {
    final parts = <String>[];
    for (final entry in groupComments.entries) {
      final text = entry.value.trim();
      if (text.isEmpty) continue;
      final label = entry.key.contains('::') ? entry.key.split('::').last : entry.key;
      parts.add('$label: $text');
    }
    return parts.join('  •  ');
  }

  LogbookEntry({
    required this.id,
    required this.engineId,
    this.generatorNumber,
    this.readingSlot,
    required this.timestamp,
    this.notes,
    this.signaturePath,
    this.photoPath,
    this.pdfPath,
    this.hmiPhotoPath,
    this.operatorName,
    this.biometricVerified = false,
    this.synced = false,
    required this.paramValues,
    this.paramPhotos = const {},
    this.groupComments = const {},
  });
}
