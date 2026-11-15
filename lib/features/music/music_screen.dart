// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../network/android_wifi_session_service.dart';
import '../../transfers/transfer_history.dart';
import '../../transfers/transfer_overlay_controller.dart';
import '../../transfers/xender_local_transfer_service.dart';

class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
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
  void dispose() {
    _roomRefreshTimer?.cancel();
    unawaited(_service.stopSharing());
    unawaited(_service.disconnect());
    super.dispose();
  }

  Future<void> _pickMusic() async {
    if (_busy) return;
    try {
      // file_picker 13 returns a List<PlatformFile>; multi-select is the default.
      final result = await FilePicker.pickFiles(type: FileType.audio);
      if (!mounted || result.isEmpty) return;
      setState(() {
        for (final item in result) {
          final path = item.path;
          if (path != null && !_selected.any((file) => file.path == path)) {
            _selected.add(File(path));
          }
        }
        _status = '${_selected.length} song(s) selected';
      });
    } catch (e) {
      _message('Could not open music: $e');
    }
  }

  Future<void> _sendMusic() async {
    if (_selected.isEmpty || _busy) return;
    setState(() { _busy = true; _status = 'Preparing music…'; });
    try {
      final names = _selected.map((f) => f.uri.pathSegments.last).toList();
      final invite = await _service.startSharing(
        files: List<File>.from(_selected),
        relativePaths: names,
        onTransferCompleted: () async {
          for (final file in _selected) {
            await TransferHistoryStore.add(
              name: file.uri.pathSegments.last,
              type: 'music',
              direction: 'sent',
              path: file.path,
              bytes: await file.length(),
              peer: 'Nearby Plazma S device',
            );
          }
        },
      );
      if (!mounted) return;
      setState(() { _invite = invite; _status = 'Room ${_invite!.roomId} · waiting for devices'; });
      _roomRefreshTimer?.cancel();
      _roomRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      TransferOverlayController.show(TransferOverlaySnapshot(
        direction: TransferOverlayDirection.sending,
        fileCount: _selected.length,
        label: 'Sharing music',
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
        title: const Text('Scan music-sharing QR code'),
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

  Future<void> _receiveMusic() async {
    if (_busy) return;
    final invite = await _scan();
    if (invite == null || !mounted) return;
    setState(() { _busy = true; _status = 'Connecting to sender…'; });
    try {
      final manifest = await _service.joinAndList(invite);
      final musicFiles = manifest.where((item) {
        final name = item.relativePath.toLowerCase();
        return name.endsWith('.mp3') || name.endsWith('.m4a') ||
            name.endsWith('.aac') || name.endsWith('.wav') ||
            name.endsWith('.flac') || name.endsWith('.ogg') ||
            name.endsWith('.opus') || name.endsWith('.wma') ||
            name.endsWith('.aiff');
      }).toList();
      if (musicFiles.isEmpty) throw StateError('No music files were found in this share.');
      if (!mounted) return;
      setState(() { _receiver = invite; _incoming..clear()..addAll(musicFiles); _status = '${musicFiles.length} song(s) ready to receive.'; });
      TransferOverlayController.show(TransferOverlaySnapshot(
        direction: TransferOverlayDirection.receiving,
        fileCount: musicFiles.length,
        label: 'Ready to receive music',
      ));
    } catch (e) {
      await _service.disconnect();
      _message('Could not connect: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadMusic() async {
    if (_receiver == null || _incoming.isEmpty || _busy) return;
    setState(() { _busy = true; _progress = 0; _status = 'Receiving music…'; });
    try {
      final root = await getApplicationDocumentsDirectory();
      final destination = Directory('${root.path}${Platform.pathSeparator}Plazma S Music');
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
          type: 'music',
          direction: 'received',
          path: '${destination.path}${Platform.pathSeparator}${item.relativePath}',
          bytes: item.size,
          peer: 'Nearby Plazma S device',
        );
      }
      if (!mounted) return;
      setState(() {
        _receivedDirectory = destination;
        _status = 'Received ${_incoming.length} song(s). Saved in Plazma S Music.';
      });
      TransferOverlayController.clear();
      await _service.stopForegroundService();
    } catch (e) {
      _message('Music transfer failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopSharing() async {
    _roomRefreshTimer?.cancel();
    _roomRefreshTimer = null;
    await _service.stopSharing();
    TransferOverlayController.clear();
    if (mounted) setState(() { _invite = null; _status = 'Music sharing stopped.'; });
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
      Text('Music', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      Text('Choose audio files stored on your device, and share them directly with another phone.',
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
      const SizedBox(height: 14),
      if (_status != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_status!))),
      if (_invite != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        const Text('Scan to receive this music', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 12),
        Container(color: Colors.white, padding: const EdgeInsets.all(10),
          child: QrImageView(data: _invite!.toQrValue(), size: 220)),
        const SizedBox(height: 8),
        Text('Same Wi-Fi · ${_invite!.host}:${_invite!.port}'),
        SelectableText(_invite!.toQrValue(), textAlign: TextAlign.center),
        TextButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: _invite!.toQrValue())), icon: const Icon(Icons.copy, size: 16), label: const Text('Copy room code')),
        Row(children: [
          const Expanded(child: Text('Connected devices', style: TextStyle(fontWeight: FontWeight.w800))),
          Text(_service.joinedDeviceCount.toString() + '/8'),
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
        Row(children: [Expanded(child: Text('${_incoming.length} song(s) ready', style: const TextStyle(fontWeight: FontWeight.w800))),
          TextButton(onPressed: _busy ? null : _disconnect, child: const Text('Disconnect'))]),
        if (_busy) LinearProgressIndicator(value: _progress > 0 ? _progress : null),
        FilledButton.icon(onPressed: _busy ? null : _downloadMusic,
          icon: const Icon(Icons.download), label: const Text('Receive music')),
      ]))),
      if (_invite == null && _receiver == null) ...[
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: _busy ? null : _pickMusic,
            icon: const Icon(Icons.library_music_rounded), label: const Text('Choose music'))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : _receiveMusic,
            icon: const Icon(Icons.qr_code_scanner), label: const Text('Receive'))),
        ]),
        const SizedBox(height: 12),
        if (_selected.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(24),
            child: Center(child: Column(children: [
              Icon(Icons.library_music_outlined, size: 44),
              SizedBox(height: 8),
              Text('Choose audio files from your device to see them here.'),
            ]))))
        else
          Card(child: Column(children: [
            for (var index = 0; index < _selected.length; index++)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.music_note_rounded)),
                title: Text(_selected[index].uri.pathSegments.last,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${(_selected[index].lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB'),
                trailing: IconButton(
                  tooltip: 'Remove song',
                  onPressed: _busy ? null : () => setState(() => _selected.removeAt(index)),
                  icon: const Icon(Icons.close_rounded)),
              ),
          ])),
        if (_selected.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _busy ? null : _sendMusic,
            icon: const Icon(Icons.send_rounded),
            label: Text('Send ${_selected.length} song(s)'),
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