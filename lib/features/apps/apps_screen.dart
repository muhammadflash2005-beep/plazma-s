// ignore_for_file: deprecated_member_use, prefer_interpolation_to_compose_strings
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_device_apps/flutter_device_apps.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../network/android_wifi_session_service.dart';
import '../../transfers/transfer_history.dart';
import '../../transfers/transfer_overlay_controller.dart';
import '../../transfers/xender_local_transfer_service.dart';

class AppsScreen extends StatefulWidget {
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
  Directory? _library;
  PlazmaConnectionInvite? _invite;
  PlazmaConnectionInvite? _receiver;
  bool _loading = false, _busy = false;
  double _progress = 0;
  String? _status, _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (kIsWeb || !Platform.isAndroid) {
      setState(() => _error = 'App sharing and installation are available on Android phones.');
      return;
    }
    setState(() => _loading = true);
    try {
      final root = await getApplicationSupportDirectory();
      final library = Directory(root.path + Platform.pathSeparator + 'saved_apps');
      await library.create(recursive: true);
      final apps = await FlutterDeviceApps.listApps(
        includeSystem: false, onlyLaunchable: true, includeIcons: true);
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
        _saved..clear()..addAll(saved);
        _selected.removeWhere((p) => !apps.any((a) => a.packageName == p));
      });
    } catch (e) { if (mounted) setState(() => _error = 'Could not load apps: ' + e.toString()); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<List<Map<String,dynamic>>> _export(List<String> packages) async {
    final result = await const MethodChannel('com.plazma.s/apps')
        .invokeListMethod<dynamic>('exportApks', {'packageNames': packages});
    final items = (result ?? []).whereType<Map>()
        .map((e) => Map<String,dynamic>.from(e)).toList();
    if (items.isEmpty) throw StateError('Android did not export any APK files.');
    return items;
  }

  Future<void> _saveApp(String pkg, String name) async {
    if (_busy || _library == null) return;
    setState(() { _busy = true; _status = 'Saving ' + name + '…'; });
    try {
      final folder = Directory(_library!.path + Platform.pathSeparator + pkg);
      await folder.create(recursive: true);
      final items = await _export([pkg]);
      for (final item in items) {
        if (item['packageName'] != pkg || item['path'] is! String || item['relativePath'] is! String) continue;
        final filename = (item['relativePath'] as String).split('/').last;
        await File(item['path'] as String).copy(folder.path + Platform.pathSeparator + filename);
      }
      if (!await File(folder.path + Platform.pathSeparator + 'base.apk').exists()) {
        throw StateError('The base APK could not be saved.');
      }
      if (!mounted) return;
      setState(() { _saved[pkg] = name; _status = name + ' saved in Saved Apps.'; });
    } catch (e) { _message('Could not save app: ' + e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _send() async {
    if (_selected.isEmpty || _busy) return;
    setState(() { _busy = true; _status = 'Preparing selected apps…'; });
    try {
      final packages = _apps.where((a) => a.packageName != null && _selected.contains(a.packageName))
          .map((a) => a.packageName!).toList();
      final items = await _export(packages);
      final files = <File>[], paths = <String>[];
      for (final item in items) {
        if (item['path'] is String && item['relativePath'] is String) {
          files.add(File(item['path'] as String));
          paths.add(item['relativePath'] as String);
        }
      }
      final invite = await _service.startSharing(files: files, relativePaths: paths);
      if (!mounted) return;
      setState(() { _invite = invite; _status = 'Scan this QR code on the receiving phone.'; });
      TransferOverlayController.show(TransferOverlaySnapshot(
        direction: TransferOverlayDirection.sending, fileCount: packages.length,
        label: 'Sharing apps', isAppTransfer: true));
    } catch (e) { _message('Could not start app sharing: ' + e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<PlazmaConnectionInvite?> _scan() async => showDialog<PlazmaConnectionInvite>(
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

  Future<void> _receive() async {
    if (_busy) return;
    final invite = await _scan();
    if (invite == null || !mounted) return;
    setState(() { _busy = true; _status = 'Connecting to sender…'; });
    try {
      final manifest = await _service.joinAndList(invite);
      final groups = <String,List<SharedLocalFile>>{};
      for (final item in manifest) {
        if (!item.relativePath.toLowerCase().endsWith('.apk')) continue;
        final pkg = item.relativePath.split('/').first;
        if (pkg.isNotEmpty && !pkg.contains('..')) groups.putIfAbsent(pkg, () => []).add(item);
      }
      if (groups.isEmpty) throw StateError('This QR code does not contain Android apps.');
      if (!mounted) return;
      setState(() { _receiver = invite; _incoming..clear()..addAll(groups); _status = 'Apps ready to receive.'; });
      TransferOverlayController.show(TransferOverlaySnapshot(
        direction: TransferOverlayDirection.receiving, fileCount: groups.length,
        label: 'Ready to receive apps', isAppTransfer: true));
    } catch (e) { await _service.disconnect(); _message('Could not connect: ' + e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _download() async {
    if (_receiver == null || _library == null || _busy) return;
    setState(() { _busy = true; _progress = 0; _status = 'Receiving apps…'; });
    try {
      final all = _incoming.values.expand((v) => v).toList();
      await _service.downloadAll(invite: _receiver!, files: all, destination: _library!,
        onProgress: (p) { if (mounted) setState(() => _progress = p.fraction.clamp(0.0,1.0)); });
      for (final entry in _incoming.entries) {
        final bytes = entry.value.fold<int>(0, (sum,item) => sum + item.size);
        _saved[entry.key] = entry.key;
        await TransferHistoryStore.add(name: entry.key, type: 'app', direction: 'received',
          path: _library!.path + Platform.pathSeparator + entry.key,
          bytes: bytes, peer: 'Nearby Plazma S device');
      }
      if (!mounted) return;
      setState(() => _status = 'Received and saved ' + _incoming.length.toString() + ' app(s).');
      TransferOverlayController.clear();
      await _service.stopForegroundService();
    } catch (e) { _message('App transfer failed: ' + e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _install(String pkg) async {
    if (_library == null) return;
    final folder = Directory(_library!.path + Platform.pathSeparator + pkg);
    final apks = <File>[];
    if (!await folder.exists()) return;
    await for (final entity in folder.list(followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.apk')) apks.add(entity);
    }
    apks.sort((a,b) {
      final an = a.uri.pathSegments.last, bn = b.uri.pathSegments.last;
      int rank(String n) {
        if (n == 'base.apk') return 0;
        final m = RegExp(r'^split_(\d+)\.apk$').firstMatch(n);
        return int.tryParse(m?.group(1) ?? '') ?? 999999;
      }
      return rank(an).compareTo(rank(bn));
    });
    if (apks.isEmpty || apks.first.uri.pathSegments.last != 'base.apk') {
      _message('Saved app is incomplete. Save or receive it again.'); return;
    }
    try {
      await const MethodChannel('com.plazma.s/apps').invokeMethod<void>('installApkSet',
        {'packageName': pkg, 'paths': apks.map((f) => f.path).toList()});
      _message('Android installer opened. Review and approve the installation.');
    } catch (e) { _message('Could not install app: ' + e.toString()); }
  }

  Future<void> _delete(String pkg) async {
    if (_library == null) return;
    final folder = Directory(_library!.path + Platform.pathSeparator + pkg);
    if (await folder.exists()) await folder.delete(recursive: true);
    if (mounted) setState(() => _saved.remove(pkg));
  }

  Future<void> _stop() async {
    await _service.stopSharing();
    TransferOverlayController.clear();
    if (mounted) setState(() { _invite = null; _status = 'App sharing stopped.'; });
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
    unawaited(_service.stopSharing());
    unawaited(_service.disconnect());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Apps', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      Text('Send complete apps, receive them, save APKs and install them later.',
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
      const SizedBox(height: 14),
      if (_status != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_status!))),
      if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
      if (_loading) const LinearProgressIndicator(),
      if (_invite != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        const Text('Scan to receive these apps', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(10), color: Colors.white,
          child: QrImageView(data: _invite!.toQrValue(), size: 220)),
        const SizedBox(height: 8), Text('Wi-Fi: ' + _invite!.ssid),
        const Text('The receiver sees each selected app as one app, with its APK parts grouped together.', textAlign: TextAlign.center),
        OutlinedButton.icon(onPressed: _busy ? null : _stop, icon: const Icon(Icons.stop), label: const Text('Stop sharing')),
      ]))),
      if (_receiver != null) Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
        Row(children: [Expanded(child: Text(_incoming.length.toString() + ' app(s) ready', style: const TextStyle(fontWeight: FontWeight.w800))),
          TextButton(onPressed: _busy ? null : _disconnect, child: const Text('Disconnect'))]),
        ..._incoming.entries.map((e) => ListTile(leading: const Icon(Icons.android),
          title: Text(e.key), subtitle: Text(e.value.length.toString() + ' APK part(s)'))),
        if (_busy) LinearProgressIndicator(value: _progress > 0 ? _progress : null),
        FilledButton.icon(onPressed: _busy ? null : _download,
          icon: const Icon(Icons.download), label: const Text('Receive and save apps')),
      ]))),
      if (_invite == null && _receiver == null) ...[
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: _busy ? null : _receive,
            icon: const Icon(Icons.qr_code_scanner), label: const Text('Receive apps'))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: _busy || _selected.isEmpty ? null : _send,
            icon: const Icon(Icons.send), label: const Text('Send selected'))),
        ]),
        const SizedBox(height: 18),
        Row(children: [Expanded(child: Text('Installed apps (' + _apps.length.toString() + ')',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))]),
        LayoutBuilder(builder: (context, c) {
          final columns = (c.maxWidth / 62).floor().clamp(2,5);
          return GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            itemCount: _apps.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns, crossAxisSpacing: 4, mainAxisSpacing: 5, childAspectRatio: .58),
            itemBuilder: (context,index) {
              final app = _apps[index], pkg = app.packageName;
              final selected = pkg != null && _selected.contains(pkg);
              final icon = app.iconBytes == null ? const Icon(Icons.android,size:30) :
                Image.memory(app.iconBytes!,width:38,height:38,fit:BoxFit.contain);
              return Card(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias,
                child: InkWell(onTap: pkg == null ? null : () => setState(() {
                  if (selected) { _selected.remove(pkg); } else { _selected.add(pkg); }
                }), child: Padding(padding: const EdgeInsets.all(3), child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, children: [
                    Stack(children: [icon, if (selected) const Positioned(right:0,top:0,
                      child: Icon(Icons.check_circle,color:Colors.green,size:16))]),
                    const SizedBox(height:4),
                    Text(app.appName ?? pkg ?? 'App', textAlign:TextAlign.center,maxLines:2,
                      overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:9,fontWeight:FontWeight.w700)),
                    SizedBox(height:22,child: IconButton(padding:EdgeInsets.zero,
                      visualDensity:VisualDensity.compact,tooltip:'Save APK',
                      onPressed: pkg == null || _busy ? null : () => _saveApp(pkg,app.appName ?? pkg),
                      icon:Icon(_saved.containsKey(pkg) ? Icons.check_circle : Icons.save_alt,
                        size:17,color:_saved.containsKey(pkg) ? Colors.green : theme.colorScheme.primary))),
                  ]))));
            });
        }),
        const SizedBox(height:18),
        Text('Saved Apps (' + _saved.length.toString() + ')',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        if (_saved.isEmpty) const Padding(padding: EdgeInsets.all(12),
          child: Text('Apps you save or receive will appear here for later installation.')),
        ..._saved.entries.map((e) => Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.android)),
          title: Text(e.value), subtitle: Text(e.key),
          trailing: Wrap(spacing:0, children: [
            IconButton(tooltip:'Install',onPressed:_busy ? null : () => _install(e.key),
              icon:const Icon(Icons.install_mobile)),
            IconButton(tooltip:'Delete saved APK',onPressed:_busy ? null : () => _delete(e.key),
              icon:const Icon(Icons.delete_outline)),
          ]),
        ))),
        if (_selected.isNotEmpty) Padding(padding: const EdgeInsets.only(top:12),
          child: SizedBox(width:double.infinity,child:FilledButton.icon(
            onPressed:_busy ? null : _send,icon:const Icon(Icons.send),
            label:Text('Send ' + _selected.length.toString() + ' selected app(s)')))),
      ],
    ]);
  }
}
