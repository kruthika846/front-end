/// The vessel configuration the LogBridge server sent at sign-in: which server screen each
/// generator is, and the server's id for each parameter. A log's id is built the way the
/// server builds it - L-<vessel>-<screen>-<date>-<round> - so the same log captured on two
/// tablets lands on one server row (design, section 5).
class ServerConfig {
  final int vesselId;
  final Map<int, ({int screenId, Map<String, int> dataPoints})> generators;

  const ServerConfig(this.vesselId, this.generators);

  static String screenCode(int generator) => 'AE-GEN-$generator';

  /// Time is round 1 and Noon round 2 of the server's aux engine log type.
  static int roundOf(String slot) => slot == 'noon' ? 2 : 1;

  static ServerConfig? fromJson(Map<String, dynamic>? cfg) {
    if (cfg == null) return null;
    final vessel = cfg['vessel'] as Map<String, dynamic>?;
    if (vessel == null) return null;
    final gens = <int, ({int screenId, Map<String, int> dataPoints})>{};
    for (final s in (cfg['screens'] as List? ?? const [])) {
      final m = RegExp(r'^AE-GEN-(\d+)$').firstMatch('${s['code']}');
      if (m == null) continue;
      gens[int.parse(m.group(1)!)] = (
        screenId: (s['id'] as num).toInt(),
        dataPoints: {
          for (final d in (s['data_points'] as List? ?? const []))
            if (d['retired'] != true) '${d['key']}': (d['id'] as num).toInt(),
        },
      );
    }
    return ServerConfig((vessel['id'] as num).toInt(), gens);
  }

  String logId(int generator, DateTime date, String slot) {
    final d = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return 'L-$vesselId-${generators[generator]!.screenId}-$d-${roundOf(slot)}';
  }
}
