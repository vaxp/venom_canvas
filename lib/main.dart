import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/gestures.dart';
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
  PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 1;
  PaintingBinding.instance.imageCache.maximumSize = 1;

  runApp(
    RepositoryProvider<DesktopRepositoryImpl>(
      create: (_) => DesktopRepositoryImpl(),
      child: BlocProvider(
        create: (ctx) =>
            DesktopManagerBloc(repository: ctx.read<DesktopRepositoryImpl>())
              ..add(LoadDesktopEvent()),
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
          return DesktopView(
            entries: state.entries,
            wallpaperPath: state.wallpaperPath,
            positions: state.positions,
          );
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
                    onPressed: () => context.read<DesktopManagerBloc>().add(
                      LoadDesktopEvent(),
                    ),
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

  const DesktopView({
    super.key,
    required this.entries,
    required this.wallpaperPath,
    required this.positions,
  });

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
  _SortMode _sortMode = _SortMode.nameAsc;
  String? _draggingPath;
  Offset? _dragOffset;
  String? _hoveredTargetPath;
  final GlobalKey _stackKey = GlobalKey();
  OverlayEntry? _contextMenuEntry;
  Offset? _lastContextTapLocal;
  String? _contextMenuTargetPath;
  bool _isSelecting = false;
  Offset? _selectionStart;
  Offset? _selectionEnd;
  final Set<String> _selectedPaths = <String>{};

  List<String> _applyView(List<String> original) {
    List<String> out = List<String>.from(original);
    if (!_showHidden) {
      out = out.where((e) => !p.basename(e).startsWith('.')).toList();
    }
    switch (_sortMode) {
      case _SortMode.nameAsc:
        out.sort(
          (a, b) => p
              .basename(a)
              .toLowerCase()
              .compareTo(p.basename(b).toLowerCase()),
        );
        break;
      case _SortMode.nameDesc:
        out.sort(
          (a, b) => p
              .basename(b)
              .toLowerCase()
              .compareTo(p.basename(a).toLowerCase()),
        );
        break;
      case _SortMode.type:
        out.sort((a, b) {
          final ea = FileSystemEntity.isDirectorySync(a)
              ? '0'
              : p.extension(a).toLowerCase();
          final eb = FileSystemEntity.isDirectorySync(b)
              ? '0'
              : p.extension(b).toLowerCase();
          final byExt = ea.compareTo(eb);
          return byExt != 0
              ? byExt
              : p
                    .basename(a)
                    .toLowerCase()
                    .compareTo(p.basename(b).toLowerCase());
        });
        break;
      case _SortMode.modifiedDesc:
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
      case _SortMode.sizeDesc:
        out.sort((a, b) {
          final sa = _entitySize(a);
          final sb = _entitySize(b);
          if (sb != sa) return sb.compareTo(sa);
          return p
              .basename(a)
              .toLowerCase()
              .compareTo(p.basename(b).toLowerCase());
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
    final visibleSet = _applyView(widget.entries).toSet();
    _selectedPaths.removeWhere((path) => !visibleSet.contains(path));
  }

  @override
  void dispose() {
    _removeContextMenu();
    super.dispose();
  }

  void _removeContextMenu() {
    _contextMenuEntry?.remove();
    _contextMenuEntry = null;
    _contextMenuTargetPath = null;
  }

  void _showContextMenu(
    Offset globalPosition, {
    List<_ContextMenuItem>? items,
    String? targetPath,
  }) {
    _removeContextMenu();
    _contextMenuTargetPath = targetPath;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;

    final anchor = overlayBox.globalToLocal(globalPosition);
    final entry = OverlayEntry(
      builder: (ctx) => _GlassContextMenu(
        anchor: anchor,
        items: items ?? _buildDesktopContextMenuItems(),
        onClose: _removeContextMenu,
        onAction: (action) => _handleContextMenuAction(action),
      ),
    );
    overlay.insert(entry);
    _contextMenuEntry = entry;
  }

  List<_ContextMenuItem> _buildDesktopContextMenuItems() {
    final bool canPaste = false; 

    return [
      _ContextMenuItem.action(
        id: 'new_folder',
        icon: Icons.create_new_folder_rounded,
        label: 'New Folder',
      ),
      _ContextMenuItem.action(
        id: 'new_document',
        icon: Icons.note_add_rounded,
        label: 'New Document',
        children: const [
          _ContextMenuItem.action(
            id: 'new_document:c',
            icon: Icons.code_rounded,
            label: 'C',
          ),
          _ContextMenuItem.action(
            id: 'new_document:cpp',
            icon: Icons.developer_mode_rounded,
            label: 'C++',
          ),
          _ContextMenuItem.action(
            id: 'new_document:dart',
            icon: Icons.flutter_dash_rounded,
            label: 'Dart',
          ),
          _ContextMenuItem.action(
            id: 'new_document:markdown',
            icon: Icons.article_outlined,
            label: 'Markdown',
          ),
          _ContextMenuItem.action(
            id: 'new_document:python',
            icon: Icons.developer_board_rounded,
            label: 'Python',
          ),
          _ContextMenuItem.action(
            id: 'new_document:text',
            icon: Icons.description_rounded,
            label: 'Text',
          ),
        ],
      ),
      const _ContextMenuItem.divider(),
      _ContextMenuItem.action(
        id: 'paste',
        icon: Icons.content_paste_rounded,
        label: 'Paste',
        enabled: canPaste,
      ),
      _ContextMenuItem.action(
        id: 'select_all',
        icon: Icons.select_all_rounded,
        label: 'Select All',
      ),
      const _ContextMenuItem.divider(),
      _ContextMenuItem.action(
        id: 'arrange_icons',
        icon: Icons.auto_awesome_mosaic_rounded,
        label: 'Arrange Icons',
      ),
      _ContextMenuItem.action(
        id: 'arrange_by',
        icon: Icons.sort_rounded,
        label: 'Arrange By...',
        children: [
          _ContextMenuItem.action(
            id: 'arrange_keep',
            icon: Icons.grid_on_rounded,
            label: 'Keep Arranged',
          ),
          _ContextMenuItem.action(
            id: 'arrange_stack_type',
            icon: Icons.layers_rounded,
            label: 'Keep Stacked by Type',
            enabled: false,
          ),
          _ContextMenuItem.action(
            id: 'sort_special',
            icon: Icons.storage_rounded,
            label: 'Sort Home/Drives/Trash',
            enabled: false,
          ),
          _ContextMenuItem.action(
            id: 'sort_name',
            icon: Icons.sort_by_alpha_rounded,
            label: 'Sort by Name',
            isActive: _sortMode == _SortMode.nameAsc,
          ),
          _ContextMenuItem.action(
            id: 'sort_name_desc',
            icon: Icons.sort_by_alpha_outlined,
            label: 'Sort by Name Descending',
            isActive: _sortMode == _SortMode.nameDesc,
          ),
          _ContextMenuItem.action(
            id: 'sort_modified',
            icon: Icons.access_time_rounded,
            label: 'Sort by Modified Time',
            isActive: _sortMode == _SortMode.modifiedDesc,
          ),
          _ContextMenuItem.action(
            id: 'sort_type',
            icon: Icons.category_rounded,
            label: 'Sort by Type',
            isActive: _sortMode == _SortMode.type,
          ),
          _ContextMenuItem.action(
            id: 'sort_size',
            icon: Icons.bar_chart_rounded,
            label: 'Sort by Size',
            isActive: _sortMode == _SortMode.sizeDesc,
          ),
          _ContextMenuItem.action(
            id: 'toggle_hidden',
            icon: _showHidden
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
            label: _showHidden ? 'Hide Hidden Files' : 'Show Hidden Files',
            isChecked: _showHidden,
          ),
        ],
      ),
      const _ContextMenuItem.divider(),
      _ContextMenuItem.action(
        id: 'show_desktop_files',
        icon: Icons.folder_open_rounded,
        label: 'Show Desktop in Files',
      ),
      _ContextMenuItem.action(
        id: 'open_terminal',
        icon: Icons.terminal_rounded,
        label: 'Open in Terminal',
      ),
      _ContextMenuItem.action(
        id: 'change_background',
        icon: Icons.wallpaper_rounded,
        label: 'Change Background...',
      ),
      _ContextMenuItem.action(
        id: 'desktop_icons_settings',
        icon: Icons.grid_view_rounded,
        label: 'Desktop Icons Settings',
      ),
      _ContextMenuItem.action(
        id: 'display_settings',
        icon: Icons.monitor_rounded,
        label: 'Display Settings',
      ),
    ];
  }

  List<_ContextMenuItem> _buildEntityContextMenuItems(String path) {
    final bool canPaste = false; // TODO: wire clipboard operations.

    return [
      _ContextMenuItem.action(
        id: 'entity:rename',
        icon: Icons.drive_file_rename_outline,
        label: 'Rename',
      ),
      _ContextMenuItem.action(
        id: 'entity:delete',
        icon: Icons.delete_rounded,
        label: 'Delete',
      ),
      const _ContextMenuItem.divider(),
      _ContextMenuItem.action(
        id: 'entity:cut',
        icon: Icons.content_cut_rounded,
        label: 'Cut',
        enabled: false,
      ),
      _ContextMenuItem.action(
        id: 'entity:copy',
        icon: Icons.content_copy_rounded,
        label: 'Copy',
        enabled: false,
      ),
      _ContextMenuItem.action(
        id: 'entity:paste',
        icon: Icons.content_paste_rounded,
        label: 'Paste',
        enabled: canPaste,
      ),
      const _ContextMenuItem.divider(),
      _ContextMenuItem.action(
        id: 'entity:details',
        icon: Icons.info_outline,
        label: 'Details',
      ),
    ];
  }

  Future<void> _handleContextMenuAction(String action) async {
    _removeContextMenu();
    final clickPos =
        _lastContextTapLocal ??
        const Offset(_gridStartX + 40, _gridStartY + 40);
    final baseDir = _desktopRoot();

    switch (action) {
      case 'new_folder':
        await _createFolder(baseDir, clickPos);
        break;
      case 'new_document:c':
        await _createDocument(
          baseDir,
          clickPos,
          suggestedName: 'main.c',
          template: _Templates.c,
        );
        break;
      case 'new_document:cpp':
        await _createDocument(
          baseDir,
          clickPos,
          suggestedName: 'main.cpp',
          template: _Templates.cpp,
        );
        break;
      case 'new_document:dart':
        await _createDocument(
          baseDir,
          clickPos,
          suggestedName: 'main.dart',
          template: _Templates.dart,
        );
        break;
      case 'new_document:markdown':
        await _createDocument(
          baseDir,
          clickPos,
          suggestedName: 'notes.md',
          template: _Templates.markdown,
        );
        break;
      case 'new_document:python':
        await _createDocument(
          baseDir,
          clickPos,
          suggestedName: 'main.py',
          template: _Templates.python,
        );
        break;
      case 'new_document:text':
        await _createDocument(
          baseDir,
          clickPos,
          suggestedName: 'Untitled.txt',
          template: '',
        );
        break;
      case 'paste':
        _showUnavailable('Paste');
        break;
      case 'select_all':
        _showUnavailable('Select all');
        break;
      case 'arrange_icons':
      case 'arrange_keep':
        _arrangeIcons(widget.entries);
        break;
      case 'arrange_stack_type':
      case 'sort_special':
        _showUnavailable('This sorting mode');
        break;
      case 'sort_name':
        setState(() => _sortMode = _SortMode.nameAsc);
        break;
      case 'sort_name_desc':
        setState(() => _sortMode = _SortMode.nameDesc);
        break;
      case 'sort_modified':
        setState(() => _sortMode = _SortMode.modifiedDesc);
        break;
      case 'sort_type':
        setState(() => _sortMode = _SortMode.type);
        break;
      case 'sort_size':
        setState(() => _sortMode = _SortMode.sizeDesc);
        break;
      case 'toggle_hidden':
        setState(() => _showHidden = !_showHidden);
        break;
      case 'show_desktop_files':
        _openDesktopInFiles();
        break;
      case 'open_terminal':
        _openTerminalAt(baseDir);
        break;
      case 'change_background':
        await _pickWallpaper();
        break;
      case 'desktop_icons_settings':
        _showUnavailable('Desktop icons settings');
        break;
      case 'display_settings':
        await _launchDisplaySettings();
        break;
      case 'entity:rename':
        final renameTarget =
            _contextMenuTargetPath != null ? p.basename(_contextMenuTargetPath!) : null;
        _showUnavailable(
          renameTarget != null ? 'Rename "$renameTarget"' : 'Rename',
        );
        break;
      case 'entity:delete':
        final deleteTarget =
            _contextMenuTargetPath != null ? p.basename(_contextMenuTargetPath!) : null;
        _showUnavailable(
          deleteTarget != null ? 'Delete "$deleteTarget"' : 'Delete',
        );
        break;
      case 'entity:cut':
        _showUnavailable('Cut');
        break;
      case 'entity:copy':
        _showUnavailable('Copy');
        break;
      case 'entity:paste':
        _showUnavailable('Paste');
        break;
      case 'entity:details':
        _showUnavailable('Details');
        break;
      default:
        break;
    }
  }

  String _desktopRoot() {
    if (widget.entries.isNotEmpty) {
      final first = widget.entries.first;
      return p.dirname(first);
    }
    final home = Platform.environment['HOME'] ?? Directory.current.path;
    return p.join(home, 'Desktop');
  }

  Future<void> _createFolder(String baseDir, Offset clickPos) async {
    final name = await _promptName(
      context,
      title: 'New Folder Name',
      initial: 'New Folder',
    );
    final value = name?.trim();
    if (value == null || value.isEmpty) return;

    final uniqueName = _ensureUniqueName(baseDir, value, isDirectory: true);
    final dir = Directory(p.join(baseDir, uniqueName));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _afterEntityCreated(dir.path, clickPos);
  }

  Future<void> _createDocument(
    String baseDir,
    Offset clickPos, {
    required String suggestedName,
    required String template,
  }) async {
    final name = await _promptName(
      context,
      title: 'New Document Name',
      initial: suggestedName,
    );
    final value = name?.trim();
    if (value == null || value.isEmpty) return;

    final uniqueName = _ensureUniqueName(baseDir, value, isDirectory: false);
    final file = File(p.join(baseDir, uniqueName));
    if (!file.existsSync()) {
      file.createSync(recursive: true);
    }
    if (template.isNotEmpty) {
      try {
        file.writeAsStringSync(template);
      } catch (_) {}
    }
    _afterEntityCreated(file.path, clickPos);
  }

  void _afterEntityCreated(String entityPath, Offset clickPos) {
    context.read<DesktopManagerBloc>().add(RefreshDesktopEvent());
    final snapped = _findNearestFreeSlot(
      clickPos,
      p.basename(entityPath),
      widget.positions,
    );
    context.read<DesktopManagerBloc>().add(
      UpdatePositionEvent(
        filename: p.basename(entityPath),
        x: snapped.dx,
        y: snapped.dy,
      ),
    );
  }

  String _ensureUniqueName(
    String baseDir,
    String desired, {
    required bool isDirectory,
  }) {
    String candidate = desired;
    String fullPath = p.join(baseDir, candidate);
    if (!_entityExists(fullPath)) {
      return candidate;
    }

    final extension = isDirectory ? '' : p.extension(candidate);
    final baseName = extension.isEmpty
        ? candidate
        : candidate.substring(0, candidate.length - extension.length);
    int counter = 1;
    while (_entityExists(p.join(baseDir, '$baseName ($counter)$extension'))) {
      counter++;
    }
    return '$baseName ($counter)$extension';
  }

  bool _entityExists(String path) {
    return FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.notFound;
  }

  int _entitySize(String path) {
    try {
      if (FileSystemEntity.isDirectorySync(path)) {
        return 0;
      }
      return File(path).statSync().size;
    } catch (_) {
      return 0;
    }
  }

  void _showUnavailable(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature is not available yet.'),
        backgroundColor: Colors.black.withOpacity(0.85),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openDesktopInFiles() {
    try {
      Process.start('xdg-open', [
        _desktopRoot(),
      ], mode: ProcessStartMode.detached);
    } catch (_) {
      _showUnavailable('File manager');
    }
  }

  Future<void> _launchDisplaySettings() async {
    const commandCandidates = [
      ['gnome-control-center', 'display'],
      ['gnome-control-center', 'monitors'],
      ['plasma-settings', 'kcm_kscreen'],
      ['kscreen'],
      ['xfce4-display-settings'],
      ['lxqt-config-monitor'],
      ['mate-control-center', 'display'],
      ['cinnamon-settings', 'display'],
    ];

    for (final candidate in commandCandidates) {
      try {
        await Process.start(
          candidate.first,
          candidate.length > 1 ? candidate.sublist(1) : const [],
          mode: ProcessStartMode.detached,
        );
        return;
      } catch (_) {
        continue;
      }
    }
    _showUnavailable('Display settings');
  }

  // keep existing methods ...

  IconData _getIconForFile(String path) {
    if (FileSystemEntity.isDirectorySync(path)) return Icons.rule_folder_sharp;
    final ext = p.extension(path).toLowerCase();
    if (path.endsWith('.desktop')) return Icons.rocket_launch_rounded;
    switch (ext) {
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
      case '.webp':
        return Icons.image_rounded;
      case '.mp4':
      case '.mkv':
      case '.avi':
      case '.mov':
      case '.webm':
        return Icons.movie_rounded;
      case '.mp3':
      case '.wav':
      case '.ogg':
        return Icons.audiotrack_rounded;
      case '.pdf':
        return Icons.picture_as_pdf_rounded;
      case '.txt':
      case '.md':
      case '.log':
      case '.cfg':
        return Icons.description_rounded;
      case '.zip':
      case '.tar':
      case '.gz':
      case '.7z':
      case '.rar':
        return Icons.folder_zip_rounded;
      case '.iso':
        return Icons.album_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Future<void> _loadThumbnail(String path, String filename) async {
    if (thumbnailsCache.containsKey(filename) ||
        _loadingTasks.containsKey(filename))
      return;
    _loadingTasks[filename] = _generateThumbnail(path, filename).whenComplete(
      () {
        _loadingTasks.remove(filename);
      },
    );
  }

  Future<void> _generateThumbnail(String path, String filename) async {
    final ext = p.extension(path).toLowerCase();
    ImageProvider? provider;

    try {
      if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext)) {
        provider = ResizeImage(
          FileImage(File(path)),
          width: 128,
          policy: ResizeImagePolicy.fit,
        );
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
    return Offset(
      _gridStartX + (col * _gridCellWidth),
      _gridStartY + (row * _gridCellHeight),
    );
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
    final visibleEntries = _applyView(entries);
    final Rect? selectionRect = _currentSelectionRect;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DropTarget(
        onDragEntered: (_) => setState(() => _isDraggingExternal = true),
        onDragExited: (_) => setState(() => _isDraggingExternal = false),
        onDragDone: (details) {
          setState(() => _isDraggingExternal = false);
          final paths = details.files.map((f) => f.path).toList();
          final drop = details.localPosition;
          context.read<DesktopManagerBloc>().add(
            DropFilesEvent(paths: paths, dropX: drop.dx, dropY: drop.dy),
          );
        },
        child: GestureDetector(
          onSecondaryTapUp: (details) {
            _lastContextTapLocal = details.localPosition;
            _showContextMenu(
              details.globalPosition,
              targetPath: null,
            );
          },
          behavior: HitTestBehavior.translucent,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _handleDesktopPointerDown,
            onPointerMove: _handleDesktopPointerMove,
            onPointerUp: _handleDesktopPointerUp,
            onPointerCancel: _handleDesktopPointerCancel,
            child: Stack(
              key: _stackKey,
              fit: StackFit.expand,
              children: [
                KeyedSubtree(key: wallpaperKey, child: _buildSmartWallpaper()),
                for (int i = 0, n = visibleEntries.length; i < n; i++)
                  _buildFreeDraggableIcon(
                    visibleEntries[i],
                    i,
                    widget.positions,
                  ),
                if (_isSelecting && selectionRect != null)
                  Positioned.fromRect(
                    rect: selectionRect,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.tealAccent.withOpacity(0.75),
                            width: 1.2,
                          ),
                          color: Colors.tealAccent.withOpacity(0.15),
                        ),
                      ),
                    ),
                  ),
                if (_isDraggingExternal)
                  Container(
                    color: Colors.teal.withOpacity(0.15),
                    child: const Center(
                      child: Icon(
                        Icons.add_to_photos_rounded,
                        size: 80,
                        color: Colors.white54,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<String?> _promptName(
    BuildContext context, {
    required String title,
    required String initial,
  }) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF23232A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Enter name',
              hintStyle: TextStyle(color: Colors.white54),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.teal),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('Create'),
            ),
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
      context.read<DesktopManagerBloc>().add(
        UpdatePositionEvent(filename: filename, x: target.dx, y: target.dy),
      );
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
      final shellCmd =
          r'''
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
'''
              .replaceAll('__WD__', workingDir);
      Process.start('sh', ['-lc', shellCmd], mode: ProcessStartMode.detached);
    } catch (_) {}
  }

  // grid snapping helper
  Offset _snapToGrid(Offset raw) {
    final col = ((raw.dx - _gridStartX) / _gridCellWidth).round().clamp(
      0,
      10000,
    );
    final row = ((raw.dy - _gridStartY) / _gridCellHeight).round().clamp(
      0,
      10000,
    );
    return Offset(
      _gridStartX + col * _gridCellWidth,
      _gridStartY + row * _gridCellHeight,
    );
  }

  (int col, int row) _cellForOffset(Offset offset) {
    final snapped = _snapToGrid(offset);
    final col = ((snapped.dx - _gridStartX) / _gridCellWidth).round();
    final row = ((snapped.dy - _gridStartY) / _gridCellHeight).round();
    return (col, row);
  }

  Offset _offsetForCell(int col, int row) {
    return Offset(
      _gridStartX + col * _gridCellWidth,
      _gridStartY + row * _gridCellHeight,
    );
  }

  bool _isCellOccupied(
    Offset candidate,
    Map<String, Map<String, double>> positions,
    String currentFilename,
  ) {
    for (final entry in positions.entries) {
      if (entry.key == currentFilename) continue;
      final pos = entry.value;
      final otherOffset = Offset(pos['x'] ?? 0, pos['y'] ?? 0);
      final otherSnapped = _snapToGrid(otherOffset);
      if ((otherSnapped.dx - candidate.dx).abs() < 0.5 &&
          (otherSnapped.dy - candidate.dy).abs() < 0.5) {
        return true;
      }
    }
    return false;
  }

  Offset _findNearestFreeSlot(
    Offset desired,
    String filename,
    Map<String, Map<String, double>> positions,
  ) {
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

  Rect _iconRectForEntry(
    String path,
    int index,
    Map<String, Map<String, double>> positions,
  ) {
    final filename = p.basename(path);
    final posMap = positions[filename];
    final basePos = posMap != null
        ? Offset(posMap['x'] ?? 0, posMap['y'] ?? 0)
        : _getDefaultPosition(index);
    return Rect.fromLTWH(basePos.dx, basePos.dy, 90, 110);
  }

  Rect _normalizedRect(Offset start, Offset end) {
    final left = math.min(start.dx, end.dx);
    final top = math.min(start.dy, end.dy);
    final right = math.max(start.dx, end.dx);
    final bottom = math.max(start.dy, end.dy);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Rect? get _currentSelectionRect {
    if (!_isSelecting || _selectionStart == null || _selectionEnd == null) {
      return null;
    }
    final rect = _normalizedRect(_selectionStart!, _selectionEnd!);
    if (rect.width <= 0 || rect.height <= 0) return null;
    return rect;
  }

  String? _findIconAtPosition(
    Offset localPos,
    Map<String, Map<String, double>> positions,
    List<String> visibleEntries,
  ) {
    for (int i = 0; i < visibleEntries.length; i++) {
      final entry = visibleEntries[i];
      final iconRect = _iconRectForEntry(entry, i, positions);
      if (iconRect.contains(localPos)) {
        return entry;
      }
    }
    return null;
  }

  void _updateSelectionRect(Offset current) {
    if (_selectionStart == null) return;
    final rect = _normalizedRect(_selectionStart!, current);
    final visibleEntries = _applyView(widget.entries);
    final Set<String> newlySelected = <String>{};
    for (int i = 0; i < visibleEntries.length; i++) {
      final candidateRect = _iconRectForEntry(
        visibleEntries[i],
        i,
        widget.positions,
      );
      if (candidateRect.isEmpty) {
        continue;
      }
      if (rect.overlaps(candidateRect)) {
        newlySelected.add(visibleEntries[i]);
      }
    }
    setState(() {
      _selectionEnd = current;
      _selectedPaths
        ..clear()
        ..addAll(newlySelected);
    });
  }

  void _endSelection() {
    if (!_isSelecting) return;
    setState(() {
      _isSelecting = false;
      _selectionStart = null;
      _selectionEnd = null;
    });
  }

  void _handleDesktopPointerDown(PointerDownEvent event) {
    if ((event.buttons & kPrimaryMouseButton) == 0) return;
    _removeContextMenu();
    final local = event.localPosition;
    final visibleEntries = _applyView(widget.entries);
    final hit = _findIconAtPosition(local, widget.positions, visibleEntries);
    if (hit == null) {
      setState(() {
        _isSelecting = true;
        _selectionStart = local;
        _selectionEnd = local;
        _selectedPaths.clear();
      });
    } else {
      setState(() {
        _isSelecting = false;
        _selectionStart = null;
        _selectionEnd = null;
        _selectedPaths
          ..clear()
          ..add(hit);
      });
    }
  }

  void _handleDesktopPointerMove(PointerMoveEvent event) {
    if (!_isSelecting || _selectionStart == null) return;
    if ((event.buttons & kPrimaryMouseButton) == 0) {
      _endSelection();
      return;
    }
    _updateSelectionRect(event.localPosition);
  }

  void _handleDesktopPointerUp(PointerUpEvent event) {
    if (_isSelecting) {
      _endSelection();
    }
  }

  void _handleDesktopPointerCancel(PointerCancelEvent event) {
    if (_isSelecting) {
      _endSelection();
    }
  }

  Widget _buildFreeDraggableIcon(
    String path,
    int index,
    Map<String, Map<String, double>> positions,
  ) {
    final filename = p.basename(path);
    final posMap = positions[filename];
    final basePosition = posMap != null
        ? Offset(posMap['x']!, posMap['y']!)
        : _getDefaultPosition(index);
    final displayName = filename.endsWith('.desktop')
        ? filename.replaceAll('.desktop', '')
        : filename;
    final isDragging = _draggingPath == path;
    final isTargeted =
        _hoveredTargetPath == path &&
        _draggingPath != null &&
        _draggingPath != path;
    final isSelected = _selectedPaths.contains(path);
    final position = isDragging && _dragOffset != null
        ? _dragOffset!
        : basePosition;

    _loadThumbnail(path, filename);

    return AnimatedPositioned(
      duration: isDragging
          ? const Duration(milliseconds: 0)
          : const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onSecondaryTapUp: (details) {
          final renderBox =
              _stackKey.currentContext?.findRenderObject() as RenderBox?;
          final localTap = renderBox != null
              ? renderBox.globalToLocal(details.globalPosition)
              : details.localPosition;

          setState(() {
            _selectedPaths
              ..clear()
              ..add(path);
          });

          _lastContextTapLocal = localTap;
          _showContextMenu(
            details.globalPosition,
            items: _buildEntityContextMenuItems(path),
            targetPath: path,
          );
        },
        onPanStart: (details) {
          setState(() {
            _draggingPath = path;
            final renderBox =
                _stackKey.currentContext?.findRenderObject() as RenderBox?;
            if (renderBox != null) {
              final localPos = renderBox.globalToLocal(details.globalPosition);
              _dragOffset = localPos - Offset(45, 55);
            } else {
              _dragOffset = basePosition;
            }
          });
        },
        onPanUpdate: (details) {
          final renderBox =
              _stackKey.currentContext?.findRenderObject() as RenderBox?;
          if (renderBox != null) {
            final localPos = renderBox.globalToLocal(details.globalPosition);
            setState(() {
              _dragOffset = localPos - Offset(45, 55);
              _hoveredTargetPath = _findIconAtPosition(
                localPos,
                positions,
                _applyView(widget.entries),
              );
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
            bloc.add(
              MoveFileEvent(sourcePath: path, targetPath: _hoveredTargetPath!),
            );
          } else {
            // Normal grid snap
            final target = _findNearestFreeSlot(position, filename, existing);
            final currentPos = existing[filename];
            if (currentPos == null ||
                (currentPos['x']! - target.dx).abs() > 0.1 ||
                (currentPos['y']! - target.dy).abs() > 0.1) {
              bloc.add(
                UpdatePositionEvent(
                  filename: filename,
                  x: target.dx,
                  y: target.dy,
                ),
              );
            }
          }

          setState(() {
            _draggingPath = null;
            _dragOffset = null;
            _hoveredTargetPath = null;
          });
        },
        onDoubleTap: () =>
            context.read<DesktopManagerBloc>().add(LaunchEntityEvent(path)),
        child: Container(
          width: 90,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isTargeted
                ? Colors.teal.withOpacity(0.3)
                : isSelected
                ? Colors.white.withOpacity(0.1)
                : Colors.transparent,
            border: isTargeted
                ? Border.all(color: Colors.teal, width: 2)
                : isSelected
                ? Border.all(
                    color: Colors.tealAccent.withOpacity(0.7),
                    width: 1.2,
                  )
                : null,
          ),
          child: Opacity(
            opacity: isDragging ? 0.3 : 1.0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: thumbnailsCache.containsKey(filename)
                      ? Image(
                          key: ValueKey('thumb-$filename'),
                          image: thumbnailsCache[filename]!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        )
                      : Icon(
                          _getIconForFile(path),
                          key: ValueKey('icon-$filename'),
                          size: 48,
                          color: isSelected
                              ? Colors.white
                              : Colors.white.withOpacity(0.9),
                        ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.tealAccent.withOpacity(0.25)
                        : Colors.black.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    displayName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      height: 1.1,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
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
        allowedExtensions: [
          'jpg',
          'jpeg',
          'png',
          'gif',
          'webp',
          'mp4',
          'mkv',
          'avi',
          'mov',
          'webm',
        ],
      );

      if (result != null && result.files.single.path != null) {
        PaintingBinding.instance.imageCache.clear();
        final path = result.files.single.path!;
        context.read<DesktopManagerBloc>().add(SetWallpaperEvent(path));
      }
    } catch (_) {}
  }
}

class _ContextMenuItem {
  const _ContextMenuItem.action({
    required this.id,
    required this.label,
    this.icon,
    this.enabled = true,
    this.children = const [],
    this.isActive = false,
    this.isChecked,
  }) : isDivider = false;

  const _ContextMenuItem.divider()
    : id = null,
      label = '',
      icon = null,
      enabled = false,
      children = const [],
      isDivider = true,
      isActive = false,
      isChecked = null;

  final String? id;
  final String label;
  final IconData? icon;
  final bool enabled;
  final List<_ContextMenuItem> children;
  final bool isDivider;
  final bool isActive;
  final bool? isChecked;

  bool get hasSubmenu => children.isNotEmpty;
}

class _GlassContextMenu extends StatefulWidget {
  const _GlassContextMenu({
    required this.anchor,
    required this.items,
    required this.onClose,
    required this.onAction,
  });

  final Offset anchor;
  final List<_ContextMenuItem> items;
  final VoidCallback onClose;
  final Future<void> Function(String action) onAction;

  @override
  State<_GlassContextMenu> createState() => _GlassContextMenuState();
}

class _GlassContextMenuState extends State<_GlassContextMenu> {
  static const double _menuWidth = 240;
  static const double _itemHeight = 38;
  static const double _menuPaddingV = 14;

  _ContextMenuItem? _hoveredItem;
  _ContextMenuItem? _activeSubmenu;
  Offset? _submenuOffset;
  Timer? _submenuCloseTimer;
  bool _submenuPinned = false;

  @override
  void dispose() {
    _submenuCloseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final estimatedHeight = _estimateHeight(widget.items);

    double left = widget.anchor.dx;
    double top = widget.anchor.dy;

    if (left + _menuWidth > media.size.width - 16) {
      left = media.size.width - _menuWidth - 16;
    }
    if (top + estimatedHeight > media.size.height - 16) {
      top = media.size.height - estimatedHeight - 16;
    }

    left = left.clamp(16.0, media.size.width - _menuWidth - 16.0);
    top = top.clamp(16.0, media.size.height - estimatedHeight - 16.0);

    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            onTap: widget.onClose,
            behavior: HitTestBehavior.opaque,
          ),
          Positioned(left: left, top: top, child: _buildMenu(widget.items)),
          if (_activeSubmenu != null && _submenuOffset != null)
            Positioned(
              left: _submenuOffset!.dx,
              top: _submenuOffset!.dy,
              child: _buildMenu(_activeSubmenu!.children, isSubmenu: true),
            ),
        ],
      ),
    );
  }

  double _estimateHeight(List<_ContextMenuItem> items) {
    double height = _menuPaddingV * 2;
    for (final item in items) {
      height += item.isDivider ? 12 : _itemHeight + 4;
    }
    return height;
  }

  Widget _buildMenu(List<_ContextMenuItem> items, {bool isSubmenu = false}) {
    const double horizontalPadding = 14;
    final Matrix4 transform = Matrix4.identity()
      ..setEntry(3, 2, 0.0012)
      ..rotateX(isSubmenu ? 0.02 : -0.05)
      ..rotateY(isSubmenu ? -0.03 : 0.05);

    final menuBody = ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 24),
        child: Container(
          width: _menuWidth,
          padding: const EdgeInsets.symmetric(
            vertical: _menuPaddingV,
            horizontal: horizontalPadding,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.18),
                const Color(0xFF0B0B0D).withOpacity(0.82),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.18), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.55),
                blurRadius: 34,
                offset: const Offset(14, 26),
                spreadRadius: -20,
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.12),
                blurRadius: 18,
                offset: const Offset(-10, -10),
                spreadRadius: -12,
              ),
            ],
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [Colors.white.withOpacity(0.06), Colors.transparent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < items.length; i++)
                  items[i].isDivider ? _buildDivider() : _buildTile(items[i]),
              ],
            ),
          ),
        ),
      ),
    );

    return MouseRegion(
      onEnter: (_) => _cancelSubmenuCloseTimer(),
      onExit: (_) {
        if (isSubmenu) {
          _scheduleSubmenuClose();
        }
      },
      child: Transform(
        alignment: Alignment.topLeft,
        transform: transform,
        child: menuBody,
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        height: 1,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white24, Colors.white10, Colors.transparent],
          ),
        ),
      ),
    );
  }

  Widget _buildTile(_ContextMenuItem item) {
    final key = GlobalKey();
    final bool isDisabled = !item.enabled;
    final bool isHovered = _hoveredItem == item;
    final Color textColor = isDisabled
        ? Colors.white.withOpacity(0.35)
        : isHovered
        ? Colors.white
        : Colors.white.withOpacity(0.82);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: MouseRegion(
        onEnter: (_) {
          if (_submenuPinned && _activeSubmenu != item) return;
          _handleHover(item, key);
        },
        onExit: (_) {
          if (item.hasSubmenu && !_submenuPinned) {
            _scheduleSubmenuClose();
          }
          if (_hoveredItem == item && !item.hasSubmenu) {
            setState(() {
              _hoveredItem = null;
            });
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: isDisabled
              ? null
              : () async {
                  if (item.hasSubmenu) {
                    if (_submenuPinned && _activeSubmenu == item) {
                      setState(() {
                        _resetSubmenuState();
                      });
                    } else {
                      _handleHover(item, key, pin: true);
                    }
                  } else if (item.id != null) {
                    setState(() {
                      _resetSubmenuState();
                    });
                    await widget.onAction(item.id!);
                  }
                },
          child: AnimatedContainer(
            key: key,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            height: _itemHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isHovered
                  ? Colors.white.withOpacity(0.18)
                  : Colors.white.withOpacity(0.04),
              boxShadow: isHovered
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 18,
                        offset: const Offset(4, 8),
                        spreadRadius: -10,
                      ),
                    ]
                  : null,
              border: isHovered
                  ? Border.all(color: Colors.white.withOpacity(0.24), width: 1)
                  : null,
            ),
            child: Row(
              children: [
                if (item.icon != null)
                  _IconOrb(
                    icon: item.icon!,
                    active: item.isActive,
                    disabled: isDisabled,
                    checked: item.isChecked ?? false,
                  ),
                if (item.icon != null) const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: item.isActive
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: textColor,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                if (item.isChecked ?? false)
                  Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: Colors.tealAccent.shade100,
                  ),
                if (item.hasSubmenu)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: Colors.white.withOpacity(isDisabled ? 0.25 : 0.7),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleHover(_ContextMenuItem item, GlobalKey key, {bool pin = false}) {
    if (_submenuPinned && !pin && _activeSubmenu != item) {
      return;
    }

    if (pin) {
      _submenuPinned = true;
    }

    _cancelSubmenuCloseTimer();
    setState(() {
      _hoveredItem = item;
      if (!item.hasSubmenu) {
        _submenuPinned = false;
        _activeSubmenu = null;
        _submenuOffset = null;
      }
    });
    if (!item.hasSubmenu) {
      return;
    }

    final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    final overlayState = Overlay.maybeOf(context);
    final overlayBox = overlayState?.context.findRenderObject() as RenderBox?;
    if (renderBox == null || overlayBox == null) return;

    final itemGlobal = renderBox.localToGlobal(Offset.zero);
    final itemLocal = overlayBox.globalToLocal(itemGlobal);
    final submenuLeft = itemLocal.dx + renderBox.size.width - 6;
    double submenuTop = itemLocal.dy - 10;

    final menuHeight = _estimateHeight(item.children);
    final mediaHeight = MediaQuery.of(context).size.height;
    if (submenuTop + menuHeight > mediaHeight - 16) {
      submenuTop = mediaHeight - menuHeight - 16;
    }
    if (submenuTop < 16) submenuTop = 16;

    setState(() {
      _activeSubmenu = item;
      _submenuOffset = Offset(submenuLeft, submenuTop);
    });
  }

  void _scheduleSubmenuClose() {
    if (_submenuPinned) return;
    _submenuCloseTimer?.cancel();
    _submenuCloseTimer = Timer(const Duration(milliseconds: 160), () {
      if (!mounted) return;
      setState(() {
        _resetSubmenuState();
      });
    });
  }

  void _cancelSubmenuCloseTimer() {
    _submenuCloseTimer?.cancel();
    _submenuCloseTimer = null;
  }

  void _resetSubmenuState() {
    _submenuPinned = false;
    _activeSubmenu = null;
    _submenuOffset = null;
    _hoveredItem = null;
  }
}

class _IconOrb extends StatelessWidget {
  const _IconOrb({
    required this.icon,
    required this.active,
    required this.disabled,
    required this.checked,
  });

  final IconData icon;
  final bool active;
  final bool disabled;
  final bool checked;

  @override
  Widget build(BuildContext context) {
    final Color baseColor = disabled
        ? Colors.white.withOpacity(0.25)
        : active || checked
        ? Colors.tealAccent.shade100
        : Colors.white.withOpacity(0.82);

    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.12),
            Colors.black.withOpacity(0.45),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.22), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(6, 8),
            spreadRadius: -6,
          ),
        ],
      ),
      child: Icon(icon, size: 14, color: baseColor),
    );
  }
}

class _Templates {
  static const String c = '''
#include <stdio.h>

int main(void) {
    printf("Hello, world!\\n");
    return 0;
}
''';

  static const String cpp = '''
#include <iostream>

int main() {
    std::cout << "Hello, world!" << std::endl;
    return 0;
}
''';

  static const String dart = '''
void main() {
  print('Hello, world!');
}
''';

  static const String markdown = '''
# New Document

Start capturing your ideas here.
''';

  static const String python = '''
def main():
    print("Hello, world!")


if __name__ == "__main__":
    main()
''';
}

enum _SortMode { nameAsc, nameDesc, type, modifiedDesc, sizeDesc }

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

      await player!.open(Media(widget.videoPath), play: true);

      // restart on completion from 0.5s instead of full reload
      _completedSubscription = player!.stream.completed.listen((
        bool isCompleted,
      ) async {
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
