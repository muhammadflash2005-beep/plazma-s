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

  Widget _appCard(AppInfo app, ThemeData theme) {
    final packageName = app.packageName;
    final selected = packageName != null && _selected.contains(packageName);
    final iconBytes = app.iconBytes;
    final icon = iconBytes == null
        ? const Icon(Icons.android_rounded, size: 42)
        : Image.memory(iconBytes, width: 54, height: 54, fit: BoxFit.contain);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: packageName == null
            ? null
            : () => setState(() {
                  if (selected) {
                    _selected.remove(packageName);
                  } else {
                    _selected.add(packageName);
                  }
                }),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Align(
                alignment: Alignment.topRight,
                heightFactor: 1,
                child: Checkbox(
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
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 76,
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: icon,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                app.appName ?? packageName ?? 'Unknown app',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              Text(
                app.versionName ?? 'Version unknown',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                selected ? 'Selected' : 'Tap to select',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
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
      if (_apps.isNotEmpty)
        LayoutBuilder(builder: (context, constraints) {
          final columns = (constraints.maxWidth / 150).floor().clamp(2, 6);
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _apps.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.78,
            ),
            itemBuilder: (context, index) => _appCard(_apps[index], theme),
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
