// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../transfers/lan_file_transfer.dart';
import '../../transfers/transfer_mode.dart';
import '../devices/plazma_discovery_service.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({this.transferMode, super.key});\n\n  final TransferMode? transferMode;
  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  final List<_PickedItem> _items = [];
  final TextEditingController _code = TextEditingController();
  late final PlazmaDiscoveryService _discovery;
  StreamSubscription<List<NearbyPlazmaDevice>>? _subscription;
  List<NearbyPlazmaDevice> _devices = [];
  LanFileTransfer? _receiver;
  String? _receiveCode;
  String? _destination;
  String? _status;
  double? _progress;
  bool _busy = false;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _discovery = PlazmaDiscoveryService();
    _subscription = _discovery.devices.listen((items) {
      if (mounted) setState(() => _devices = items);
    });
    unawaited(_startDiscovery());
  }

  String get _platform {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return 'Desktop';
  }

  Future<void> _startDiscovery() async {
    if (!mounted) return;
    setState(() => _scanning = true);
    try {
      await _discovery.start(
        deviceName: 'Plazma S device',
        platform: _platform,
        publish: _receiver?.isListening ?? false,
      );
    } catch (error) {
      _message('Discovery failed: $error');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _refresh() async {
    await _discovery.stop();
    await _startDiscovery();
  }

  Future<void> _pickFiles() async {
    setState(() => _busy = true);
    try {
      final files = await FilePicker.pickFiles();
      if (!mounted || files.isEmpty) return;
      setState(() {
        for (final file in files) {
          final path = file.path;
          if (path == null || _items.any((item) => item.path == path)) continue;
          _items.add(_PickedItem(
            file.name,
            path,
            File(path).lengthSync(),
            false,
          ));
        }
      });
    } catch (error) {
      _message('File selection failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFolder() async {
    final path = await FilePicker.getDirectoryPath();
    if (!mounted || path == null) return;
    final parts = path.split(RegExp(r'[/\\]')).where((part) => part.isNotEmpty).toList();
    setState(() {
      if (!_items.any((item) => item.path == path)) {
        _items.add(_PickedItem(
          parts.isEmpty ? path : parts.last,
          path,
          null,
          true,
        ));
      }
    });
  }

  Future<void> _startReceiving() async {
    setState(() => _busy = true);
    try {
      final path = await FilePicker.getDirectoryPath();
      if (!mounted || path == null) return;
      final receiver = LanFileTransfer(port: PlazmaDiscoveryService.advertisedPort);
      final code = (100000 + Random.secure().nextInt(900000)).toString();
      await receiver.startReceiver(
        destination: Directory(path),
        authorizationCode: code,
        onReceived: (file, name, hash) {
          _message('Received $name · SHA-256 verified');
        },
        onError: (error) {
          _message('Incoming transfer rejected: $error');
        },
      );
      _receiver = receiver;
      _receiveCode = code;
      _destination = path;
      await _refresh();
      if (mounted) setState(() => _status = 'Ready to receive files');
    } catch (error) {
      _message('Could not start receiver: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopReceiving() async {
    await _receiver?.close();
    _receiver = null;
    _receiveCode = null;
    _destination = null;
    await _refresh();
    if (mounted) setState(() => _status = 'Receiving stopped');
  }

  Future<String?> _askCode(NearbyPlazmaDevice device) {
    _code.clear();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Send to ${device.name}'),
        content: TextField(
          controller: _code,
          autofocus: true,
          maxLength: 6,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Six-digit receiver code'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = _code.text.trim();
              if (value.length == 6 && RegExp(r'^[0-9]{6}').hasMatch(value)) {
                Navigator.pop(dialogContext, value);
              }
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  Future<void> _send(NearbyPlazmaDevice device) async {
    final files = _items.where((item) => !item.isFolder).toList();
    if (files.isEmpty) {
      _message('Choose files first. Folder sending is not enabled yet.');
      return;
    }

    final code = await _askCode(device);
    if (code == null || !mounted) return;

    setState(() {
      _busy = true;
      _progress = 0;
      _status = 'Connecting to ${device.name}…';
    });

    try {
      final sender = LanFileTransfer();
      for (var index = 0; index < files.length; index++) {
        final item = files[index];
        if (!mounted) return;
        setState(() {
          _status = 'Sending ${item.name} (${index + 1}/${files.length})';
          _progress = 0;
        });
        await sender.sendFile(
          host: device.address,
          port: device.port,
          file: File(item.path),
          authorizationCode: code,
          onProgress: (progress) {
            if (mounted) {
              setState(() => _progress = progress.fraction.clamp(0.0, 1.0));
            }
          },
        );
      }
      if (mounted) {
        setState(() {
          _progress = 1;
          _status = 'Transfer sent and receiver-verified';
        });
        _message('Sent ${files.length} file(s) to ${device.name}.');
      }
    } catch (error) {
      if (mounted) setState(() => _status = 'Transfer failed: $error');
      _message('Transfer failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  String _size(int? bytes) {
    if (bytes == null) return 'Folder · not transferable yet';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  void dispose() {
    _subscription?.cancel();
    unawaited(_receiver?.close());
    unawaited(_discovery.dispose());
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalBytes = _items.fold<int>(0, (sum, item) => sum + (item.bytes ?? 0));\n    final localModeSupported = transferMode == null || transferMode!.supportsLocal(_platform);\n    final compatibleDevices = _devices.where((device) =>\n        transferMode == null || transferMode!.matches(_platform, device.platform)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Files',
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          'Send files directly to nearby devices on your local network.',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.wifi_tethering_rounded),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Receive files', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    if (_receiver?.isListening == true)
                      TextButton(
                        onPressed: _busy ? null : _stopReceiving,
                        child: const Text('Stop'),
                      )
                    else
                      FilledButton(
                        onPressed: _busy ? null : _startReceiving,
                        child: const Text('Start receiving'),
                      ),
                  ],
                ),
                if (_receiveCode != null) ...[
                  const Text('Share this pairing code with the sender:'),
                  SelectableText(
                    _receiveCode!,
                    style: TextStyle(
                      fontSize: 28,
                      letterSpacing: 6,
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Text(
                    'Save location: $_destination',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ] else
                  const Text('Choose a destination folder to enable receiving.'),
              ],
            ),
          ),
        ),
        Card(
          color: theme.colorScheme.surfaceContainerHighest,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'The six-digit code authorizes the sender. TCP traffic is not encrypted yet; only receive over a trusted network.',
              style: TextStyle(fontSize: 11, height: 1.4),
            ),
          ),
        ),
        Wrap(
          spacing: 10,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _pickFiles,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Choose files'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickFolder,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Choose folder'),
            ),
          ],
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.folder_copy_outlined),
            title: Text('${_items.length} selected · ${_size(totalBytes)}'),
            trailing: TextButton(
              onPressed: _busy || _items.isEmpty ? null : () => setState(_items.clear),
              child: const Text('Clear'),
            ),
          ),
        ),
        ..._items.asMap().entries.map((entry) {
          final item = entry.value;
          return Card(
            child: ListTile(
              leading: Icon(item.isFolder ? Icons.folder_rounded : Icons.insert_drive_file_outlined),
              title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(_size(item.bytes)),
              trailing: IconButton(
                onPressed: _busy ? null : () => setState(() => _items.removeAt(entry.key)),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Nearby devices',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              onPressed: _busy || _scanning ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        if (compatibleDevices.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Center(
                child: Text(
                  _scanning
                      ? 'Searching local network…'
                      : transferMode != null && _devices.isNotEmpty\n                          ? 'Nearby devices were found, but none match ${transferMode!.label}. Check that the other device is running Plazma S and has receiving enabled.'\n                          : 'No devices found. Enable Receive files on the destination device.',
                ),
              ),
            ),
          )
        else
          ...compatibleDevices.map((device) => Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.devices_rounded)),
                  title: Text(device.name),
                  subtitle: Text('${device.platform} · ${device.address}:${device.port}'),
                  trailing: FilledButton(
                    onPressed: _busy ? null : () => _send(device),
                    child: const Text('Send'),
                  ),
                ),
              )),
        if (_status != null) ...[
          const SizedBox(height: 10),
          Text(_status!, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (_progress != null) LinearProgressIndicator(value: _progress),
        ],
        const SizedBox(height: 8),
        Text(
          'Folder transfer, resume, room approvals and encrypted sessions remain in development.',
          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _PickedItem {
  const _PickedItem(this.name, this.path, this.bytes, this.isFolder);
  final String name;
  final String path;
  final int? bytes;
  final bool isFolder;
}
