import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';

String agoText(DateTime? t) {
  if (t == null) return 'never';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
}

String sizeText(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// The Sync tab (design, section 3): when this tablet last synced, what is waiting to go,
/// device storage, anything the server refused, and Sync now.
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  int? _storage;

  @override
  void initState() {
    super.initState();
    SyncService.storageUsed().then((b) => mounted ? setState(() => _storage = b) : null);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(syncProvider);
    final sync = ref.read(syncProvider.notifier);
    final fmt = DateFormat('dd MMM HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: RefreshIndicator(
        onRefresh: () => sync.syncNow(manual: true),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Last synced ${agoText(s.lastOk)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    if (s.lastOk != null)
                      Text(fmt.format(s.lastOk!), style: const TextStyle(color: AppColors.textMuted)),
                    const SizedBox(height: 10),
                    const Text(
                      'This tablet syncs by itself every 45 seconds while the app is open, and when it comes back to the front.',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                    if (s.lastError != null) ...[
                      const SizedBox(height: 10),
                      Text(s.lastError!, style: const TextStyle(color: AppColors.alarm)),
                    ] else if (s.offline) ...[
                      const SizedBox(height: 10),
                      const Text('The server can\'t be reached right now. Everything waits on this tablet.',
                          style: TextStyle(color: AppColors.gold)),
                    ],
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: s.running ? null : () => sync.syncNow(manual: true),
                      icon: s.running
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.sync),
                      label: Text(s.running ? 'Syncing…' : 'Sync now'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Waiting to go', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    _row('Changes (values, submissions)', '${s.pendingOps}'),
                    _row('Photos and PDFs', s.pendingPhotos == 0 ? '0' : '${s.pendingPhotos} (${sizeText(s.pendingBytes)})'),
                    const SizedBox(height: 6),
                    const Text(
                      'Values go first, photos after. A photo counts on the server only when its checksum matches.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Device storage', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    _row('Used by LogBridge (photos, PDFs, logs)', _storage == null ? '…' : sizeText(_storage!)),
                  ],
                ),
              ),
            ),
            if (s.refused.isNotEmpty) ...[
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Not accepted by the server', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      for (final r in s.refused)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.alarm.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(r.type, style: const TextStyle(color: AppColors.alarm, fontSize: 11.5, fontWeight: FontWeight.w700)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(r.message)),
                              Text(fmt.format(r.at), style: const TextStyle(color: AppColors.textFaint, fontSize: 11.5)),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      OutlinedButton(onPressed: sync.clearRefused, child: const Text('Clear this list')),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(k)),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
