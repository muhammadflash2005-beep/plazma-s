// ignore_for_file: deprecated_member_use

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  final List<_PickedItem> _items = [];
  bool _busy = false;

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
            name: file.name,
            path: path,
            bytes: file.lengthSync(),
            isFolder: false,
          ));
        }
      });
    } catch (error) {
      _showError('Could not open the file picker: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFolder() async {
    setState(() => _busy = true);
    try {
      final path = await FilePicker.getDirectoryPath();
      if (!mounted || path == null) return;
      final parts = path.split(RegExp(r'[/\\]')).where((part) => part.isNotEmpty).toList();
      final name = parts.isEmpty ? path : parts.last;
      setState(() {
        if (!_items.any((item) => item.path == path)) {
          _items.add(_PickedItem(name: name, path: path, bytes: null, isFolder: true));
        }
      });
    } catch (error) {
      _showError('Could not open the folder picker: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatBytes(int? bytes) {
    if (bytes == null) return 'Folder · contents will be scanned when transfer support is connected';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalBytes = _items.fold<int>(0, (sum, item) => sum + (item.bytes ?? 0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Files', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text('Choose files and folders from this device to prepare them for local sharing.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 20),
        Wrap(spacing: 12, runSpacing: 12, children: [
          FilledButton.icon(
            onPressed: _busy ? null : _pickFiles,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Choose files'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Choose folder'),
          ),
        ]),
        if (_busy) const Padding(
          padding: EdgeInsets.only(top: 18),
          child: LinearProgressIndicator(),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.folder_copy_outlined, size: 28),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_items.length} selected items', style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text('Known file size: ${_formatBytes(totalBytes)}',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
              ])),
              if (_items.isNotEmpty)
                TextButton(onPressed: () => setState(_items.clear), child: const Text('Clear')),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        if (_items.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 18),
              child: Center(child: Column(children: [
                Icon(Icons.snippet_folder_outlined, size: 46, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                const Text('No files selected', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text('Your selected files and folders will appear here.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
              ])),
            ),
          )
        else
          ..._items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(item.isFolder ? Icons.folder_rounded : _iconFor(item.name),
                      color: theme.colorScheme.primary),
                ),
                title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_formatBytes(item.bytes), maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: 'Remove',
                  onPressed: () => setState(() => _items.removeAt(index)),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            );
          }),
        const SizedBox(height: 18),
        Card(
          color: theme.colorScheme.surfaceContainerHighest,
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline_rounded),
              SizedBox(width: 10),
              Expanded(child: Text(
                'File selection is ready. Sending, chunked progress, resume and integrity checks will be connected to the LAN transfer engine next.',
                style: TextStyle(fontSize: 12, height: 1.45),
              )),
            ]),
          ),
        ),
      ],
    );
  }

  IconData _iconFor(String name) {
    final extension = name.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].contains(extension)) return Icons.image_outlined;
    if (['mp4', 'mov', 'mkv', 'avi'].contains(extension)) return Icons.video_file_outlined;
    if (['mp3', 'wav', 'aac', 'flac'].contains(extension)) return Icons.audio_file_outlined;
    if (['pdf', 'doc', 'docx', 'txt', 'xls', 'xlsx', 'ppt', 'pptx'].contains(extension)) return Icons.description_outlined;
    if (['zip', 'rar', '7z', 'tar'].contains(extension)) return Icons.archive_outlined;
    return Icons.insert_drive_file_outlined;
  }
}

class _PickedItem {
  const _PickedItem({
    required this.name,
    required this.path,
    required this.bytes,
    required this.isFolder,
  });

  final String name;
  final String path;
  final int? bytes;
  final bool isFolder;
}
