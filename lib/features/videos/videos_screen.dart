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
import '../../transfers/transfer_overlay_controller.dart';
import '../../transfers/xender_local_transfer_service.dart';

class VideosScreen extends StatefulWidget {
  static final ValueNotifier<int> selectedCount = ValueNotifier<int>(0);
  static VoidCallback? sendSelected;
  const VideosScreen({this.enabled = true, this.scrollController, super.key});
  final bool enabled;
  final ScrollController? scrollController;

  @override
  State<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends State<VideosScreen> {
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
  StreamSubscription<List<SharedLocalFile>>? _manifestSubscription;

  @override
  void initState() {
    super.initState();
    VideosScreen.sendSelected = _sendVideos;
    _service.roomFiles.addListener(_syncRoomFiles);
    _syncRoomFiles();
    _invite = _service.invite;
    _receiver = _service.joinedInvite;
    if (_receiver != null) _watchIncomingVideos(_receiver!);
  }

  void _updateSelectionCount() => VideosScreen.selectedCount.value = _selected.length;

  @override
  void dispose() {
    if (VideosScreen.sendSelected == _sendVideos) VideosScreen.sendSelected = null;
    VideosScreen.selectedCount.value = 0;
    _roomRefreshTimer?.cancel();
    _manifestSubscription?.cancel();
    _service.roomFiles.removeListener(_syncRoomFiles);
    super.dispose();
  }

  void _syncRoomFiles() {
    final invite = _service.joinedInvite;
    final items = invite == null ? <SharedLocalFile>[] : _service.roomFiles.value.where((item) {
      final name = item.relativePath.toLowerCase();
      return ['.mp4', '.m4v', '.mov', '.mkv', '.webm', '.avi', '.3gp'].any(name.endsWith);
    }).toList();
    if (!mounted) return;
    setState(() { _receiver = invite; _incoming..clear()..addAll(items); });
  }
  void _watchIncomingVideos(PlazmaConnectionInvite invite) {
    _manifestSubscription?.cancel();
    _manifestSubscription = _service.watchManifest(invite).listen((manifest) {
      final items = manifest.where((item) {
        final name = item.relativePath.toLowerCase();
        return name.endsWith('.mp4') || name.endsWith('.m4v') ||
            name.endsWith('.mov') || name.endsWith('.mkv') ||
            name.endsWith('.webm') || name.endsWith('.avi') ||
            name.endsWith('.3gp');
      }).toList();
      if (!mounted) return;
      setState(() { _incoming..clear()..addAll(items); _status = '${items.length} video(s) available in this room.'; });
    }, onError: (Object error) { if (mounted) _message('Live room update failed: $error'); });
  }

  // ignore: unused_element
  Future<void> _pickVideos() async {
    if (_busy) return;
    try {
      // file_picker 13 returns a List<PlatformFile>; multi-select is the default.
      final result = await FilePicker.pickFiles(type: FileType.video);
      if (!mounted || result.isEmpty) return;
      setState(() {
        for (final item in result) {
          final path = item.path;
          if (path != null && !_selected.any((file) => file.path == path)) {
            _selected.add(File(path));
          }
        }
        _status = '${_selected.length} video(s) selected';
      });
      _updateSelectionCount();
    } catch (e) {
      _message('Could not open videos: $e');
    }
  }

  Future<void> _sendVideos() async {
    if (_selected.isEmpty || _busy) return;
    setState(() { _busy = true; _status = 'Preparing videos…'; });
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
        label: 'Sharing videos',
      ));
    } catch (e) {
      _message('Could not start video sharing: $e');
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
        title: const Text('Scan video-sharing QR code'),
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
  Future<void> _receiveVideos() async {
    if (_busy) return;
    final invite = await _scan();
    if (invite == null || !mounted) return;
    setState(() { _busy = true; _status = 'Connecting to sender…'; });
    try {
      final manifest = await _service.joinAndList(invite);
      final videos = manifest.where((item) {
        final name = item.relativePath.toLowerCase();
        return name.endsWith('.mp4') || name.endsWith('.mkv') ||
            name.endsWith('.mov') || name.endsWith('.avi') ||
            name.endsWith('.webm') || name.endsWith('.3gp') ||
            name.endsWith('.m4v') || name.endsWith('.wmv') || name.endsWith('.flv');
      }).toList();
      if (videos.isEmpty) throw StateError('No videos were found in this share.');
      if (!mounted) return;
      setState(() { _receiver = invite; _incoming..clear()..addAll(videos); _status = '${videos.length} video(s) ready to receive.'; });
      _watchIncomingVideos(invite);
      TransferOverlayController.show(TransferOverlaySnapshot(
        direction: TransferOverlayDirection.receiving,
        fileCount: videos.length,
        label: 'Ready to receive videos',
      ));
      // Joining starts the full room queue automatically.
      if (mounted) setState(() => _busy = false);
      await _downloadVideos();
    } catch (e) {
      await _service.disconnect();
      _message('Could not connect: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshVideos() async {
    if (_receiver == null || _busy) return;
    try {
      final all = await _service.refreshManifest(_receiver!);
      final items = all.where((item) { final n=item.relativePath.toLowerCase(); return n.endsWith('.mp4') || n.endsWith('.mkv') || n.endsWith('.mov') || n.endsWith('.avi') || n.endsWith('.webm') || n.endsWith('.3gp') || n.endsWith('.m4v') || n.endsWith('.wmv') || n.endsWith('.flv'); }).toList();
      setState(() {
        _incoming..clear()..addAll(items);
        _status = '${items.length} video(s) available in this room.';
      });
    } catch (e) { _message('Could not refresh shared items: $e'); }
  }

  Future<void> _downloadVideos() async {
    if (_receiver == null || _incoming.isEmpty || _busy) return;
    setState(() { _busy = true; _progress = 0; _status = 'Receiving videos…'; });
    try {
      final root = await getApplicationDocumentsDirectory();
      final destination = Directory('${root.path}${Platform.pathSeparator}Plazma S Received');
      await destination.create(recursive: true);
      await _service.downloadAll(
        invite: _receiver!,
        files: _service.roomFiles.value,
        destination: destination,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p.fraction.clamp(0.0, 1.0));
        },
        onSaved: (item, path, uri) => _savedMessage(path, uri),
      );
      if (!mounted) return;
      setState(() {
        _receivedDirectory = destination;
        _status = 'Received all ${_service.roomFiles.value.length} item(s) in this room.';
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

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Videos', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      Text('Choose videos on this device and share them with up to seven PCs or phones on the same Wi-Fi.',
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
      const SizedBox(height: 14),
      if (_status != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_status!))),
      if (_invite != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        Text('Room ${_invite!.roomId}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 12),
        Container(color: Colors.white, padding: const EdgeInsets.all(10),
          child: QrImageView(data: _invite!.toQrValue(), size: 220)),
        const SizedBox(height: 8),
        Text('Same Wi-Fi · ${_invite!.host}:${_invite!.port}'),
        TextButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: _invite!.roomId)), icon: const Icon(Icons.copy, size: 16), label: const Text('Copy room code')),
        PopupMenuButton<String>(
          tooltip: 'More room actions',
          onSelected: (value) { if (value == 'link') Clipboard.setData(ClipboardData(text: _invite!.toQrValue())); },
          itemBuilder: (context) => const [PopupMenuItem(value: 'link', child: Text('Copy connection link'))],
        ),
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
        Row(children: [Expanded(child: Text('${_incoming.length} video(s) ready', style: const TextStyle(fontWeight: FontWeight.w800))),
          TextButton(onPressed: _busy ? null : _refreshVideos, child: const Text('Refresh')),
          TextButton(onPressed: _busy ? null : _disconnect, child: const Text('Disconnect'))]),
        if (_busy) LinearProgressIndicator(value: _progress > 0 ? _progress : null),
        if (!_service.isReceiving)
          FilledButton.icon(onPressed: _busy || _receivedDirectory != null ? null : _downloadVideos,
            icon: const Icon(Icons.download), label: Text(_busy ? 'Receiving files…' : _receivedDirectory != null ? 'Received' : 'Receive videos')),
      ]))),
      if (_receiver == null) ...[
        DeviceMediaBrowser(
          enabled: widget.enabled,
          parentScrollController: widget.scrollController,
          kind: MediaKind.videos,
          selectedPaths: _selected.map((file) => file.path).toSet(),
          onSelect: (file) {
            setState(() {
              if (_selected.any((existing) => existing.path == file.path)) {
                _selected.removeWhere((existing) => existing.path == file.path);
              } else {
                _selected.add(file);
              }
              _status = _selected.isEmpty ? null : '${_selected.length} video(s) selected';
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