// Flutter stable 3.50 currently deprecates the umbrella Material import during its API migration.
// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import '../../transfers/transfer_history.dart';
import '../apps/apk_bundle.dart';
import '../apps/install_status_store.dart';

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
    InstallStatusStore.installed.addListener(_onInstallStatusChanged);
  }

  @override
  void dispose() {
    InstallStatusStore.installed.removeListener(_onInstallStatusChanged);
    super.dispose();
  }

  void _onInstallStatusChanged() {
    if (mounted) setState(() {});
  }
  String _selectedDirection = 'received';

  static const _audioExtensions = {
    'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'wma', 'aiff',
  };
  static const _videoExtensions = {'mp4', 'm4v', 'mov', 'mkv', 'webm', 'avi', '3gp', 'wmv', 'flv'};
  static const _imageExtensions = {
    'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await TransferHistoryStore.load();
    if (Platform.isAndroid) {
      final receivedApps = entries.where((entry) =>
          entry.direction == 'received' && entry.type == 'app');
      for (final entry in receivedApps) {
        try {
          final installed = await const MethodChannel('com.plazma.s/apps')
              .invokeMethod<bool>('isPackageInstalled', {'packageName': entry.name});
          if (installed != null) InstallStatusStore.report(entry.name, installed);
        } catch (_) {
          // Keep the Install action available if Android cannot confirm the package state.
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  String _category(TransferHistoryEntry entry) {
    if (entry.type == 'app') return 'app';
    if (entry.type == 'music') return 'music';
    if (entry.type == 'image') return 'image';
    if (entry.type == 'video') return 'video';
    final extension = entry.name.contains('.')
        ? entry.name.split('.').last.toLowerCase()
        : '';
    if (_audioExtensions.contains(extension)) return 'music';
    if (_imageExtensions.contains(extension)) return 'image';
    if (_videoExtensions.contains(extension)) return 'video';
    return 'file';
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

  Future<void> _installApp(TransferHistoryEntry entry) async {
    if (!Platform.isAndroid) {
      _message('Installing Android apps is available on Android devices.');
      return;
    }
    final folder = Directory(entry.installPath ?? entry.path);
    if (!await folder.exists()) {
      _message('This saved app is no longer available on this device.');
      return;
    }
    final apks = <File>[];
    await for (final item in folder.list(followLinks: false)) {
      if (item is File && item.path.toLowerCase().endsWith('.apk')) {
        apks.add(item);
      }
    }
    apks.sort((a, b) {
      final an = a.uri.pathSegments.last;
      final bn = b.uri.pathSegments.last;
      int rank(String name) {
        if (name == 'base.apk') return 0;
        final match = RegExp(r'^split_(\d+)\.apk$').firstMatch(name);
        return int.tryParse(match?.group(1) ?? '') ?? 999999;
      }
      return rank(an).compareTo(rank(bn));
    });
    if (apks.isEmpty || apks.first.uri.pathSegments.last != 'base.apk') {
      _message('The saved app package is incomplete and cannot be installed.');
      return;
    }
    try {
      if (apks.length == 1) {
        final cache = await getTemporaryDirectory();
        final staged = File('${cache.path}${Platform.pathSeparator}${entry.name}.apk');
        await apks.single.copy(staged.path);
        await ApkBundle.install(staged.path);
        InstallStatusStore.report(entry.name, true);
      } else {
        await const MethodChannel('com.plazma.s/apps').invokeMethod<void>(
          'installApkSet',
          {'packageName': entry.name, 'paths': apks.map((file) => file.path).toList()},
        );
      }
      _message('Android installer opened. Review and approve the installation.');
    } catch (error) {
      _message('Could not open the installer: $error');
    }
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Widget _categorySection(
    String direction,
    String category,
    String title,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    final items = _entries
        .where((entry) => entry.direction == direction && _category(entry) == category)
        .toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 5),
          child: Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(title.toUpperCase(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  )),
              const Spacer(),
              Text('${items.length}',
                  style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 5, 4, 9),
            child: Text('No $title transfers yet.',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          )
        else
          ...items.map((entry) => ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
                ),
                title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${entry.peer} · ${_date(entry.completedAt)}\n${_size(entry.bytes)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: category == 'app' && direction == 'received'
                    ? (InstallStatusStore.isInstalled(entry.name)
                        ? const Text('Installed', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w700))
                        : TextButton(
                            onPressed: () => _installApp(entry),
                            child: const Text('Install'),
                          ))
                    : null,
              )),
      ],
    );
  }

  Widget _directionCard({
    required String title,
    required String direction,
    required IconData icon,
  }) {
    final entries = _entries.where((entry) => entry.direction == direction).toList();
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(title,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                ),
                Text('${entries.length}',
                    style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w800)),
                IconButton(
                  tooltip: 'Clear $title',
                  onPressed: entries.isEmpty
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
            _categorySection(direction, 'file', 'Files', Icons.insert_drive_file_outlined),
            _categorySection(direction, 'app', 'Apps', Icons.android_rounded),
            _categorySection(direction, 'music', 'Music', Icons.music_note_rounded),
            _categorySection(direction, 'image', 'Images', Icons.image_outlined),
            _categorySection(direction, 'video', 'Videos', Icons.video_library_rounded),
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
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
            ),
            IconButton(
              tooltip: 'Refresh history',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text('Your sent and received files, apps, music and images stay listed here.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'received', label: Text('Received'), icon: Icon(Icons.download_rounded)),
            ButtonSegment(value: 'sent', label: Text('Sent'), icon: Icon(Icons.send_rounded)),
          ],
          selected: {_selectedDirection},
          onSelectionChanged: (values) => setState(() => _selectedDirection = values.first),
        ),
        if (_loading) const LinearProgressIndicator(),
        const SizedBox(height: 12),
        _directionCard(
          title: _selectedDirection == 'received' ? 'Received' : 'Sent',
          direction: _selectedDirection,
          icon: _selectedDirection == 'received' ? Icons.south_west_rounded : Icons.north_east_rounded,
        ),
      ],
    );
  }
}
