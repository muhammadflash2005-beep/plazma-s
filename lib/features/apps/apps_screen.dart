// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_device_apps/flutter_device_apps.dart';

class AppsScreen extends StatefulWidget {
  const AppsScreen({required this.onSendSelected, super.key});

  final ValueChanged<int> onSendSelected;

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


  Widget _appCard(AppInfo app, ThemeData theme) {
    final packageName = app.packageName;
    final selected = packageName != null && _selected.contains(packageName);
    final iconBytes = app.iconBytes;
    final icon = iconBytes == null
        ? const Icon(Icons.android_rounded, size: 30)
        : Image.memory(iconBytes, width: 38, height: 38, fit: BoxFit.contain);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
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
          padding: const EdgeInsets.fromLTRB(3, 6, 3, 5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: icon,
                    ),
                  ),
                  if (selected)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        width: 17,
                        height: 17,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: theme.colorScheme.surface, width: 1.5),
                        ),
                        child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                app.appName ?? packageName ?? 'Unknown app',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9.5,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                  color: selected ? theme.colorScheme.primary : null,
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
          // Five compact app tiles fit across a typical phone content width.
          final columns = (constraints.maxWidth / 62).floor().clamp(2, 5);
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _apps.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 4,
              mainAxisSpacing: 5,
              childAspectRatio: 0.62,
            ),
            itemBuilder: (context, index) => _appCard(_apps[index], theme),
          );
        }),
      if (_selected.isNotEmpty) ...[
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => widget.onSendSelected(_selected.length),
            icon: const Icon(Icons.send_rounded),
            label: Text('Send ${_selected.length} selected app(s)'),
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
