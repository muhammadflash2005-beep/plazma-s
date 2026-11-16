// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../media/permanent_delete_confirmation.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../network/android_wifi_session_service.dart';
import '../../transfers/transfer_history.dart';
import '../../transfers/transfer_mode.dart';
import '../../transfers/transfer_overlay_controller.dart';
import '../../transfers/xender_local_transfer_service.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({this.transferMode, this.initialPaths = const [], this.initialAction, super.key});

  final TransferMode? transferMode;
  final List<String> initialPaths;
  final String? initialAction;

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  final XenderLocalTransferService _service = XenderLocalTransferService();
  final List<File> _files = [];
  final List<String> _relativePaths = [];
  PlazmaConnectionInvite? _invite;
  PlazmaConnectionInvite? _receiverInvite;
  List<SharedLocalFile> _availableFiles = [];
  String? _destination;
  String? _status;
  String? _currentFile;
  double _progress = 0;
  bool _busy = false;
  bool _downloading = false;
  bool _downloaded = false;
  Timer? _roomRefreshTimer;
  Timer? _statusMessageTimer;
  String _fileSearchQuery = '';
  StreamSubscription<List<SharedLocalFile>>? _manifestSubscription;

  @override
  void initState() {
    super.initState();
    _invite = _service.invite;
    _service.roomFiles.addListener(_syncRoomFiles);
    _syncRoomFiles();
    _receiverInvite = _service.joinedInvite;
    if (_receiverInvite != null) _watchIncomingFiles(_receiverInvite!);
    _addInitialPaths(widget.initialPaths);
  }

  @override
  void didUpdateWidget(covariant FilesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPaths != widget.initialPaths) {
      _addInitialPaths(widget.initialPaths);
    }
  }

  List<int> get _visibleFileIndexes {
    final query = _fileSearchQuery.trim().toLowerCase();
    return List<int>.generate(_files.length, (index) => index)
        .where((index) => query.isEmpty || _relativePaths[index].toLowerCase().contains(query))
        .toList();
  }

  void _addInitialPaths(List<String> paths) {
    var added = 0;
    for (final path in paths) {
      if (_files.any((file) => file.path == path)) continue;
      final file = File(path);
      if (!file.existsSync()) continue;
      final segments = path.split(Platform.pathSeparator);
      final relative = segments.length >= 2
          ? '${segments[segments.length - 2]}/${segments.last}'
          : segments.last;
      _files.add(file);
      _relativePaths.add(relative);
      added++;
    }
    if (added > 0) _status = 'Added $added exported APK file(s) from selected apps';
  }

  @override
  void dispose() {
    _roomRefreshTimer?.cancel();
    _statusMessageTimer?.cancel();
    _manifestSubscription?.cancel();
    _service.roomFiles.removeListener(_syncRoomFiles);
    super.dispose();
  }

  void _syncRoomFiles() {
    final invite = _service.joinedInvite;
    if (!mounted) return;
    setState(() { _receiverInvite = invite; _availableFiles = invite == null ? const [] : _service.roomFiles.value; });
  }
  Future<void> _deleteSelectedFiles() async {
    if (_files.isEmpty || _busy) return;
    final count = _files.length;
    final confirmed = await confirmPermanentDelete(
      context,
      itemDescription: '$count selected file(s)',
    );
    if (!confirmed) return;
    var deleted = 0;
    final errors = <String>[];
    final failedPaths = <String>{};
    for (final file in List<File>.from(_files)) {
      try {
        if (await file.exists()) await file.delete();
        deleted++;
      } catch (error) {
        failedPaths.add(file.path);
        errors.add('${file.uri.pathSegments.last}: $error');
      }
    }
    if (!mounted) return;
    setState(() {
      if (errors.isEmpty) {
        _files.clear();
        _relativePaths.clear();
      } else {
        for (var i = _files.length - 1; i >= 0; i--) {
          if (!failedPaths.contains(_files[i].path)) {
            _files.removeAt(i);
            _relativePaths.removeAt(i);
          }
        }
      }
    });
    _message(errors.isEmpty
        ? 'Permanently deleted $deleted file(s).'
        : 'Deleted $deleted file(s); ${errors.length} could not be deleted.');
  }

  Future<void> _manageStagedFile(int index, String action) async {
    if (index < 0 || index >= _files.length || _busy) return;
    final source = _files[index];
    final name = _relativePaths[index].split('/').last;
    try {
      if (action == 'remove') {
        setState(() { _files.removeAt(index); _relativePaths.removeAt(index); });
        return;
      }
      if (action == 'rename') {
        final controller = TextEditingController(text: name);
        final nextName = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Rename file'),
            content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'New name')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Rename')),
            ],
          ),
        );
        controller.dispose();
        if (nextName == null || nextName.isEmpty || nextName == name) return;
        final target = File('${source.parent.path}${Platform.pathSeparator}$nextName');
        if (await target.exists()) throw FileSystemException('A file with that name already exists.', target.path);
        final renamed = await source.rename(target.path);
        if (!mounted) return;
        setState(() { _files[index] = renamed; _relativePaths[index] = nextName; });
        _message('File renamed');
      } else if (action == 'copy' || action == 'move') {
        final directory = await FilePicker.getDirectoryPath();
        if (directory == null) return;
        final target = File('$directory${Platform.pathSeparator}$name');
        if (await target.exists()) throw FileSystemException('A file with that name already exists in the selected folder.', target.path);
        await source.copy(target.path);
        if (action == 'move') {
          final confirmed = await confirmPermanentDelete(context,
            itemDescription: 'the original $name after it is copied to the selected folder');
          if (!confirmed) { await target.delete(); return; }
          await source.delete();
          if (!mounted) return;
          setState(() { _files[index] = target; _relativePaths[index] = name; });
        }
        _message(action == 'move' ? 'File moved' : 'File copied to selected folder');
      } else if (action == 'delete') {
        final confirmed = await confirmPermanentDelete(context, itemDescription: name);
        if (!confirmed) return;
        await source.delete();
        if (!mounted) return;
        setState(() { _files.removeAt(index); _relativePaths.removeAt(index); });
        _message('File permanently deleted');
      }
    } catch (error) {
      if (mounted) _message('Could not $action file: $error');
    }
  }

  Future<void> _pickFiles() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await FilePicker.pickFiles();
      if (!mounted || result.isEmpty) return;
      setState(() {
        for (final picked in result) {
          final path = picked.path;
          if (path == null || _files.any((file) => file.path == path)) continue;
          _files.add(File(path));
          _relativePaths.add(picked.name);
        }
        _status = _files.isEmpty ? 'No files selected' : '${_files.length} file(s) ready to share';
      });
    } catch (error) {
      _message('Could not select files: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFolder() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final path = await FilePicker.getDirectoryPath();
      if (path == null || !mounted) return;
      final root = Directory(path);
      final prefix = root.path.endsWith(Platform.pathSeparator)
          ? root.path
          : '${root.path}${Platform.pathSeparator}';
      final foundFiles = <File>[];
      final foundPaths = <String>[];
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        if (stat.type != FileSystemEntityType.file) continue;
        final relative = entity.path.substring(prefix.length).replaceAll(Platform.pathSeparator, '/');
        if (relative.isEmpty || relative.startsWith('../')) continue;
        if (_relativePaths.contains(relative) || foundPaths.contains(relative)) continue;
        foundFiles.add(entity);
        foundPaths.add(relative);
      }
      if (!mounted) return;
      setState(() {
        _files.addAll(foundFiles);
        _relativePaths.addAll(foundPaths);
        _status = 'Added ${foundFiles.length} file(s) from folder';
      });
    } catch (error) {
      _message('Could not read folder: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startSharing() async {
    if (_files.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _status = Platform.isAndroid
          ? 'Starting local Wi-Fi room…'
          : 'Preparing a local network share…';
    });
    try {
      final invite = _service.isSharing
          ? await _service.addFiles(
              files: List<File>.from(_files),
              relativePaths: List<String>.from(_relativePaths),
            ).then((_) => _service.invite!)
          : await _service.startSharing(
        files: List<File>.from(_files),
        relativePaths: List<String>.from(_relativePaths),
        onTransferCompleted: () async {
          for (var index = 0; index < _files.length; index++) {
            final file = _files[index];
            await TransferHistoryStore.add(
              name: _relativePaths[index].split('/').last,
              type: 'file',
              direction: 'sent',
              path: file.path,
              bytes: await file.length(),
              peer: 'Nearby Plazma S device',
            );
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _status = 'Room ${invite.roomId} is open · waiting for devices';
      });
      _roomRefreshTimer?.cancel();
      _roomRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      TransferOverlayController.show(TransferOverlaySnapshot(
        direction: TransferOverlayDirection.sending,
        fileCount: _files.length,
        label: 'Waiting for receiver',
      ));
    } catch (error) {
      _message('Could not start sharing: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<PlazmaConnectionInvite?> _scanInvite() async {
    if (!Platform.isAndroid) {
      final controller = TextEditingController();
      final raw = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Enter connection code'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('On the sending device, open More room actions → Copy connection link, then paste that link below. The short room code is for identifying the room; it does not contain the connection details. Both devices must already be connected to the same Wi-Fi.'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Plazma S connection link',
                    hintText: 'Paste the copied connection link',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Connect'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (raw == null) return null;
      final invite = PlazmaConnectionInvite.tryParse(raw);
      if (invite == null) _message('That is not a valid Plazma S connection code.');
      return invite;
    }
    return showDialog<PlazmaConnectionInvite>(
      context: context,
      builder: (dialogContext) {
        var handled = false;
        return AlertDialog(
          title: const Text('Scan sender QR code'),
          content: SizedBox(
            width: 320,
            height: 340,
            child: Column(
              children: [
                const Text('Scan the QR code shown by the sending device.'),
                const SizedBox(height: 14),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: MobileScanner(
                      onDetect: (capture) {
                        if (handled) return;
                        final raw = capture.barcodes
                            .map((barcode) => barcode.rawValue)
                            .whereType<String>()
                            .firstOrNull;
                        if (raw == null) return;
                        final invite = PlazmaConnectionInvite.tryParse(raw);
                        if (invite == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('That is not a valid Plazma S connection QR code.')),
                          );
                          return;
                        }
                        handled = true;
                        Navigator.of(dialogContext).pop(invite);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _watchIncomingFiles(PlazmaConnectionInvite invite) {
    _manifestSubscription?.cancel();
    _manifestSubscription = _service.watchManifest(invite).listen((manifest) {
      if (!mounted) return;
      setState(() { _availableFiles = manifest; _status = 'Connected — ${manifest.length} item(s) available'; });
    }, onError: (Object error) { if (mounted) _message('Live room update failed: $error'); });
  }

  Future<void> _joinSender() async {
    if (_busy) return;
    final invite = await _scanInvite();
    if (invite == null || !mounted) return;
    setState(() {
      _busy = true;
      _status = 'Connecting to the sender…';
    });
    try {
      final files = await _service.joinAndList(invite);
      if (!mounted) return;
      setState(() {
        _downloaded = false;
        _receiverInvite = invite;
        _availableFiles = files;
        _status = files.isEmpty ? 'Connected. The sender has no files available.' : 'Connected — ${files.length} file(s) available';
      });
      _watchIncomingFiles(invite);
      if (files.isNotEmpty) {
        TransferOverlayController.show(TransferOverlaySnapshot(
          direction: TransferOverlayDirection.receiving,
          fileCount: files.length,
          label: 'Ready to receive',
        ));
      }
      if (files.isEmpty) {
        _message('Connected, but the sender has not shared any files.');
      }
    } catch (error) {
      await _service.disconnect();
      _message('Could not connect: $error');
      if (mounted) setState(() => _status = 'Connection failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseDestination() async {
    final path = await FilePicker.getDirectoryPath();
    if (path != null && mounted) setState(() => _destination = path);
  }

  Future<void> _downloadFiles() async {
    final invite = _receiverInvite;
    if (invite == null || _availableFiles.isEmpty || _downloading) return;
    var destination = _destination;
    if (destination == null) {
      await _chooseDestination();
      destination = _destination;
    }
    if (destination == null || !mounted) return;
    setState(() {
      _downloading = true;
      _progress = 0;
      _status = 'Preparing downloads…';
    });
    try {
      await _service.downloadAll(
        invite: invite,
        files: _availableFiles,
        destination: Directory(destination),
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _currentFile = progress.fileName;
            _progress = progress.totalSize == 0
                ? 1
                : progress.totalBytes / progress.totalSize;
            _status = 'Receiving ${progress.fileName}';
          });
          TransferOverlayController.show(TransferOverlaySnapshot(
            direction: TransferOverlayDirection.receiving,
            fileCount: _availableFiles.length,
            label: '${(progress.fraction * 100).clamp(0, 100).toStringAsFixed(0)}% · ${progress.fileName}',
            progress: progress.fraction.clamp(0, 1),
          ));
        },
      );
      for (final item in _availableFiles) {
        await TransferHistoryStore.add(
          name: item.name,
          type: 'file',
          direction: 'received',
          path: '$destination/${item.relativePath}',
          bytes: item.size,
          peer: 'Nearby Plazma S device',
        );
      }
      if (!mounted) return;
      setState(() {
        _progress = 1;
        _status = 'All ${_availableFiles.length} file(s) received successfully';
        _downloaded = true;
      });
      TransferOverlayController.clear();
      await _service.stopForegroundService();
      _message('Transfer complete. Files saved to $destination');
    } catch (error) {
      TransferOverlayController.show(TransferOverlaySnapshot(
        direction: TransferOverlayDirection.receiving,
        fileCount: _availableFiles.length,
        label: 'Transfer interrupted',
      ));
      _message('Transfer failed: $error');
      if (mounted) setState(() => _status = 'Transfer failed');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _installReceivedApp(String packageName) async {
    final parts = _availableFiles
        .where((item) => item.relativePath.startsWith('$packageName/'))
        .toList()
      ..sort((a, b) {
        int splitOrder(SharedLocalFile item) {
          if (item.relativePath.endsWith('/base.apk')) return 0;
          final match = RegExp(r'/split_(\d+)\.apk$').firstMatch(item.relativePath);
          return int.tryParse(match?.group(1) ?? '') ?? (1 << 30);
        }
        return splitOrder(a).compareTo(splitOrder(b));
      });
    if (parts.isEmpty || _destination == null) return;
    final paths = parts.map((item) {
      final relative = item.relativePath.replaceAll('/', Platform.pathSeparator);
      return '$_destination${Platform.pathSeparator}$relative';
    }).toList();
    try {
      await const MethodChannel('com.plazma.s/apps').invokeMethod<void>(
        'installApkSet',
        {'packageName': packageName, 'paths': paths},
      );
      _message('Android package installer opened for $packageName. Review and approve the installation there.');
    } catch (error) {
      _message('Could not start installation: $error');
    }
  }

  List<String> get _receivedAppPackages {
    if (!_downloaded) return const [];
    return _availableFiles
        .where((item) => item.relativePath.endsWith('/base.apk'))
        .map((item) => item.relativePath.split('/').first)
        .toSet()
        .toList();
  }

  Future<void> _stopSharing() async {
    await _service.stopSharing();
    TransferOverlayController.clear();
    if (!mounted) return;
    _statusMessageTimer?.cancel();
    setState(() {
      _invite = null;
      _status = 'Sharing stopped';
    });
    // Keep the confirmation visible briefly, then clear it so the idle
    // Files screen does not retain a stale session message indefinitely.
    _statusMessageTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _status != 'Sharing stopped') return;
      setState(() => _status = null);
    });
  }

  Future<void> _disconnectReceiver() async {
    if (_downloading) {
      _message('A transfer is active. Wait for it to finish before disconnecting.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disconnect?'),
        content: const Text('End this Wi-Fi transfer session and disconnect from the sender?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.disconnect();
    TransferOverlayController.clear();
    if (!mounted) return;
    setState(() {
      _receiverInvite = null;
      _availableFiles = [];
      _destination = null;
      _status = 'Disconnected';
    });
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Share files', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text('Connect devices on the same Wi-Fi network. No hotspot switching or internet required.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 18),
        if (_status != null) _statusCard(theme),
        if (widget.initialAction != 'join') ...[
          if (_invite == null) _senderPanel(theme) else _senderQrPanel(theme),
        ],
        if (widget.initialAction == null) const SizedBox(height: 18),
        if (widget.initialAction != 'create') ...[
          if (_receiverInvite == null) _receiverPanel(theme) else _receiverFilesPanel(theme),
        ],
        if (_busy) const Padding(
          padding: EdgeInsets.only(top: 14),
          child: LinearProgressIndicator(),
        ),
      ],
    );
  }

  Widget _statusCard(ThemeData theme) => Card(
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(children: [
            Icon(Icons.info_outline_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(_status!)),
          ]),
        ),
      );

  Widget _senderPanel(ThemeData theme) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.upload_rounded),
              SizedBox(width: 8),
              Text('Send', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 8),
            Text(Platform.isAndroid
                ? 'Choose files or a folder. Plazma S will share them over your current Wi-Fi and show a room QR code.'
                : 'Choose files or a folder. Plazma S will share them over your current Wi-Fi or wired LAN and show a room QR code.'),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickFiles,
                icon: const Icon(Icons.add),
                label: const Text('Add files'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickFolder,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Add folder'),
              ),
              if (_files.isNotEmpty)
                TextButton(
                  onPressed: _busy ? null : () => setState(() {
                    _files.clear();
                    _relativePaths.clear();
                    _status = 'Selection cleared';
                  }),
                  child: const Text('Clear'),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : _deleteSelectedFiles,
                  icon: const Icon(Icons.delete_outline_rounded, size: 17),
                  label: const Text('Delete selected'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
            ]),
            if (_files.isNotEmpty) ...[
              const SizedBox(height: 10),
              TextField(
                decoration: const InputDecoration(hintText: 'Search selected files', prefixIcon: Icon(Icons.search_rounded), isDense: true, border: OutlineInputBorder()),
                onChanged: (value) => setState(() => _fileSearchQuery = value),
              ),
              Text('${_visibleFileIndexes.length} shown · ${_files.length} selected · ${_formatBytes(_files.fold<int>(0, (sum, file) => sum + file.lengthSync()))}',
                  style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ..._visibleFileIndexes.take(5).map((index) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: Text(_relativePaths[index], maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_formatBytes(_files[index].lengthSync())),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Manage file',
                      onSelected: (action) => _manageStagedFile(index, action),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'copy', child: Text('Copy to folder')),
                        PopupMenuItem(value: 'move', child: Text('Move to folder')),
                        PopupMenuDivider(),
                        PopupMenuItem(value: 'delete', child: Text('Delete permanently')),
                        PopupMenuItem(value: 'remove', child: Text('Remove from selection')),
                      ],
                    ),
                  )),
              if (_visibleFileIndexes.length > 5) Text('And ${_visibleFileIndexes.length - 5} more…'),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy || _files.isEmpty ? null : _startSharing,
                icon: const Icon(Icons.qr_code_2_rounded),
                label: Text(_service.isSharing ? 'Add to room' : 'Start sharing'),
              ),
            ),
          ]),
        ),
      );

  Widget _senderQrPanel(ThemeData theme) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(children: [
            Text('Room ${_invite!.roomId}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
            const SizedBox(height: 4),
            const Text('Scan this code on the receiving device', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: QrImageView(data: _invite!.toQrValue(), size: 230),
            ),
            const SizedBox(height: 12),
            Text(
              _invite!.ssid.isEmpty
                  ? 'Network address: ${_invite!.host}:${_invite!.port}'
                  : 'Wi-Fi: ${_invite!.ssid}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: _invite!.roomId)),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy room code'),
            ),
            PopupMenuButton<String>(
              tooltip: 'More room actions',
              onSelected: (value) {
                if (value == 'link') {
                  Clipboard.setData(ClipboardData(text: _invite!.toQrValue()));
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'link', child: Text('Copy connection link')),
              ],
            ),

            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Text(
                'Connected devices',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              )),
              Text('${_service.joinedDeviceCount}/7',
                  style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 6),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.computer_rounded)),
              title: const Text('This device · Host'),
              subtitle: Text(Platform.operatingSystem),
              trailing: const Icon(Icons.check_circle, color: Colors.green),
            ),
            if (_service.roomMembers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Waiting for up to seven people to join this room.'),
              )
            else
              ..._service.roomMembers.map((member) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  child: Icon(member.platform == 'android'
                      ? Icons.phone_android_rounded
                      : Icons.computer_rounded),
                ),
                title: Text(member.deviceName),
                subtitle: Text(member.platform),
                trailing: Icon(
                  member.completed ? Icons.check_circle : Icons.wifi,
                  color: member.completed ? Colors.green : theme.colorScheme.primary,
                ),
              )),
            const SizedBox(height: 4),
            const Text('The room stays open until you stop it. Each recipient transfers independently.', textAlign: TextAlign.center),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _busy ? null : _stopSharing,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Stop sharing'),
            ),
          ]),
        ),
      );

  Widget _receiverPanel(ThemeData theme) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.download_rounded),
              SizedBox(width: 8),
              Text('Receive', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 8),
            Text(Platform.isAndroid
                ? 'Tap Receive and scan the sender QR code. If it is a PC share, connect to the same Wi-Fi first.'
                : 'Tap Receive, then paste the connection code from the sender. Both PCs must be on the same Wi-Fi or wired LAN. If the sender is an Android phone, connect this PC to the same Wi-Fi network.'),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _joinSender,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: Text(Platform.isAndroid ? 'Scan to receive' : 'Enter connection code'),
              ),
            ),
          ]),
        ),
      );

  Widget _receiverFilesPanel(ThemeData theme) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.wifi_rounded, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(child: Text('${_availableFiles.length} file(s) ready', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
              TextButton(onPressed: _downloading ? null : _disconnectReceiver, child: const Text('Disconnect')),
            ]),
            const SizedBox(height: 8),
            ..._availableFiles.map((item) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: Text(item.relativePath, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_formatBytes(item.size)),
                )),
            if (_receivedAppPackages.isNotEmpty) ...[
              const Divider(),
              const Text('Install received apps', style: TextStyle(fontWeight: FontWeight.w800)),
              ..._receivedAppPackages.map((packageName) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.android_rounded),
                    title: Text(packageName),
                    trailing: FilledButton.tonal(
                      onPressed: _downloading ? null : () => _installReceivedApp(packageName),
                      child: const Text('Install'),
                    ),
                  )),
            ],
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_open_rounded),
              title: Text(_destination ?? 'Choose save location'),
              subtitle: const Text('Files are saved on this phone'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _downloading ? null : _chooseDestination,
            ),
            if (_downloading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 6),
              Text(_currentFile == null ? 'Receiving…' : 'Receiving $_currentFile'),
              Text('${(_progress * 100).toStringAsFixed(0)}%'),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _downloading || _availableFiles.isEmpty ? null : _downloadFiles,
                icon: const Icon(Icons.download_rounded),
                label: Text(_downloading ? 'Receiving files…' : 'Receive all files'),
              ),
            ),
          ]),
        ),
      );
}
