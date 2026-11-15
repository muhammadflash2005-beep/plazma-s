import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../network/android_wifi_session_service.dart';
import '../../transfers/transfer_history.dart';
import '../../transfers/transfer_overlay_controller.dart';
import '../../transfers/xender_local_transfer_service.dart';

class ImagesScreen extends StatefulWidget {
  const ImagesScreen({super.key});

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

  @override
  void dispose() {
    unawaited(_service.stopSharing());
    unawaited(_service.disconnect());
    super.dispose();
  }

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
    } catch (e) {
      _message('Could not open images: $e');
    }
  }

  Future<void> _sendImages() async {
    if (_selected.isEmpty || _busy) return;
    setState(() { _busy = true; _status = 'Preparing images…'; });
    try {
      final names = _selected.map((f) => f.uri.pathSegments.last).toList();
      final invite = await _service.startSharing(
        files: List<File>.from(_selected),
        relativePaths: names,
      );
      if (!mounted) return;
      setState(() { _invite = invite; _status = 'Scan this QR code on the receiving phone.'; });
      TransferOverlayController.show(TransferOverlaySnapshot(
        direction: TransferOverlayDirection.sending,
        fileCount: _selected.length,
        label: 'Sharing images',
      ));
    } catch (e) {
      _message('Could not start image sharing: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<PlazmaConnectionInvite?> _scan() => showDialog<PlazmaConnectionInvite>(
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
      Text('Choose photos, preview your selection, and share them directly with another phone.',
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
      const SizedBox(height: 14),
      if (_status != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_status!))),
      if (_invite != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        const Text('Scan to receive these images', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 12),
        Container(color: Colors.white, padding: const EdgeInsets.all(10),
          child: QrImageView(data: _invite!.toQrValue(), size: 220)),
        const SizedBox(height: 8),
        Text('Wi-Fi: ${_invite!.ssid}'),
        OutlinedButton.icon(onPressed: _busy ? null : _stopSharing,
          icon: const Icon(Icons.stop), label: const Text('Stop sharing')),
      ]))),
      if (_receiver != null) Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
        Row(children: [Expanded(child: Text('${_incoming.length} image(s) ready', style: const TextStyle(fontWeight: FontWeight.w800))),
          TextButton(onPressed: _busy ? null : _disconnect, child: const Text('Disconnect'))]),
        if (_busy) LinearProgressIndicator(value: _progress > 0 ? _progress : null),
        FilledButton.icon(onPressed: _busy ? null : _downloadImages,
          icon: const Icon(Icons.download), label: const Text('Receive images')),
      ]))),
      if (_invite == null && _receiver == null) ...[
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: _busy ? null : _pickImages,
            icon: const Icon(Icons.add_photo_alternate), label: const Text('Choose images'))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : _receiveImages,
            icon: const Icon(Icons.qr_code_scanner), label: const Text('Receive'))),
        ]),
        const SizedBox(height: 12),
        if (_selected.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(24),
            child: Center(child: Column(children: [
              Icon(Icons.photo_library_outlined, size: 44),
              SizedBox(height: 8),
              Text('Your selected images will appear here.'),
            ]))))
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _selected.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
            itemBuilder: (context, index) => Stack(fit: StackFit.expand, children: [
              ClipRRect(borderRadius: BorderRadius.circular(12),
                child: Image.file(_selected[index], fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const ColoredBox(
                    color: Colors.black12, child: Icon(Icons.image_not_supported)))),
              Positioned(right: 4, top: 4, child: IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                onPressed: _busy ? null : () => setState(() => _selected.removeAt(index)),
                icon: const Icon(Icons.close, size: 17))),
            ]),
          ),
        if (_selected.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _busy ? null : _sendImages,
            icon: const Icon(Icons.send_rounded),
            label: Text('Send ${_selected.length} image(s)'),
          )),
          TextButton(onPressed: _busy ? null : () => setState(() => _selected.clear()),
            child: const Text('Clear selection')),
        ],
      ],
      if (_receivedDirectory != null) Text('Saved to: ${_receivedDirectory!.path}',
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
      if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
    ]);
  }
}