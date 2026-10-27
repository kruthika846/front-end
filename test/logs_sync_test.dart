import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logbridge/data/app_database.dart';
import 'package:logbridge/data/logbook_repository.dart';
import 'package:logbridge/models/logbook_entry.dart';
import 'package:logbridge/models/param_definition.dart';
import 'package:logbridge/providers/entry_form_provider.dart';
import 'package:logbridge/providers/session_provider.dart';
import 'package:logbridge/services/auth_service.dart';
import 'package:logbridge/services/server_config.dart';
import 'package:logbridge/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, dynamic> configJson() => {
      'vessel': {'id': 1, 'code': 'DEMO'},
      'screens': [
        {'id': 7, 'code': 'ER-HEADER', 'data_points': []},
        {
          'id': 40,
          'code': 'AE-GEN-1',
          'data_points': [
            {'id': 900, 'key': 'load_kw'},
            {'id': 901, 'key': 'lo_press'},
            {'id': 902, 'key': 'old_one', 'retired': true},
          ],
        },
        {'id': 41, 'code': 'AE-GEN-2', 'data_points': []},
      ],
    };

void main() {
  test('the server log id: vessel, the generator\'s screen, date, Time or Noon', () {
    final cfg = ServerConfig.fromJson(configJson())!;
    expect(cfg.generators.keys, [1, 2]);
    expect(cfg.generators[1]!.dataPoints, {'load_kw': 900, 'lo_press': 901});
    expect(cfg.logId(1, DateTime(2026, 10, 27, 9), 'time'), 'L-1-40-2026-10-27-1');
    expect(cfg.logId(2, DateTime(2026, 1, 5, 12), 'noon'), 'L-1-41-2026-01-05-2');
    expect(ServerConfig.fromJson(null), isNull);
  });

  test('typed values count as checked; reader values wait for a person', () {
    final n = EntryFormNotifier();
    n.setValue('load_kw', '442');
    n.setReaderValue('lo_press', '0.40');
    expect(n.uncheckedFilled, ['lo_press']);
    expect(n.debugState.ocrValues, {'lo_press': '0.40'});
    n.setChecked('lo_press', true);
    expect(n.uncheckedFilled, isEmpty);
    n.setReaderValue('fo_press', '0.80');
    n.setValue('fo_press', '0.81'); // the person corrected it: checked, the reader's value is kept
    expect(n.uncheckedFilled, isEmpty);
    expect(n.debugState.ocrValues['fo_press'], '0.80');
    n.setReaderValue('cfw_in_press', '0.37');
    n.checkAll();
    expect(n.uncheckedFilled, isEmpty);
  });

  // End to end against a LogBridge server seeded with the aux engines:
  // LOGBRIDGE_TEST_SERVER=http://127.0.0.1:8091
  final server = Platform.environment['LOGBRIDGE_TEST_SERVER'];
  test('submit an entry, sync it, and see it signed', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.deleteDatabase('${await getDatabasesPath()}/logbridge.db');
    SharedPreferences.setMockInitialValues({});

    final auth = AuthService(store: MemorySecretStore());
    final session = await auth.signIn(server!, 'demo.duty', 'LogBridge-demo-1');
    final cfg = ServerConfig.fromJson(await auth.cachedConfig('demo.duty'))!;
    expect(cfg.generators.keys, containsAll([1, 2, 3]));

    final container = ProviderContainer(overrides: [
      sessionProvider.overrideWith((ref) => session),
      authServiceProvider.overrideWithValue(auth),
    ]);
    addTearDown(container.dispose);
    final sync = container.read(syncProvider.notifier);
    final repo = LogbookRepository();

    final photo = File('${Directory.systemTemp.path}/lb_sync_test_${DateTime.now().microsecondsSinceEpoch}.jpg')
      ..writeAsBytesSync(List.generate(5000, (i) => i % 251));
    final now = DateTime.now();
    // a generator and column with no log on the server yet today (earlier runs signed theirs)
    final api = Dio(BaseOptions(baseUrl: server, headers: {'authorization': 'Bearer ${session.token}'}, validateStatus: (_) => true));
    var gen = 0;
    var slot = '';
    for (final (g, s) in [(1, 'time'), (1, 'noon'), (2, 'time'), (2, 'noon'), (3, 'time'), (3, 'noon')]) {
      if ((await api.get('/api/logs/${cfg.logId(g, now, s)}')).statusCode == 404) {
        (gen, slot) = (g, s);
        break;
      }
    }
    expect(gen, isNot(0), reason: 'reseed the test server: every generator log of today is used');
    final logId = cfg.logId(gen, now, slot);
    final entry = LogbookEntry(
      id: 'test-${now.microsecondsSinceEpoch}',
      engineId: 'Aux Engine 1',
      generatorNumber: gen,
      readingSlot: slot,
      timestamp: now,
      operatorName: 'Demo Duty Engineer',
      paramValues: {'load_kw': '442', 'lo_press': '0.41', 'cfw_inlet_valve': 'OK'},
      ocrValues: {'lo_press': '0.40'},
      hmiPhotoPath: photo.path,
      logId: logId,
      status: 'submitted',
    );
    await repo.saveEntry(entry, categoryByKey: {'load_kw': ParamCategory.remote, 'lo_press': ParamCategory.remote});
    await sync.queueSubmit(entry, cfg);
    expect(container.read(syncProvider).pendingOps, greaterThan(3));

    await sync.syncNow(manual: true);
    final st = container.read(syncProvider);
    expect(st.lastError, isNull);
    expect(st.pendingOps, 0);
    expect(st.pendingPhotos, 0, reason: 'the photo was received with a matching checksum');
    expect(st.refused, isEmpty);
    expect(await repo.statusOf(logId), 'submitted');

    // what the server holds
    final d = (await api.get('/api/logs/$logId')).data as Map;
    expect(d['status'], 'submitted');
    final byId = {for (final r in d['readings'] as List) r['data_point_id']: r};
    final lo = byId[cfg.generators[gen]!.dataPoints['lo_press']];
    expect(lo['value'], '0.41');
    expect(lo['ocr_value'], '0.40', reason: 'the correction pair is kept');
    expect(lo['confirmed'], isTrue);
    expect((d['photos'] as List).single['received'], 1);

    // a second person signs it with the PIN; the tablet sees it on its next sync
    final chief = await AuthService(store: MemorySecretStore()).signIn(server, 'demo.chief', 'LogBridge-demo-1');
    await Dio(BaseOptions(baseUrl: server, headers: {'authorization': 'Bearer ${chief.token}'}))
        .post('/api/logs/$logId/approve', data: {'pin': '123456'});
    await sync.syncNow(manual: true);
    expect(await repo.statusOf(logId), 'approved');

    // and the database file is the app's own
    expect(await AppDatabase.instance.database, isNotNull);
    photo.deleteSync();
  }, skip: server == null ? 'set LOGBRIDGE_TEST_SERVER to run against a LogBridge server' : false);
}
