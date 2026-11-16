// Flutter stable 3.50 marks Material's umbrella library and legacy RadioListTile
// selection parameters deprecated while transitioning to the new Material API.
// Keep the UI compatible with the current stable SDK during that migration.
// ignore_for_file: deprecated_member_use


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'updates/app_update_card.dart';

import 'features/apps/apps_screen.dart';
import 'features/files/files_screen.dart';
import 'features/images/images_screen.dart';
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.themes, super.key});
  final ThemeController themes;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  int _category = 0;
  final ScrollController _contentScrollController = ScrollController();

  @override
  void dispose() {
    _contentScrollController.dispose();
    super.dispose();
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
                    Text('Overall progress · ${(transferredBytes / totalBytes * 100).clamp(0, 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: (transferredBytes / totalBytes).clamp(0.0, 1.0)),
                  ],
                  const SizedBox(height: 10),
                  Expanded(child: items.isEmpty
                    ? const Center(child: Text('No items in this room yet. Add files from any category.'))
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return ListTile(
                            leading: Icon(switch (item.type) { 'app' => Icons.apps_rounded, 'image' => Icons.image_outlined, 'video' => Icons.movie_outlined, 'music' => Icons.music_note_rounded, _ => Icons.insert_drive_file_outlined }),
                            title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(item.relativePath),
                            trailing: SizedBox(width: 92, child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text(isReceiver ? (item.status == 'sending' ? 'receiving' : item.status == 'done' ? 'saved' : item.status) : (item.status == 'done' ? 'sent' : item.status), style: const TextStyle(fontSize: 10)),
                              const SizedBox(height: 4),
                              LinearProgressIndicator(value: item.size <= 0 ? 0 : (item.bytesTransferred / item.size).clamp(0.0, 1.0)),
                              if (item.status == 'waiting' || item.status == 'sending')
                                IconButton(visualDensity: VisualDensity.compact, tooltip: isReceiver ? 'Cancel receiving item' : 'Cancel sending item',
                                  onPressed: () => service.cancelQueuedItem(item.id),
                                  icon: const Icon(Icons.close_rounded, size: 17)),
                            ])),
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
          if (_tab == 0 && _category == 0)
            Positioned(
              left: wide ? 300 : 16,
              right: 16,
              bottom: wide ? 84 : 84,
              child: ValueListenableBuilder<int>(
                valueListenable: AppsScreen.selectedCount,
                builder: (context, count, _) => count == 0
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: Alignment.centerRight,
                        child: _stickySendButton(onPressed: AppsScreen.sendSelected),
                      ),
              ),
            ),
          if (_tab == 0 && _category == 1)
            Positioned(
              right: 16, bottom: wide ? 92 : 158,
              child: ValueListenableBuilder<int>(
                valueListenable: ImagesScreen.selectedCount,
                builder: (context, count, _) => count == 0
                    ? const SizedBox.shrink()
                    : _stickySendButton(onPressed: ImagesScreen.sendSelected),
              ),
            ),
          if (_tab == 0 && _category == 2)
            Positioned(
              right: 16, bottom: wide ? 92 : 158,
              child: ValueListenableBuilder<int>(
                valueListenable: MusicScreen.selectedCount,
                builder: (context, count, _) => count == 0
                    ? const SizedBox.shrink()
                    : _stickySendButton(onPressed: MusicScreen.sendSelected),
              ),
            ),
          if (_tab == 0 && _category == 3)
            Positioned(
              right: 16, bottom: wide ? 92 : 158,
              child: ValueListenableBuilder<int>(
                valueListenable: VideosScreen.selectedCount,
                builder: (context, count, _) => count == 0
                    ? const SizedBox.shrink()
                    : _stickySendButton(onPressed: VideosScreen.sendSelected),
              ),
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
                (_category == 0 && AppsScreen.selectedCount.value > 0) ||
                (_category == 1 && ImagesScreen.selectedCount.value > 0) ||
                (_category == 2 && MusicScreen.selectedCount.value > 0) ||
                (_category == 3 && VideosScreen.selectedCount.value > 0)
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

