import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:file_picker/file_picker.dart'; // إضافة هامة

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const VenomDesktopApp());
}

class VenomDesktopApp extends StatelessWidget {
  const VenomDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Venom Desktop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.teal,
        fontFamily: 'Sans',
      ),
      home: const DesktopPage(),
    );
  }
}

class DesktopPage extends StatefulWidget {
  const DesktopPage({super.key});

  @override
  State<DesktopPage> createState() => _DesktopPageState();
}

class _DesktopPageState extends State<DesktopPage> {
  late final Directory desktopDir;
  late final String configDirPath;
  List<FileSystemEntity> entries = [];
  Map<String, Offset> iconPositions = {};
  StreamSubscription? _watchSub;
  Timer? _debounceTimer;
  bool _isDraggingExternal = false;
  String wallpaperPath = '';
  late File layoutFile;
  late File configFile; // ملف جديد لحفظ الإعدادات العامة

  @override
  void initState() {
    super.initState();
    _initPaths();
    _loadConfig(); // تحميل الإعدادات (الخلفية)
    _loadLayout(); // تحميل مواقع الأيقونات
    _setupFileWatcher();
    _refreshEntries();
  }

  @override
  void dispose() {
    _watchSub?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _initPaths() {
    final home = Platform.environment['HOME'] ?? Directory.current.path;
    desktopDir = Directory(p.join(home, 'Desktop'));
    configDirPath = p.join(home, '.config', 'venom');
    final configDir = Directory(configDirPath);
    if (!configDir.existsSync()) configDir.createSync(recursive: true);

    // المسارات الافتراضية لملفات التكوين
    layoutFile = File(p.join(configDirPath, 'desktop_layout.json'));
    configFile = File(p.join(configDirPath, 'venom.json'));

    // خلفية افتراضية أولية
    wallpaperPath = p.join(configDirPath, 'wallpaper.jpg');

    if (!desktopDir.existsSync()) {
      desktopDir.createSync(recursive: true);
    }
  }

  // --- Config Persistence: حفظ واسترجاع الإعدادات العامة ---
  void _loadConfig() {
    try {
      if (configFile.existsSync()) {
        final data = jsonDecode(configFile.readAsStringSync());
        setState(() {
          // استرجاع مسار الخلفية المحفوظ، أو البقاء على الافتراضي
          wallpaperPath = data['wallpaper'] ?? wallpaperPath;
        });
      }
    } catch (e) {
      debugPrint("Config load error: $e");
    }
  }

  void _saveConfig() {
    try {
      final data = {
        'wallpaper': wallpaperPath,
        // يمكن إضافة المزيد من الإعدادات هنا مستقبلاً
      };
      configFile.writeAsStringSync(jsonEncode(data));
    } catch (e) {
      debugPrint("Config save error: $e");
    }
  }

  // --- Layout Persistence ---
  void _loadLayout() {
    try {
      if (layoutFile.existsSync()) {
        final content = layoutFile.readAsStringSync();
        final Map<String, dynamic> json = jsonDecode(content);
        setState(() {
          iconPositions = json.map((key, value) => MapEntry(
              key, Offset((value['x'] as num).toDouble(), (value['y'] as num).toDouble())));
        });
      }
    } catch (e) {
      debugPrint("Layout load error: $e");
    }
  }

  void _saveLayout() {
    try {
      final json = iconPositions
          .map((key, value) => MapEntry(key, {'x': value.dx, 'y': value.dy}));
      layoutFile.writeAsStringSync(jsonEncode(json));
    } catch (e) {
      debugPrint("Layout save error: $e");
    }
  }

  // --- File Watching & Refresh ---
  void _setupFileWatcher() {
    _watchSub = desktopDir.watch().listen((_) => _debouncedRefresh());
  }

  void _debouncedRefresh() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), _refreshEntries);
  }

  void _refreshEntries() {
    if (!mounted) return;
    try {
      final currentFiles =
          desktopDir.listSync().map((e) => p.basename(e.path)).toSet();
      iconPositions.removeWhere((key, _) => !currentFiles.contains(key));
      setState(() {
        entries = desktopDir.listSync().toList();
      });
    } catch (_) {}
  }

  // --- Launch Logic ---
  Future<void> _launchEntity(FileSystemEntity entity) async {
    final path = entity.path;
    if (path.endsWith('.desktop')) {
      await _launchDesktopFile(File(path));
    } else {
      await Process.start('xdg-open', [path], mode: ProcessStartMode.detached);
    }
  }

  Future<void> _launchDesktopFile(File file) async {
    try {
      final content = await file.readAsString();
      final execMatch =
          RegExp(r'^Exec=(.*)$', multiLine: true).firstMatch(content);
      if (execMatch != null) {
        String cmd = execMatch.group(1)!.trim();
        cmd = cmd.replaceAll(RegExp(r' %[fFuUicwk]'), '');
        await Process.start('sh', ['-c', cmd], mode: ProcessStartMode.detached);
      }
    } catch (_) {}
  }

  IconData _getIconForFile(String path) {
    if (FileSystemEntity.isDirectorySync(path)) return Icons.folder_rounded;
    final ext = p.extension(path).toLowerCase();
    if (path.endsWith('.desktop')) return Icons.rocket_launch_rounded;
    switch (ext) {
      case '.jpg': case '.jpeg': case '.png': case '.gif': case '.webp':
        return Icons.image_rounded;
      case '.mp4': case '.mkv': case '.avi': case '.mov': case '.webm':
        return Icons.movie_rounded;
      case '.mp3': case '.wav': case '.ogg':
        return Icons.audiotrack_rounded;
      case '.pdf':
        return Icons.picture_as_pdf_rounded;
      case '.txt': case '.md': case '.log': case '.cfg':
        return Icons.description_rounded;
      case '.zip': case '.tar': case '.gz': case '.7z': case '.rar':
        return Icons.folder_zip_rounded;
      case '.iso':
        return Icons.album_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  // --- UI Building ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DropTarget(
        onDragEntered: (_) => setState(() => _isDraggingExternal = true),
        onDragExited: (_) => setState(() => _isDraggingExternal = false),
        onDragDone: _handleExternalDrop,
        child: GestureDetector(
          onSecondaryTapUp: (details) => _showContextMenu(details.globalPosition),
          behavior: HitTestBehavior.translucent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Layer 1: Smart Wallpaper
              _buildSmartWallpaper(),

              // Layer 2: Icons
              ...entries.asMap().entries.map((entry) {
                return _buildFreeDraggableIcon(entry.value, entry.key);
              }),

              // Layer 3: Drag Overlay
              if (_isDraggingExternal)
                Container(
                  color: Colors.teal.withOpacity(0.15),
                  child: Center(
                      child: Icon(Icons.add_to_photos_rounded,
                          size: 80, color: Colors.white.withOpacity(0.5))),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmartWallpaper() {
    final file = File(wallpaperPath);
    if (!file.existsSync()) return _buildFallbackBackground();

    final ext = p.extension(wallpaperPath).toLowerCase();
    const videoExtensions = ['.mp4', '.mkv', '.avi', '.mov', '.webm'];

    if (videoExtensions.contains(ext)) {
      return VideoWallpaper(videoPath: wallpaperPath, key: ValueKey(wallpaperPath));
    } else {
      return Image.file(
        file,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _buildFallbackBackground(),
      );
    }
  }

  Widget _buildFallbackBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  Widget _buildFreeDraggableIcon(FileSystemEntity entity, int index) {
    final filename = p.basename(entity.path);
    final position = iconPositions[filename] ?? _getDefaultPosition(index);
    final displayName = filename.endsWith('.desktop')
        ? filename.replaceAll('.desktop', '')
        : filename;

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            iconPositions[filename] =
                (iconPositions[filename] ?? position) + details.delta;
          });
        },
        onPanEnd: (_) => _saveLayout(),
        onDoubleTap: () => _launchEntity(entity),
        child: Container(
          width: 90,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.transparent, 
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getIconForFile(entity.path),
                size: 48,
                color: Colors.white.withOpacity(0.95),
                shadows: const [
                  BoxShadow(blurRadius: 4, color: Colors.black54, offset: Offset(0, 2))
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  displayName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12, height: 1.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Offset _getDefaultPosition(int index) {
    const colCount = 6;
    const startX = 20.0;
    const startY = 20.0;
    const iconWidth = 100.0;
    const iconHeight = 110.0;
    final row = index % colCount;
    final col = index ~/ colCount;
    return Offset(startX + (col * iconWidth), startY + (row * iconHeight));
  }

  Future<void> _handleExternalDrop(DropDoneDetails details) async {
    setState(() => _isDraggingExternal = false);
    Offset dropPos = details.localPosition ?? const Offset(100, 100);
    for (int i = 0; i < details.files.length; i++) {
      final file = details.files[i];
      final destPath = p.join(desktopDir.path, p.basename(file.path));
      if (file.path == destPath) continue;
      try {
        await File(file.path).rename(destPath);
        iconPositions[p.basename(destPath)] =
            dropPos + Offset(i * 20.0, i * 20.0);
      } catch (_) {
        try {
          await File(file.path).copy(destPath);
        } catch (_) {}
      }
    }
    _saveLayout();
    _debouncedRefresh();
  }

  // --- Context Menu & Wallpaper Picker ---
  void _showContextMenu(Offset position) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      color: const Color(0xFF2A2A2A),
      items: [
        const PopupMenuItem(value: 'refresh', child: Text('Refresh', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(value: 'wallpaper', child: Text('Change Wallpaper...', style: TextStyle(color: Colors.white))),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'terminal', child: Text('Open Terminal Here', style: TextStyle(color: Colors.white))),
      ],
    );

    if (result == 'refresh') _refreshEntries();
    if (result == 'wallpaper') _pickWallpaper(); // استخدام منتقي الملفات الجديد
    if (result == 'terminal') {
      Process.run('exo-open', [
        '--launch',
        'TerminalEmulator',
        '--working-directory',
        desktopDir.path
      ]);
    }
  }

  // دالة اختيار الخلفية الجديدة باستخدام FilePicker
  Future<void> _pickWallpaper() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        // دعم الصور والفيديوهات معاً
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'mp4', 'mkv', 'avi', 'mov', 'webm'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          wallpaperPath = result.files.single.path!;
        });
        _saveConfig(); // حفظ الاختيار الجديد
      }
    } catch (e) {
      debugPrint("Error picking wallpaper: $e");
      // يمكن إضافة SnackBar هنا لإظهار خطأ للمستخدم إذا لزم الأمر
    }
  }
}

// --- Video Wallpaper Widget (Reusable) ---
class VideoWallpaper extends StatefulWidget {
  final String videoPath;
  const VideoWallpaper({super.key, required this.videoPath});

  @override
  State<VideoWallpaper> createState() => _VideoWallpaperState();
}

class _VideoWallpaperState extends State<VideoWallpaper> {
  late final Player player = Player();
  late final VideoController controller = VideoController(player);

  @override
  void initState() {
    super.initState();
    player.setPlaylistMode(PlaylistMode.loop);
    player.setVolume(0);
    player.open(Media(widget.videoPath));
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

 @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          // هنا التعديل: نضيف controls: NoVideoControls
          child: Video(
            controller: controller,
            fit: BoxFit.cover,
            controls: NoVideoControls, // <--- هذا السطر السحري يخفي كل شيء
          ),
        ),
      ),
    );
  }
}