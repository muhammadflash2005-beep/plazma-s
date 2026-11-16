// ignore_for_file: deprecated_member_use, prefer_interpolation_to_compose_strings
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../media/permanent_delete_confirmation.dart';

import '../media/permanent_delete_confirmation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_device_apps/flutter_device_apps.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../network/android_wifi_session_service.dart';
import '../../transfers/transfer_history.dart';
import '../../transfers/transfer_overlay_controller.dart';
import '../../transfers/xender_local_transfer_service.dart';

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
  final Map<String, Future<void>> _saveTasks = {};
  final Map<String, Future<Uint8List?>> _iconFutures = {};
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
  Timer? _roomRefreshTimer;
  StreamSubscription<List<SharedLocalFile>>? _manifestSubscription;
  double _progress = 0;
  String? _status, _error;

  @override
  void initState() {
    super.initState();
    AppsScreen.sendSelected = _send;
    _service.roomFiles.addListener(_syncRoomFiles);
    _syncRoomFiles();
    _invite = _service.invite;
    _receiver = _service.joinedInvite;
    if (_receiver != null) _watchIncomingApps(_receiver!);
    _load();
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
        setState(() {
          _library = library;
          _error = 'On this computer, send complete app installers or portable bundles (.exe, .msi, .dmg, .pkg, .AppImage, .deb, .rpm or .zip). Received packages are saved for you to install.';
        });
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
      apps.sort((a,b) => (a.appName ?? '').toLowerCase().compareTo((b.appName ?? '').toLowerCase()));
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
        _visibleAppCount = _appPageSize;
        _iconFutures.clear();
        _saved..clear()..addAll(saved);
        _selected.removeWhere((p) => !apps.any((a) => a.packageName == p));
      });
    } catch (e) { if (mounted) setState(() => _error = 'Could not load apps: ' + e.toString()); }
    finally { if (mounted) setState(() => _loading = false); }
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
      final confirmed = await confirmPermanentDelete(
        context,
        itemDescription: 'the saved APK copy of $appName',
      );
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
          'openAppSettings',
          {'packageName': packageName},
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
      await _sendDesktopInstallers();
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
        for (final file in savedFiles) {
          files.add(file);
          paths.add(pkg + '/' + file.uri.pathSegments.last);
        }
      }

      final invite = await (_service.isSharing
          ? _service.addFiles(files: files, relativePaths: paths).then((_) => _service.invite!)
          : _service.startSharing(files: files, relativePaths: paths));
      if (!mounted) return;
      setState(() { _invite = invite; _selected.removeAll(packages); _status = 'Room ' + invite.roomId + ' is open. You can add more items from other tabs.'; });
      _updateSelectionCount();
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
      final invite = await _service.startSharing(files: files, relativePaths: paths);
      if (!mounted) return;
      setState(() { _invite = invite; _status = 'Room ' + invite.roomId + ' is open. Waiting for computers.'; });
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

  void _syncRoomFiles() {
    final invite = _service.joinedInvite;
    final groups = <String, List<SharedLocalFile>>{};
    if (invite != null) {
      for (final item in _service.roomFiles.value) {
        if (!item.relativePath.toLowerCase().endsWith('.apk')) continue;
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
        if (!item.relativePath.toLowerCase().endsWith('.apk')) continue;
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
        if (!item.relativePath.toLowerCase().endsWith('.apk')) continue;
        final pkg = item.relativePath.split('/').first;
        if (pkg.isNotEmpty && !pkg.contains('..')) groups.putIfAbsent(pkg, () => []).add(item);
      }
      if (groups.isEmpty) throw StateError('This QR code does not contain Android apps.');
      if (!mounted) return;
      setState(() { _receiver = invite; _incoming..clear()..addAll(groups); _status = 'Apps ready to receive.'; });
      _watchIncomingApps(invite);
      TransferOverlayController.show(TransferOverlaySnapshot(
        direction: TransferOverlayDirection.receiving, fileCount: groups.length,
        label: 'Ready to receive apps', isAppTransfer: true));
    } catch (e) { await _service.disconnect(); _message('Could not connect: ' + e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _refreshIncomingApps() async {
    if (_receiver == null || _busy) return;
    try {
      final manifest = await _service.refreshManifest(_receiver!);
      final groups = <String,List<SharedLocalFile>>{};
      for (final item in manifest) {
        if (!item.relativePath.toLowerCase().endsWith('.apk')) continue;
        final pkg = item.relativePath.split('/').first;
        if (pkg.isNotEmpty && !pkg.contains('..')) groups.putIfAbsent(pkg, () => []).add(item);
      }
      setState(() {
        _incoming..clear()..addAll(groups);
        _status = '${groups.length} app(s) available in this room.';
      });
    } catch (e) { _message('Could not refresh shared apps: $e'); }
  }

  Future<void> _download() async {
    if (_receiver == null || _library == null || _busy) return;
    setState(() { _busy = true; _progress = 0; _status = 'Receiving apps…'; });
    try {
      final all = _incoming.values.expand((v) => v).toList();
      await _service.downloadAll(invite: _receiver!, files: all, destination: _library!,
        onProgress: (p) { if (mounted) setState(() => _progress = p.fraction.clamp(0.0,1.0)); });
      if (!Platform.isAndroid) {
        for (final item in all) {
          await TransferHistoryStore.add(name: item.name, type: 'app-installer', direction: 'received',
            path: _library!.path + Platform.pathSeparator + item.relativePath,
            bytes: item.size, peer: 'Nearby Plazma S device');
        }
        if (!mounted) return;
        setState(() => _status = 'Received ' + all.length.toString() + ' application package(s). Saved in ' + _library!.path);
      } else {
        for (final entry in _incoming.entries) {
          final bytes = entry.value.fold<int>(0, (sum,item) => sum + item.size);
          _saved[entry.key] = entry.key;
          await TransferHistoryStore.add(name: entry.key, type: 'app', direction: 'received',
            path: _library!.path + Platform.pathSeparator + entry.key,
            bytes: bytes, peer: 'Nearby Plazma S device');
        }
        if (!mounted) return;
        setState(() => _status = 'Received and saved ' + _incoming.length.toString() + ' app(s).');
      }
      TransferOverlayController.clear();
      await _service.stopForegroundService();
    } catch (e) { _message('App transfer failed: ' + e.toString()); }
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
    if (mounted) setState(() { _receiver = null; _incoming.clear(); _status = 'Disconnected.'; });
  }

  void _message(String s) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }

  @override
  void dispose() {
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
        ..._incoming.entries.map((e) => ListTile(leading: const Icon(Icons.android),
          title: Text(e.key), subtitle: Text(e.value.length.toString() + ' APK part(s)'))),
        if (_busy) LinearProgressIndicator(value: _progress > 0 ? _progress : null),
        FilledButton.icon(onPressed: _busy ? null : _download,
          icon: const Icon(Icons.download), label: const Text('Receive and save apps')),
      ]))),
      if (_receiver == null) ...[
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: _busy || _preparing ? null : _receive,
            icon: const Icon(Icons.qr_code_scanner), label: const Text('Receive apps'))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: _busy || _preparing || (Platform.isAndroid && _selected.isEmpty) ? null : _send,
            icon: const Icon(Icons.send), label: Text(_service.isSharing ? 'Add to room' : (Platform.isAndroid ? 'Send selected' : 'Send installers')))),
        ]),
        const SizedBox(height: 18),
        if (!Platform.isAndroid) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Computer application packages', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Send complete installers or portable bundles. Recipients can join from another PC or Android device and save the package locally.'),
          const SizedBox(height: 6),
          const Text('Supported formats: EXE, MSI, MSIX, AppImage, DEB, RPM, DMG, PKG and ZIP.'),
        ]))),
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
                        onTap: pkg == null || _busy
                            ? null
                            : () => _toggleAppSelection(pkg, app.appName ?? pkg),
                        child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        icon,
                        const SizedBox(height: 6),
                        Text(
                          app.appName ?? pkg ?? 'App',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
                        ),
                      ],
                        ),
                      ),
                    ),
                    if (pkg != null)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: PopupMenuButton<String>(
                          tooltip: 'Manage app',
                          padding: EdgeInsets.zero,
                          iconSize: 16,
                          onSelected: (action) => _manageInstalledApp(
                            pkg, app.appName ?? pkg, action,
                          ),
                          itemBuilder: (_) => [
                            if (_saved.containsKey(pkg))
                              const PopupMenuItem(
                                value: 'deleteSaved',
                                child: Text('Delete saved APK copy'),
                              ),
                            const PopupMenuItem(
                              value: 'settings',
                              child: Text('App settings / uninstall'),
                            ),
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
