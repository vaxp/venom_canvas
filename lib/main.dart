import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

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
  // كاش للثمنيلات لتقليل إعادة التحميل
  final Map<String, ImageProvider> thumbnailsCache = {};
  final Map<String, Future<void>> _loadingTasks = {};
  StreamSubscription? _watchSub;
  Timer? _debounceTimer;
  bool _isDraggingExternal = false;
  String wallpaperPath = '';
  late File layoutFile;
  late File configFile;

  @override
  void initState() {
    super.initState();
    _initPaths();
    _loadConfig();
    _loadLayout();
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
    layoutFile = File(p.join(configDirPath, 'desktop_layout.json'));
    configFile = File(p.join(configDirPath, 'venom.json'));
    wallpaperPath = p.join(configDirPath, 'wallpaper.jpg');
    if (!desktopDir.existsSync()) desktopDir.createSync(recursive: true);
  }

  void _loadConfig() {
    try {
      if (configFile.existsSync()) {
        final data = jsonDecode(configFile.readAsStringSync());
        wallpaperPath = data['wallpaper'] ?? wallpaperPath;
      }
    } catch (_) {}
  }

  void _saveConfig() {
    try {
      configFile.writeAsStringSync(jsonEncode({'wallpaper': wallpaperPath}));
    } catch (_) {}
  }

  void _loadLayout() {
    try {
      if (layoutFile.existsSync()) {
        final json = jsonDecode(layoutFile.readAsStringSync());
        iconPositions = (json as Map<String, dynamic>).map((k, v) =>
            MapEntry(k, Offset((v['x'] as num).toDouble(), (v['y'] as num).toDouble())));
      }
    } catch (_) {}
  }

  void _saveLayout() {
    try {
      layoutFile.writeAsStringSync(jsonEncode(
          iconPositions.map((k, v) => MapEntry(k, {'x': v.dx, 'y': v.dy}))));
    } catch (_) {}
  }

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
      final currentFiles = desktopDir.listSync().toList();
      // تنظيف الكاش من الملفات المحذوفة لتوفير الرام
      final currentNames = currentFiles.map((e) => p.basename(e.path)).toSet();
      thumbnailsCache.removeWhere((key, _) => !currentNames.contains(key));
      iconPositions.removeWhere((key, _) => !currentNames.contains(key));

      setState(() {
        entries = currentFiles;
      });
    } catch (_) {}
  }

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
      final execMatch = RegExp(r'^Exec=(.*)$', multiLine: true).firstMatch(content);
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
      case '.zip': case '.tar': case '.gz': case '.7z': case '.rar':
        return Icons.folder_zip_rounded;
      case '.iso':
        return Icons.album_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  // --- تحسين تحميل الثمنيل ---
  Future<void> _loadThumbnail(String path, String filename) async {
    if (thumbnailsCache.containsKey(filename) || _loadingTasks.containsKey(filename)) return;

    _loadingTasks[filename] = _generateThumbnail(path, filename).whenComplete(() {
      _loadingTasks.remove(filename);
    });
  }

  Future<void> _generateThumbnail(String path, String filename) async {
    final ext = p.extension(path).toLowerCase();
    ImageProvider? provider;

    try {
      if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext)) {
        // أهم تحسين: ResizeImage لتقليل استهلاك الرام
        provider = ResizeImage(FileImage(File(path)), width: 128);
      } else if (['.mp4', '.mkv', '.avi', '.mov', '.webm'].contains(ext)) {
        final thumbPath = await VideoThumbnail.thumbnailFile(
          video: path,
          imageFormat: ImageFormat.PNG,
          maxWidth: 128, // تقليل جودة الثمنيل لتوفير الرام
          quality: 50,
        );
        if (thumbPath != null) {
          provider = FileImage(File(thumbPath));
        }
      }
      
      if (provider != null && mounted) {
        setState(() {
          thumbnailsCache[filename] = provider!;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DropTarget(
        onDragEntered: (_) => setState(() => _isDraggingExternal = true),
        onDragExited: (_) => setState(() => _isDraggingExternal = false),
        onDragDone: _handleExternalDrop,
        child: GestureDetector(
          onSecondaryTapUp: (d) => _showContextMenu(d.globalPosition),
          behavior: HitTestBehavior.translucent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildSmartWallpaper(),
              // استخدام for loop بدلاً من map لتقليل overhead
              for (int i = 0; i < entries.length; i++)
                _buildFreeDraggableIcon(entries[i], i),
              if (_isDraggingExternal)
                Container(
                  color: Colors.teal.withOpacity(0.15),
                  child: const Center(
                    child: Icon(Icons.add_to_photos_rounded,
                        size: 80, color: Colors.white54),
                  ),
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
    const vids = ['.mp4', '.mkv', '.avi', '.mov', '.webm'];

    if (vids.contains(ext)) {
      // استخدام Key لضمان عدم إعادة بناء مشغل الفيديو إلا عند تغير المسار
      return VideoWallpaper(videoPath: wallpaperPath, key: ValueKey(wallpaperPath));
    }
    return Image.file(
      file,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _buildFallbackBackground(),
    );
  }

  Widget _buildFallbackBackground() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );

  Widget _buildFreeDraggableIcon(FileSystemEntity entity, int index) {
    final filename = p.basename(entity.path);
    final position = iconPositions[filename] ?? _getDefaultPosition(index);
    final displayName = filename.endsWith('.desktop')
        ? filename.replaceAll('.desktop', '')
        : filename;

    // بدء تحميل الثمنيل إذا لم يكن موجوداً
    _loadThumbnail(entity.path, filename);

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
            color: Colors.transparent, // لتحسين الأداء، تجنب الألوان غير الضرورية
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // استخدام AnimatedSwitcher لتنعيم ظهور الثمنيل
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: thumbnailsCache.containsKey(filename)
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image(
                          key: ValueKey('thumb-$filename'),
                          image: thumbnailsCache[filename]!,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      )
                    : Icon(
                        _getIconForFile(entity.path),
                        key: ValueKey('icon-$filename'),
                        size: 48,
                        color: Colors.white.withOpacity(0.9),
                      ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  displayName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12, height: 1.1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Offset _getDefaultPosition(int index) {
    const colCount = 6, startX = 20.0, startY = 20.0;
    const iconWidth = 100.0, iconHeight = 110.0;
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

  void _showContextMenu(Offset position) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      color: const Color(0xFF2A2A2A),
      items: [
        const PopupMenuItem(
            value: 'refresh',
            child: Text('Refresh', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(
            value: 'wallpaper',
            child: Text('Change Wallpaper...',
                style: TextStyle(color: Colors.white))),
        const PopupMenuDivider(),
        const PopupMenuItem(
            value: 'terminal',
            child: Text('Open Terminal Here',
                style: TextStyle(color: Colors.white))),
      ],
    );

    if (result == 'refresh') _refreshEntries();
    if (result == 'wallpaper') _pickWallpaper();
    if (result == 'terminal') {
      Process.run('exo-open', [
        '--launch',
        'TerminalEmulator',
        '--working-directory',
        desktopDir.path
      ]);
    }
  }

  Future<void> _pickWallpaper() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'jpg', 'jpeg', 'png', 'gif', 'webp',
          'mp4', 'mkv', 'avi', 'mov', 'webm'
        ],
      );
      if (result != null && result.files.single.path != null) {
        setState(() => wallpaperPath = result.files.single.path!);
        _saveConfig();
      }
    } catch (_) {}
  }
}

// --- Video Wallpaper Widget (Optimized) ---
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
        // استخدام const هنا يمنع إعادة بناء ويدجت الفيديو بلا داعٍ
        child: SizedBox(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          child: Video(
            controller: controller,
            fit: BoxFit.cover,
            controls: NoVideoControls,
          ),
        ),
      ),
    );
  }
}