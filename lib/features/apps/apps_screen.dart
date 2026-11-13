// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_device_apps/flutter_device_apps.dart';

class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key});

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  List<AppInfo> _apps = [];
  final Set<String> _selected = {};
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      setState(() {
        _loaded = true;
        _error = 'Installed-app browsing is available on Android devices.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final apps = await FlutterDeviceApps.listApps(
        includeSystem: false,
        onlyLaunchable: true,
        includeIcons: true,
      );
      apps.sort((a, b) =>
          (a.appName ?? a.packageName ?? '').toLowerCase().compareTo(
                (b.appName ?? b.packageName ?? '').toLowerCase(),
              ));
      if (!mounted) return;
      setState(() {
        _apps = apps;
        _loaded = true;
        _selected.removeWhere((packageName) =>
            !apps.any((app) => app.packageName == packageName));
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not read installed apps: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _queueSelected() async {
    final chosen = _apps
        .where((app) => app.packageName != null && _selected.contains(app.packageName))
        .toList();
    if (chosen.isEmpty) return;
    final readable = <String>[];
    for (final app in chosen) {
      final path = app.apkPath;
      if (path == null || path.isEmpty) continue;
      try {
        if (await File(path).exists()) readable.add(app.appName ?? app.packageName ?? 'Unknown app');
      } catch (_) {
        // Some Android builds restrict direct reads of installed package paths.
      }
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('APK selection checked'),
        content: Text(
          '${readable.length} of ${chosen.length} selected base APKs are readable. '
          'Split APK collection, export into a shareable cache, and sending are the next app-sharing steps.',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Apps', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      Text('Browse installed Android apps and select the packages you want to share.',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(child: Text(
          _loaded ? '${_apps.length} user apps found' : 'Scanning installed apps…',
          style: const TextStyle(fontWeight: FontWeight.w700),
        )),
        IconButton(onPressed: _loading ? null : _loadApps, tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded)),
      ]),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null)
        Card(child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        )),
      if (!_loading && _loaded && _apps.isEmpty && _error == null)
        const Card(child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('No launchable user apps were found.'),
        )),
      ..._apps.map((app) {
        final packageName = app.packageName;
        final selected = packageName != null && _selected.contains(packageName);
        final iconBytes = app.iconBytes;
        final icon = iconBytes == null
            ? const Icon(Icons.android_rounded, size: 38)
            : Image.memory(iconBytes, width: 44, height: 44);
        return Card(
          child: CheckboxListTile(
            value: selected,
            onChanged: packageName == null
                ? null
                : (value) => setState(() {
                      if (value == true) {
                        _selected.add(packageName);
                      } else {
                        _selected.remove(packageName);
                      }
                    }),
            secondary: ClipRRect(borderRadius: BorderRadius.circular(10), child: icon),
            title: Text(app.appName ?? packageName ?? 'Unknown app',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${app.versionName ?? 'Version unknown'} · ${packageName ?? 'Package unknown'}',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            controlAffinity: ListTileControlAffinity.trailing,
          ),
        );
      }),
      if (_selected.isNotEmpty) ...[
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _queueSelected,
            icon: const Icon(Icons.archive_outlined),
            label: Text('Prepare ${_selected.length} selected APK(s)'),
          ),
        ),
      ],
      const SizedBox(height: 16),
      Card(
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded),
            SizedBox(width: 10),
            Expanded(child: Text(
              'This first app-sharing step reads app names, icons, versions and base APK paths. Split APKs, reliable package export and sending will be added before app sharing is considered complete.',
              style: TextStyle(fontSize: 12, height: 1.45),
            )),
          ]),
        ),
      ),
    ]);
  }
}
