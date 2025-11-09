import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'src/presentation/bloc/desktop_manager_bloc.dart';
import 'src/data/desktop_repository_impl.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // إعدادات صارمة لكاش الصور لتقليل استهلاك الرام
  PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 5; // 50 MB
  PaintingBinding.instance.imageCache.maximumSize = 5;

  runApp(
    RepositoryProvider<DesktopRepositoryImpl>(
      create: (_) => DesktopRepositoryImpl(),
      child: BlocProvider(
        create: (ctx) => DesktopManagerBloc(repository: ctx.read<DesktopRepositoryImpl>())..add(LoadDesktopEvent()),
        child: const VenomDesktopApp(),
      ),
    ),
  );
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

class DesktopPage extends StatelessWidget {
  const DesktopPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DesktopManagerBloc, DesktopManagerState>(
      builder: (context, state) {
        if (state is DesktopLoaded) {
          return DesktopView(entries: state.entries, wallpaperPath: state.wallpaperPath, positions: state.positions);
        } else if (state is DesktopLoading || state is DesktopInitial) {
          return const Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(child: CircularProgressIndicator()),
          );
        } else if (state is DesktopError) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Error: ${state.message}'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => context.read<DesktopManagerBloc>().add(LoadDesktopEvent()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class DesktopView extends StatefulWidget {
  final List<String> entries;
  final String wallpaperPath;
  final Map<String, Map<String, double>> positions;

  const DesktopView({super.key, required this.entries, required this.wallpaperPath, required this.positions});

  @override
  State<DesktopView> createState() => _DesktopViewState();
}

class _DesktopViewState extends State<DesktopView> {
  final Map<String, ImageProvider> thumbnailsCache = {};
  final Map<String, Future<void>> _loadingTasks = {};
  bool _isDraggingExternal = false;
  Key wallpaperKey = UniqueKey();

  @override
  void didUpdateWidget(covariant DesktopView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wallpaperPath != widget.wallpaperPath) {
      // force rebuild of wallpaper widget to clear previous image cache
      PaintingBinding.instance.imageCache.clear();
      setState(() => wallpaperKey = UniqueKey());
    }
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
        provider = ResizeImage(FileImage(File(path)), width: 128, policy: ResizeImagePolicy.fit);
      } else if (['.mp4', '.mkv', '.avi', '.mov', '.webm'].contains(ext)) {
        final thumbPath = await VideoThumbnail.thumbnailFile(
          video: path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 128,
          quality: 50,
        );
        if (thumbPath != null) {
          provider = ResizeImage(FileImage(File(thumbPath)), width: 128);
        }
      }
      if (provider != null && mounted) {
        setState(() {
          thumbnailsCache[filename] = provider!;
        });
      }
    } catch (_) {}
  }

  Offset _getDefaultPosition(int index) {
    const colCount = 6, startX = 20.0, startY = 20.0;
    const iconWidth = 100.0, iconHeight = 110.0;
    final row = index % colCount;
    final col = index ~/ colCount;
    return Offset(startX + (col * iconWidth), startY + (row * iconHeight));
  }

  Widget _buildSmartWallpaper() {
    final file = File(widget.wallpaperPath);
    if (!file.existsSync()) return Container(color: const Color(0xFF203A43));

    final ext = p.extension(widget.wallpaperPath).toLowerCase();
    const vids = ['.mp4', '.mkv', '.avi', '.mov', '.webm'];

    if (vids.contains(ext)) {
      return VideoWallpaper(videoPath: widget.wallpaperPath);
    }
    return Image.file(
      file,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => Container(color: const Color(0xFF203A43)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final positions = widget.positions;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DropTarget(
        onDragEntered: (_) => setState(() => _isDraggingExternal = true),
        onDragExited: (_) => setState(() => _isDraggingExternal = false),
        onDragDone: (details) {
          setState(() => _isDraggingExternal = false);
          final paths = details.files.map((f) => f.path).toList();
          final drop = details.localPosition;
          context.read<DesktopManagerBloc>().add(DropFilesEvent(paths: paths, dropX: drop.dx, dropY: drop.dy));
        },
        child: GestureDetector(
          onSecondaryTapUp: (d) async {
            final result = await showMenu<String>(
              context: context,
              position: RelativeRect.fromLTRB(d.globalPosition.dx, d.globalPosition.dy, d.globalPosition.dx, d.globalPosition.dy),
              color: const Color(0xFF2A2A2A),
              items: [
                const PopupMenuItem(value: 'refresh', child: Text('Refresh', style: TextStyle(color: Colors.white))),
                const PopupMenuItem(value: 'wallpaper', child: Text('Change Wallpaper...', style: TextStyle(color: Colors.white))),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'terminal', child: Text('Open Terminal Here', style: TextStyle(color: Colors.white))),
              ],
            );

            if (result == 'refresh') context.read<DesktopManagerBloc>().add(RefreshDesktopEvent());
            if (result == 'wallpaper') _pickWallpaper();
            if (result == 'terminal') {
              final base = entries.isNotEmpty ? p.dirname(entries.first) : p.join(Platform.environment['HOME'] ?? '.', 'Desktop');
              Process.run('exo-open', ['--launch', 'TerminalEmulator', '--working-directory', base]);
            }
          },
          behavior: HitTestBehavior.translucent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              KeyedSubtree(key: wallpaperKey, child: _buildSmartWallpaper()),
              for (int i = 0; i < entries.length; i++)
                _buildFreeDraggableIcon(entries[i], i, positions),
              if (_isDraggingExternal)
                Container(
                  color: Colors.teal.withOpacity(0.15),
                  child: const Center(child: Icon(Icons.add_to_photos_rounded, size: 80, color: Colors.white54)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFreeDraggableIcon(String path, int index, Map<String, Map<String, double>> positions) {
    final filename = p.basename(path);
    final posMap = positions[filename];
    final position = posMap != null ? Offset(posMap['x']!, posMap['y']!) : _getDefaultPosition(index);
    final displayName = filename.endsWith('.desktop') ? filename.replaceAll('.desktop', '') : filename;

    _loadThumbnail(path, filename);

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          final newPos = Offset(position.dx + details.delta.dx, position.dy + details.delta.dy);
          context.read<DesktopManagerBloc>().add(UpdatePositionEvent(filename: filename, x: newPos.dx, y: newPos.dy));
        },
        onDoubleTap: () => context.read<DesktopManagerBloc>().add(LaunchEntityEvent(path)),
        child: Container(
          width: 90,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.transparent),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: thumbnailsCache.containsKey(filename)
                    ? Image(key: ValueKey('thumb-$filename'), image: thumbnailsCache[filename]!, width: 48, height: 48, fit: BoxFit.cover, gaplessPlayback: true)
                    : Icon(_getIconForFile(path), key: ValueKey('icon-$filename'), size: 48, color: Colors.white.withOpacity(0.9)),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.25), borderRadius: BorderRadius.circular(4)),
                child: Text(displayName, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.1)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickWallpaper() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'mp4', 'mkv', 'avi', 'mov', 'webm'],
      );

      if (result != null && result.files.single.path != null) {
        PaintingBinding.instance.imageCache.clear();
        final path = result.files.single.path!;
        context.read<DesktopManagerBloc>().add(SetWallpaperEvent(path));
      }
    } catch (_) {}
  }
}

// --- Video Wallpaper Widget (Nuclear Disposal) ---
class VideoWallpaper extends StatefulWidget {
  final String videoPath;
  const VideoWallpaper({super.key, required this.videoPath});

  @override
  State<VideoWallpaper> createState() => _VideoWallpaperState();
}

class _VideoWallpaperState extends State<VideoWallpaper> {
  Player? player;
  VideoController? controller;
  StreamSubscription<bool>? _completedSubscription;
  bool isRestarting = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    if (!mounted) return;
    player = Player(
        configuration: const PlayerConfiguration(
            bufferSize: 1024 * 512, // بافر صغير جداً (0.5 ميجا)
        ));
    controller = VideoController(player!);
    
    player!.setVolume(0);
    player!.setPlaylistMode(PlaylistMode.none);

    await player!.open(Media(widget.videoPath, extras: {
      'mpv': {'cache': 'no', 'demuxer-max-bytes': '128KiB'}
    }));

    _completedSubscription = player!.stream.completed.listen((bool isCompleted) {
      if (isCompleted && mounted && !isRestarting) {
        _nukeAndRestart();
      }
    });

    if (mounted) setState(() {});
  }

  Future<void> _nukeAndRestart() async {
    isRestarting = true;
    await player?.dispose();
    player = null;
    controller = null;
    if (mounted) setState(() {});
    await Future.delayed(const Duration(milliseconds: 50));
    if (mounted) {
      await _initPlayer();
      isRestarting = false;
    }
  }

  @override
  void dispose() {
    _completedSubscription?.cancel();
    player?.stop();
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (player == null || controller == null) return const SizedBox();
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          child: Video(
            
            controller: controller!,
            fit: BoxFit.cover,
            controls: NoVideoControls,
          ),
        ),
      ),
    );
  }
}