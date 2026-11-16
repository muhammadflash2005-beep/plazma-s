import 'dart:io' as io;
import 'dart:ui' as ui;
// Flutter stable 3.50 marks Material's umbrella library and legacy RadioListTile
// selection parameters deprecated while transitioning to the new Material API.
// Keep the UI compatible with the current stable SDK during that migration.
// ignore_for_file: deprecated_member_use


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_device_apps/flutter_device_apps.dart';

import 'updates/app_update_card.dart';

import 'features/apps/apps_screen.dart';
import 'features/files/files_screen.dart';
import 'features/images/images_screen.dart';
import 'features/media/device_media_browser.dart';
import 'features/music/music_screen.dart';
import 'features/videos/videos_screen.dart';
import 'transfers/transfer_overlay_controller.dart';
import 'transfers/xender_local_transfer_service.dart';
import 'features/history/transfer_history_screen.dart';

void main() => runApp(const PlazmaApp());

enum PlazmaTheme { light, dark, ocean, sunset, forest, purple, crimson, midnight, obsidian }

extension PlazmaThemeInfo on PlazmaTheme {
  String get label => switch (this) {
        PlazmaTheme.light => 'Plazma Light',
        PlazmaTheme.dark => 'Plazma Dark',
        PlazmaTheme.ocean => 'Ocean',
        PlazmaTheme.sunset => 'Sunset',
        PlazmaTheme.forest => 'Forest',
        PlazmaTheme.purple => 'Purple',
        PlazmaTheme.crimson => 'Crimson',
        PlazmaTheme.midnight => 'Midnight',
        PlazmaTheme.obsidian => 'Obsidian',
      };

  bool get isDark => this == PlazmaTheme.dark || this == PlazmaTheme.midnight || this == PlazmaTheme.obsidian;

  String get description => switch (this) {
        PlazmaTheme.light => 'Clean white surfaces and electric blue',
        PlazmaTheme.dark => 'Deep navy with bright blue accents',
        PlazmaTheme.ocean => 'Cool blue with teal accents',
        PlazmaTheme.sunset => 'Warm orange with pink accents',
        PlazmaTheme.forest => 'Fresh green with golden accents',
        PlazmaTheme.purple => 'Royal violet with lavender accents',
        PlazmaTheme.crimson => 'Bold red with soft rose accents',
        PlazmaTheme.midnight => 'Near-black surfaces with violet-blue accents',
        PlazmaTheme.obsidian => 'Deep graphite with vivid emerald accents',
      };

  Color get background => switch (this) {
        PlazmaTheme.light => const Color(0xFFFFFFFF),
        PlazmaTheme.dark => const Color(0xFF0F172A),
        PlazmaTheme.ocean => const Color(0xFFF0F9FF),
        PlazmaTheme.sunset => const Color(0xFFFFF7ED),
        PlazmaTheme.forest => const Color(0xFFF0FDF4),
        PlazmaTheme.purple => const Color(0xFFFAF5FF),
        PlazmaTheme.crimson => const Color(0xFFFFF1F2),
        PlazmaTheme.midnight => const Color(0xFF09090F),
        PlazmaTheme.obsidian => const Color(0xFF07130F),
      };

  Color get surface => switch (this) {
        PlazmaTheme.light => const Color(0xFFF8FAFC),
        PlazmaTheme.dark => const Color(0xFF1E293B),
        PlazmaTheme.ocean => const Color(0xFFFFFFFF),
        PlazmaTheme.sunset => const Color(0xFFFFFFFF),
        PlazmaTheme.forest => const Color(0xFFFFFFFF),
        PlazmaTheme.purple => const Color(0xFFFFFFFF),
        PlazmaTheme.crimson => const Color(0xFFFFFFFF),
        PlazmaTheme.midnight => const Color(0xFF181824),
        PlazmaTheme.obsidian => const Color(0xFF10231B),
      };

  Color get primary => switch (this) {
        PlazmaTheme.light => const Color(0xFF2563EB),
        PlazmaTheme.dark => const Color(0xFF3B82F6),
        PlazmaTheme.ocean => const Color(0xFF0284C7),
        PlazmaTheme.sunset => const Color(0xFFEA580C),
        PlazmaTheme.forest => const Color(0xFF16A34A),
        PlazmaTheme.purple => const Color(0xFF7C3AED),
        PlazmaTheme.crimson => const Color(0xFFE11D48),
        PlazmaTheme.midnight => const Color(0xFF8B5CF6),
        PlazmaTheme.obsidian => const Color(0xFF10B981),
      };

  Color get accent => switch (this) {
        PlazmaTheme.light => const Color(0xFFF59E0B),
        PlazmaTheme.dark => const Color(0xFFFBBF24),
        PlazmaTheme.ocean => const Color(0xFF14B8A6),
        PlazmaTheme.sunset => const Color(0xFFDB2777),
        PlazmaTheme.forest => const Color(0xFFCA8A04),
        PlazmaTheme.purple => const Color(0xFFC084FC),
        PlazmaTheme.crimson => const Color(0xFFFB7185),
        PlazmaTheme.midnight => const Color(0xFF22D3EE),
        PlazmaTheme.obsidian => const Color(0xFFA3E635),
      };

  Color get foreground => switch (this) {
        PlazmaTheme.dark || PlazmaTheme.midnight || PlazmaTheme.obsidian => const Color(0xFFF1F5F9),
        _ => const Color(0xFF0F172A),
      };

  Color get muted => switch (this) {
        PlazmaTheme.dark || PlazmaTheme.midnight || PlazmaTheme.obsidian => const Color(0xFF94A3B8),
        _ => const Color(0xFF64748B),
      };

  ThemeData toThemeData() {
    final isDark = this == PlazmaTheme.dark || this == PlazmaTheme.midnight || this == PlazmaTheme.obsidian;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: primary,
      secondary: accent,
      surface: surface,
      onSurface: foreground,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: background,
      colorScheme: scheme,
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: foreground.withValues(alpha: 0.08)),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: foreground,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: 0.13),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: foreground, fontWeight: FontWeight.w600, fontSize: 10.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class ThemeController extends ChangeNotifier {
  ThemeController();

  PlazmaTheme selected = PlazmaTheme.light;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('plazma_theme');
    selected = PlazmaTheme.values.firstWhere(
      (theme) => theme.name == saved,
      orElse: () => PlazmaTheme.light,
    );
    notifyListeners();
  }

  Future<void> setTheme(PlazmaTheme theme) async {
    selected = theme;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('plazma_theme', theme.name);
  }
}

class PlazmaApp extends StatefulWidget {
  const PlazmaApp({super.key});

  @override
  State<PlazmaApp> createState() => _PlazmaAppState();
}

class _PlazmaAppState extends State<PlazmaApp> {
  late final ThemeController _themes;

  @override
  void initState() {
    super.initState();
    _themes = ThemeController()..load();
  }

  @override
  void dispose() {
    _themes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _themes,
        builder: (context, _) => MaterialApp(
          title: 'Plazma S',
          debugShowCheckedModeBanner: false,
          theme: _themes.selected.toThemeData(),
          home: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: _themes.selected.background,
              statusBarIconBrightness: _themes.selected.isDark ? Brightness.light : Brightness.dark,
              systemNavigationBarColor: _themes.selected.surface,
              systemNavigationBarIconBrightness: _themes.selected.isDark ? Brightness.light : Brightness.dark,
            ),
            child: HomeScreen(themes: _themes),
          ),
        ),
      );
}


class _ElectricTransferProgress extends StatefulWidget {
  const _ElectricTransferProgress({required this.value, this.height = 8});
  final double value;
  final double height;

  @override
  State<_ElectricTransferProgress> createState() => _ElectricTransferProgressState();
}

class _ElectricTransferProgressState extends State<_ElectricTransferProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1250),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.value.clamp(0.0, 1.0).toDouble();
    final colors = Theme.of(context).colorScheme;
    final primary = colors.primary;
    final secondary = colors.secondary;
    final track = colors.primary.withValues(alpha: 0.13);
    final boltGlow = Color.lerp(primary, colors.onPrimary, 0.62)!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.height),
      child: SizedBox(
        height: widget.height,
        child: LayoutBuilder(builder: (context, constraints) {
          final fillWidth = constraints.maxWidth * progress;
          return Stack(children: [
            Positioned.fill(child: ColoredBox(color: track)),
            if (fillWidth > 0)
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => CustomPaint(
                  size: Size(fillWidth, widget.height),
                  painter: _ElectricBoltPainter(
                    phase: _pulse.value,
                    primary: primary,
                    secondary: secondary,
                    boltGlow: boltGlow,
                  ),
                ),
              ),
          ]);
        }),
      ),
    );
  }
}

class _ElectricBoltPainter extends CustomPainter {
  const _ElectricBoltPainter({
    required this.phase,
    required this.primary,
    required this.secondary,
    required this.boltGlow,
  });
  final double phase;
  final Color primary;
  final Color secondary;
  final Color boltGlow;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final glow = Paint()
      ..color = primary.withValues(alpha: 0.82)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(size.height)), glow);
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft, end: Alignment.centerRight,
        colors: [Color.lerp(primary, Colors.white, 0.18)!, primary, secondary],
      ).createShader(rect);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(size.height)), fill);

    final path = ui.Path();
    final mid = size.height / 2;
    path.moveTo(0, mid);
    final segments = (size.width / 13).ceil().clamp(1, 180);
    for (var i = 1; i <= segments; i++) {
      final x = size.width * i / segments;
      final wave = ((i * 17) % 11 - 5) * size.height * .075;
      final spark = (i / segments - phase).abs() < .045 ? -size.height * .28 : 0.0;
      path.lineTo(x, (mid + wave + spark).clamp(1.0, size.height - 1.0).toDouble());
    }
    final boltGlowPaint = Paint()
      ..color = boltGlow
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.height * .36).clamp(1.0, 3.0).toDouble()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(path, boltGlowPaint);
    final boltCore = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.height * .13).clamp(.8, 1.5).toDouble()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, boltCore);
    final sparkPaint = Paint()
      ..color = Colors.white
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(Offset(size.width * phase, mid), size.height * .38, sparkPaint);
  }

  @override
  bool shouldRepaint(covariant _ElectricBoltPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary || oldDelegate.boltGlow != boltGlow;
}

class _TransferSpeedLabel extends StatefulWidget {
  const _TransferSpeedLabel({required this.bytesTransferred, super.key});
  final int bytesTransferred;

  @override
  State<_TransferSpeedLabel> createState() => _TransferSpeedLabelState();
}

class _TransferSpeedLabelState extends State<_TransferSpeedLabel> {
  DateTime _sampledAt = DateTime.now();
  int _sampledBytes = 0;
  double _bytesPerSecond = 0;

  @override
  void didUpdateWidget(covariant _TransferSpeedLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final now = DateTime.now();
    final elapsed = now.difference(_sampledAt).inMicroseconds / 1000000;
    final delta = widget.bytesTransferred - _sampledBytes;
    if (elapsed > 0 && delta >= 0) {
      _bytesPerSecond = delta / elapsed;
      _sampledAt = now;
      _sampledBytes = widget.bytesTransferred;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mb = _bytesPerSecond / (1024 * 1024);
    return Text(
      '${mb.toStringAsFixed(1)} MB/s',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.themes, super.key});
  final ThemeController themes;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  int _category = 0;
  bool _autoSaveReceivedFiles = true;
  final Map<String, String> _saveFolderLabels = {};
  static const _saveFolderTypes = <String, String>{
    'image': 'Images', 'video': 'Videos', 'music': 'Music', 'file': 'Files', 'app': 'Apps',
  };
  final ScrollController _contentScrollController = ScrollController();
  final Map<String, Future<Uint8List?>> _transferAppIcons = {};

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() {
        _autoSaveReceivedFiles = prefs.getBool('plazma_auto_save_received') ?? true;
        for (final type in _saveFolderTypes.keys) {
          final label = prefs.getString('plazma_save_folder_label_$type');
          if (label != null && label.isNotEmpty) _saveFolderLabels[type] = label;
        }
      });
    });
  }

  Future<void> _setAutoSaveReceivedFiles(bool value) async {
    setState(() => _autoSaveReceivedFiles = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('plazma_auto_save_received', value);
  }

  Future<void> _chooseSaveFolder(String type) async {
    if (!io.Platform.isAndroid) return;
    try {
      final selected = await const MethodChannel('com.plazma.s/storage')
          .invokeMapMethod<String, dynamic>('selectSaveFolder', {'type': type});
      final uri = selected?['uri'];
      final label = selected?['name'];
      if (uri is! String || uri.isEmpty || label is! String || label.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('plazma_save_folder_$type', uri);
      await prefs.setString('plazma_save_folder_label_$type', label);
      if (mounted) setState(() => _saveFolderLabels[type] = label);
    } on PlatformException catch (error) {
      if (error.code != 'FOLDER_PICKER_CANCELLED' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not select that folder. Try again.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Folder selection is unavailable on this device.')),
        );
      }
    }
  }

  Future<void> _resetSaveFolder(String type) async {
    final prefs = await SharedPreferences.getInstance();
    final uri = prefs.getString('plazma_save_folder_$type');
    if (io.Platform.isAndroid && uri != null && uri.isNotEmpty) {
      try {
        await const MethodChannel('com.plazma.s/storage')
            .invokeMethod<void>('releaseSaveFolder', {'uri': uri});
      } catch (_) {
        // Clearing the saved override should still work if Android already revoked it.
      }
    }
    await prefs.remove('plazma_save_folder_$type');
    await prefs.remove('plazma_save_folder_label_$type');
    if (mounted) setState(() => _saveFolderLabels.remove(type));
  }

  @override
  void dispose() {
    _contentScrollController.dispose();
    super.dispose();
  }


  Future<Uint8List?> _transferAppIcon(String packageName) =>
      _transferAppIcons.putIfAbsent(packageName, () => FlutterDeviceApps.getAppIcon(packageName));

  String? _packageFromTransferPath(SharedLocalFile item) {
    if (item.type != 'app') return null;
    final parts = item.relativePath.replaceAll('\\\\', '/').split('/');
    if (parts.length > 1 && parts.first.toLowerCase() == 'apps') return parts[1];
    return null;
  }

  Widget _transferItemIcon(SharedLocalFile item) {
    final packageName = _packageFromTransferPath(item);
    if (packageName == null || !io.Platform.isAndroid) {
      return Icon(switch (item.type) {
        'app' => Icons.android_rounded,
        'image' => Icons.image_outlined,
        'video' => Icons.movie_outlined,
        'music' => Icons.music_note_rounded,
        _ => Icons.insert_drive_file_outlined,
      }, size: 34);
    }
    return FutureBuilder<Uint8List?>(
      future: _transferAppIcon(packageName),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) return const Icon(Icons.android_rounded, size: 34);
        return ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Image.memory(bytes, width: 42, height: 42, fit: BoxFit.contain),
        );
      },
    );
  }

  void _showTransferQueue() {
    final service = XenderLocalTransferService();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ValueListenableBuilder<List<SharedLocalFile>>(
          valueListenable: service.roomFiles,
          builder: (context, items, _) {
            final roomId = service.invite?.roomId ?? service.joinedInvite?.roomId;
            final isReceiver = service.isReceiving;
            final totalBytes = items.fold<int>(0, (sum, item) => sum + item.size);
            final transferredBytes = items.fold<int>(0, (sum, item) => sum + item.bytesTransferred);
            return SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.65,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(roomId == null ? 'Transfer queue' : 'Room $roomId',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                    IconButton(onPressed: () => Navigator.of(sheetContext).pop(), icon: const Icon(Icons.close)),
                  ]),
                  Text(isReceiver ? 'Receiving ${items.length} file(s)' : 'Sending ${items.length} file(s)',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  if (items.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      OutlinedButton.icon(onPressed: () => service.cancelAllQueuedItems(),
                        icon: const Icon(Icons.cancel_outlined, size: 16), label: Text(isReceiver ? 'Cancel receiving' : 'Cancel all')),
                      OutlinedButton.icon(onPressed: () => service.retryFailedQueueItems(),
                        icon: const Icon(Icons.refresh_rounded, size: 16), label: Text(isReceiver ? 'Retry failed receives' : 'Retry failed sends')),
                    ]),
                  ],
                  if (totalBytes > 0) ...[
                    Text('Overall progress · ${(transferredBytes / totalBytes * 100).clamp(0, 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    _ElectricTransferProgress(value: transferredBytes / totalBytes, height: 7),
                  ],
                  const SizedBox(height: 10),
                  Expanded(child: items.isEmpty
                    ? const Center(child: Text('No items in this room yet. Add files from any category.'))
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final fraction = item.size <= 0
                              ? (item.status == 'done' ? 1.0 : 0.0)
                              : (item.bytesTransferred / item.size).clamp(0.0, 1.0).toDouble();
                          final status = isReceiver
                              ? (item.status == 'sending' ? 'receiving' : item.status == 'done' ? 'saved' : item.status)
                              : (item.status == 'done' ? 'sent' : item.status);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                              SizedBox(width: 48, height: 48, child: Center(child: _transferItemIcon(item))),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700))),
                                  Text('${(fraction * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                                ]),
                                Text(item.relativePath, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                const SizedBox(height: 7),
                                _ElectricTransferProgress(value: fraction, height: 9),
                                const SizedBox(height: 4),
                                Row(children: [
                                  Text(status, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                  const Spacer(),
                                  _TransferSpeedLabel(key: ValueKey('speed-${item.id}'), bytesTransferred: item.bytesTransferred),
                                ]),
                              ])),
                              if (item.status == 'waiting' || item.status == 'sending') ...[
                                const SizedBox(width: 4),
                                IconButton(visualDensity: VisualDensity.compact,
                                  tooltip: isReceiver ? 'Cancel receiving item' : 'Cancel sending item',
                                  onPressed: () => service.cancelQueuedItem(item.id),
                                  icon: const Icon(Icons.close_rounded, size: 18)),
                              ],
                            ]),
                          );
                        },
                      )),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _sendAllSelected() async {
    // Keep each category's existing preparation/validation logic, but run the
    // selected categories sequentially so each one appends to the same room.
    final senders = <Future<void> Function()?>[
      AppsScreen.sendSelected,
      ImagesScreen.sendSelected,
      MusicScreen.sendSelected,
      VideosScreen.sendSelected,
    ];
    for (final send in senders) {
      if (send != null) await send();
    }
  }

  Widget _stickySendButton({required VoidCallback? onPressed}) {
    final addToRoom = XenderLocalTransferService().isSharing;
    final colors = Theme.of(context).colorScheme;
    final label = addToRoom ? 'Add to room' : 'Send';
    return Tooltip(
      message: label,
      child: Material(
        color: colors.primary,
        elevation: 7,
        shape: const StadiumBorder(),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(28),
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 17),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13,
                )),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Row(
          children: [
            if (wide) _Sidebar(selected: _tab, onSelect: (value) => setState(() => _tab = value)),
            Expanded(
              child: Column(
                children: [
                  const _TopBar(),
                  if (_tab == 0) _topCategoryNavigation(),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: SingleChildScrollView(
                          controller: _contentScrollController,
                          physics: const ClampingScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(16, 10, 16, _tab == 0 ? 112 : 18),
                          child: IndexedStack(
                            index: _tab,
                            children: [
                              _categoryContent(),
                              const FilesScreen(),
                              _meContent(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!wide)
                    NavigationBar(
                      labelTextStyle: WidgetStateProperty.resolveWith((states) => const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                      selectedIndex: _tab,
                      onDestinationSelected: (value) => setState(() {
                        _tab = value;
                      }),
                      destinations: const [
                        NavigationDestination(icon: Icon(Icons.apps_rounded), label: 'Apps'),
                        NavigationDestination(icon: Icon(Icons.swap_horiz_rounded), label: 'Transfer'),
                        NavigationDestination(icon: Icon(Icons.person_rounded), label: 'Me'),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
          ),
          if (_tab == 0)
            AnimatedBuilder(
              animation: Listenable.merge([
                AppsScreen.selectedCount,
                ImagesScreen.selectedCount,
                VideosScreen.selectedCount,
                MusicScreen.selectedCount,
              ]),
              builder: (context, _) {
                final count = AppsScreen.selectedCount.value +
                    ImagesScreen.selectedCount.value +
                    MusicScreen.selectedCount.value +
                    VideosScreen.selectedCount.value;
                if (count == 0) return const SizedBox.shrink();
                return Positioned(
                  left: wide ? 300 : 16,
                  right: 16,
                  bottom: wide ? 84 : 158,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (AppsScreen.selectedCount.value > 0 ||
                            ImagesScreen.selectedCount.value > 0 ||
                            VideosScreen.selectedCount.value > 0 ||
                            MusicScreen.selectedCount.value > 0) ...[
                          OutlinedButton.icon(
                            onPressed: () async {
                              final mediaDelete = [
                                DeviceMediaBrowser.deleteSelected[MediaKind.images],
                                DeviceMediaBrowser.deleteSelected[MediaKind.videos],
                                DeviceMediaBrowser.deleteSelected[MediaKind.music],
                              ];
                              for (final delete in mediaDelete) {
                                if (delete != null) await delete();
                              }
                              if (AppsScreen.selectedCount.value > 0 &&
                                  AppsScreen.deleteSelected != null) {
                                await AppsScreen.deleteSelected!();
                              }
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('Delete'),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.surface,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        _stickySendButton(onPressed: _sendAllSelected),
                      ],
                    ),
                  ),
                );
              },
            ),
          AnimatedBuilder(
            animation: Listenable.merge([
              AppsScreen.selectedCount,
              ImagesScreen.selectedCount,
              VideosScreen.selectedCount,
              MusicScreen.selectedCount,
            ]),
            builder: (context, _) {
              final hasSelection = _tab == 0 && (
                AppsScreen.selectedCount.value +
                ImagesScreen.selectedCount.value +
                MusicScreen.selectedCount.value +
                VideosScreen.selectedCount.value > 0
              );
              if (hasSelection) return const SizedBox.shrink();
              final service = XenderLocalTransferService();
              return ValueListenableBuilder<List<SharedLocalFile>>(
                valueListenable: service.roomFiles,
                builder: (context, items, _) {
                  return ValueListenableBuilder<TransferOverlaySnapshot?>(
                    valueListenable: TransferOverlayController.current,
                    builder: (context, transfer, _) {
                      final hasRoom = service.isSharing || service.joinedInvite != null;
                      if (!hasRoom && transfer == null) return const SizedBox.shrink();
                      final colors = Theme.of(context).colorScheme;
                      final sending = transfer?.direction == TransferOverlayDirection.sending || (transfer == null && service.isSharing);
                      return Positioned(
                        right: 16,
                        bottom: wide ? 24 : 92,
                        child: Material(
                          color: colors.surface,
                          elevation: 8,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _showTransferQueue,
                            child: SizedBox(
                              width: 58,
                              height: 58,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: CircularProgressIndicator(
                                      value: transfer?.progress ?? 0,
                                      strokeWidth: 3.5,
                                      color: colors.primary,
                                      backgroundColor: colors.primary.withValues(alpha: 0.16),
                                    ),
                                  ),
                                  Icon(
                                    sending ? Icons.upload_rounded : Icons.download_rounded,
                                    size: 19,
                                    color: colors.primary,
                                  ),
                                  Positioned(
                                    right: 1,
                                    top: 1,
                                    child: Container(
                                      constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: colors.primary,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${items.length}',
                                        style: TextStyle(
                                          color: colors.onPrimary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _topCategoryNavigation() {
    const labels = ['Apps', 'Images', 'Music', 'Videos', 'Files'];
    const icons = [Icons.apps_rounded, Icons.photo_library_rounded, Icons.library_music_rounded, Icons.video_library_rounded, Icons.folder_rounded];
    return SizedBox(
      height: 54,
      child: ListView.separated(
        clipBehavior: Clip.hardEdge,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) => ChoiceChip(
          avatar: Icon(icons[index], size: 17),
          label: Text(labels[index]),
          selected: _category == index,
          onSelected: (_) => setState(() => _category = index),
        ),
      ),
    );
  }

  Widget _categoryContent() => IndexedStack(
    index: _category,
    children: [
      const AppsScreen(),
      ImagesScreen(enabled: _category == 1, scrollController: _contentScrollController),
      MusicScreen(enabled: _category == 2, scrollController: _contentScrollController),
      VideosScreen(enabled: _category == 3, scrollController: _contentScrollController),
      const FilesScreen(),
    ],
  );

  Widget _meContent() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _settingsContent(),
    const SizedBox(height: 22),
    _secondaryContent(),
  ]);

  Widget _settingsContent() {
    final selected = widget.themes.selected;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Settings', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text('Make Plazma S look the way you want. Your choice is saved on this device.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 22),
      Text('Appearance', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: PlazmaTheme.values.map((theme) {
          final isSelected = selected == theme;
          final brightness = {PlazmaTheme.dark, PlazmaTheme.midnight, PlazmaTheme.obsidian}.contains(theme) ? 'Dark' : 'Light';
          return SizedBox(
            width: 92,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => widget.themes.setTheme(theme),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: _ThemeSwatch(theme: theme),
                  ),
                  const SizedBox(height: 4),
                  Text(theme.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  Text(brightness, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ]),
              ),
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 20),
      const AppUpdateCard(),
      const SizedBox(height: 12),
      Card(child: SwitchListTile(
        secondary: const Icon(Icons.save_alt_rounded),
        title: const Text('Auto-save received files'),
        subtitle: const Text('Save incoming media and documents automatically to the device folders.'),
        value: _autoSaveReceivedFiles,
        onChanged: _setAutoSaveReceivedFiles,
      )),
      if (io.Platform.isAndroid) ...[
        const SizedBox(height: 14),
        Text('Save locations', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Choose a separate destination folder for each type. Unselected types use the default Plazma S folders.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Card(child: Column(children: _saveFolderTypes.entries.map((entry) {
          final label = _saveFolderLabels[entry.key];
          return ListTile(
            leading: Icon(switch (entry.key) {
              'image' => Icons.image_outlined,
              'video' => Icons.movie_outlined,
              'music' => Icons.music_note_rounded,
              'app' => Icons.apps_rounded,
              _ => Icons.folder_outlined,
            }),
            title: Text(entry.value),
            subtitle: Text(label ?? 'Default Plazma S folder', maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (label != null) IconButton(
                tooltip: 'Use default folder',
                onPressed: () => _resetSaveFolder(entry.key),
                icon: const Icon(Icons.restart_alt_rounded),
              ),
              IconButton(
                tooltip: 'Choose folder',
                onPressed: () => _chooseSaveFolder(entry.key),
                icon: const Icon(Icons.folder_open_rounded),
              ),
            ]),
          );
        }).toList())),
      ],
      Card(child: ListTile(
        leading: const Icon(Icons.wifi_rounded),
        title: const Text('Connection mode'),
        subtitle: const Text('Local network only · No cloud or internet relay'),
      )),
    ]);
  }

  Widget _secondaryContent() => const TransferHistoryScreen();
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.theme});
  final PlazmaTheme theme;

  @override
  Widget build(BuildContext context) => Container(
    width: 30, height: 30,
    decoration: BoxDecoration(
      color: theme.background,
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: theme.foreground.withValues(alpha: 0.15)),
    ),
    child: Center(child: Container(
      width: 17, height: 17,
      decoration: BoxDecoration(color: theme.primary, shape: BoxShape.circle),
    )),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3))),
      ),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 25),
        ),
        const SizedBox(width: 10),
        Text('plazma', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface, letterSpacing: -0.8)),
        Text(' S', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: theme.colorScheme.primary)),
        const Spacer(),
      ]),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selected, required this.onSelect});
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Container(
    width: 228,
    color: Theme.of(context).colorScheme.surface,
    padding: const EdgeInsets.fromLTRB(14, 22, 14, 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, 26), child: Text('WORKSPACE', style: TextStyle(fontSize: 10, letterSpacing: 1.8, fontWeight: FontWeight.w800))),
      _navItem(context, Icons.apps_rounded, 'Apps', 0),
      _navItem(context, Icons.swap_horiz_rounded, 'Transfer', 1),
      _navItem(context, Icons.person_rounded, 'Me', 2),
      const Spacer(),
      const Padding(padding: EdgeInsets.all(12), child: Text('LOCAL NETWORK ONLY\nDirect device-to-device sharing.', style: TextStyle(fontSize: 11, height: 1.5))),
    ]),
  );

  Widget _navItem(BuildContext context, IconData icon, String label, int index) => ListTile(
    selected: selected == index,
    selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    leading: Icon(icon),
    title: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    onTap: () => onSelect(index),
    dense: true,
  );
}

