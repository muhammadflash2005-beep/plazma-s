// Flutter 3.50 currently reports the Material library import as deprecated.
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:photo_manager/photo_manager.dart';

import 'permanent_delete_confirmation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MediaKind { images, videos, music }

class DeviceMediaBrowser extends StatefulWidget {
  const DeviceMediaBrowser({
    required this.kind,
    required this.onSelect,
    this.enabled = true,
    this.selectedPaths = const <String>{},
    this.parentScrollController,
    super.key,
  });

  final MediaKind kind;
  final ValueChanged<File> onSelect;
  final bool enabled;
  final Set<String> selectedPaths;
  final ScrollController? parentScrollController;

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
  final Map<String, Future<Map<String, String?>>> _musicMetadataFutures = {};
  final Map<String, String> _assetPaths = {};
  int _totalCount = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _loaded = false;
  bool _hasMore = false;
  bool _needsRefresh = false;
  String? _message;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.parentScrollController?.addListener(_handleParentScroll);
    if (widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.enabled) _load();
      });
    }
  }

  @override
  void didUpdateWidget(covariant DeviceMediaBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parentScrollController != widget.parentScrollController) {
      oldWidget.parentScrollController?.removeListener(_handleParentScroll);
      widget.parentScrollController?.addListener(_handleParentScroll);
    }
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
    widget.parentScrollController?.removeListener(_handleParentScroll);
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
      // Preserve the loaded page depth when refreshing after a tab switch or
      // app resume instead of silently collapsing a 96-item list to 48.
      final previouslyLoaded = _assets.length;
      final targetLength = previouslyLoaded > _pageSize ? previouslyLoaded : _pageSize;
      final end = count < targetLength ? count : targetLength;
      final firstPage = await album.getAssetListRange(start: 0, end: end);
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

  void _handleParentScroll() {
    final controller = widget.parentScrollController;
    if (!widget.enabled || _loading || _loadingMore || !_hasMore ||
        controller == null || !controller.hasClients) {
      return;
    }
    if (controller.position.extentAfter < 420) {
      unawaited(_loadMore());
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

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }

  Future<Map<String, String?>> _musicMetadata(AssetEntity asset) {
    return _musicMetadataFutures.putIfAbsent(asset.id, () async {
      try {
        final file = await asset.file;
        if (file == null || !await file.exists()) return const {};
        final metadata = readMetadata(file, getImage: false);
        return {
          'title': metadata.title,
          'artist': metadata.artist,
          'duration': metadata.duration?.inSeconds.toString(),
        };
      } catch (_) {
        return const {};
      }
    });
  }

  Future<Uint8List?> _thumbnail(AssetEntity asset) {
    return _thumbnailFutures.putIfAbsent(
      asset.id,
      () => asset.thumbnailDataWithSize(const ThumbnailSize(180, 180)),
    );
  }

  List<AssetEntity> get _filteredAssets {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _assets;
    return _assets.where((asset) =>
      (asset.title ?? '').toLowerCase().contains(query)).toList();
  }

  Future<void> _selectAllVisible() async {
    for (final asset in _filteredAssets) {
      try {
        final file = await asset.file;
        if (file == null || !await file.exists()) continue;
        _assetPaths[asset.id] = file.path;
        if (!widget.selectedPaths.contains(file.path)) widget.onSelect(file);
      } catch (_) {}
    }
  }

  Future<void> _clearVisibleSelection() async {
    // Resolve paths for the visible page as well as assets selected before a
    // refresh. The in-memory cache can be empty after the browser reloads.
    for (final asset in _filteredAssets) {
      var path = _assetPaths[asset.id];
      if (path == null) {
        try {
          final file = await asset.file;
          if (file != null) {
            path = file.path;
            _assetPaths[asset.id] = path;
          }
        } catch (_) {
          continue;
        }
      }
      if (path != null && widget.selectedPaths.contains(path)) {
        widget.onSelect(File(path));
      }
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
      _assetPaths[asset.id] = file.path;
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
          TextField(
            decoration: InputDecoration(
              hintText: 'Search device $_label',
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          Row(children: [
            TextButton(onPressed: _selectAllVisible, child: const Text('Select all')),
            TextButton(onPressed: _clearVisibleSelection, child: const Text('Clear selection')),
            if (widget.selectedPaths.isNotEmpty)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: _deleteSelectedVisible,
                child: const Text('Delete'),
              ),
            const Spacer(),
            Text('${widget.selectedPaths.length} selected',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
          ]),

          Text(
            _searchQuery.trim().isEmpty
                ? 'Showing ${_assets.length} of $_totalCount'
                : 'Showing ${_filteredAssets.length} matching items · ${_assets.length} loaded of $_totalCount',
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
                  for (final asset in _filteredAssets)
                    FutureBuilder<Map<String, String?>>(
                      future: _musicMetadata(asset),
                      builder: (context, snapshot) {
                        final details = snapshot.data ?? const <String, String?>{};
                        final title = (details['title']?.trim().isNotEmpty ?? false)
                            ? details['title']!
                            : (asset.title?.trim().isNotEmpty ?? false)
                                ? asset.title!
                                : (asset.relativePath ?? 'Audio file').split('/').last;
                        final artist = details['artist']?.trim();
                        final duration = int.tryParse(details['duration'] ?? '') ?? asset.duration;
                        final subtitle = [
                          artist?.isNotEmpty == true ? artist! : 'Unknown artist',
                          duration > 0 ? _formatDuration(duration) : 'Duration unavailable',
                        ].join(' · ');
                        final selected = widget.selectedPaths.contains(_assetPaths[asset.id]);
                        return ListTile(
                          dense: true,
                          leading: const CircleAvatar(child: Icon(Icons.music_note_rounded)),
                          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Icon(
                            selected ? Icons.check_circle : Icons.circle_outlined,
                            color: selected ? colors.primary : colors.onSurfaceVariant,
                          ),
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
              itemCount: _filteredAssets.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 7,
                mainAxisSpacing: 7,
              ),
              itemBuilder: (context, index) {
                final asset = _filteredAssets[index];
                final selected = widget.selectedPaths.contains(_assetPaths[asset.id]);
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
                            if (snapshot.hasError ||
                                (snapshot.connectionState == ConnectionState.done && bytes == null)) {
                              return ColoredBox(
                                color: const Color(0x22000000),
                                child: Center(
                                  child: IconButton(
                                    tooltip: 'Retry thumbnail',
                                    onPressed: () {
                                      _thumbnailFutures.remove(asset.id);
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.refresh_rounded, size: 22),
                                  ),
                                ),
                              );
                            }
                            if (bytes == null) {
                              return const ColoredBox(
                                color: Color(0x22000000),
                                child: Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
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
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: .28),
                                border: Border.all(color: colors.primary, width: 3),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(Icons.check_circle, color: colors.primary, size: 25),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
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
