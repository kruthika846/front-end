import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/logbook_repository.dart';
import '../data/parameter_config.dart';

final logbookRepositoryProvider = Provider<LogbookRepository>((ref) {
  return LogbookRepository();
});

/// Loads the form schema from assets/config/engine_parameters.json once
/// and caches it. Riverpod re-runs this automatically if invalidated.
final parameterConfigProvider = FutureProvider<ParameterConfig>((ref) async {
  return ParameterConfig.load();
});
