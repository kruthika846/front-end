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
  final String? signaturePath;
  final String? photoPath;
  final String? pdfPath;
  final String? hmiPhotoPath;
  final bool synced;

  /// Remote + local parameter values keyed by ParamDefinition.key.
  final Map<String, String> paramValues;

  /// Evidence photo of the physical gauge for a parameter, keyed the same
  /// way. Not every parameter has one — mainly used for local readings.
  final Map<String, String> paramPhotos;

  /// One comment per parameter group/panel (e.g. "remote::Turbocharger"),
  /// not per individual reading.
  final Map<String, String> groupComments;

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
    this.synced = false,
    required this.paramValues,
    this.paramPhotos = const {},
    this.groupComments = const {},
  });
}
