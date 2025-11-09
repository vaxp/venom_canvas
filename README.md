
import 'dart:async';
import 'dart:convert'; // نحتاجها لحفظ واسترجاع مواقع الأيقونات
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        textTheme: const TextTheme(
          bodyMedium: TextStyle(
            shadows: [Shadow(blurRadius: 4.0, color: Colors.black87, offset: Offset(1, 1))],
            fontFamily: 'Sans', // خط افتراضي جيد للنظام
            fontWeight: FontWeight.w500,
          ),
        ),
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
  List<FileSystemEntity> entries = [];
  // خريطة لتخزين موقع كل أيقونة بناءً على اسم الملف
  Map<String, Offset> iconPositions = {};
  StreamSubscription? _watchSub;
  Timer? _debounceTimer;
  bool _isDraggingExternal = false; // للتمييز بين سحب الملفات الخارجية والتحريك الداخلي
  String wallpaperPath = '';
  late File layoutFile; // ملف حفظ تخطيط سطح المكتب

  @override
  void initState() {
    super.initState();
    _initPaths();
    _loadLayout(); // تحميل المواقع المحفوظة
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
    final configDir = Directory(p.join(home, '.config', 'venom'));
    if (!configDir.existsSync()) configDir.createSync(recursive: true);
    
    wallpaperPath = p.join(configDir.path, 'wallpaper.jpg');
    layoutFile = File(p.join(configDir.path, 'desktop_layout.json'));

    if (!desktopDir.existsSync()) {
      desktopDir.createSync(recursive: true);
    }
  }

  // --- Layout Persistence: حفظ واسترجاع المواقع ---
  void _loadLayout() {
    try {
      if (layoutFile.existsSync()) {
        final content = layoutFile.readAsStringSync();
        final Map<String, dynamic> json = jsonDecode(content);
        setState(() {
          iconPositions = json.map((key, value) => 
              MapEntry(key, Offset((value['x'] as num).toDouble(), (value['y'] as num).toDouble())));
        });
      }
    } catch (e) {
      debugPrint("Error loading layout: $e");
    }
  }

  void _saveLayout() {
    try {
      final json = iconPositions.map((key, value) => 
          MapEntry(key, {'x': value.dx, 'y': value.dy}));
      layoutFile.writeAsStringSync(jsonEncode(json));
    } catch (e) {
      debugPrint("Error saving layout: $e");
    }
  }

  // --- File Watching ---
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
      // تنظيف المواقع القديمة للملفات المحذوفة
      final currentFiles = desktopDir.listSync().map((e) => p.basename(e.path)).toSet();
      iconPositions.removeWhere((key, _) => !currentFiles.contains(key));
      
      setState(() {
        entries = desktopDir.listSync().toList();
      });
    } catch (e) {
      debugPrint("Error refreshing desktop: $e");
    }
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
      case '.jpg': case '.jpeg': case '.png': case '.gif': case '.webp': return Icons.image_rounded;
      case '.mp4': case '.mkv': case '.avi': case '.mov': return Icons.movie_rounded;
      case '.mp3': case '.wav': case '.ogg': return Icons.audiotrack_rounded;
      case '.pdf': return Icons.picture_as_pdf_rounded;
      case '.txt': case '.md': case '.log': case '.cfg': return Icons.description_rounded;
      case '.zip': case '.tar': case '.gz': case '.7z': case '.rar': return Icons.folder_zip_rounded;
      case '.iso': return Icons.album_rounded;
      default: return Icons.insert_drive_file_rounded;
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
              // طبقة 1: الخلفية
              _buildWallpaper(),

              // طبقة 2: الأيقونات الحرة (Free Positioning Icons)
              // نستخدم Stack هنا بدلاً من Wrap للسماح بالحرية المطلقة
              ...entries.asMap().entries.map((entry) {
                return _buildFreeDraggableIcon(entry.value, entry.key);
              }),

              // طبقة 3: تأثير السحب الخارجي
              if (_isDraggingExternal)
                Container(
                  color: Colors.teal.withOpacity(0.15),
                  child: Center(
                    child: Icon(Icons.add_to_photos_rounded, 
                      size: 80, color: Colors.white.withOpacity(0.5)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWallpaper() {
    final file = File(wallpaperPath);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _buildFallbackBackground());
    }
    return _buildFallbackBackground();
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

  // بناء أيقونة قابلة للتحريك الحر
  Widget _buildFreeDraggableIcon(FileSystemEntity entity, int index) {
    final filename = p.basename(entity.path);
    // إذا لم يكن لها موقع محفوظ، نعطيها موقعاً افتراضياً مرتباً
    final position = iconPositions[filename] ?? _getDefaultPosition(index);
    final displayName = filename.endsWith('.desktop') ? filename.replaceAll('.desktop', '') : filename;

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        // هنا سحر التحريك: عند سحب الأيقونة، نحدث موقعها
        onPanUpdate: (details) {
          setState(() {
            // تحديث الموقع بناءً على حركة الماوس
            final newPos = (iconPositions[filename] ?? position) + details.delta;
            // (اختياري) يمكن إضافة حدود لمنع خروج الأيقونة من الشاشة هنا
            iconPositions[filename] = newPos;
          });
        },
        onPanEnd: (_) => _saveLayout(), // حفظ الموقع الجديد عند انتهاء السحب
        
        onDoubleTap: () => _launchEntity(entity),
        child: Container(
          width: 90,
          // لون خلفية شفاف جداً عند التحويم لتحديد العنصر
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.transparent, // يمكن تغييره عند الـ Hover إذا أردت
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getIconForFile(entity.path),
                size: 48,
                color: Colors.white.withOpacity(0.95),
                shadows: const [BoxShadow(blurRadius: 5, color: Colors.black45, offset: Offset(0, 2))],
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
                  style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // حساب موقع افتراضي للأيقونات الجديدة (ترتيب شبكي بسيط)
  Offset _getDefaultPosition(int index) {
    const colCount = 6; // عدد الأيقونات التقريبي في العمود قبل الانتقال للعمود التالي
    const startX = 20.0;
    const startY = 20.0;
    const iconWidth = 100.0;
    const iconHeight = 110.0;

    final row = index % colCount;
    final col = index ~/ colCount;

    return Offset(startX + (col * iconWidth), startY + (row * iconHeight));
  }

  // --- معالجة الإفلات الخارجي ---
  Future<void> _handleExternalDrop(DropDoneDetails details) async {
    setState(() => _isDraggingExternal = false);
    
    // محاولة الحصول على موقع الإفلات (قد لا يكون دقيقاً دائماً حسب نظام التشغيل)
    // إذا لم يتوفر، سنستخدم موقعاً افتراضياً
    // ignore: dead_code
    Offset dropPos = details.localPosition ?? const Offset(100, 100);

    for (int i = 0; i < details.files.length; i++) {
      final file = details.files[i];
      final destPath = p.join(desktopDir.path, p.basename(file.path));
      if (file.path == destPath) continue;

      try {
        await File(file.path).rename(destPath);
        // تعيين موقع الملف الجديد مكان ما تم إفلاته (مع إزاحة بسيطة إذا كانت ملفات متعددة)
        iconPositions[p.basename(destPath)] = dropPos + Offset(i * 20.0, i * 20.0);
      } catch (_) {
        try { await File(file.path).copy(destPath); } catch (_) {}
      }
    }
    _saveLayout();
    _debouncedRefresh();
  }

  // --- القائمة المنبثقة ---
  void _showContextMenu(Offset position) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      color: const Color(0xFF1A1A1A), // لون داكن للقائمة
      elevation: 8,
      items: [
        const PopupMenuItem(value: 'refresh', child: Text('Refresh', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(value: 'wallpaper', child: Text('Change Wallpaper...', style: TextStyle(color: Colors.white))),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'terminal', child: Text('Open Terminal Here', style: TextStyle(color: Colors.white))),
      ],
    );

    if (result == 'refresh') _refreshEntries();
    if (result == 'wallpaper') _showWallpaperDialog();
    if (result == 'terminal') {
      Process.run('exo-open', ['--launch', 'TerminalEmulator', '--working-directory', desktopDir.path]);
    }
    }
  void _showWallpaperDialog() {
    final controller = TextEditingController(text: wallpaperPath);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Set Wallpaper"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Enter full path to image file:"),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: "/home/user/Pictures/wall.jpg",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          FilledButton(
              onPressed: () {
                setState(() {
                  wallpaperPath = controller.text.trim();
                });
                Navigator.pop(ctx);
              },
              child: const Text("Apply")),
        ],
      ),
    );
  }
}









مكتبه مهمه لنضام   apt install libmpv-dev gdk-pixbuf-thumbnailer ffmpegthumbnailer
