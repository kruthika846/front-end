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
import 'package:logbridge/services/signing_service.dart';
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
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen(entryFormProvider, (_, __) {}); // keeps the form alive for the test
    final n = c.read(entryFormProvider.notifier);
    n.setValue('load_kw', '442');
    n.setReaderValue('lo_press', '0.40');
    expect(n.uncheckedFilled, ['lo_press']);
    expect(c.read(entryFormProvider).ocrValues, {'lo_press': '0.40'});
    n.setChecked('lo_press', true);
    expect(n.uncheckedFilled, isEmpty);
    n.setReaderValue('fo_press', '0.80');
    n.setValue('fo_press', '0.81'); // the person corrected it: checked, the reader's value is kept
    expect(n.uncheckedFilled, isEmpty);
    expect(c.read(entryFormProvider).ocrValues['fo_press'], '0.80');
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

  test('sent back with a reason, corrected and resubmitted, then signed with the PIN', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // (the database was emptied by the test above; deleting it again would close the app's handle)
    SharedPreferences.setMockInitialValues({});

    final auth = AuthService(store: MemorySecretStore());
    final duty = await auth.signIn(server!, 'demo.duty', 'LogBridge-demo-1');
    final cfgJson = await auth.cachedConfig('demo.duty');
    final cfg = ServerConfig.fromJson(cfgJson)!;
    final container = ProviderContainer(overrides: [
      sessionProvider.overrideWith((ref) => duty),
      authServiceProvider.overrideWithValue(auth),
    ]);
    addTearDown(container.dispose);
    final sync = container.read(syncProvider.notifier);
    final repo = LogbookRepository();

    final now = DateTime.now();
    final api = Dio(BaseOptions(baseUrl: server, headers: {'authorization': 'Bearer ${duty.token}'}, validateStatus: (_) => true));
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
    final photo = File('${Directory.systemTemp.path}/lb_sign_test_${now.microsecondsSinceEpoch}.jpg')
      ..writeAsBytesSync(List.generate(3000, (i) => i % 241));
    final first = LogbookEntry(
      id: 'sign-${now.microsecondsSinceEpoch}',
      engineId: 'Aux Engine $gen',
      generatorNumber: gen,
      readingSlot: slot,
      timestamp: now,
      operatorName: 'Demo Duty Engineer',
      paramValues: {'load_kw': '440', 'lo_temp': '60.6'},
      hmiPhotoPath: photo.path,
      logId: logId,
      status: 'submitted',
    );
    await repo.saveEntry(first, categoryByKey: const {});
    await sync.queueSubmit(first, cfg);
    await sync.syncNow(manual: true);
    expect(await repo.statusOf(logId), 'submitted');

    // the Chief Engineer: waiting, details, send back
    final chiefSession = await AuthService(store: MemorySecretStore()).signIn(server, 'demo.chief', 'LogBridge-demo-1');
    final chief = SigningService(chiefSession);
    final waiting = await chief.waiting(cfgJson);
    expect(waiting.map((w) => w.id), contains(logId));
    expect(waiting.firstWhere((w) => w.id == logId).logType, 'aux_engine');
    expect(roundLabel(cfgJson, 'aux_engine', slot == 'noon' ? 2 : 1), slot == 'noon' ? 'Noon' : 'Time');
    final d = await chief.detail(logId);
    expect((d['readings'] as List).map((r) => r['value']), containsAll(['440', '60.6']));
    await chief.sendBack(logId, 'Load looks low - check the HMI again');

    await sync.syncNow(manual: true);
    expect(await repo.statusOf(logId), 'rejected');
    final sentBack = (await repo.fetchRecentEntries(limit: 30, generatorNumber: gen)).firstWhere((e) => e.logId == logId);
    expect(sentBack.rejectReason, 'Load looks low - check the HMI again');

    // corrected and resubmitted as the same log; the photo is not sent twice
    final corrected = LogbookEntry(
      id: sentBack.id,
      engineId: sentBack.engineId,
      generatorNumber: gen,
      readingSlot: slot,
      timestamp: sentBack.timestamp,
      operatorName: 'Demo Duty Engineer',
      paramValues: {'load_kw': '452'}, // lo_temp cleared
      hmiPhotoPath: photo.path,
      logId: logId,
      status: 'submitted',
    );
    await repo.saveEntry(corrected, categoryByKey: const {});
    await sync.queueSubmit(corrected, cfg, previous: sentBack);
    await sync.syncNow(manual: true);
    expect(container.read(syncProvider).refused, isEmpty);
    expect(await repo.statusOf(logId), 'submitted');
    final d2 = await chief.detail(logId);
    final values = [for (final r in d2['readings'] as List) r['value']];
    expect(values, contains('452'));
    expect(values, isNot(contains('60.6')), reason: 'the cleared value is cleared on the server too');
    expect((d2['photos'] as List).length, 1);

    // a wrong PIN changes nothing; the right one signs
    await expectLater(chief.approve(logId, '000000'), throwsA(isA<SigningException>()));
    expect((await chief.detail(logId))['status'], 'submitted');
    await chief.approve(logId, '123456');
    await sync.syncNow(manual: true);
    expect(await repo.statusOf(logId), 'approved');
    photo.deleteSync();
  }, skip: server == null ? 'set LOGBRIDGE_TEST_SERVER to run against a LogBridge server' : false);
}
