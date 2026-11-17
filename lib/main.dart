import 'dart:io' as io;
import 'dart:convert';
// Flutter stable 3.50 marks Material's umbrella library and legacy RadioListTile
// selection parameters deprecated while transitioning to the new Material API.
// Keep the UI compatible with the current stable SDK during that migration.
// ignore_for_file: deprecated_member_use


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_device_apps/flutter_device_apps.dart';
import 'package:media_kit/media_kit.dart';
import 'services/update_notification_service.dart';

import 'updates/app_update_card.dart';
import 'widgets/electric_progress_bar.dart';

import 'features/apps/apps_screen.dart';
import 'features/files/files_screen.dart';
import 'features/images/images_screen.dart';
import 'features/media/device_media_browser.dart';
import 'features/music/music_screen.dart';
import 'features/videos/videos_screen.dart';
import 'transfers/transfer_overlay_controller.dart';
import 'transfers/xender_local_transfer_service.dart';
import 'features/history/transfer_history_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await UpdateNotificationService.initialize();
  runApp(const PlazmaApp());
}

enum PlazmaTheme { light, dark, ocean, sunset, forest, purple, crimson, midnight, obsidian, monochrome, blackGold, abyssalAmethyst }

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
        PlazmaTheme.monochrome => 'Black & White',
        PlazmaTheme.blackGold => 'Black & Gold',
        PlazmaTheme.abyssalAmethyst => 'Abyssal Amethyst',
      };

  bool get isDark => {PlazmaTheme.dark, PlazmaTheme.midnight, PlazmaTheme.obsidian, PlazmaTheme.monochrome, PlazmaTheme.blackGold, PlazmaTheme.abyssalAmethyst}.contains(this);

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
        PlazmaTheme.monochrome => 'Pure black surfaces with crisp white and grey details',
        PlazmaTheme.blackGold => 'Matte black surfaces with elegant gold highlights',
        PlazmaTheme.abyssalAmethyst => 'Obsidian darkness with rare amethyst and ultraviolet accents',
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
        PlazmaTheme.monochrome => const Color(0xFF000000),
        PlazmaTheme.blackGold => const Color(0xFF080808),
        PlazmaTheme.abyssalAmethyst => const Color(0xFF08050D),
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
        PlazmaTheme.monochrome => const Color(0xFF101010),
        PlazmaTheme.blackGold => const Color(0xFF19150B),
        PlazmaTheme.abyssalAmethyst => const Color(0xFF15101D),
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
        PlazmaTheme.monochrome => const Color(0xFFFFFFFF),
        PlazmaTheme.blackGold => const Color(0xFFD4AF37),
        PlazmaTheme.abyssalAmethyst => const Color(0xFF9D4EDD),
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
        PlazmaTheme.monochrome => const Color(0xFFBDBDBD),
        PlazmaTheme.blackGold => const Color(0xFFFFD76A),
        PlazmaTheme.abyssalAmethyst => const Color(0xFFE0AAFF),
      };

  Color get foreground => switch (this) {
        PlazmaTheme.dark || PlazmaTheme.midnight || PlazmaTheme.obsidian || PlazmaTheme.monochrome || PlazmaTheme.blackGold || PlazmaTheme.abyssalAmethyst => const Color(0xFFF1F5F9),
        _ => const Color(0xFF0F172A),
      };

  Color get muted => switch (this) {
        PlazmaTheme.dark || PlazmaTheme.midnight || PlazmaTheme.obsidian || PlazmaTheme.monochrome || PlazmaTheme.blackGold || PlazmaTheme.abyssalAmethyst => const Color(0xFFB8A9C9),
        _ => const Color(0xFF64748B),
      };

  ThemeData toThemeData() {
    final isDark = this.isDark;
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
  final List<CustomPlazmaTheme> customThemes=[];
  String? selectedCustomId;
  CustomPlazmaTheme? get activeCustom { for(final t in customThemes){if(t.id==selectedCustomId)return t;} return null; }
  bool get activeIsDark=>activeCustom?.isDark??selected.isDark;
  Color get activeBackground=>activeCustom?.color('background')??selected.background;
  Color get activeSurface=>activeCustom?.color('surface')??selected.surface;
  ThemeData get activeThemeData=>activeCustom?.toThemeData()??selected.toThemeData();

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('plazma_theme');
    selected = PlazmaTheme.values.firstWhere(
      (theme) => theme.name == saved,
      orElse: () => PlazmaTheme.light,
    );
    final raw=prefs.getString('plazma_custom_themes');
    if(raw!=null){try{customThemes..clear()..addAll((jsonDecode(raw) as List).map((e)=>CustomPlazmaTheme.fromJson(Map<String,dynamic>.from(e))));}catch(_){customThemes.clear();}}
    selectedCustomId=prefs.getString('plazma_selected_custom_theme');
    if(activeCustom==null)selectedCustomId=null;
    notifyListeners();
  }
  Future<void> _persistCustom() async {final p=await SharedPreferences.getInstance();await p.setString('plazma_custom_themes',jsonEncode(customThemes.map((e)=>e.toJson()).toList()));if(selectedCustomId==null){await p.remove('plazma_selected_custom_theme');}else{await p.setString('plazma_selected_custom_theme',selectedCustomId!);}}
  Future<void> saveCustom(CustomPlazmaTheme t,{bool apply=true}) async {final i=customThemes.indexWhere((e)=>e.id==t.id);if(i<0)customThemes.add(t);else customThemes[i]=t;if(apply)selectedCustomId=t.id;await _persistCustom();notifyListeners();}
  Future<void> applyCustom(String id) async {if(!customThemes.any((e)=>e.id==id))return;selectedCustomId=id;await _persistCustom();notifyListeners();}
  Future<void> deleteCustom(String id) async {customThemes.removeWhere((e)=>e.id==id);if(selectedCustomId==id)selectedCustomId=null;await _persistCustom();notifyListeners();}

  Future<void> setTheme(PlazmaTheme theme) async {
    selected = theme;
    selectedCustomId = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('plazma_theme', theme.name);
    await prefs.remove('plazma_selected_custom_theme');
  }
}


class CustomPlazmaTheme {
  CustomPlazmaTheme({required this.id,required this.name,required this.background,required this.surface,required this.primary,required this.accent,required this.foreground,required this.muted,required this.isDark});
  final String id; String name; int background,surface,primary,accent,foreground,muted; bool isDark;
  Map<String,dynamic> toJson()=>{'id':id,'name':name,'background':background,'surface':surface,'primary':primary,'accent':accent,'foreground':foreground,'muted':muted,'isDark':isDark};
  factory CustomPlazmaTheme.fromJson(Map<String,dynamic> j)=>CustomPlazmaTheme(id:j['id'],name:j['name'],background:j['background'],surface:j['surface'],primary:j['primary'],accent:j['accent'],foreground:j['foreground'],muted:j['muted'],isDark:j['isDark']??false);
  Color color(String k)=>Color(switch(k){'background'=>background,'surface'=>surface,'primary'=>primary,'accent'=>accent,'foreground'=>foreground,_=>muted});
  void setColor(String k,int v){switch(k){case 'background':background=v;break;case 'surface':surface=v;break;case 'primary':primary=v;break;case 'accent':accent=v;break;case 'foreground':foreground=v;break;case 'muted':muted=v;break;}}
  CustomPlazmaTheme copy({String? id,String? name})=>CustomPlazmaTheme(id:id??this.id,name:name??this.name,background:background,surface:surface,primary:primary,accent:accent,foreground:foreground,muted:muted,isDark:isDark);
  ThemeData toThemeData(){final scheme=ColorScheme.fromSeed(seedColor:Color(primary),brightness:isDark?Brightness.dark:Brightness.light,primary:Color(primary),secondary:Color(accent),surface:Color(surface),onSurface:Color(foreground));return ThemeData(useMaterial3:true,brightness:isDark?Brightness.dark:Brightness.light,scaffoldBackgroundColor:Color(background),colorScheme:scheme,cardTheme:CardThemeData(color:Color(surface),elevation:0),appBarTheme:AppBarTheme(backgroundColor:Color(surface),foregroundColor:Color(foreground)),navigationBarTheme:NavigationBarThemeData(backgroundColor:Color(surface),indicatorColor:Color(primary).withValues(alpha:.13)));}
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
          theme: _themes.activeThemeData,
          home: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: _themes.activeBackground,
              statusBarIconBrightness: _themes.activeIsDark ? Brightness.light : Brightness.dark,
              systemNavigationBarColor: _themes.activeSurface,
              systemNavigationBarIconBrightness: _themes.selected.isDark ? Brightness.light : Brightness.dark,
            ),
            child: HomeScreen(themes: _themes),
          ),
        ),
      );
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

String _formatTransferSize(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
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
                    Text('Overall progress · ${(transferredBytes / totalBytes * 100).clamp(0, 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    ElectricProgressBar(value: transferredBytes / totalBytes, height: 10),
                  ],
                  const SizedBox(height: 10),
                  Expanded(child: items.isEmpty
                    ? const Center(child: Text('No items in this room yet. Add files from any category.'))
                    : ListView.separated(
                        itemCount: items.length,
                        padding: const EdgeInsets.only(bottom: 8),
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final fraction = item.size <= 0
                              ? (item.status == 'done' ? 1.0 : 0.0)
                              : (item.bytesTransferred / item.size).clamp(0.0, 1.0).toDouble();
                          final status = isReceiver
                              ? (item.status == 'sending' ? 'Receiving' : item.status == 'done' ? 'Saved' : item.status)
                              : (item.status == 'done' ? 'Sent' : item.status);
                          final sizeLabel = _formatTransferSize(item.size);
                          return ElectricTransferProgressCard(
                            key: ValueKey('transfer-card-${item.id}'),
                            icon: _transferItemIcon(item),
                            title: item.name,
                            subtitle: '$sizeLabel · ${item.relativePath}',
                            progress: fraction,
                            status: status,
                            speed: _TransferSpeedLabel(
                              key: ValueKey('speed-${item.id}'),
                              bytesTransferred: item.bytesTransferred,
                            ),
                            trailing: item.status == 'waiting' || item.status == 'sending'
                                ? IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: isReceiver ? 'Cancel receiving item' : 'Cancel sending item',
                                    onPressed: () => service.cancelQueuedItem(item.id),
                                    icon: const Icon(Icons.close_rounded, size: 18),
                                  )
                                : null,
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
          final brightness = theme.isDark ? 'Dark' : 'Light';
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
      Card(child: ListTile(leading: const Icon(Icons.palette_outlined),title: const Text('Theme Studio'),subtitle: const Text('Create, preview and manage custom themes'),trailing: const Icon(Icons.chevron_right),onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ThemeStudioScreen(controller: widget.themes))))),
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


class ThemeStudioScreen extends StatefulWidget {
 const ThemeStudioScreen({required this.controller,super.key}); final ThemeController controller;
 @override State<ThemeStudioScreen> createState()=>_ThemeStudioScreenState();
}
class _ThemeStudioScreenState extends State<ThemeStudioScreen>{
 late CustomPlazmaTheme draft;
 static const fields={'background':'Background','surface':'Surface','primary':'Primary','accent':'Accent','foreground':'Text','muted':'Muted text'};
 @override void initState(){super.initState();final a=widget.controller.activeCustom;draft=a?.copy()??CustomPlazmaTheme(id:DateTime.now().microsecondsSinceEpoch.toString(),name:'My Theme',background:0xFF080B14,surface:0xFF151B2B,primary:0xFF8B5CF6,accent:0xFF22D3EE,foreground:0xFFF8FAFC,muted:0xFF94A3B8,isDark:true);}
 Future<void> editColor(String k)async{final c=TextEditingController(text:draft.color(k).value.toRadixString(16).substring(2).toUpperCase());final s=await showDialog<String>(context:context,builder:(x)=>AlertDialog(title:Text('Set \${fields[k]}'),content:TextField(controller:c,maxLength:6,decoration:const InputDecoration(prefixText:'#',hintText:'RRGGBB')),actions:[TextButton(onPressed:()=>Navigator.pop(x),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(x,c.text),child:const Text('Apply'))]));if(s==null)return;final v=int.tryParse(s.replaceAll('#',''),radix:16);if(v==null||s.replaceAll('#','').length!=6){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter a valid 6-digit HEX color.')));return;}setState(()=>draft.setColor(k,0xFF000000|v));}
 Future<void> save()async{final c=TextEditingController(text:draft.name);final n=await showDialog<String>(context:context,builder:(x)=>AlertDialog(title:const Text('Save theme'),content:TextField(controller:c,decoration:const InputDecoration(labelText:'Theme name')),actions:[TextButton(onPressed:()=>Navigator.pop(x),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(x,c.text.trim()),child:const Text('Save'))]));if(n==null||n.isEmpty)return;draft.name=n;await widget.controller.saveCustom(draft.copy());if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Theme saved and applied.')));}
 @override Widget build(BuildContext context){final cs=Theme.of(context).colorScheme;return Scaffold(appBar:AppBar(title:const Text('Theme Studio'),actions:[IconButton(onPressed:save,icon:const Icon(Icons.save))]),body:ListView(padding:const EdgeInsets.all(16),children:[
 Text('Build your look',style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.w900)),const SizedBox(height:5),Text('Customize six colors and preview your theme live.',style:TextStyle(color:cs.onSurfaceVariant)),const SizedBox(height:16),
 Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:draft.color('background'),borderRadius:BorderRadius.circular(20)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
 Row(children:[Icon(Icons.bolt,color:draft.color('primary'),size:32),Text('plazma S',style:TextStyle(color:draft.color('foreground'),fontWeight:FontWeight.w900,fontSize:20))]),const SizedBox(height:14),
 Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:draft.color('surface'),borderRadius:BorderRadius.circular(14)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Transfer preview',style:TextStyle(color:draft.color('foreground'),fontWeight:FontWeight.w800)),Text('Sending your files…',style:TextStyle(color:draft.color('muted'))),const SizedBox(height:12),ClipRRect(borderRadius:BorderRadius.circular(12),child:LinearProgressIndicator(value:.68,minHeight:9,color:draft.color('primary'),backgroundColor:draft.color('muted').withValues(alpha:.25))),const SizedBox(height:8),Text('68% · 12.4 MB/s',style:TextStyle(color:draft.color('accent')))]) )])),
 SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Dark appearance'),value:draft.isDark,onChanged:(v)=>setState(()=>draft.isDark=v)),
 Text('Theme colors',style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w800)),
 ...fields.entries.map((e)=>Card(child:ListTile(leading:CircleAvatar(backgroundColor:draft.color(e.key)),title:Text(e.value),subtitle:Text('#\${draft.color(e.key).value.toRadixString(16).padLeft(8,'0').substring(2).toUpperCase()}'),trailing:const Icon(Icons.colorize),onTap:()=>editColor(e.key)))),
 FilledButton.icon(onPressed:save,icon:const Icon(Icons.save),label:const Text('Save and apply')),
 if(widget.controller.customThemes.isNotEmpty)...[const SizedBox(height:20),Text('Saved themes',style:Theme.of(context).textTheme.titleMedium),...widget.controller.customThemes.map((t)=>Card(child:ListTile(leading:CircleAvatar(backgroundColor:t.color('primary')),title:Text(t.name),subtitle:Text(t.id==widget.controller.selectedCustomId?'Applied':'Saved'),onTap:()=>setState(()=>draft=t.copy()),trailing:PopupMenuButton<String>(onSelected:(v)async{if(v=='apply')await widget.controller.applyCustom(t.id);if(v=='delete')await widget.controller.deleteCustom(t.id);if(v=='duplicate')await widget.controller.saveCustom(t.copy(id:DateTime.now().microsecondsSinceEpoch.toString(),name:'\${t.name} Copy'),apply:false);if(mounted)setState((){});},itemBuilder:(_)=>const[PopupMenuItem(value:'apply',child:Text('Apply')),PopupMenuItem(value:'duplicate',child:Text('Duplicate')),PopupMenuItem(value:'delete',child:Text('Delete'))]))))]
 ]));}
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
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.secondary.withValues(alpha: 0.72)),
            boxShadow: [
              BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.42), blurRadius: 14, spreadRadius: 1),
              BoxShadow(color: theme.colorScheme.secondary.withValues(alpha: 0.20), blurRadius: 20, spreadRadius: 2),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/icon/plazma_s.jpg',
              width: 38,
              height: 38,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            ),
          ),
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

