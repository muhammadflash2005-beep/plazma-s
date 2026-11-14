// Flutter stable 3.50 marks Material's umbrella library and legacy RadioListTile
// selection parameters deprecated while transitioning to the new Material API.
// Keep the UI compatible with the current stable SDK during that migration.
// ignore_for_file: deprecated_member_use

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/apps/apps_screen.dart';
import 'features/devices/devices_screen.dart';
import 'features/files/files_screen.dart';
import 'transfers/transfer_mode.dart';

void main() => runApp(const PlazmaApp());

enum PlazmaTheme { light, dark, ocean, sunset, forest, purple, crimson, midnight }

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
      };

  Color get foreground => switch (this) {
        PlazmaTheme.dark || PlazmaTheme.midnight => const Color(0xFFF1F5F9),
        _ => const Color(0xFF0F172A),
      };

  Color get muted => switch (this) {
        PlazmaTheme.dark || PlazmaTheme.midnight => const Color(0xFF94A3B8),
        _ => const Color(0xFF64748B),
      };

  ThemeData toThemeData() {
    final isDark = this == PlazmaTheme.dark || this == PlazmaTheme.midnight;
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
          TextStyle(color: foreground, fontWeight: FontWeight.w600),
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
  int _tab = 0;
  String? _roomId;
  int _roomAppCount = 0;
  TransferMode? _transferMode;
  final _joinController = TextEditingController();

  @override
  void dispose() {
    _joinController.dispose();
    super.dispose();
  }

  String _newRoomId() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(6, (_) => alphabet[random.nextInt(alphabet.length)]).join();
  }

  void _createRoom() => setState(() {
        _roomId = _newRoomId();
        _roomAppCount = 0;
      });

  void _createRoomForSelectedApps(int count) => setState(() {
        _roomId = _newRoomId();
        _roomAppCount = count;
        _tab = 0;
      });

  void _joinRoom() {
    final code = _joinController.text.trim().toUpperCase();
    if (!RegExp(r'^[A-HJ-NP-Z2-9]{6}$').hasMatch(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid 6-character room code.')),
      );
      return;
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Room discovery will be connected in the next native milestone.')),
    );
  }

  void _showJoinDialog() => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Join a room'),
          content: TextField(
            controller: _joinController,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'Room code', hintText: 'K7M4PX'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: _joinRoom, child: const Text('Continue')),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide) _Sidebar(selected: _tab, onSelect: (value) => setState(() => _tab = value)),
            Expanded(
              child: Column(
                children: [
                  _TopBar(onJoin: _showJoinDialog),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(22, 20, 22, 34),
                          child: switch (_tab) {
                            0 => _homeContent(wide),
                            1 => FilesScreen(transferMode: _transferMode),
                            2 => AppsScreen(onSendSelected: _createRoomForSelectedApps),
                            3 => const DevicesScreen(),
                            4 => _secondaryContent(),
                            _ => _settingsContent(),
                          },
                        ),
                      ),
                    ),
                  ),
                  if (!wide)
                    NavigationBar(
                      selectedIndex: _tab,
                      onDestinationSelected: (value) => setState(() => _tab = value),
                      destinations: const [
                        NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
                        NavigationDestination(icon: Icon(Icons.folder_rounded), label: 'Files'),
                        NavigationDestination(icon: Icon(Icons.apps_rounded), label: 'Apps'),
                        NavigationDestination(icon: Icon(Icons.devices_rounded), label: 'Devices'),
                        NavigationDestination(icon: Icon(Icons.history_rounded), label: 'History'),
                        NavigationDestination(icon: Icon(Icons.settings_rounded), label: 'Settings'),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _homeContent(bool wide) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your files. Your devices.\nOne local connection.',
            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, height: 1.15)),
        const SizedBox(height: 10),
        Text('Share directly across devices on the same Wi-Fi or hotspot.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 15)),
        const SizedBox(height: 22),
        _notice(),
        const SizedBox(height: 22),
        Text('Choose your connection', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            SizedBox(
              width: wide ? 350 : double.infinity,
              child: _TransferModeCard(
                icon: Icons.computer_rounded,
                title: 'PC to PC',
                subtitle: 'Share between Windows, macOS and Linux computers.',
                onTap: () => _openTransfer(TransferMode.pcToPc),
              ),
            ),
            SizedBox(
              width: wide ? 350 : double.infinity,
              child: _TransferModeCard(
                icon: Icons.phone_android_rounded,
                title: 'Android to Android',
                subtitle: 'Send files between Android phones and tablets.',
                onTap: () => _openTransfer(TransferMode.androidToAndroid),
              ),
            ),
            SizedBox(
              width: wide ? 350 : double.infinity,
              child: _TransferModeCard(
                icon: Icons.devices_rounded,
                title: 'PC to Android',
                subtitle: 'Move files between a computer and an Android device.',
                onTap: () => _openTransfer(TransferMode.pcToAndroid),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_roomId == null) _roomActions(wide) else _roomPanel(),
        const SizedBox(height: 24),
        Text('Quick access', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Wrap(spacing: 14, runSpacing: 14, children: const [
          _QuickCard(icon: Icons.folder_rounded, title: 'Files', subtitle: 'Photos, videos & documents'),
          _QuickCard(icon: Icons.android_rounded, title: 'Apps', subtitle: 'APK sharing for Android'),
          _QuickCard(icon: Icons.devices_rounded, title: 'Devices', subtitle: 'Nearby device connections'),
        ]),
      ],
    );
  }

  void _openTransfer(TransferMode mode) => setState(() {
        _transferMode = mode;
        _tab = 1;
      });

  Widget _notice() => Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.wifi_rounded, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            const Expanded(child: Text(
              'Plazma S is designed for direct local-network transfers. Connect devices to the same reachable Wi-Fi or hotspot. Internet transfer is not part of this app.',
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
            icon: Icons.add_circle_rounded,
            title: 'Create a room',
            subtitle: 'Start a sharing space and invite nearby devices.',
            buttonText: 'Create room',
            onPressed: _createRoom,
          )),
          SizedBox(width: wide ? 350 : double.infinity, child: _ActionCard(
            icon: Icons.login_rounded,
            title: 'Join a room',
            subtitle: 'Enter the six-character code shared by the host.',
            buttonText: 'Enter room code',
            onPressed: _showJoinDialog,
            outlined: true,
          )),
        ],
      );

  Widget _roomPanel() => Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Your room', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
              IconButton(onPressed: () => setState(() => _roomId = null), icon: const Icon(Icons.close_rounded)),
            ]),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(children: [
                const Text('ROOM CODE', style: TextStyle(fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                SelectableText(_roomId!, style: TextStyle(
                  fontSize: 34, letterSpacing: 7, fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.primary,
                )),
                const SizedBox(height: 8),
                const Text('Share this code with someone on your local network.', textAlign: TextAlign.center),
              ]),
            ),
            const SizedBox(height: 18),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Icon(Icons.devices_rounded)),
              title: Text('This device'),
              subtitle: Text('Room host · Local preview'),
              trailing: Icon(Icons.check_circle_rounded, color: Color(0xFF10B981)),
            ),
            const Divider(),
            const Text('Network room invitations and connected devices are the next native milestone.'),
          ]),
        ),
      );

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
      ...PlazmaTheme.values.map((theme) => Card(
        child: RadioListTile<PlazmaTheme>(
          value: theme,
          groupValue: selected,
          onChanged: (value) {
            if (value != null) widget.themes.setTheme(value);
          },
          title: Text(theme.label, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(theme.description),
          secondary: _ThemeSwatch(theme: theme),
        ),
      )),
      const SizedBox(height: 20),
      Card(child: ListTile(
        leading: const Icon(Icons.wifi_rounded),
        title: const Text('Connection mode'),
        subtitle: const Text('Local network only · No cloud or internet relay'),
      )),
    ]);
  }

  Widget _secondaryContent() {
    final titles = ['Home', 'Files', 'Apps', 'Devices', 'Transfer history', 'Settings'];
    final descriptions = [
      'Your local sharing space.',
      'Browse files and folders on this device.',
      'Browse installed Android apps and prepare APK packages.',
      'Find nearby Plazma S devices on your local network.',
      'Active, completed, paused and failed transfers will appear here.',
      'Appearance and network preferences.',
    ];
    return Card(child: Padding(
      padding: const EdgeInsets.all(26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titles[_tab], style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(descriptions[_tab]),
      ]),
    ));
  }
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
        OutlinedButton.icon(onPressed: onJoin, icon: const Icon(Icons.meeting_room_outlined, size: 18), label: const Text('Join room')),
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
      _navItem(context, Icons.folder_rounded, 'Files', 1),
      _navItem(context, Icons.apps_rounded, 'Apps', 2),
      _navItem(context, Icons.devices_rounded, 'Devices', 3),
      _navItem(context, Icons.history_rounded, 'History', 4),
      _navItem(context, Icons.settings_rounded, 'Settings', 5),
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


class _TransferModeCard extends StatelessWidget {
  const _TransferModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: theme.colorScheme.primary, size: 26),
              ),
              const SizedBox(height: 14),
              Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Choose connection', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w800, fontSize: 12)),
                  const Spacer(),
                  Icon(Icons.arrow_forward_rounded, size: 17, color: theme.colorScheme.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title, subtitle;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 225,
    child: Card(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 25),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(subtitle, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ])),
      ]),
    )),
  );
}
