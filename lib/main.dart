// Flutter 3.50 deprecates the umbrella Material import while its replacement
// package is still evolving; keep this preview compatible with stable Flutter.
// ignore_for_file: deprecated_member_use

import 'dart:math';

import 'package:flutter/material.dart';

void main() => runApp(const PlazmaApp());

const electricBlue = Color(0xFF2563EB);
const ink = Color(0xFF0F172A);
const muted = Color(0xFF64748B);
const canvas = Color(0xFFF4F7FC);

class PlazmaApp extends StatelessWidget {
  const PlazmaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Plazma S',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: canvas,
          colorScheme: ColorScheme.fromSeed(
            seedColor: electricBlue,
            primary: electricBlue,
            surface: Colors.white,
          ),
          fontFamily: 'Roboto',
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: Color(0xFFE8EEF7)),
            ),
          ),
        ),
        home: const HomeScreen(),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  String? _roomId;
  final _joinController = TextEditingController();

  @override
  void dispose() {
    _joinController.dispose();
    super.dispose();
  }

  String _newRoomId() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(6, (_) => alphabet[random.nextInt(alphabet.length)])
        .join();
  }

  void _createRoom() => setState(() {
        _roomId = _newRoomId();
        _tab = 0;
      });

  void _joinRoom() {
    final code = _joinController.text.trim().toUpperCase();
    if (code.length != 6 || !RegExp(r'^[A-HJ-NP-Z2-9]{6}$').hasMatch(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid 6-character room code.')),
      );
      return;
    }
    setState(() {
      _roomId = code;
      _tab = 0;
    });
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Preview only: joining real devices is not enabled on web yet.'),
      ),
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
            decoration: const InputDecoration(
              labelText: 'Room code',
              hintText: 'e.g. K7M4PX',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
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
                          padding: const EdgeInsets.fromLTRB(22, 18, 22, 34),
                          child: _tab == 0
                              ? _homeContent(wide)
                              : _secondaryContent(),
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
                        NavigationDestination(icon: Icon(Icons.apps_rounded), label: 'Apps'),
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

  Widget _homeContent(bool wide) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your files. Your devices.\nOne local connection.',
              style: TextStyle(fontSize: 30, height: 1.16, fontWeight: FontWeight.w800, color: ink)),
          const SizedBox(height: 10),
          const Text('Share directly across devices on the same Wi-Fi or hotspot.',
              style: TextStyle(color: muted, fontSize: 15)),
          const SizedBox(height: 22),
          _previewNotice(),
          const SizedBox(height: 22),
          if (_roomId == null) _roomActions(wide) else _roomPanel(),
          const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(child: Text('Quick access', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: ink))),
              Text('PREVIEW', style: TextStyle(fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w800, color: electricBlue)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: const [
              _QuickCard(icon: Icons.folder_rounded, title: 'Files', subtitle: 'Photos, videos & documents'),
              _QuickCard(icon: Icons.android_rounded, title: 'Apps', subtitle: 'APK sharing for Android'),
              _QuickCard(icon: Icons.devices_rounded, title: 'Devices', subtitle: 'Nearby device connections'),
            ],
          ),
        ],
      );

  Widget _previewNotice() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF2FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD6E5FF)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: electricBlue),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Web preview is for testing the interface and room flow. Live device discovery and file transfers require the Android or desktop app.',
                style: TextStyle(color: Color(0xFF244477), height: 1.4, fontSize: 13),
              ),
            ),
          ],
        ),
      );

  Widget _roomActions(bool wide) => Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          SizedBox(
            width: wide ? 350 : double.infinity,
            child: _ActionCard(
              icon: Icons.add_circle_rounded,
              title: 'Create a room',
              subtitle: 'Start a private sharing space and invite nearby devices.',
              buttonText: 'Create room',
              onPressed: _createRoom,
            ),
          ),
          SizedBox(
            width: wide ? 350 : double.infinity,
            child: _ActionCard(
              icon: Icons.login_rounded,
              title: 'Join a room',
              subtitle: 'Enter a six-character code shared by the host.',
              buttonText: 'Enter room code',
              onPressed: _showJoinDialog,
              outlined: true,
            ),
          ),
        ],
      );

  Widget _roomPanel() => Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Your room', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                  IconButton(
                    tooltip: 'Close preview room',
                    onPressed: () => setState(() => _roomId = null),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 18),
                decoration: BoxDecoration(color: const Color(0xFFF0F5FF), borderRadius: BorderRadius.circular(18)),
                child: Column(
                  children: [
                    const Text('ROOM CODE', style: TextStyle(color: muted, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    SelectableText(_roomId!, style: const TextStyle(fontSize: 34, letterSpacing: 7, fontWeight: FontWeight.w900, color: electricBlue)),
                    const SizedBox(height: 8),
                    const Text('Share this code with someone on your local network.', style: TextStyle(color: muted, fontSize: 12), textAlign: TextAlign.center),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Row(
                children: [
                  Icon(Icons.devices_rounded, color: electricBlue),
                  SizedBox(width: 8),
                  Text('Connected devices', style: TextStyle(fontWeight: FontWeight.w700)),
                  Spacer(),
                  Text('1 / 8', style: TextStyle(color: muted, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 12),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(backgroundColor: Color(0xFFEAF2FF), child: Icon(Icons.laptop_mac_rounded, color: electricBlue)),
                title: Text('This device'),
                subtitle: Text('Room host · Preview'),
                trailing: Icon(Icons.check_circle_rounded, color: Color(0xFF10B981)),
              ),
              const Divider(),
              const Text('Transfers will appear here when device-to-device sharing is enabled in the native app.', style: TextStyle(color: muted, height: 1.4, fontSize: 13)),
            ],
          ),
        ),
      );

  Widget _secondaryContent() {
    final titles = ['Home', 'App sharing', 'Transfer history', 'Settings'];
    final descriptions = [
      'Your local sharing space.',
      'Browse and share installed apps or APK files from the Android app.',
      'Completed and active transfers will be listed here.',
      'Themes, device name, privacy and connection preferences.',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titles[_tab], style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(descriptions[_tab], style: const TextStyle(color: muted)),
            const SizedBox(height: 22),
            const Text('This section is being built. The web preview currently focuses on the home and room interface.', style: TextStyle(height: 1.5)),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onJoin});
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) => Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Color(0xFFE8EEF7)))),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: electricBlue, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 25),
            ),
            const SizedBox(width: 10),
            const Text('plazma', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: ink, letterSpacing: -0.8)),
            const Text(' S', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: electricBlue)),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: onJoin,
              icon: const Icon(Icons.meeting_room_outlined, size: 18),
              label: const Text('Join room'),
            ),
            const SizedBox(width: 10),
            const CircleAvatar(radius: 17, backgroundColor: Color(0xFFEAF2FF), child: Icon(Icons.person_rounded, color: electricBlue, size: 19)),
          ],
        ),
      );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selected, required this.onSelect});
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Container(
        width: 228,
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(14, 22, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 26),
              child: Text('WORKSPACE', style: TextStyle(fontSize: 10, letterSpacing: 1.8, fontWeight: FontWeight.w800, color: muted)),
            ),
            _navItem(Icons.home_rounded, 'Home', 0),
            _navItem(Icons.apps_rounded, 'App sharing', 1),
            _navItem(Icons.history_rounded, 'History', 2),
            _navItem(Icons.settings_rounded, 'Settings', 3),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('LOCAL NETWORK ONLY\nBuilt for direct device-to-device sharing.', style: TextStyle(color: muted, fontSize: 11, height: 1.5)),
            ),
          ],
        ),
      );

  Widget _navItem(IconData icon, String label, int index) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: ListTile(
          selected: selected == index,
          selectedTileColor: const Color(0xFFEAF2FF),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: Icon(icon, color: selected == index ? electricBlue : muted, size: 20),
          title: Text(label, style: TextStyle(fontSize: 13, fontWeight: selected == index ? FontWeight.w700 : FontWeight.w500, color: selected == index ? electricBlue : ink)),
          onTap: () => onSelect(index),
          dense: true,
        ),
      );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.title, required this.subtitle, required this.buttonText, required this.onPressed, this.outlined = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onPressed;
  final bool outlined;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFFEAF2FF), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: electricBlue, size: 25)),
              const SizedBox(height: 15),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ink)),
              const SizedBox(height: 6),
              Text(subtitle, style: const TextStyle(fontSize: 13, color: muted, height: 1.45)),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: outlined
                    ? OutlinedButton(onPressed: onPressed, child: Text(buttonText))
                    : FilledButton.icon(onPressed: onPressed, icon: const Icon(Icons.arrow_forward_rounded, size: 17), label: Text(buttonText)),
              ),
            ],
          ),
        ),
      );
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 225,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: electricBlue, size: 25),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: ink)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: muted)),
                ])),
              ],
            ),
          ),
        ),
      );
}
