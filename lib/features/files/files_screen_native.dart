// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../network/android_wifi_session_service.dart';
import '../../transfers/transfer_history.dart';
import '../../transfers/transfer_mode.dart';
import '../../transfers/xender_local_transfer_service.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({this.transferMode, super.key});

  final TransferMode? transferMode;

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

  @override
  void dispose() {
    unawaited(_service.stopSharing());
    unawaited(_service.disconnect());
    super.dispose();
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
    if (!Platform.isAndroid) {
      _message('Xender-style hotspot sharing is currently available on Android phones.');
      return;
    }
    if (_files.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _status = 'Starting secure local Wi-Fi…';
    });
    try {
      final invite = await _service.startSharing(
        files: List<File>.from(_files),
        relativePaths: List<String>.from(_relativePaths),
      );
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _status = 'Waiting for the other phone to scan this QR code';
      });
    } catch (error) {
      _message('Could not start sharing: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<PlazmaConnectionInvite?> _scanInvite() async {
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
                const Text('Scan the QR code shown on the sending phone.'),
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

  Future<void> _joinSender() async {
    if (!Platform.isAndroid) {
      _message('Xender-style Wi-Fi joining is currently available on Android phones.');
      return;
    }
    if (_busy) return;
    final invite = await _scanInvite();
    if (invite == null || !mounted) return;
    setState(() {
      _busy = true;
      _status = 'Connecting to sender Wi-Fi…';
    });
    try {
      final files = await _service.joinAndList(invite);
      if (!mounted) return;
      setState(() {
        _receiverInvite = invite;
        _availableFiles = files;
        _status = files.isEmpty ? 'Connected. The sender has no files available.' : 'Connected — ${files.length} file(s) available';
      });
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
      });
      _message('Transfer complete. Files saved to $destination');
    } catch (error) {
      _message('Transfer failed: $error');
      if (mounted) setState(() => _status = 'Transfer failed');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _stopSharing() async {
    await _service.stopSharing();
    if (!mounted) return;
    setState(() {
      _invite = null;
      _status = 'Sharing stopped';
    });
  }

  Future<void> _disconnectReceiver() async {
    await _service.disconnect();
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
        Text('Connect phones directly. No mobile data or internet required.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 18),
        if (_status != null) _statusCard(theme),
        if (_invite == null) _senderPanel(theme) else _senderQrPanel(theme),
        const SizedBox(height: 18),
        if (_receiverInvite == null) _receiverPanel(theme) else _receiverFilesPanel(theme),
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
            const Text('Choose files or an entire folder. Plazma S will create a private Wi-Fi hotspot and show a QR code for the receiving phone.'),
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
            ]),
            if (_files.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('${_files.length} selected · ${_formatBytes(_files.fold<int>(0, (sum, file) => sum + file.lengthSync()))}',
                  style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ...List.generate(_files.length > 5 ? 5 : _files.length, (index) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: Text(_relativePaths[index], maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_formatBytes(_files[index].lengthSync())),
                    trailing: IconButton(
                      tooltip: 'Remove',
                      onPressed: _busy ? null : () => setState(() {
                        _files.removeAt(index);
                        _relativePaths.removeAt(index);
                      }),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  )),
              if (_files.length > 5) Text('And ${_files.length - 5} more…'),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy || _files.isEmpty ? null : _startSharing,
                icon: const Icon(Icons.qr_code_2_rounded),
                label: const Text('Start sharing'),
              ),
            ),
          ]),
        ),
      );

  Widget _senderQrPanel(ThemeData theme) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(children: [
            const Text('Scan this code on the receiving phone', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: QrImageView(data: _invite!.toQrValue(), size: 230),
            ),
            const SizedBox(height: 12),
            Text('Wi-Fi: ${_invite!.ssid}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Keep this screen open while the other phone connects and receives files.', textAlign: TextAlign.center),
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
            const Text('Tap Receive and scan the QR code on the sender phone. Android will ask you to approve joining its local Wi-Fi network.'),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _joinSender,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Scan to receive'),
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
