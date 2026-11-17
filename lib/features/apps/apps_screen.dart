// ignore_for_file: deprecated_member_use, prefer_interpolation_to_compose_strings
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'apk_bundle.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../media/permanent_delete_confirmation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_device_apps/flutter_device_apps.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../network/android_wifi_session_service.dart';
import '../../transfers/transfer_overlay_controller.dart';
import '../../transfers/xender_local_transfer_service.dart';

class DesktopInstalledApp {
  const DesktopInstalledApp({required this.name, required this.version, required this.publisher, required this.installLocation});
  final String name;
  final String version;
  final String publisher;
  final String? installLocation;
  bool get canBundle => installLocation != null;

  factory DesktopInstalledApp.fromRegistry(Map<String, dynamic> value) {
    String read(String key) => (value[key] ?? '').toString().trim();
    var location = read('InstallLocation');
    if (location.isEmpty) {
      var icon = read('DisplayIcon');
      if (icon.startsWith('"')) {
        final end = icon.indexOf('"', 1);
        if (end > 1) icon = icon.substring(1, end);
      } else {
        icon = icon.replaceFirst(RegExp(r',-?\d+$'), '');
      }
      if (icon.isNotEmpty && File(icon).existsSync()) location = File(icon).parent.path;
    }
    if (location.isNotEmpty) {
      final normalized = location.replaceAll('"', '').trim();
      final lower = normalized.toLowerCase();
      if (!Directory(normalized).existsSync() || lower.contains(r'\windowsapps') ||
          lower.startsWith(r'c:\windows') || lower.startsWith(r'c:\programdata\microsoft\windows')) {
        location = '';
      } else {
        location = normalized;
      }
    }
    return DesktopInstalledApp(name: read('DisplayName'), version: read('DisplayVersion'),
      publisher: read('Publisher'), installLocation: location.isEmpty ? null : location);
  }
}

class AppsScreen extends StatefulWidget {
  static final ValueNotifier<int> selectedCount = ValueNotifier<int>(0);
  static VoidCallback? sendSelected;

  const AppsScreen({super.key});
  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  final _service = XenderLocalTransferService();
  final List<AppInfo> _apps = [];
  final Set<String> _selected = {};
  final Map<String, List<SharedLocalFile>> _incoming = {};
  final Map<String, String> _saved = {};
  final Map<String, int> _appSizes = {};
  final Map<String, Map<String, dynamic>> _incomingDetails = {};
  final Map<String, Future<void>> _saveTasks = {};
  final Map<String, Future<Uint8List?>> _iconFutures = {};
  final List<DesktopInstalledApp> _desktopApps = [];
  final Set<String> _desktopSelected = {};
  String _desktopSearchQuery = '';
  static const int _appPageSize = 60;
  int _visibleAppCount = _appPageSize;
  String _appSearchQuery = '';
  bool _preparing = false;
  int _preparedApps = 0;
  int _preparingTotal = 0;
  String? _preparingAppName;
  Directory? _library;
  PlazmaConnectionInvite? _invite;
  PlazmaConnectionInvite? _receiver;
  bool _loading = false, _busy = false;
  bool _receivedRoom = false;
  Timer? _roomRefreshTimer;
  StreamSubscription<List<SharedLocalFile>>? _manifestSubscription;
  double _progress = 0;
  String? _status, _error;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      const MethodChannel('com.plazma.s/apps').setMethodCallHandler(_handleInstallerCallback);
    }
    AppsScreen.sendSelected = _send;
    _service.roomFiles.addListener(_syncRoomFiles);
    _syncRoomFiles();
    _invite = _service.invite;
    _receiver = _service.joinedInvite;
    if (_receiver != null) _watchIncomingApps(_receiver!);
    _load();
  }

  Future<void> _handleInstallerCallback(MethodCall call) async {
    if (call.method != 'installStatus' || !mounted) return;
    final details = Map<String, dynamic>.from(call.arguments as Map);
    final message = (details['message'] ?? 'Android installer returned an unknown result.').toString();
    setState(() => _status = message);
    _message(message);
  }

  void _updateSelectionCount() => AppsScreen.selectedCount.value = _selected.length;

  List<AppInfo> get _filteredApps {
    final query = _appSearchQuery.trim().toLowerCase();
    if (query.isEmpty) return _apps;
    return _apps.where((app) =>
      (app.appName ?? '').toLowerCase().contains(query) ||
      (app.packageName ?? '').toLowerCase().contains(query)).toList();
  }

  void _selectAllVisibleApps() {
    final targets = _filteredApps.take(_visibleAppCount).where((app) =>
      app.packageName != null && !_selected.contains(app.packageName)).toList();
    setState(() => _selected.addAll(targets.map((app) => app.packageName!)));
    _updateSelectionCount();
    for (final app in targets) {
      final package = app.packageName!;
      unawaited(_saveApp(package, app.appName ?? package).catchError((Object error) {
        if (mounted) _message('Could not save ${app.appName ?? package}: $error');
      }));
    }
  }

  void _clearSelectedApps() {
    setState(() => _selected.clear());
    _updateSelectionCount();
  }

  Future<void> _load() async {
    if (kIsWeb) {
      setState(() => _error = 'App package transfer is available in the installed Plazma S app.');
      return;
    }
    if (!Platform.isAndroid) {
      setState(() => _loading = true);
      try {
        final root = await getApplicationSupportDirectory();
        final library = Directory(root.path + Platform.pathSeparator + 'received_installers');
        await library.create(recursive: true);
        if (!mounted) return;
        setState(() => _library = library);
        if (Platform.isWindows) {
          await _loadWindowsApps();
        } else if (mounted) {
          setState(() => _error = 'Send complete installers or portable bundles (.exe, .msi, .dmg, .pkg, .AppImage, .deb, .rpm or .zip).');
        }
      } catch (e) {
        if (mounted) setState(() => _error = 'Could not prepare the installer library: ' + e.toString());
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }
    setState(() => _loading = true);
    try {
      final root = await getApplicationSupportDirectory();
      final library = Directory(root.path + Platform.pathSeparator + 'saved_apps');
      await library.create(recursive: true);
      final apps = await FlutterDeviceApps.listApps(
        includeSystem: false, onlyLaunchable: true, includeIcons: false);
      apps.removeWhere((app) => (app.packageName ?? '').startsWith('org.chromium.webapk.'));
      apps.sort((a,b) => (a.appName ?? '').toLowerCase().compareTo((b.appName ?? '').toLowerCase()));
      final nativeDetails = await const MethodChannel('com.plazma.s/apps')
          .invokeListMethod<dynamic>('listInstalledApps') ?? const <dynamic>[];
      final appSizes = <String, int>{};
      for (final value in nativeDetails.whereType<Map>()) {
        final detail = Map<String, dynamic>.from(value);
        final packageName = detail['packageName'];
        final size = detail['sizeBytes'];
        if (packageName is String && size is num) appSizes[packageName] = size.toInt();
      }
      final saved = <String,String>{};
      await for (final entity in library.list(followLinks: false)) {
        if (entity is Directory) {
          final pkg = entity.path.split(Platform.pathSeparator).last;
          if (await File(entity.path + Platform.pathSeparator + 'base.apk').exists()) {
            final match = apps.where((a) => a.packageName == pkg);
            saved[pkg] = match.isEmpty ? pkg : (match.first.appName ?? pkg);
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _library = library;
        _apps..clear()..addAll(apps);
        _appSizes..clear()..addAll(appSizes);
        _visibleAppCount = _appPageSize;
        _iconFutures.clear();
        _saved..clear()..addAll(saved);
        _selected.removeWhere((p) => !apps.any((a) => a.packageName == p));
        _error = apps.isEmpty ? 'No installed apps were returned. Check app visibility permissions, then tap refresh.' : null;
      });
    } catch (e) { if (mounted) setState(() => _error = 'Could not load apps: ' + e.toString()); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  String _formatAppSize(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  Future<Uint8List?> _appIcon(String packageName) {
    return _iconFutures.putIfAbsent(
      packageName,
      () => FlutterDeviceApps.getAppIcon(packageName),
    );
  }

  Future<List<Map<String,dynamic>>> _export(List<String> packages) async {
    final result = await const MethodChannel('com.plazma.s/apps')
        .invokeListMethod<dynamic>('exportApks', {'packageNames': packages});
    final items = (result ?? []).whereType<Map>()
        .map((e) => Map<String,dynamic>.from(e)).toList();
    if (items.isEmpty) throw StateError('Android did not export any APK files.');
    return items;
  }

  Future<void> _saveApp(String pkg, String name) {
    if (_saved.containsKey(pkg)) return Future<void>.value();
    final existing = _saveTasks[pkg];
    if (existing != null) return existing;

    late final Future<void> task;
    task = _performSaveApp(pkg, name).whenComplete(() {
      _saveTasks.remove(pkg);
    });
    _saveTasks[pkg] = task;
    return task;
  }

  Future<void> _performSaveApp(String pkg, String name) async {
    if (_library == null) throw StateError('The Saved Apps folder is not ready.');
    final folder = Directory(_library!.path + Platform.pathSeparator + pkg);
    await folder.create(recursive: true);
    final items = await _export([pkg]);
    for (final item in items) {
      if (item['packageName'] != pkg ||
          item['path'] is! String ||
          item['relativePath'] is! String) {
        continue;
      }
      final filename = (item['relativePath'] as String).split('/').last;
      await File(item['path'] as String).copy(
        folder.path + Platform.pathSeparator + filename,
      );
    }
    if (!await File(folder.path + Platform.pathSeparator + 'base.apk').exists()) {
      throw StateError('The base APK could not be saved.');
    }
    if (!mounted) return;
    setState(() => _saved[pkg] = name);
  }

  Future<void> _manageInstalledApp(String packageName, String appName, String action) async {
    if (action == 'deleteSaved') {
      final directory = Directory(_library!.path + Platform.pathSeparator + packageName);
      if (!await directory.exists()) {
        if (mounted) setState(() => _saved.remove(packageName));
        return;
      }
      if (!mounted) return;
      final confirmed = await confirmPermanentDelete(context, itemDescription: 'the saved APK copy of $appName');
      if (!confirmed) return;
      try {
        await directory.delete(recursive: true);
        if (mounted) {
          setState(() => _saved.remove(packageName));
          _message('Saved APK copy deleted. The installed app was not uninstalled.');
        }
      } catch (error) {
        if (mounted) _message('Could not delete saved APK copy: $error');
      }
    } else if (action == 'settings') {
      try {
        await const MethodChannel('com.plazma.s/apps').invokeMethod<void>(
          'openAppSettings', {'packageName': packageName},
        );
      } catch (error) {
        if (mounted) _message('Could not open Android app settings: $error');
      }
    }
  }

  Future<void> _toggleAppSelection(String pkg, String name) async {
    if (_selected.contains(pkg)) {
      setState(() => _selected.remove(pkg));
      _updateSelectionCount();
      return;
    }
    setState(() => _selected.add(pkg));
    _updateSelectionCount();

    // Selecting an app automatically stores its complete APK set locally.
    // The same in-flight task is reused if Send is tapped before saving ends.
    try {
      await _saveApp(pkg, name);
    } catch (e) {
      if (mounted) _message('Could not save $name automatically: $e');
    }
  }

  Future<void> _send() async {
    if (!Platform.isAndroid) {
      if (Platform.isWindows && _desktopSelected.isNotEmpty) {
        await _sendSelectedDesktopApps();
      } else {
        await _sendDesktopInstallers();
      }
      return;
    }
    if (_selected.isEmpty || _busy || _preparing) return;
    setState(() { _preparing = true; _preparedApps = 0; _preparingTotal = _selected.length; _status = 'Saving and preparing selected apps…'; });
    try {
      final packages = _apps
          .where((a) => a.packageName != null && _selected.contains(a.packageName))
          .map((a) => a.packageName!)
          .toList();

      // Finish any automatic saves started when the apps were selected.
      // Prepare sequentially so the displayed app name and completed count
      // always describe the same operation, and avoid competing APK exports.
      for (final pkg in packages) {
        final app = _apps.firstWhere((a) => a.packageName == pkg);
        if (mounted) setState(() => _preparingAppName = app.appName ?? pkg);
        await _saveApp(pkg, app.appName ?? pkg);
        if (mounted) setState(() => _preparedApps++);
      }
      if (mounted) setState(() { _preparing = false; _busy = true; _preparingAppName = null; });

      final files = <File>[], paths = <String>[];
      for (final pkg in packages) {
        final folder = Directory(_library!.path + Platform.pathSeparator + pkg);
        final savedFiles = <File>[];
        await for (final entity in folder.list(recursive: true, followLinks: false)) {
          if (entity is File && entity.path.toLowerCase().endsWith('.apk')) {
            savedFiles.add(entity);
          }
        }
        savedFiles.sort((x, y) {
          final xn = x.uri.pathSegments.last, yn = y.uri.pathSegments.last;
          if (xn == 'base.apk') return -1;
          if (yn == 'base.apk') return 1;
          return xn.compareTo(yn);
        });
        if (savedFiles.isEmpty || savedFiles.first.uri.pathSegments.last != 'base.apk') {
          throw StateError('The saved APK set for $pkg is incomplete.');
        }
        final bundleDirectory = Directory(
          _library!.path + Platform.pathSeparator + '.transfer-bundles',
        );
        final bundle = await ApkBundle.create(
          packageName: pkg,
          apkFiles: savedFiles,
          outputDirectory: bundleDirectory,
        );
        // A whole installed app (base APK + every split) is one transfer item.
        files.add(bundle);
        paths.add(pkg + '/' + bundle.uri.pathSegments.last);
      }

      final invite = await (_service.isSharing
          ? _service.addFiles(files: files, relativePaths: paths).then((_) => _service.invite!)
          : _service.startSharing(files: files, relativePaths: paths));
      if (!mounted) return;
      setState(() { _invite = invite; _selected.removeAll(packages); _status = 'Room ' + invite.roomId + ' is open. You can add more items from other tabs.'; });
      _updateSelectionCount();
      _updateDesktopSelectionCount();
      _roomRefreshTimer?.cancel();
      _roomRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      TransferOverlayController.show(TransferOverlaySnapshot(
        direction: TransferOverlayDirection.sending, fileCount: packages.length,
        label: 'Sharing apps', isAppTransfer: true));
    } catch (e) { _message('Could not start app sharing: ' + e.toString()); }
    finally { if (mounted) setState(() { _busy = false; _preparing = false; _preparingAppName = null; }); }
  }

  List<DesktopInstalledApp> get _filteredDesktopApps {
    final query = _desktopSearchQuery.trim().toLowerCase();
    if (query.isEmpty) return _desktopApps;
    return _desktopApps.where((app) => app.name.toLowerCase().contains(query) ||
      app.publisher.toLowerCase().contains(query)).toList();
  }

  String _encodePowerShell(String script) => base64.encode(
    script.codeUnits.expand((unit) => [unit & 0xff, (unit >> 8) & 0xff]).toList());

  Future<void> _loadWindowsApps() async {
    if (!Platform.isWindows) return;
    setState(() { _loading = true; _error = null; });
    const script = r'''
      $ErrorActionPreference = 'SilentlyContinue'
      $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
      )
      $apps = @(Get-ItemProperty -Path $roots |
        Where-Object { $_.DisplayName -and -not $_.SystemComponent -and $_.ReleaseType -notin @('Update','Hotfix','Security Update') } |
        Sort-Object DisplayName -Unique |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation, DisplayIcon)
      ConvertTo-Json -InputObject $apps -Depth 3 -Compress
    ''';
    try {
      final result = await Process.run('powershell.exe',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', _encodePowerShell(script)]);
      if (result.exitCode != 0) throw ProcessException('powershell.exe', [], result.stderr.toString(), result.exitCode);
      final output = result.stdout.toString().trim();
      final decoded = output.isEmpty ? <dynamic>[] : jsonDecode(output);
      final values = decoded is List ? decoded : [decoded];
      final apps = values.whereType<Map>().map((entry) =>
        DesktopInstalledApp.fromRegistry(Map<String, dynamic>.from(entry)))
        .where((app) => app.name.isNotEmpty).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _desktopApps..clear()..addAll(apps);
        _desktopSelected.removeWhere((name) => !apps.any((app) => app.name == name && app.canBundle));
        _error = apps.isEmpty ? 'No installed desktop applications were found in the Windows app registry.' : null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not read installed Windows apps: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _updateDesktopSelectionCount() => AppsScreen.selectedCount.value = _desktopSelected.length;

  void _toggleDesktopApp(DesktopInstalledApp app) {
    if (!app.canBundle) {
      _message('No accessible install folder was found for ${app.name}. Use Choose installer to share its setup file.');
      return;
    }
    setState(() {
      if (!_desktopSelected.add(app.name)) _desktopSelected.remove(app.name);
    });
    _updateDesktopSelectionCount();
  }

  Future<File> _bundleDesktopApp(DesktopInstalledApp app, Directory output) async {
    final source = app.installLocation;
    if (source == null) throw StateError('No accessible installation folder for ${app.name}.');
    final safeName = app.name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_').trim();
    final destination = '${output.path}${Platform.pathSeparator}${safeName.isEmpty ? 'Application' : safeName}.zip';
    String quote(String value) => "'" + value.replaceAll("'", "''") + "'";
    final script = r'''
      $ErrorActionPreference = 'Stop'
      $source = __SOURCE__
      $destination = __DESTINATION__
      if (!(Test-Path -LiteralPath $source -PathType Container)) { throw 'Application folder is no longer available.' }
      $items = @(Get-ChildItem -LiteralPath $source -Force | Select-Object -ExpandProperty FullName)
      if ($items.Count -eq 0) { throw 'Application folder is empty.' }
      if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Force }
      Compress-Archive -Path (Join-Path $source '*') -DestinationPath $destination -CompressionLevel Fastest -Force
      if (!(Test-Path -LiteralPath $destination -PathType Leaf)) { throw 'Bundle archive was not created.' }
    '''
      .replaceAll('__SOURCE__', quote(source))
      .replaceAll('__DESTINATION__', quote(destination));
    final result = await Process.run('powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', _encodePowerShell(script)]);
    if (result.exitCode != 0 || !await File(destination).exists()) {
      throw StateError('Could not bundle ${app.name}: ${result.stderr}');
    }
    return File(destination);
  }

  Future<void> _sendSelectedDesktopApps() async {
    if (_busy || _desktopSelected.isEmpty || _library == null) return;
    setState(() { _busy = true; _status = 'Preparing selected Windows applications…'; });
    try {
      final selected = _desktopApps.where((app) => _desktopSelected.contains(app.name) && app.canBundle).toList();
      if (selected.isEmpty) throw StateError('None of the selected apps has an accessible install folder.');
      final output = Directory('${_library!.path}${Platform.pathSeparator}desktop_app_bundles');
      await output.create(recursive: true);
      final files = <File>[];
      final paths = <String>[];
      for (var i = 0; i < selected.length; i++) {
        final app = selected[i];
        if (mounted) setState(() => _status = 'Packaging ${app.name} · ${i + 1}/${selected.length}');
        final bundle = await _bundleDesktopApp(app, output);
        files.add(bundle);
        paths.add('Applications/${bundle.uri.pathSegments.last}');
      }
      final invite = await (_service.isSharing
          ? _service.addFiles(files: files, relativePaths: paths).then((_) => _service.invite!)
          : _service.startSharing(files: files, relativePaths: paths));
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _desktopSelected.clear();
        _status = 'Packaged ${files.length} app(s). Room ${invite.roomId} is open; recipients receive ZIP bundles.';
      });
      _roomRefreshTimer?.cancel();
      _roomRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
      TransferOverlayController.show(TransferOverlaySnapshot(
        direction: TransferOverlayDirection.sending, fileCount: files.length,
        label: 'Sharing Windows apps', isAppTransfer: true));
    } catch (error) {
      _message('Could not package Windows apps: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendDesktopInstallers() async {
    if (_busy) return;
    setState(() { _busy = true; _status = 'Choose application installers or portable app bundles…'; });
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['exe', 'msi', 'msix', 'appx', 'appimage', 'deb', 'rpm', 'dmg', 'pkg', 'zip'],
      );
      if (result.isEmpty) return;
      final files = <File>[];
      final paths = <String>[];
      for (final picked in result) {
        if (picked.path == null) continue;
        files.add(File(picked.path!));
        paths.add('Applications/' + picked.name);
      }
      if (files.isEmpty) throw StateError('The selected packages are not accessible as files.');
      final invite = await (_service.isSharing
          ? _service.addFiles(files: files, relativePaths: paths).then((_) => _service.invite!)
          : _service.startSharing(files: files, relativePaths: paths));
      if (!mounted) return;
      setState(() { _invite = invite; _status = 'Room ' + invite.roomId + ' is open. Waiting for devices.'; });
      _roomRefreshTimer?.cancel();
      _roomRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
    } catch (e) {
      _message('Could not share application installers: ' + e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  Future<PlazmaConnectionInvite?> _scan() async {
    if (!Platform.isAndroid) {
      final controller = TextEditingController();
      final raw = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Join app-sharing room'),
          content: TextField(controller: controller, minLines: 2, maxLines: 4,
            decoration: const InputDecoration(labelText: 'Paste room connection code')),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()), child: const Text('Join')),
          ],
        ),
      );
      controller.dispose();
      if (raw == null) return null;
      final invite = PlazmaConnectionInvite.tryParse(raw);
      if (invite == null) _message('That is not a valid Plazma S room code.');
      return invite;
    }
    return showDialog<PlazmaConnectionInvite>(
    context: context, builder: (dialogContext) {
      var handled = false;
      return AlertDialog(
        title: const Text('Scan app-sharing QR code'),
        content: SizedBox(height: 330, child: Column(children: [
          const Text('Scan the QR code shown on the sending phone.'),
          const SizedBox(height: 12),
          Expanded(child: MobileScanner(onDetect: (capture) {
            if (handled) return;
            for (final code in capture.barcodes) {
              final invite = PlazmaConnectionInvite.tryParse(code.rawValue ?? '');
              if (invite != null) {
                handled = true;
                Navigator.of(dialogContext).pop(invite);
                break;
              }
            }
          })),
        ])),
        actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel'))],
      );
    });
  }

  bool _isAppTransferItem(SharedLocalFile item) =>
      ApkBundle.isBundlePath(item.relativePath) || ApkBundle.isApkPath(item.relativePath);

  void _syncRoomFiles() {
    final invite = _service.joinedInvite;
    final groups = <String, List<SharedLocalFile>>{};
    if (invite != null) {
      for (final item in _service.roomFiles.value) {
        if (!_isAppTransferItem(item)) continue;
        final package = item.relativePath.split('/').first;
        if (package.isNotEmpty && !package.contains('..')) groups.putIfAbsent(package, () => []).add(item);
      }
    }
    if (!mounted) return;
    setState(() { _receiver = invite; _incoming..clear()..addAll(groups); });
  }
  void _watchIncomingApps(PlazmaConnectionInvite invite) {
    _manifestSubscription?.cancel();
    _manifestSubscription = _service.watchManifest(invite).listen((manifest) {
      final groups = <String, List<SharedLocalFile>>{};
      for (final item in manifest) {
        if (!_isAppTransferItem(item)) continue;
        final package = item.relativePath.split('/').first;
        if (package.isNotEmpty && !package.contains('..')) groups.putIfAbsent(package, () => []).add(item);
      }
      if (!mounted) return;
      setState(() { _incoming..clear()..addAll(groups); _status = '${groups.length} app(s) available in this room.'; });
    }, onError: (Object error) { if (mounted) _message('Live room update failed: $error'); });
  }

  Future<void> _receive() async {
    if (_busy) return;
    final invite = await _scan();
    if (invite == null || !mounted) return;
    setState(() { _busy = true; _status = 'Connecting to sender…'; });
    try {
      final manifest = await _service.joinAndList(invite);
      if (!Platform.isAndroid) {
        if (manifest.isEmpty) throw StateError('The sender has not shared any application packages yet.');
        if (!mounted) return;
        setState(() {
          _receiver = invite;
          _incoming..clear()..['Application installers'] = manifest;
          _status = manifest.length.toString() + ' application package(s) ready to receive.';
        });
        _watchIncomingApps(invite);
        return;
      }
      final groups = <String,List<SharedLocalFile>>{};
      for (final item in manifest) {
        if (!_isAppTransferItem(item)) continue;
        final pkg = item.relativePath.split('/').first;
        if (pkg.isNotEmpty && !pkg.contains('..')) groups.putIfAbsent(pkg, () => []).add(item);
      }
      
      if (!mounted) return;
      setState(() { _receiver = invite; _incoming..clear()..addAll(groups); _status = 'Apps ready to receive.'; });
      _watchIncomingApps(invite);
      TransferOverlayController.show(TransferOverlaySnapshot(
        direction: TransferOverlayDirection.receiving, fileCount: groups.length,
        label: 'Receiving files', isAppTransfer: groups.isNotEmpty));
      if (mounted) setState(() => _busy = false);
      await _download(automatic: true);
    } catch (e) { await _service.disconnect(); _message('Could not connect: ' + e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _refreshIncomingApps() async {
    if (_receiver == null || _busy) return;
    try {
      final manifest = await _service.refreshManifest(_receiver!);
      final groups = <String,List<SharedLocalFile>>{};
      for (final item in manifest) {
        if (!_isAppTransferItem(item)) continue;
        final pkg = item.relativePath.split('/').first;
        if (pkg.isNotEmpty && !pkg.contains('..')) groups.putIfAbsent(pkg, () => []).add(item);
      }
      setState(() {
        _incoming..clear()..addAll(groups);
        _status = '${groups.length} app(s) available in this room.';
      });
    } catch (e) { _message('Could not refresh shared apps: $e'); }
  }

  Future<void> _extractIncomingBundles(Directory documentsRoot) async {
    for (final entry in _incoming.entries) {
      final bundles = entry.value
          .where((item) => ApkBundle.isBundlePath(item.relativePath))
          .toList();
      if (bundles.isEmpty) continue;
      if (bundles.length != 1 || entry.value.length != 1) {
        throw StateError('An app must arrive as exactly one grouped APK bundle.');
      }
      if (!ApkBundle.isValidPackageName(entry.key)) {
        throw FormatException('Invalid Android package folder: ${entry.key}');
      }
      final bundleName = bundles.single.relativePath.split('/').last;
      final folder = Directory(
        documentsRoot.path + Platform.pathSeparator + 'Plazma S Received' +
        Platform.pathSeparator + 'Download' + Platform.pathSeparator + 'Plazma S' +
        Platform.pathSeparator + entry.key,
      );
      final bundleFile = File(folder.path + Platform.pathSeparator + bundleName);
      if (!await bundleFile.exists()) {
        throw StateError('The grouped APK bundle for ${entry.key} was not saved.');
      }
      final actualDigest = await sha256.bind(bundleFile.openRead()).first;
      if (actualDigest.toString() != bundles.single.sha256) {
        throw StateError('The grouped APK bundle checksum is invalid for ${entry.key}.');
      }
      await ApkBundle.extract(
        bundle: bundleFile,
        expectedPackageName: entry.key,
        destinationDirectory: folder,
      );
    }
  }

  Future<void> _inspectIncomingApps() async {
    if (!Platform.isAndroid || _library == null) return;
    final root = await getApplicationDocumentsDirectory();
    await _extractIncomingBundles(root);
    for (final entry in _incoming.entries) {
      final baseApk = File(root.path + Platform.pathSeparator + 'Plazma S Received' +
        Platform.pathSeparator + 'Download' + Platform.pathSeparator + 'Plazma S' +
        Platform.pathSeparator + entry.key + Platform.pathSeparator + 'base.apk');
      if (!await baseApk.exists()) continue;
      try {
        final details = await const MethodChannel('com.plazma.s/apps')
          .invokeMapMethod<String, dynamic>('inspectApk', {'path': baseApk.path});
        if (details == null || details['packageName'] != entry.key) {
          throw StateError('Received APK package metadata does not match the package folder.');
        }
        if (mounted) setState(() => _incomingDetails[entry.key] = details);
      } catch (error) {
        if (mounted) _message('Could not read received app details: ' + error.toString());
      }
    }
  }

  Future<void> _installReceivedApp(String packageName) async {
    if (!Platform.isAndroid) return;
    final root = await getApplicationDocumentsDirectory();
    final folder = Directory(root.path + Platform.pathSeparator + 'Plazma S Received' +
        Platform.pathSeparator + 'Download' + Platform.pathSeparator + 'Plazma S' +
        Platform.pathSeparator + packageName);
    if (!await folder.exists()) {
      _message('This app has not been saved on this device yet.');
      return;
    }
    try {
    final manifestParts = _incoming[packageName] ?? const <SharedLocalFile>[];
    final bundleParts = manifestParts
        .where((part) => ApkBundle.isBundlePath(part.relativePath))
        .toList();
    late final List<File> apks;
    if (bundleParts.isNotEmpty) {
      if (bundleParts.length != 1 || manifestParts.length != 1) {
        throw StateError('The app was not transferred as one complete bundle.');
      }
      final bundleFile = File(
        folder.path + Platform.pathSeparator + bundleParts.single.relativePath.split('/').last,
      );
      if (!await bundleFile.exists()) {
        throw StateError('The grouped APK bundle is missing. Receive the app again.');
      }
      final actual = await sha256.bind(bundleFile.openRead()).first;
      if (actual.toString() != bundleParts.single.sha256) {
        throw StateError('The grouped APK bundle checksum is invalid. Receive the app again.');
      }
      apks = await ApkBundle.extract(
        bundle: bundleFile,
        expectedPackageName: packageName,
        destinationDirectory: folder,
      );
    } else {
      // Compatibility with rooms created by older Plazma S versions.
      final legacyApks = <File>[];
      await for (final entry in folder.list(followLinks: false)) {
        if (entry is File && entry.path.toLowerCase().endsWith('.apk')) {
          legacyApks.add(entry);
        }
      }
      legacyApks.sort((a, b) => a.path.contains('base.apk')
          ? -1
          : b.path.contains('base.apk')
              ? 1
              : a.path.compareTo(b.path));
      if (legacyApks.isEmpty || !legacyApks.first.path.endsWith('base.apk')) {
        throw StateError('This app package is incomplete and cannot be installed.');
      }
      if (manifestParts.length != legacyApks.length) {
        throw StateError('The received app is missing one or more APK split files. Receive the complete app again.');
      }
      for (final apk in legacyApks) {
        final filename = apk.uri.pathSegments.last;
        final matches = manifestParts.where((part) => part.relativePath.split('/').last == filename);
        if (matches.length != 1) {
          throw StateError('No trusted transfer checksum was found for ' + filename + '.');
        }
        final actual = await sha256.bind(apk.openRead()).first;
        if (actual.toString() != matches.first.sha256) {
          throw StateError('Integrity check failed for ' + filename + '. Receive the app again before installing.');
        }
      }
      apks = legacyApks;
    }
      final inspected = await const MethodChannel('com.plazma.s/apps')
        .invokeMapMethod<String, dynamic>('inspectApk', {'path': apks.first.path});
      if (inspected == null || inspected['packageName'] != packageName) {
        throw StateError('The base APK is invalid or belongs to a different app.');
      }
      if (mounted) setState(() => _incomingDetails[packageName] = inspected);
      await const MethodChannel('com.plazma.s/apps').invokeMethod<void>(
        'installApkSet',
        {'packageName': packageName, 'paths': apks.map((file) => file.path).toList()},
      );
      _message('Android installer opened. Review and approve the installation.');
    } on PlatformException catch (error) {
      final detail = (error.message ?? error.toString()).toLowerCase();
      if (detail.contains('allow installs') || detail.contains('unknown app')) {
        _message('Allow Plazma S to install unknown apps in Android settings, return here, then tap Install again.');
      } else if (detail.contains('signature') || detail.contains('conflict')) {
        _message('Installation blocked by a package/signature conflict. Android may require uninstalling the existing app first; its data could be lost.');
      } else if (detail.contains('downgrade') || detail.contains('older version')) {
        _message('Android blocked this older app version. Install a newer or matching version instead.');
      } else if (detail.contains('storage') || detail.contains('space')) {
        _message('Not enough storage to install this app. Free space and try again.');
      } else if (detail.contains('incompatible') || detail.contains('abi')) {
        _message('This app is not compatible with this device or CPU architecture.');
      } else {
        _message('Android could not start installation: ${error.message ?? error.code}');
      }
    } catch (error) {
      _message('Could not start installation: $error');
    }
  }

  Future<void> _download({bool automatic = false}) async {
    if (_receiver == null || _library == null || (_busy && !automatic)) return;
    setState(() { _busy = true; _progress = 0; _status = 'Receiving apps…'; });
    try {
      final all = _service.roomFiles.value;
      final Directory receiveRoot;
      if (Platform.isAndroid) {
        final root = await getApplicationDocumentsDirectory();
        receiveRoot = Directory(root.path + Platform.pathSeparator + 'Plazma S Received');
      } else {
        receiveRoot = _library!;
      }
      await _service.downloadAll(invite: _receiver!, files: all, destination: receiveRoot,
        onProgress: (p) { if (mounted) setState(() => _progress = p.fraction.clamp(0.0,1.0)); },
        onSaved: (item, path, uri) => _savedMessage(path, uri));
      if (Platform.isAndroid) {
        for (final entry in _incoming.entries) {
          _saved[entry.key] = entry.key;
        }
        await _inspectIncomingApps();
      }
      if (!mounted) return;
      setState(() {
        _receivedRoom = true;
        _status = Platform.isAndroid
            ? 'Received and saved ' + _incoming.length.toString() + ' app(s).'
            : 'Received ' + all.length.toString() + ' item(s). Saved in ' + receiveRoot.path;
      });
      TransferOverlayController.clear();
      await _service.stopForegroundService();
    } catch (e) { _message('App transfer interrupted. Check Wi-Fi, then tap Retry failed in the room queue.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _stop() async {
    _roomRefreshTimer?.cancel();
    _roomRefreshTimer = null;
    await _service.stopSharing();
    TransferOverlayController.clear();
    if (mounted) {
      setState(() { _invite = null; _status = 'App sharing stopped.'; });
      _roomRefreshTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _status == 'App sharing stopped.') setState(() => _status = null);
      });
    }
  }

  Future<void> _disconnect() async {
    if (_busy) return;
    await _service.disconnect();
    TransferOverlayController.clear();
    if (mounted) setState(() { _receiver = null; _incoming.clear(); _receivedRoom = false; _status = 'Disconnected.'; });
  }

  void _savedMessage(String path, String? uri) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Saved to $path'),
      action: uri == null ? null : SnackBarAction(
        label: 'Open',
        onPressed: () {
          unawaited(const MethodChannel('com.plazma.s/storage').invokeMethod<void>(
            'openSavedFile', {'uri': uri},
          ));
        },
      ),
    ));
  }

  void _message(String s) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }

  @override
  void dispose() {
    if (Platform.isAndroid) {
      const MethodChannel('com.plazma.s/apps').setMethodCallHandler(null);
    }
    _roomRefreshTimer?.cancel();
    _manifestSubscription?.cancel();
    _service.roomFiles.removeListener(_syncRoomFiles);
    if (AppsScreen.sendSelected == _send) AppsScreen.sendSelected = null;
    AppsScreen.selectedCount.value = 0;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Apps', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      Text('Send complete installed apps. Selected apps are saved automatically for transfer.',
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
      const SizedBox(height: 14),
      if (_status != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_status!))),
      if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
      if (_loading) const LinearProgressIndicator(),
      if (_preparing) Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LinearProgressIndicator(value: _preparingTotal == 0 ? null : _preparedApps / _preparingTotal),
          const SizedBox(height: 5),
          Text('Preparing ${_preparingAppName ?? 'selected apps'} · $_preparedApps/$_preparingTotal',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
        ]),
      ),
      if (_invite != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        Text('Room ' + _invite!.roomId, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(10), color: Colors.white,
          child: QrImageView(data: _invite!.toQrValue(), size: 220)),
        const SizedBox(height: 8), Text('Same Wi-Fi · ' + _invite!.host + ':' + _invite!.port.toString()),
        TextButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: _invite!.roomId)), icon: const Icon(Icons.copy, size: 16), label: const Text('Copy room code')),
        PopupMenuButton<String>(
          tooltip: 'More room actions',
          onSelected: (value) { if (value == 'link') Clipboard.setData(ClipboardData(text: _invite!.toQrValue())); },
          itemBuilder: (context) => const [PopupMenuItem(value: 'link', child: Text('Copy connection link'))],
        ),
        Row(children: [Expanded(child: Text('Connected devices', style: const TextStyle(fontWeight: FontWeight.w800))), Text(_service.joinedDeviceCount.toString() + '/7')]),
        ..._service.roomMembers.map((member) => ListTile(dense: true, leading: Icon(member.platform == 'android' ? Icons.phone_android : Icons.computer), title: Text(member.deviceName), subtitle: Text(member.platform), trailing: Icon(member.completed ? Icons.check_circle : Icons.wifi, color: member.completed ? Colors.green : null))),
        const Text('Up to seven devices can join this room. Each selected app is sent as one app, with its APK parts grouped together.', textAlign: TextAlign.center),
        OutlinedButton.icon(onPressed: _busy ? null : _stop, icon: const Icon(Icons.stop), label: const Text('Stop sharing')),
      ]))),
      if (_receiver != null) Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
        Row(children: [Expanded(child: Text(_incoming.length.toString() + ' app(s) ready', style: const TextStyle(fontWeight: FontWeight.w800))),
          TextButton(onPressed: _busy ? null : _refreshIncomingApps, child: const Text('Refresh')),
          TextButton(onPressed: _busy ? null : _disconnect, child: const Text('Disconnect'))]),
        ..._incoming.entries.map((e) {
          final details = _incomingDetails[e.key];
          final iconData = details?['iconBase64'];
          final appName = (details?['appName'] ?? e.key).toString();
          final version = (details?['versionName'] ?? '').toString();
          return ListTile(
          leading: iconData is String
              ? Image.memory(base64Decode(iconData), width: 40, height: 40, fit: BoxFit.contain)
              : const Icon(Icons.android),
          title: Text(appName),
          subtitle: Text([e.key, if (version.isNotEmpty) 'Version ' + version, e.value.length.toString() + ' APK part(s)'].join(' · ')),
          trailing: _saved.containsKey(e.key)
              ? TextButton.icon(onPressed: _busy ? null : () => _installReceivedApp(e.key),
                  icon: const Icon(Icons.install_mobile_rounded), label: const Text('Install'))
              : null);
        }),
        if (Platform.isAndroid)
          const Padding(padding: EdgeInsets.only(top: 6), child: Text(
            'Apps are transferred as APK files only; app data and account data are not included. Some Play Store apps may not run because of licensing or device restrictions.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 11))),
        if (_busy) LinearProgressIndicator(value: _progress > 0 ? _progress : null),
        if (!_receivedRoom)
          FilledButton.icon(onPressed: _busy ? null : _download,
            icon: const Icon(Icons.download), label: Text(_busy ? 'Receiving files…' : 'Receive and save apps'))
        else
          const Text('Room files received and saved.'),
      ]))),
      if (_receiver == null) ...[
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: _busy || _preparing ? null : _receive,
            icon: const Icon(Icons.qr_code_scanner), label: const Text('Receive apps'))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: _busy || _preparing || (Platform.isAndroid && _selected.isEmpty) ? null : _send,
            icon: const Icon(Icons.send), label: Text(_service.isSharing ? 'Add to room' : (Platform.isAndroid ? 'Send selected' : (Platform.isWindows && _desktopSelected.isNotEmpty ? 'Send selected' : 'Choose installer'))))),
        ]),
        const SizedBox(height: 18),
        if (!Platform.isAndroid) ...[
          if (Platform.isWindows) ...[
            Row(children: [
              Expanded(child: Text('Installed Windows apps (${_filteredDesktopApps.length})',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
              IconButton(onPressed: _loading ? null : _loadWindowsApps, icon: const Icon(Icons.refresh)),
            ]),
            TextField(
              decoration: const InputDecoration(hintText: 'Search installed Windows apps', prefixIcon: Icon(Icons.search_rounded), isDense: true, border: OutlineInputBorder()),
              onChanged: (value) => setState(() => _desktopSearchQuery = value),
            ),
            Row(children: [
              TextButton(onPressed: () {
                setState(() {
                  _desktopSelected.addAll(_filteredDesktopApps.where((app) => app.canBundle).map((app) => app.name));
                });
                _updateDesktopSelectionCount();
              }, child: const Text('Select all')),
              TextButton(onPressed: () {
                setState(() => _desktopSelected.clear());
                _updateDesktopSelectionCount();
              }, child: const Text('Clear selection')),
              const Spacer(),
              Text('${_desktopSelected.length} selected', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
            ]),
            if (_desktopApps.isEmpty && !_loading)
              const Padding(padding: EdgeInsets.all(12), child: Text('No installed apps found. You can still choose an EXE or MSI installer below.')),
            ..._filteredDesktopApps.map((app) {
              final selected = _desktopSelected.contains(app.name);
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: CheckboxListTile(
                  value: selected,
                  onChanged: app.canBundle && !_busy ? (_) => _toggleDesktopApp(app) : null,
                  secondary: Icon(app.canBundle ? Icons.desktop_windows : Icons.install_desktop_outlined),
                  title: Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text([
                    if (app.version.isNotEmpty) 'Version ${app.version}',
                    if (app.publisher.isNotEmpty) app.publisher,
                    app.canBundle ? 'Install folder can be bundled' : 'Installer file required',
                  ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
                  controlAffinity: ListTileControlAffinity.trailing,
                  dense: true,
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Share an installer instead', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('Choose an EXE, MSI, MSIX or portable ZIP when an app cannot be safely bundled from its install folder. Installers remain the most reliable way to reproduce an app on another PC.'),
            const SizedBox(height: 6),
            const Text('Received ZIP bundles may need extracting. Some apps also require dependencies, services, registry settings or a separate installer and may not run by copying files alone.'),
          ]))),
        ],
        if (Platform.isAndroid) ...[
        Row(children: [Expanded(child: Text('Installed apps (' + _filteredApps.length.toString() + ')',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))]),
        TextField(
          decoration: const InputDecoration(hintText: 'Search installed apps', prefixIcon: Icon(Icons.search_rounded), isDense: true, border: OutlineInputBorder()),
          onChanged: (value) => setState(() { _appSearchQuery = value; _visibleAppCount = _appPageSize; }),
        ),
        Row(children: [
          TextButton(onPressed: _selectAllVisibleApps, child: const Text('Select all')),
          TextButton(onPressed: _clearSelectedApps, child: const Text('Clear selection')),
          const Spacer(),
          Text('${_selected.length} selected', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
        ]),
        LayoutBuilder(builder: (context, c) {
          final columns = (c.maxWidth / 62).floor().clamp(2,5);
          return GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            itemCount: _visibleAppCount.clamp(0, _filteredApps.length).toInt(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns, crossAxisSpacing: 4, mainAxisSpacing: 5, childAspectRatio: .58),
            itemBuilder: (context,index) {
              final app = _filteredApps[index], pkg = app.packageName;
              final selected = pkg != null && _selected.contains(pkg);
              final icon = pkg == null
                  ? const Icon(Icons.android, size: 30)
                  : FutureBuilder<Uint8List?>(
                      future: _appIcon(pkg),
                      builder: (context, snapshot) {
                        final bytes = snapshot.data;
                        if (bytes == null) {
                          return const Icon(Icons.android, size: 30);
                        }
                        return Image.memory(bytes, width: 38, height: 38, fit: BoxFit.contain);
                      },
                    );
              return Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                color: selected ? theme.colorScheme.primaryContainer : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                    width: selected ? 1.6 : 0.7,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: InkWell(
                        onTap: pkg == null || _busy ? null : () => _toggleAppSelection(pkg, app.appName ?? pkg),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              icon,
                              const SizedBox(height: 6),
                              Text(app.appName ?? pkg ?? 'App', textAlign: TextAlign.center,
                                maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700)),
                              if (pkg != null && _appSizes.containsKey(pkg))
                                Text(_formatAppSize(_appSizes[pkg]!), textAlign: TextAlign.center,
                                  maxLines: 1, style: TextStyle(fontSize: 8, color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (pkg != null)
                      Positioned(
                        top: 0, right: 0,
                        child: PopupMenuButton<String>(
                          tooltip: 'Manage app', padding: EdgeInsets.zero, iconSize: 16,
                          onSelected: (action) => _manageInstalledApp(pkg, app.appName ?? pkg, action),
                          itemBuilder: (_) => [
                            if (_saved.containsKey(pkg))
                              const PopupMenuItem(value: 'deleteSaved', child: Text('Delete saved APK copy')),
                            const PopupMenuItem(value: 'settings', child: Text('App settings / uninstall')),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            });
        }),
        if (_visibleAppCount < _filteredApps.length)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: OutlinedButton.icon(
                onPressed: () => setState(() {
                  _visibleAppCount = (_visibleAppCount + _appPageSize)
                      .clamp(0, _filteredApps.length).toInt();
                }),
                icon: const Icon(Icons.expand_more_rounded),
                label: Text('Load more apps (${_apps.length - _visibleAppCount} remaining)'),
              ),
            ),
          ),
        const SizedBox(height: 18),
        ],
      ],
    ]);
  }
}
