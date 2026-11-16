// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../media/device_media_browser.dart';

import '../../network/android_wifi_session_service.dart';
import '../../transfers/transfer_history.dart';
import '../../transfers/transfer_overlay_controller.dart';
import '../../transfers/xender_local_transfer_service.dart';

class ImagesScreen extends StatefulWidget {
  static final ValueNotifier<int> selectedCount = ValueNotifier<int>(0);
  static VoidCallback? sendSelected;
  const ImagesScreen({this.enabled = true, super.key});
  final bool enabled;

  @override
  State<ImagesScreen> createState() => _ImagesScreenState();
}

class _ImagesScreenState extends State<ImagesScreen> {
  final XenderLocalTransferService _service = XenderLocalTransferService();
  final List<File> _selected = [];
  final List<SharedLocalFile> _incoming = [];
  PlazmaConnectionInvite? _invite;
  PlazmaConnectionInvite? _receiver;
  Directory? _receivedDirectory;
  bool _busy = false;
  double _progress = 0;
  String? _status;
  Timer? _roomRefreshTimer;

  @override
  void initState() { super.initState(); ImagesScreen.sendSelected = _sendImages; }

  void _updateSelectionCount() => ImagesScreen.selectedCount.value = _selected.length;

  @override
  void dispose() {
    if (ImagesScreen.sendSelected == _sendImages) ImagesScreen.sendSelected = null;
    ImagesScreen.selectedCount.value = 0;
    _roomRefreshTimer?.cancel();
    super.dispose();
  }

  // ignore: unused_element
  Future<void> _pickImages() async {
    if (_busy) return;
    try {
      // file_picker 13 returns a List<PlatformFile>; multi-select is the default.
      final result = await FilePicker.pickFiles(type: FileType.image);
      if (!mounted || result.isEmpty) return;
      setState(() {
        for (final item in result) {
          final path = item.path;
          if (path != null && !_selected.any((file) => file.path == path)) {
            _selected.add(File(path));
          }
        }
        _status = '${_selected.length} image(s) selected';
      });
      _updateSelectionCount();
    } catch (e) {
      _message('Could not open images: $e');
    }
  }

  Future<void> _sendImages() async {
    if (_selected.isEmpty || _busy) return;
    setState(() { _busy = true; _status = 'Preparing images…'; });
    final fileCount = _selected.length;
    try {
      final names = _selected.map((f) => f.uri.pathSegments.last).toList();
      final invite = await (_service.isSharing
          ? _service.addFiles(files: List<File>.from(_selected), relativePaths: names)
              .then((_) => _service.invite!)
          : _service.startSharing(files: List<File>.from(_selected), relativePaths: names));
      if (!mounted) return;
      setState(() { _invite = invite; _selected.clear(); _status = 'Room ${_invite!.roomId} · ${_service.roomMembers.length} device(s) connected'; });
      _updateSelectionCount();
      _roomRefreshTimer?.cancel();
      _roomRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      TransferOverlayController.show(TransferOverlaySnapshot(
        direction: TransferOverlayDirection.sending,
        fileCount: fileCount,
        label: 'Sharing images',
      ));
    } catch (e) {
      _message('Could not start image sharing: $e');
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
          title: const Text('Join transfer room'),
          content: TextField(controller: controller, minLines: 2, maxLines: 4,
            decoration: const InputDecoration(labelText: 'Paste Plazma S room code')),
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
    context: context,
    builder: (dialogContext) {
      var handled = false;
      return AlertDialog(
        title: const Text('Scan image-sharing QR code'),
        content: SizedBox(
          height: 320,
          child: Column(children: [
            const Text('Scan the code shown on the sending phone.'),
            const SizedBox(height: 12),
            Expanded(child: MobileScanner(onDetect: (capture) {
              if (handled) return;
              for (final barcode in capture.barcodes) {
                final invite = PlazmaConnectionInvite.tryParse(barcode.rawValue ?? '');
                if (invite != null) {
                  handled = true;
                  Navigator.of(dialogContext).pop(invite);
                  break;
                }
              }
            })),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel'))],
      );
    },
  );
  }

  // ignore: unused_element
  Future<void> _receiveImages() async {
    if (_busy) return;
    final invite = await _scan();
    if (invite == null || !mounted) return;
    setState(() { _busy = true; _status = 'Connecting to sender…'; });
    try {
      final manifest = await _service.joinAndList(invite);
      final images = manifest.where((item) {
        final name = item.relativePath.toLowerCase();
        return name.endsWith('.jpg') || name.endsWith('.jpeg') ||
            name.endsWith('.png') || name.endsWith('.webp') ||
            name.endsWith('.gif') || name.endsWith('.bmp') ||
            name.endsWith('.heic') || name.endsWith('.heif');
      }).toList();
      if (images.isEmpty) throw StateError('No images were found in this share.');
      if (!mounted) return;
      setState(() { _receiver = invite; _incoming..clear()..addAll(images); _status = '${images.length} image(s) ready to receive.'; });
      TransferOverlayController.show(TransferOverlaySnapshot(
        direction: TransferOverlayDirection.receiving,
        fileCount: images.length,
        label: 'Ready to receive images',
      ));
    } catch (e) {
      await _service.disconnect();
      _message('Could not connect: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshImages() async {
    if (_receiver == null || _busy) return;
    try {
      final all = await _service.refreshManifest(_receiver!);
      final items = all.where((item) { final n=item.relativePath.toLowerCase(); return n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.png') || n.endsWith('.webp') || n.endsWith('.gif') || n.endsWith('.bmp') || n.endsWith('.heic') || n.endsWith('.heif'); }).toList();
      setState(() {
        _incoming..clear()..addAll(items);
        _status = '${items.length} image(s) available in this room.';
      });
    } catch (e) { _message('Could not refresh shared items: $e'); }
  }

  Future<void> _downloadImages() async {
    if (_receiver == null || _incoming.isEmpty || _busy) return;
    setState(() { _busy = true; _progress = 0; _status = 'Receiving images…'; });
    try {
      final root = await getApplicationDocumentsDirectory();
      final destination = Directory('${root.path}${Platform.pathSeparator}Plazma S Images');
      await destination.create(recursive: true);
      await _service.downloadAll(
        invite: _receiver!,
        files: _incoming,
        destination: destination,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p.fraction.clamp(0.0, 1.0));
        },
      );
      for (final item in _incoming) {
        await TransferHistoryStore.add(
          name: item.name,
          type: 'image',
          direction: 'received',
          path: '${destination.path}${Platform.pathSeparator}${item.relativePath}',
          bytes: item.size,
          peer: 'Nearby Plazma S device',
        );
      }
      if (!mounted) return;
      setState(() {
        _receivedDirectory = destination;
        _status = 'Received ${_incoming.length} image(s). Saved in Plazma S Images.';
      });
      TransferOverlayController.clear();
      await _service.stopForegroundService();
    } catch (e) {
      _message('Image transfer failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopSharing() async {
    _roomRefreshTimer?.cancel();
    _roomRefreshTimer = null;
    await _service.stopSharing();
    TransferOverlayController.clear();
    if (mounted) setState(() { _invite = null; _status = 'Image sharing stopped.'; });
  }

  Future<void> _disconnect() async {
    if (_busy) return;
    await _service.disconnect();
    TransferOverlayController.clear();
    if (mounted) setState(() { _receiver = null; _incoming.clear(); _status = 'Disconnected.'; });
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Images', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      Text('Choose images on this device and share them with up to seven PCs or phones on the same Wi-Fi.',
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
      const SizedBox(height: 14),
      if (_status != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_status!))),
      if (_invite != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        Text('Room ${_invite!.roomId} · Scan to join this room', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 12),
        Container(color: Colors.white, padding: const EdgeInsets.all(10),
          child: QrImageView(data: _invite!.toQrValue(), size: 220)),
        const SizedBox(height: 8),
        Text('Same Wi-Fi · ${_invite!.host}:${_invite!.port}'),
        TextButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: _invite!.roomId)), icon: const Icon(Icons.copy, size: 16), label: const Text('Copy room code')),
        Row(children: [
          const Expanded(child: Text('Connected devices', style: TextStyle(fontWeight: FontWeight.w800))),
          Text('${_service.joinedDeviceCount}/7'),
        ]),
        ..._service.roomMembers.map((member) => ListTile(
          dense: true,
          leading: Icon(member.platform == 'android' ? Icons.phone_android : Icons.computer),
          title: Text(member.deviceName),
          subtitle: Text(member.platform),
          trailing: Icon(member.completed ? Icons.check_circle : Icons.wifi, color: member.completed ? Colors.green : null),
        )),
        OutlinedButton.icon(onPressed: _busy ? null : _stopSharing,
          icon: const Icon(Icons.stop), label: const Text('Stop sharing')),
      ]))),
      if (_receiver != null) Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
        Row(children: [Expanded(child: Text('${_incoming.length} image(s) ready', style: const TextStyle(fontWeight: FontWeight.w800))),
          TextButton(onPressed: _busy ? null : _refreshImages, child: const Text('Refresh')),
          TextButton(onPressed: _busy ? null : _disconnect, child: const Text('Disconnect'))]),
        if (_busy) LinearProgressIndicator(value: _progress > 0 ? _progress : null),
        FilledButton.icon(onPressed: _busy ? null : _downloadImages,
          icon: const Icon(Icons.download), label: const Text('Receive images')),
      ]))),
      if (_receiver == null) ...[
        DeviceMediaBrowser(
          enabled: widget.enabled,
          kind: MediaKind.images,
          selectedPaths: _selected.map((file) => file.path).toSet(),
          onSelect: (file) {
            setState(() {
              if (_selected.any((existing) => existing.path == file.path)) {
                _selected.removeWhere((existing) => existing.path == file.path);
              } else {
                _selected.add(file);
              }
              _status = _selected.isEmpty ? null : '${_selected.length} image(s) selected';
            });
            _updateSelectionCount();
          },
        ),
        const SizedBox(height: 12),
      ],
      if (_receivedDirectory != null) Text('Saved to: ${_receivedDirectory!.path}',
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
      if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
    ]);
  }
}