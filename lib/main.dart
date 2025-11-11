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
  PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 1; // 50 MB
  PaintingBinding.instance.imageCache.maximumSize = 1;

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
        popupMenuTheme: const PopupMenuThemeData(
          color: Color(0xFF1F1F24),
          elevation: 10,
          shadowColor: Colors.black87,
          textStyle: TextStyle(color: Colors.white, fontSize: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            side: BorderSide(color: Color(0x3322FFFF), width: 1),
          ),
        ),
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
  static const double _gridStartX = 20.0;
  static const double _gridStartY = 20.0;
  static const double _gridCellWidth = 100.0;
  static const double _gridCellHeight = 110.0;

  final Map<String, ImageProvider> thumbnailsCache = {};
  final Map<String, Future<void>> _loadingTasks = {};
  bool _isDraggingExternal = false;
  Key wallpaperKey = UniqueKey();
  bool _showHidden = false;
  _SortMode _sortMode = _SortMode.name;
  String? _draggingPath;
  Offset? _dragOffset;
  String? _hoveredTargetPath;
  final GlobalKey _stackKey = GlobalKey();

  List<String> _applyView(List<String> original) {
    List<String> out = List<String>.from(original);
    if (!_showHidden) {
      out = out.where((e) => !p.basename(e).startsWith('.')).toList();
    }
    switch (_sortMode) {
      case _SortMode.name:
        out.sort((a, b) => p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase()));
        break;
      case _SortMode.type:
        out.sort((a, b) {
          final ea = FileSystemEntity.isDirectorySync(a) ? '0' : p.extension(a).toLowerCase();
          final eb = FileSystemEntity.isDirectorySync(b) ? '0' : p.extension(b).toLowerCase();
          final byExt = ea.compareTo(eb);
          return byExt != 0 ? byExt : p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase());
        });
        break;
      case _SortMode.date:
        out.sort((a, b) {
          DateTime ma, mb;
          try {
            ma = File(a).statSync().modified;
          } catch (_) {
            ma = DateTime.fromMillisecondsSinceEpoch(0);
          }
          try {
            mb = File(b).statSync().modified;
          } catch (_) {
            mb = DateTime.fromMillisecondsSinceEpoch(0);
          }
          return mb.compareTo(ma);
        });
        break;
    }
    return out;
  }

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
    const colCount = 6;
    final row = index % colCount;
    final col = index ~/ colCount;
    return Offset(_gridStartX + (col * _gridCellWidth), _gridStartY + (row * _gridCellHeight));
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
              color: const Color(0xFF1F1F24),
              items: [
                _menuItem(Icons.create_new_folder_rounded, 'New Folder', 'new_folder'),
                _menuItem(Icons.note_add_rounded, 'New File', 'new_file'),
                const PopupMenuDivider(height: 10),
                _menuItem(Icons.auto_awesome_mosaic_rounded, 'Arrange Icons', 'arrange'),
                _menuItem(Icons.sort_by_alpha_rounded, 'Sort by Name', 'sort_name'),
                _menuItem(Icons.category_rounded, 'Sort by Type', 'sort_type'),
                _menuItem(Icons.access_time_rounded, 'Sort by Date', 'sort_date'),
                _menuItem(_showHidden ? Icons.visibility_off_rounded : Icons.visibility_rounded, _showHidden ? 'Hide Hidden Files' : 'Show Hidden Files', 'toggle_hidden'),
                const PopupMenuDivider(height: 10),
                _menuItem(Icons.wallpaper_rounded, 'Change Wallpaper...', 'wallpaper'),
                _menuItem(Icons.terminal_rounded, 'Open Terminal Here', 'terminal'),
                _menuItem(Icons.folder_open_rounded, 'Open in Files', 'open_files'),
                const PopupMenuDivider(height: 10),
                _menuItem(Icons.refresh_rounded, 'Refresh', 'refresh'),
              ],
            );

            if (result == null) return;
            final clickPos = d.localPosition;
            if (result == 'refresh') context.read<DesktopManagerBloc>().add(RefreshDesktopEvent());
            if (result == 'wallpaper') _pickWallpaper();
            if (result == 'terminal') {
              final base = entries.isNotEmpty ? p.dirname(entries.first) : p.join(Platform.environment['HOME'] ?? '.', 'Desktop');
              _openTerminalAt(base);
            }
            if (result == 'open_files') {
              final base = entries.isNotEmpty ? p.dirname(entries.first) : p.join(Platform.environment['HOME'] ?? '.', 'Desktop');
              Process.start('xdg-open', [base], mode: ProcessStartMode.detached);
            }
            if (result == 'new_folder') {
              final name = await _promptName(context, title: 'New Folder Name', initial: 'New Folder');
              if (name != null && name.trim().isNotEmpty) {
                final base = entries.isNotEmpty ? p.dirname(entries.first) : p.join(Platform.environment['HOME'] ?? '.', 'Desktop');
                final dir = Directory(p.join(base, name.trim()));
                if (!dir.existsSync()) {
                  dir.createSync(recursive: true);
                  context.read<DesktopManagerBloc>().add(RefreshDesktopEvent());
                  final snapped = _findNearestFreeSlot(clickPos, p.basename(dir.path), widget.positions);
                  context.read<DesktopManagerBloc>().add(UpdatePositionEvent(filename: p.basename(dir.path), x: snapped.dx, y: snapped.dy));
                }
              }
            }
            if (result == 'new_file') {
              final name = await _promptName(context, title: 'New File Name', initial: 'Untitled.txt');
              if (name != null && name.trim().isNotEmpty) {
                final base = entries.isNotEmpty ? p.dirname(entries.first) : p.join(Platform.environment['HOME'] ?? '.', 'Desktop');
                final file = File(p.join(base, name.trim()));
                if (!file.existsSync()) {
                  file.createSync(recursive: true);
                  context.read<DesktopManagerBloc>().add(RefreshDesktopEvent());
                  final snapped = _findNearestFreeSlot(clickPos, p.basename(file.path), widget.positions);
                  context.read<DesktopManagerBloc>().add(UpdatePositionEvent(filename: p.basename(file.path), x: snapped.dx, y: snapped.dy));
                }
              }
            }
            if (result == 'arrange') {
              _arrangeIcons(entries);
            }
            if (result == 'sort_name') setState(() => _sortMode = _SortMode.name);
            if (result == 'sort_type') setState(() => _sortMode = _SortMode.type);
            if (result == 'sort_date') setState(() => _sortMode = _SortMode.date);
            if (result == 'toggle_hidden') setState(() => _showHidden = !_showHidden);
          },
          behavior: HitTestBehavior.translucent,
          child: Stack(
            key: _stackKey,
            fit: StackFit.expand,
            children: [
              KeyedSubtree(key: wallpaperKey, child: _buildSmartWallpaper()),
              for (int i = 0, n = _applyView(entries).length; i < n; i++)
                _buildFreeDraggableIcon(_applyView(entries)[i], i, widget.positions),
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

  PopupMenuItem<String> _menuItem(IconData icon, String label, String value) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0x2222FFFF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  Future<String?> _promptName(BuildContext context, {required String title, required String initial}) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF23232A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Enter name',
              hintStyle: TextStyle(color: Colors.white54),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.teal)),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: const Text('Create')),
          ],
        );
      },
    );
  }

  void _arrangeIcons(List<String> allEntries) {
    final visible = _applyView(allEntries);
    int col = 0, row = 0;
    const int colCount = 6;
    for (final path in visible) {
      final filename = p.basename(path);
      final target = _offsetForCell(_safeInt(col), _safeInt(row));
      context.read<DesktopManagerBloc>().add(UpdatePositionEvent(filename: filename, x: target.dx, y: target.dy));
      row++;
      if (row % colCount == 0) {
        col++;
        row = 0;
      }
    }
  }

  int _safeInt(int v) => v < 0 ? 0 : v;

  void _openTerminalAt(String workingDir) {
    try {
      final shellCmd = r'''
# Prefer Vater if available
if command -v vater >/dev/null 2>&1; then
  cd "__WD__" && exec vater
fi
# Otherwise try common terminals
TERM_CANDIDATES="$TERMINAL gnome-terminal konsole xfce4-terminal kitty alacritty tilix mate-terminal xterm";
for term in $TERM_CANDIDATES; do
  if [ -n "$term" ] && command -v $term >/dev/null 2>&1; then
    case $term in
      gnome-terminal) exec $term --working-directory "__WD__";;
      konsole) exec $term --workdir "__WD__";;
      xfce4-terminal) exec $term --working-directory "__WD__";;
      kitty) exec $term --directory "__WD__";;
      alacritty) exec $term --working-directory "__WD__";;
      tilix) exec $term --working-directory "__WD__";;
      mate-terminal) exec $term --working-directory "__WD__";;
      xterm) cd "__WD__" && exec $term;;
      *) cd "__WD__" && exec $term;;
    esac
  fi
done
# Xfce fallback
if command -v exo-open >/dev/null 2>&1; then
  exec exo-open --launch TerminalEmulator --working-directory "__WD__"
fi
# Final fallback: user's shell
cd "__WD__" && exec sh -lc "${SHELL:-bash}"
'''.replaceAll('__WD__', workingDir);
      Process.start('sh', ['-lc', shellCmd], mode: ProcessStartMode.detached);
    } catch (_) {}
  }

  // grid snapping helper
  Offset _snapToGrid(Offset raw) {
    final col = ((raw.dx - _gridStartX) / _gridCellWidth).round().clamp(0, 10000);
    final row = ((raw.dy - _gridStartY) / _gridCellHeight).round().clamp(0, 10000);
    return Offset(_gridStartX + col * _gridCellWidth, _gridStartY + row * _gridCellHeight);
  }

  (int col, int row) _cellForOffset(Offset offset) {
    final snapped = _snapToGrid(offset);
    final col = ((snapped.dx - _gridStartX) / _gridCellWidth).round();
    final row = ((snapped.dy - _gridStartY) / _gridCellHeight).round();
    return (col, row);
  }

  Offset _offsetForCell(int col, int row) {
    return Offset(_gridStartX + col * _gridCellWidth, _gridStartY + row * _gridCellHeight);
  }

  bool _isCellOccupied(Offset candidate, Map<String, Map<String, double>> positions, String currentFilename) {
    for (final entry in positions.entries) {
      if (entry.key == currentFilename) continue;
      final pos = entry.value;
      final otherOffset = Offset(pos['x'] ?? 0, pos['y'] ?? 0);
      final otherSnapped = _snapToGrid(otherOffset);
      if ((otherSnapped.dx - candidate.dx).abs() < 0.5 && (otherSnapped.dy - candidate.dy).abs() < 0.5) {
        return true;
      }
    }
    return false;
  }

  Offset _findNearestFreeSlot(Offset desired, String filename, Map<String, Map<String, double>> positions) {
    final snappedDesired = _snapToGrid(desired);
    if (!_isCellOccupied(snappedDesired, positions, filename)) {
      return snappedDesired;
    }

    final (baseCol, baseRow) = _cellForOffset(snappedDesired);
    const int maxRadius = 50;
    for (int radius = 1; radius <= maxRadius; radius++) {
      for (int dx = -radius; dx <= radius; dx++) {
        for (int dy = -radius; dy <= radius; dy++) {
          if (dx.abs() != radius && dy.abs() != radius) continue;
          final col = baseCol + dx;
          final row = baseRow + dy;
          if (col < 0 || row < 0) continue;
          final candidate = _offsetForCell(col, row);
          if (!_isCellOccupied(candidate, positions, filename)) {
            return candidate;
          }
        }
      }
    }
    return snappedDesired;
  }

  String? _findIconAtPosition(Offset localPos, Map<String, Map<String, double>> positions, List<String> visibleEntries) {
    for (int i = 0; i < visibleEntries.length; i++) {
      final entry = visibleEntries[i];
      final filename = p.basename(entry);
      final posMap = positions[filename];
      final basePos = posMap != null ? Offset(posMap['x']!, posMap['y']!) : _getDefaultPosition(i);
      final iconRect = Rect.fromLTWH(basePos.dx, basePos.dy, 90, 110);
      if (iconRect.contains(localPos)) {
        return entry;
      }
    }
    return null;
  }

  Widget _buildFreeDraggableIcon(String path, int index, Map<String, Map<String, double>> positions) {
    final filename = p.basename(path);
    final posMap = positions[filename];
    final basePosition = posMap != null ? Offset(posMap['x']!, posMap['y']!) : _getDefaultPosition(index);
    final displayName = filename.endsWith('.desktop') ? filename.replaceAll('.desktop', '') : filename;
    final isDragging = _draggingPath == path;
    final isTargeted = _hoveredTargetPath == path && _draggingPath != null && _draggingPath != path;
    final position = isDragging && _dragOffset != null
        ? _dragOffset!
        : basePosition;

    _loadThumbnail(path, filename);

    return AnimatedPositioned(
      duration: isDragging ? const Duration(milliseconds: 0) : const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            _draggingPath = path;
            final renderBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
            if (renderBox != null) {
              final localPos = renderBox.globalToLocal(details.globalPosition);
              _dragOffset = localPos - Offset(45, 55);
            } else {
              _dragOffset = basePosition;
            }
          });
        },
        onPanUpdate: (details) {
          final renderBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
          if (renderBox != null) {
            final localPos = renderBox.globalToLocal(details.globalPosition);
            setState(() {
              _dragOffset = localPos - Offset(45, 55);
              _hoveredTargetPath = _findIconAtPosition(localPos, positions, _applyView(widget.entries));
            });
          }
        },
        onPanEnd: (details) {
          final bloc = context.read<DesktopManagerBloc>();
          Map<String, Map<String, double>> existing = positions;
          final state = bloc.state;
          if (state is DesktopLoaded) {
            existing = state.positions;
          }
          
          // Check if dropped on another icon
          if (_hoveredTargetPath != null && _hoveredTargetPath != path) {
            bloc.add(MoveFileEvent(sourcePath: path, targetPath: _hoveredTargetPath!));
          } else {
            // Normal grid snap
            final target = _findNearestFreeSlot(position, filename, existing);
            final currentPos = existing[filename];
            if (currentPos == null ||
                (currentPos['x']! - target.dx).abs() > 0.1 ||
                (currentPos['y']! - target.dy).abs() > 0.1) {
              bloc.add(UpdatePositionEvent(filename: filename, x: target.dx, y: target.dy));
            }
          }
          
          setState(() {
            _draggingPath = null;
            _dragOffset = null;
            _hoveredTargetPath = null;
          });
        },
        onDoubleTap: () => context.read<DesktopManagerBloc>().add(LaunchEntityEvent(path)),
        child: Container(
          width: 90,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isTargeted ? Colors.teal.withOpacity(0.3) : Colors.transparent,
            border: isTargeted ? Border.all(color: Colors.teal, width: 2) : null,
          ),
          child: Opacity(
            opacity: isDragging ? 0.3 : 1.0,
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

enum _SortMode { name, type, date }
// --- Video Wallpaper Widget (Nuclear Disposal) ---
class VideoWallpaper extends StatefulWidget {
  final String videoPath;
  const VideoWallpaper({super.key, required this.videoPath});

  @override
  State<VideoWallpaper> createState() => _VideoWallpaperState();
}

class _VideoWallpaperState extends State<VideoWallpaper>
    with SingleTickerProviderStateMixin {
  Player? player;
  VideoController? controller;
  StreamSubscription<bool>? _completedSubscription;
  bool isRestarting = false;
  late AnimationController fadeController;

  @override
  void initState() {
    super.initState();
    fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..value = 1.0;
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 1024 * 1024, // 1MB buffer for smoother playback
        ),
      );
      controller = VideoController(player!);

      await player!.setVolume(0);
      await player!.setPlaylistMode(PlaylistMode.none);

      await player!.open(
        Media(widget.videoPath),
        play: true,
      );

      // restart on completion from 0.5s instead of full reload
      _completedSubscription =
          player!.stream.completed.listen((bool isCompleted) async {
        if (isCompleted && mounted && !isRestarting) {
          await _restartSmooth();
        }
      });

      setState(() {});
    } catch (e) {
      debugPrint('VideoWallpaper init error: $e');
    }
  }

  Future<void> _restartSmooth() async {
    if (player == null || isRestarting) return;
    isRestarting = true;

    try {
      // Smooth fade out then seek then fade in
      await fadeController.reverse();
      await player!.pause();
      await player!.seek(const Duration(milliseconds: 100)); // ثانيتك 0.5
      await player!.play();
      await fadeController.forward();
    } catch (e) {
      await _hardRestart();
    }

    isRestarting = false;
  }

  Future<void> _hardRestart() async {
    try {
      await player?.dispose();
      player = null;
      controller = null;
      setState(() {});
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) await _initPlayer();
    } catch (_) {}
  }

  @override
  void dispose() {
    _completedSubscription?.cancel();
    player?.dispose();
    fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (player == null || controller == null) {
      return const SizedBox.expand();
    }

    return FadeTransition(
      opacity: fadeController,
      child: SizedBox.expand(
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
      ),
    );
  }
}