// Flutter stable 3.50 currently deprecates the umbrella Material import during its API migration.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../../transfers/transfer_history.dart';

class TransferHistoryScreen extends StatefulWidget {
  const TransferHistoryScreen({super.key});

  @override
  State<TransferHistoryScreen> createState() => _TransferHistoryScreenState();
}

class _TransferHistoryScreenState extends State<TransferHistoryScreen> {
  List<TransferHistoryEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await TransferHistoryStore.load();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    final date = '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
    final time = '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    return '$date · $time';
  }

  Widget _section({
    required String title,
    required String direction,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final files = _entries
        .where((entry) => entry.direction == direction && entry.type == 'file')
        .toList();
    final apps = _entries
        .where((entry) => entry.direction == direction && entry.type == 'app')
        .toList();
    final all = [...files, ...apps]
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      )),
                ),
                Text('${all.length}',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    )),
                IconButton(
                  tooltip: 'Clear $title',
                  onPressed: all.isEmpty
                      ? null
                      : () async {
                          await TransferHistoryStore.clear(direction: direction);
                          await _load();
                        },
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            const Divider(),
            Text('FILES · ${files.length}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                )),
            if (files.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 10, 4, 14),
                child: Text('No file transfers yet.'),
              )
            else
              ...files.map((entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: Text(entry.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${entry.peer} · ${_date(entry.completedAt)}\n'
                      '${_size(entry.bytes)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )),
            const SizedBox(height: 8),
            Text('APPS · ${apps.length}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                )),
            if (apps.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 10, 4, 14),
                child: Text('No app transfers yet. App package sending and receiving are not connected yet.'),
              )
            else
              ...apps.map((entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.android_rounded),
                    title: Text(entry.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${entry.peer} · ${_date(entry.completedAt)}\n'
                      '${_size(entry.bytes)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Transfer history',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  )),
            ),
            IconButton(
              tooltip: 'Refresh history',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text('A record of completed file and app transfers on this device.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        if (_loading) const LinearProgressIndicator(),
        _section(
          title: 'Sent Files / Apps',
          direction: 'sent',
          icon: Icons.north_east_rounded,
        ),
        const SizedBox(height: 12),
        _section(
          title: 'Received Files / Apps',
          direction: 'received',
          icon: Icons.south_west_rounded,
        ),
      ],
    );
  }
}
