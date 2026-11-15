// Flutter stable 3.50 marks Material's umbrella library and legacy RadioListTile
// selection parameters deprecated while transitioning to the new Material API.
// Keep the UI compatible with the current stable SDK during that migration.
// ignore_for_file: deprecated_member_use


import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'updates/app_update_card.dart';

import 'features/apps/apps_screen.dart';
import 'features/devices/devices_screen.dart';
import 'features/files/files_screen.dart';
import 'features/images/images_screen.dart';
import 'features/music/music_screen.dart';
import 'features/videos/videos_screen.dart';
import 'transfers/transfer_mode.dart';
import 'transfers/transfer_overlay_controller.dart';
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
          home: HomeScreen(themes: _themes),
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
  int _tab = 1;
  int _category = 0;
  TransferMode? _transferMode;
  String? _transferAction;

  @override
  void dispose() {
    super.dispose();
  }

  void _showJoinDialog() => setState(() { _transferAction = null; _transferMode = null; _tab = 2; });

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Row(
          children: [
            if (wide) _Sidebar(selected: _tab, onSelect: (value) => setState(() { _tab = value; if (value != 2) { _transferMode = null; _transferAction = null; } })),
            Expanded(
              child: Column(
                children: [
                  _TopBar(onJoin: _showJoinDialog),
                  if (_tab == 1) _topCategoryNavigation(),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                          child: IndexedStack(
                            index: _tab,
                            children: [
                              _homeContent(wide),
                              _categoryContent(),
                              _transferAction == null ? _transferChooser(wide) : FilesScreen(transferMode: _transferMode, initialAction: _transferAction),
                              _meContent(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!wide)
                    NavigationBar(
                      selectedIndex: _tab,
                      onDestinationSelected: (value) => setState(() {
                        _tab = value;
                        if (value != 2) { _transferMode = null; _transferAction = null; }
                      }),
                      destinations: const [
                        NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
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
          if (_tab == 1)
            Positioned(
              left: wide ? 300 : 16,
              right: 16,
              bottom: wide ? 92 : 158,
              child: ValueListenableBuilder<int>(
                valueListenable: AppsScreen.selectedCount,
                builder: (context, count, _) => count == 0
                    ? const SizedBox.shrink()
                    : SizedBox(
                        height: 54,
                        child: FilledButton.icon(
                          onPressed: AppsScreen.sendSelected,
                          icon: const Icon(Icons.send_rounded),
                          label: Text('Send $count selected app${count == 1 ? '' : 's'}'),
                        ),
                      ),
              ),
            ),
          Positioned(
            right: 16,
            bottom: wide ? 24 : 92,
            child: ValueListenableBuilder<TransferOverlaySnapshot?>(
              valueListenable: TransferOverlayController.current,
              builder: (context, transfer, _) {
                if (transfer == null) return const SizedBox.shrink();
                final colors = Theme.of(context).colorScheme;
                return Material(
                  color: colors.surface,
                  elevation: 8,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _tab = transfer.isAppTransfer ? 1 : 2),
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
                              value: transfer.progress,
                              strokeWidth: 3.5,
                              color: colors.primary,
                              backgroundColor: colors.primary.withValues(alpha: 0.16),
                            ),
                          ),
                          Icon(
                            transfer.direction == TransferOverlayDirection.sending
                                ? Icons.upload_rounded
                                : Icons.download_rounded,
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
                                '${transfer.fileCount}',
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _homeContent(bool wide) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your devices. One room.\nSend together.',
            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, height: 1.15)),
        const SizedBox(height: 6),
        Text('Connect Android phones and computers on the same Wi-Fi. Create a room, invite up to seven other devices, and send apps, files, images, music and videos.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 15)),
        const SizedBox(height: 12),
        _notice(),
        const SizedBox(height: 14),
        Text('Multi-device transfer room', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        _roomActions(wide),
      ],
    );
  }

  void _openTransfer(TransferMode? mode, String action) => setState(() {
        _transferMode = mode;
        _transferAction = action;
        _tab = 2;
      });

  Widget _notice() => Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.wifi_rounded, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            const Expanded(child: Text(
              'All devices must already be connected to the same Wi-Fi network. Plazma S does not create or switch hotspots. Rooms support up to one sender and seven recipients across Android and PC.',
              style: TextStyle(height: 1.4, fontSize: 13),
            )),
          ]),
        ),
      );

  Widget _roomActions(bool wide) => Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          SizedBox(width: wide ? 350 : double.infinity, child: _ActionCard(
            icon: Icons.send_rounded,
            title: 'Create a room',
            subtitle: 'Start a room from this PC or Android device. Share the QR code or connection code with up to seven recipients.',
            buttonText: 'Create room',
            onPressed: () => _openTransfer(null, 'create'),
          )),
          SizedBox(width: wide ? 350 : double.infinity, child: _ActionCard(
            icon: Icons.qr_code_scanner_rounded,
            title: 'Join a room',
            subtitle: 'Join a room hosted by another PC or Android device. Each recipient receives independently.',
            buttonText: 'Join room',
            onPressed: _showJoinDialog,
            outlined: true,
          )),
        ],
      );

  Widget _topCategoryNavigation() {
    const labels = ['Apps', 'Images', 'Music', 'Videos', 'Files'];
    const icons = [Icons.apps_rounded, Icons.photo_library_rounded, Icons.library_music_rounded, Icons.video_library_rounded, Icons.folder_rounded];
    return SizedBox(
      height: 54,
      child: ListView.separated(
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
    children: const [
      AppsScreen(),
      ImagesScreen(),
      MusicScreen(),
      VideosScreen(),
      FilesScreen(),
    ],
  );

  Widget _transferChooser(bool wide) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Transfer', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      Text('All devices must be connected to the same Wi-Fi. Create a room or join someone else’s room.',
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant, height: 1.4)),
      const SizedBox(height: 22),
      _notice(),
      const SizedBox(height: 20),
      _ActionCard(
        icon: Icons.add_circle_outline_rounded,
        title: 'Create room',
        subtitle: 'Choose apps, files, images, music or videos to share. Invite up to seven devices using a QR code or room code.',
        buttonText: 'Create room',
        onPressed: () => _openTransfer(null, 'join'),
      ),
      const SizedBox(height: 14),
      _ActionCard(
        icon: Icons.meeting_room_outlined,
        title: 'Join room',
        subtitle: 'Scan the host QR code on Android or enter the connection code on a computer to receive shared content.',
        buttonText: 'Join room',
        outlined: true,
        onPressed: () => _openTransfer(null, 'create'),
      ),
    ]);
  }

  Widget _meContent() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Me', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
    const SizedBox(height: 16),
    _settingsContent(),
    const SizedBox(height: 22),
    Text('Transfer history', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
    const SizedBox(height: 10),
    _secondaryContent(),
  ]);

  Widget _settingsContent() {
    final selected = widget.themes.selected;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Settings', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      Text('Make Plazma S look the way you want. Your choice is saved on this device.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 22),
      Text('Appearance', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 3,
        crossAxisSpacing: 9,
        mainAxisSpacing: 9,
        childAspectRatio: 0.76,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: PlazmaTheme.values.map((theme) {
          final isSelected = selected == theme;
          return Card(
            clipBehavior: Clip.antiAlias,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outlineVariant,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: InkWell(
              onTap: () => widget.themes.setTheme(theme),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _ThemeSwatch(theme: theme),
                        const Spacer(),
                        if (isSelected)
                          Icon(
                            Icons.check_circle_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 18,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      theme.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Expanded(
                      child: Text(
                        theme.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          height: 1.2,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
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
    width: 42, height: 42,
    decoration: BoxDecoration(
      color: theme.background,
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: theme.foreground.withValues(alpha: 0.15)),
    ),
    child: Center(child: Container(
      width: 22, height: 22,
      decoration: BoxDecoration(color: theme.primary, shape: BoxShape.circle),
    )),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onJoin});
  final VoidCallback onJoin;

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
        OutlinedButton.icon(onPressed: onJoin, icon: const Icon(Icons.meeting_room_outlined, size: 18), label: const Text('Transfer')),
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
      _navItem(context, Icons.home_rounded, 'Home', 0),
      _navItem(context, Icons.apps_rounded, 'Apps', 1),
      _navItem(context, Icons.swap_horiz_rounded, 'Transfer', 2),
      _navItem(context, Icons.person_rounded, 'Me', 3),
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

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.title, required this.subtitle, required this.buttonText, required this.onPressed, this.outlined = false});
  final IconData icon;
  final String title, subtitle, buttonText;
  final VoidCallback onPressed;
  final bool outlined;

  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: Theme.of(context).colorScheme.primary, size: 30),
      const SizedBox(height: 15),
      Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.45)),
      const SizedBox(height: 18),
      SizedBox(width: double.infinity, child: outlined
        ? OutlinedButton(onPressed: onPressed, child: Text(buttonText))
        : FilledButton.icon(onPressed: onPressed, icon: const Icon(Icons.arrow_forward_rounded, size: 17), label: Text(buttonText))),
    ]),
  ));
}


