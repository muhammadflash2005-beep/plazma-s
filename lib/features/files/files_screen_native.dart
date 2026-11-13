// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../transfers/lan_file_transfer.dart';
import '../devices/plazma_discovery_service.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});
  @override
  State<FilesScreen> createState() => _FilesScreenState();
}
class _FilesScreenState extends State<FilesScreen> {
  final _items = <_PickedItem>[];
  final _code = TextEditingController();
  late final PlazmaDiscoveryService _discovery;
  StreamSubscription<List<NearbyPlazmaDevice>>? _sub;
  List<NearbyPlazmaDevice> _devices = [];
  LanFileTransfer? _receiver;
  String? _receiveCode, _destination, _status;
  double? _progress;
  bool _busy = false, _scanning = false;

  @override
  void initState() {
    super.initState();
    _discovery = PlazmaDiscoveryService();
    _sub = _discovery.devices.listen((v) { if (mounted) setState(() => _devices = v); });
    unawaited(_startDiscovery());
  }
  String get _platform => Platform.isAndroid ? 'Android' : Platform.isIOS ? 'iOS'
      : Platform.isWindows ? 'Windows' : Platform.isMacOS ? 'macOS'
      : Platform.isLinux ? 'Linux' : 'Desktop';

  Future<void> _startDiscovery() async {
    if (!mounted) return;
    setState(() => _scanning = true);
    try {
      await _discovery.start(deviceName: 'Plazma S device', platform: _platform,
          publish: _receiver?.isListening ?? false);
    } catch (e) { _message('Discovery failed: $e'); }
    finally { if (mounted) setState(() => _scanning = false); }
  }
  Future<void> _refresh() async { await _discovery.stop(); await _startDiscovery(); }

  Future<void> _pickFiles() async {
    setState(() => _busy = true);
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty || !mounted) return;
      setState(() {
        for (final f in files) {
          if (f.path != null && !_items.any((x) => x.path == f.path)) {
            _items.add(_PickedItem(f.name, f.path!, File(f.path!).lengthSync(), false));
          }
        }
      });
    } catch (e) { _message('File selection failed: $e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _pickFolder() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null || !mounted) return;
    final parts = path.split(RegExp(r'[/\\]')).where((x) => x.isNotEmpty).toList();
    setState(() {
      if (!_items.any((x) => x.path == path)) {
        _items.add(_PickedItem(parts.isEmpty ? path : parts.last, path, null, true));
      }
    });
  }
  Future<void> _startReceiving() async {
    setState(() => _busy = true);
    try {
      final path = await FilePicker.getDirectoryPath();
      if (path == null || !mounted) return;
      final server = LanFileTransfer(port: PlazmaDiscoveryService.advertisedPort);
      final code = (100000 + Random.secure().nextInt(900000)).toString();
      await server.startReceiver(destination: Directory(path), authorizationCode: code,
        onReceived: (file, name, hash) => _message('Received $name · SHA-256 verified'),
        onError: (error) => _message('Incoming transfer rejected: $error'));
      _receiver = server; _receiveCode = code; _destination = path;
      await _refresh();
      if (mounted) setState(() => _status = 'Ready to receive files');
    } catch (e) { _message('Could not start receiver: $e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _stopReceiving() async {
    await _receiver?.close(); _receiver = null; _receiveCode = null; _destination = null;
    await _refresh();
    if (mounted) setState(() => _status = 'Receiving stopped');
  }
  Future<String?> _askCode(NearbyPlazmaDevice d) => showDialog<String>(
    context: context, builder: (ctx) => AlertDialog(
      title: Text('Send to ${d.name}'),
      content: TextField(controller: _code, autofocus: true, maxLength: 6,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Six-digit receiver code')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () {
          final v = _code.text.trim();
          if (RegExp(r'^\d{6}$').hasMatch(v)) Navigator.pop(ctx, v);
        }, child: const Text('Connect')),
      ],
    ));
  Future<void> _send(NearbyPlazmaDevice d) async {
    final files = _items.where((x) => !x.isFolder).toList();
    if (files.isEmpty) { _message('Choose files first. Folder sending is not enabled yet.'); return; }
    _code.clear();
    final code = await _askCode(d);
    if (code == null || !mounted) return;
    setState(() { _busy = true; _progress = 0; });
    try {
      final sender = LanFileTransfer();
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        setState(() => _status = 'Sending ${f.name} (${i + 1}/${files.length})');
        await sender.sendFile(host: d.address, port: d.port, file: File(f.path),
          authorizationCode: code,
          onProgress: (p) { if (mounted) setState(() => _progress = p.fraction.clamp(0.0, 1.0)); });
      }
      if (mounted) { setState(() { _progress = 1; _status = 'Transfer sent'; }); _message('Sent ${files.length} file(s) to ${d.name}.'); }
    } catch (e) { if (mounted) setState(() => _status = 'Transfer failed: $e'); _message('Transfer failed: $e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  void _message(String s) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s), duration: const Duration(seconds: 4)));
  }
  String _size(int? n) {
    if (n == null) return 'Folder · not transferable yet';
    if (n < 1024) return '${n} B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  @override
  void dispose() {
    _sub?.cancel(); unawaited(_receiver?.close()); unawaited(_discovery.dispose()); _code.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final total = _items.fold<int>(0, (s, x) => s + (x.bytes ?? 0));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Files', style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      Text('Send files directly to nearby devices on your local network.',
          style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
        Row(children: [
          const Icon(Icons.wifi_tethering_rounded), const SizedBox(width: 8),
          const Expanded(child: Text('Receive files', style: TextStyle(fontWeight: FontWeight.w800))),
          if (_receiver?.isListening == true)
            TextButton(onPressed: _busy ? null : _stopReceiving, child: const Text('Stop'))
          else FilledButton(onPressed: _busy ? null : _startReceiving, child: const Text('Start receiving')),
        ]),
        if (_receiveCode != null) ...[
          const Text('Share this pairing code with the sender:'),
          SelectableText(_receiveCode!, style: TextStyle(fontSize: 28, letterSpacing: 6,
              fontWeight: FontWeight.w900, color: t.colorScheme.primary)),
          Text('Save location: $_destination', maxLines: 2, overflow: TextOverflow.ellipsis),
        ] else const Text('Choose a destination folder to enable receiving.'),
      ]))),
      Card(color: t.colorScheme.surfaceContainerHighest, child: const Padding(
        padding: EdgeInsets.all(12), child: Text(
          'The six-digit code authorizes the sender. TCP traffic is not encrypted yet; only receive over a trusted network.',
          style: TextStyle(fontSize: 11, height: 1.4)))),
      Wrap(spacing: 10, children: [
        FilledButton.icon(onPressed: _busy ? null : _pickFiles,
          icon: const Icon(Icons.add_rounded), label: const Text('Choose files')),
        OutlinedButton.icon(onPressed: _busy ? null : _pickFolder,
          icon: const Icon(Icons.folder_open_rounded), label: const Text('Choose folder')),
      ]),
      Card(child: ListTile(
        leading: const Icon(Icons.folder_copy_outlined),
        title: Text('${_items.length} selected · ${_size(total)}'),
        trailing: TextButton(onPressed: _busy || _items.isEmpty ? null : () => setState(_items.clear),
          child: const Text('Clear')))),
      ..._items.asMap().entries.map((e) => Card(child: ListTile(
        leading: Icon(e.value.isFolder ? Icons.folder_rounded : Icons.insert_drive_file_outlined),
        title: Text(e.value.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(_size(e.value.bytes)),
        trailing: IconButton(onPressed: _busy ? null : () => setState(() => _items.removeAt(e.key)),
          icon: const Icon(Icons.close_rounded))))),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Text('Nearby devices', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
        IconButton(onPressed: _busy || _scanning ? null : _refresh, icon: const Icon(Icons.refresh_rounded)),
      ]),
      if (_devices.isEmpty) Card(child: Padding(padding: const EdgeInsets.all(18),
        child: Center(child: Text(_scanning ? 'Searching local network…' :
          'No devices found. Enable Receive files on the destination device.'))))
      else ..._devices.map((d) => Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.devices_rounded)),
        title: Text(d.name), subtitle: Text('${d.platform} · ${d.address}:${d.port}'),
        trailing: FilledButton(onPressed: _busy ? null : () => _send(d), child: const Text('Send'))))),
      if (_status != null) ...[
        const SizedBox(height: 10), Text(_status!, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (_progress != null) LinearProgressIndicator(value: _progress),
      ],
      const SizedBox(height: 8),
      Text('Folder transfer, resume, room approvals and encrypted sessions remain in development.',
        style: TextStyle(fontSize: 11, color: t.colorScheme.onSurfaceVariant)),
    ]);
  }
}
class _PickedItem {
  const _PickedItem(this.name, this.path, this.bytes, this.isFolder);
  final String name, path;
  final int? bytes;
  final bool isFolder;
}
