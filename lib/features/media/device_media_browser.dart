// Flutter 3.50 currently reports the Material library import as deprecated.
// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MediaKind { images, videos, music }

class DeviceMediaBrowser extends StatefulWidget {
  const DeviceMediaBrowser({
    required this.kind,
    required this.onSelect,
    this.isSelected,
    this.enabled = true;
    super.key,
  });

  final MediaKind kind;
  final ValueChanged<File> onSelect;
  final bool Function(File file)? isSelected;
  final bool enabled;

  @override
  State<DeviceMediaBrowser> createState() => _DeviceMediaBrowserState();
}

class _DeviceMediaBrowserState extends State<DeviceMediaBrowser>
    with WidgetsBindingObserver {
  static const String _permissionRequestedKey = 'plazma_media_permission_requested';
  static const int _pageSize = 48;
  static Future<PermissionState>? _permissionCheck;

  static Future<PermissionState> _ensureMediaPermission() {
    return _permissionCheck ??= _readOrRequestMediaPermission().whenComplete(() {
      _permissionCheck = null;
    });
  }

  static Future<PermissionState> _readOrRequestMediaPermission() async {
    final prefs = await SharedPreferences.getInstance();
    const requestOption = PermissionRequestOption(
      androidPermission: AndroidPermission(type: RequestType.all, mediaLocation: false),
    );
    final current = await PhotoManager.getPermissionState(requestOption: requestOption);
    if (current.hasAccess) {
      await prefs.setBool(_permissionRequestedKey, true);
      return current;
    }
    if (prefs.getBool(_permissionRequestedKey) == true) return current;
    await prefs.setBool(_permissionRequestedKey, true);
    return PhotoManager.requestPermissionExtend(requestOption: requestOption);
  }

  AssetPathEntity? _album;
  List<AssetEntity> _assets = [];
  final Map<String, Future<Uint8List?>> _thumbnailFutures = {};
  int _totalCount = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _loaded = false;
  bool _hasMore = false;
  bool _needsRefresh = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.enabled) _load();
      });
    }
  }

  @override
  void didUpdateWidget(covariant DeviceMediaBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.enabled && widget.enabled && (!_loaded || _needsRefresh)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.enabled) _load();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _needsRefresh = true;
    } else if (state == AppLifecycleState.resumed && widget.enabled && _needsRefresh) {
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

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
    if (!widget.enabled || _loading) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final permission = await _ensureMediaPermission();
      if (!permission.hasAccess) {
        if (mounted) {
          setState(() {
            _message = 'Allow Plazma S to access images, videos and music in Android settings.';
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
            _album = null;
            _assets = [];
            _totalCount = 0;
            _loaded = true;
            _hasMore = false;
            _message = 'No $_label found on this device.';
          });
        }
        return;
      }
      final album = albums.first;
      final count = await album.assetCountAsync;
      final firstPage = await album.getAssetListRange(
        start: 0,
        end: count < _pageSize ? count : _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _album = album;
        _assets = firstPage;
        _totalCount = count;
        _hasMore = firstPage.length < count;
        _thumbnailFutures.clear();
        _loaded = true;
        _needsRefresh = false;
        _message = firstPage.isEmpty ? 'No $_label found on this device.' : null;
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

  Future<void> _loadMore() async {
    final album = _album;
    if (!widget.enabled || album == null || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final start = _assets.length;
      final end = (start + _pageSize).clamp(0, _totalCount).toInt();
      final next = await album.getAssetListRange(start: start, end: end);
      if (!mounted) return;
      setState(() {
        _assets.addAll(next);
        _hasMore = _assets.length < _totalCount;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load more $_label: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<Uint8List?> _thumbnail(AssetEntity asset) {
    return _thumbnailFutures.putIfAbsent(
      asset.id,
      () => asset.thumbnailDataWithSize(const ThumbnailSize(180, 180)),
    );
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
    if (!widget.enabled && !_loaded) {
      return Text(
        'Open this tab to load device $_label.',
        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(
              _loading ? 'Loading device $_label…' : 'On this device · $_label',
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Refresh device media',
            visualDensity: VisualDensity.compact,
            onPressed: _loading || !widget.enabled ? null : _load,
            icon: _loading
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ]),
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
            'Showing ${_assets.length} of $_totalCount',
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (widget.kind == MediaKind.music)
            Card(
              child: Column(
                children: [
                  for (final asset in _assets)
                    FutureBuilder<File?>(
                      future: asset.file,
                      builder: (context, snapshot) {
                        final selected = snapshot.data != null &&
                            (widget.isSelected?.call(snapshot.data!) ?? false);
                        return ListTile(
                          dense: true,
                          leading: const CircleAvatar(child: Icon(Icons.music_note_rounded)),
                          title: Text(asset.title ?? 'Audio file',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(asset.createDateTime.toLocal().toString().split('.').first),
                          trailing: selected
                              ? Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary)
                              : const Icon(Icons.circle_outlined),
                          onTap: () => _select(asset),
                        );
                      },
                    ),
                ],
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
                return FutureBuilder<File?>(
                  future: asset.file,
                  builder: (context, fileSnapshot) {
                    final selected = fileSnapshot.data != null &&
                        (widget.isSelected?.call(fileSnapshot.data!) ?? false);
                    return InkWell(
                      onTap: () => _select(asset),
                      borderRadius: BorderRadius.circular(10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            FutureBuilder<Uint8List?>(
                              future: _thumbnail(asset),
                              builder: (context, snapshot) {
                                final bytes = snapshot.data;
                                if (bytes == null) {
                                  return const ColoredBox(
                                    color: Color(0x22000000),
                                    child: Center(child: Icon(Icons.photo_outlined, size: 22)),
                                  );
                                }
                                return Image.memory(bytes, fit: BoxFit.cover);
                              },
                            ),
                            if (widget.kind == MediaKind.videos)
                              const Center(
                                child: Icon(Icons.play_circle_fill_rounded,
                                    color: Colors.white, size: 32),
                              ),
                            if (selected)
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  padding: const EdgeInsets.all(3),
                                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 17),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          if (_hasMore)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: OutlinedButton.icon(
                  onPressed: _loadingMore ? null : _loadMore,
                  icon: _loadingMore
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more_rounded),
                  label: Text(_loadingMore ? 'Loading…' : 'Load more'),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
