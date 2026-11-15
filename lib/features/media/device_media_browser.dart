import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

enum MediaKind { images, videos, music }

class DeviceMediaBrowser extends StatefulWidget {
  const DeviceMediaBrowser({
    required this.kind,
    required this.onSelect,
    super.key,
  });

  final MediaKind kind;
  final ValueChanged<File> onSelect;

  @override
  State<DeviceMediaBrowser> createState() => _DeviceMediaBrowserState();
}

class _DeviceMediaBrowserState extends State<DeviceMediaBrowser> {
  List<AssetEntity> _assets = [];
  bool _loading = false;
  bool _loaded = false;
  String? _message;

  RequestType get _requestType => switch (widget.kind) {
        MediaKind.images => RequestType.image,
        MediaKind.videos => RequestType.video,
        MediaKind.music => RequestType.audio,
      };

  String get _label => switch (widget.kind) {
        MediaKind.images => 'images',
        MediaKind.videos => 'videos',
        MediaKind.music => 'music',
      };

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final permission = await PhotoManager.requestPermissionExtend(
        requestOption: PermissionRequestOption(
          androidPermission: AndroidPermission(type: _requestType, mediaLocation: false),
        ),
      );
      if (!permission.hasAccess) {
        if (mounted) {
          setState(() {
            _message = 'Allow Plazma S to access your $_label in Android settings.';
            _loaded = true;
          });
        }
        return;
      }
      final albums = await PhotoManager.getAssetPathList(
        type: _requestType,
        onlyAll: true,
      );
      if (albums.isEmpty) {
        if (mounted) {
          setState(() {
            _assets = [];
            _loaded = true;
            _message = 'No $_label found on this device.';
          });
        }
        return;
      }
      final assets = await albums.first.getAssetListRange(start: 0, end: 160);
      if (!mounted) return;
      setState(() {
        _assets = assets;
        _loaded = true;
        _message = assets.isEmpty ? 'No $_label found on this device.' : null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loaded = true;
          _message = 'Could not read device $_label: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(AssetEntity asset) async {
    try {
      final file = await asset.file;
      if (file == null || !await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This media item is not available.')),
          );
        }
        return;
      }
      widget.onSelect(file);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open media: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _loading ? null : _load,
            icon: _loading
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.storage_rounded),
            label: Text(_loading ? 'Reading device storage…' : 'Browse phone $_label'),
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 8),
          Text(_message!, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
          if (_message!.startsWith('Allow'))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: PhotoManager.openSetting,
                icon: const Icon(Icons.settings_outlined, size: 17),
                label: const Text('Open app settings'),
              ),
            ),
        ],
        if (_loaded && _assets.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'On this device · ${_assets.length} recent item(s)',
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (widget.kind == MediaKind.music)
            Card(
              child: Column(
                children: _assets.map((asset) => ListTile(
                  dense: true,
                  leading: const CircleAvatar(child: Icon(Icons.music_note_rounded)),
                  title: Text(asset.title ?? 'Audio file', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(asset.createDateTime.toLocal().toString().split('.').first),
                  trailing: const Icon(Icons.add_circle_outline_rounded),
                  onTap: () => _select(asset),
                )).toList(),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _assets.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 7,
                mainAxisSpacing: 7,
              ),
              itemBuilder: (context, index) {
                final asset = _assets[index];
                return InkWell(
                  onTap: () => _select(asset),
                  borderRadius: BorderRadius.circular(10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        FutureBuilder<Uint8List?>(
                          future: asset.thumbnailDataWithSize(const ThumbnailSize(300, 300)),
                          builder: (context, snapshot) {
                            final bytes = snapshot.data;
                            if (bytes == null) {
                              return const ColoredBox(
                                color: Color(0x22000000),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              );
                            }
                            return Image.memory(bytes, fit: BoxFit.cover);
                          },
                        ),
                        if (widget.kind == MediaKind.videos)
                          const Center(
                            child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 32),
                          ),
                        Positioned(
                          right: 5,
                          bottom: 5,
                          child: Icon(Icons.add_circle_rounded, color: Colors.white.withValues(alpha: .95)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ],
    );
  }
}
