import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:venom_canvas/src/presentation/bloc/desktop_manager_bloc.dart';
import 'package:venom_canvas/src/data/desktop_repository_impl.dart';
import '../widgets/context_menu/glass_context_menu.dart';
import '../widgets/wallpaper/video_wallpaper.dart';
import 'package:venom_canvas/src/core/enums/sort_mode.dart';
import 'package:venom_canvas/src/core/constants/file_templates.dart';
import 'desktop/logic/grid_system.dart';
import 'desktop/logic/desktop_file_operations.dart';
import 'desktop/logic/desktop_context_menu_builder.dart';
import 'desktop/widgets/desktop_icon.dart';

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
  final GridSystem _gridSystem = GridSystem();
  late final DesktopFileOperations _fileOps;

  bool _isDraggingExternal = false;
  Key wallpaperKey = UniqueKey();
  bool _showHidden = false;
  SortMode _sortMode = SortMode.nameAsc;
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
  final List<String> _clipboardPaths = <String>[];
  bool _clipboardIsCut = false;

  // For multi-drag
  final Map<String, Offset> _initialItemPositions = {};
  double? _minDragX;
  double? _maxDragX;
  double? _minDragY;
  double? _maxDragY;

  @override
  void initState() {
    super.initState();
    _fileOps = DesktopFileOperations(context: context, gridSystem: _gridSystem);
  }

  List<String> _applyView(List<String> original) {
    List<String> out = List<String>.from(original);
    if (!_showHidden) {
      out = out.where((e) => !p.basename(e).startsWith('.')).toList();
    }
    switch (_sortMode) {
      case SortMode.nameAsc:
        out.sort(
          (a, b) => p
              .basename(a)
              .toLowerCase()
              .compareTo(p.basename(b).toLowerCase()),
        );
        break;
      case SortMode.nameDesc:
        out.sort(
          (a, b) => p
              .basename(b)
              .toLowerCase()
              .compareTo(p.basename(a).toLowerCase()),
        );
        break;
      case SortMode.type:
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
      case SortMode.modifiedDesc:
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
      case SortMode.sizeDesc:
        out.sort((a, b) {
          final sa = _fileOps.entitySize(a);
          final sb = _fileOps.entitySize(b);
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
    List<ContextMenuItem>? items,
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
      builder: (ctx) => GlassContextMenu(
        anchor: anchor,
        items:
            items ??
            DesktopContextMenuBuilder.buildDesktopContextMenuItems(
              sortMode: _sortMode,
              showHidden: _showHidden,
              canPaste: _clipboardPaths.isNotEmpty,
            ),
        onClose: _removeContextMenu,
        onAction: (action) => _handleContextMenuAction(action),
      ),
    );
    overlay.insert(entry);
    _contextMenuEntry = entry;
  }

  Future<void> _handleContextMenuAction(String action) async {
    final targetPath = _contextMenuTargetPath;
    final clickPos =
        _lastContextTapLocal ??
        const Offset(GridSystem.startX + 40, GridSystem.startY + 40);
    final baseDir = _desktopRoot();
    _removeContextMenu();

    switch (action) {
      case 'new_folder':
        await _fileOps.createFolder(baseDir, clickPos, widget.positions);
        break;
      case 'new_document:c':
        await _fileOps.createDocument(
          baseDir,
          clickPos,
          suggestedName: 'main.c',
          template: FileTemplates.c,
          positions: widget.positions,
        );
        break;
      case 'new_document:cpp':
        await _fileOps.createDocument(
          baseDir,
          clickPos,
          suggestedName: 'main.cpp',
          template: FileTemplates.cpp,
          positions: widget.positions,
        );
        break;
      case 'new_document:dart':
        await _fileOps.createDocument(
          baseDir,
          clickPos,
          suggestedName: 'main.dart',
          template: FileTemplates.dart,
          positions: widget.positions,
        );
        break;
      case 'new_document:markdown':
        await _fileOps.createDocument(
          baseDir,
          clickPos,
          suggestedName: 'notes.md',
          template: FileTemplates.markdown,
          positions: widget.positions,
        );
        break;
      case 'new_document:python':
        await _fileOps.createDocument(
          baseDir,
          clickPos,
          suggestedName: 'main.py',
          template: FileTemplates.python,
          positions: widget.positions,
        );
        break;
      case 'new_document:text':
        await _fileOps.createDocument(
          baseDir,
          clickPos,
          suggestedName: 'Untitled.txt',
          template: '',
          positions: widget.positions,
        );
        break;
      case 'paste':
        await _pasteClipboard(null, clickPos);
        break;
      case 'select_all':
        _fileOps.showUnavailable('Select all');
        break;
      case 'arrange_icons':
      case 'arrange_keep':
        _arrangeIcons(widget.entries);
        break;
      case 'arrange_stack_type':
      case 'sort_special':
        _fileOps.showUnavailable('This sorting mode');
        break;
      case 'sort_name':
        setState(() => _sortMode = SortMode.nameAsc);
        break;
      case 'sort_name_desc':
        setState(() => _sortMode = SortMode.nameDesc);
        break;
      case 'sort_modified':
        setState(() => _sortMode = SortMode.modifiedDesc);
        break;
      case 'sort_type':
        setState(() => _sortMode = SortMode.type);
        break;
      case 'sort_size':
        setState(() => _sortMode = SortMode.sizeDesc);
        break;
      case 'toggle_hidden':
        setState(() => _showHidden = !_showHidden);
        break;
      case 'show_desktop_files':
        _fileOps.openDesktopInFiles(_desktopRoot());
        break;
      case 'open_terminal':
        _openTerminalAt(baseDir);
        break;
      case 'change_background':
        await _pickWallpaper();
        break;
      case 'desktop_icons_settings':
        _fileOps.showUnavailable('Desktop icons settings');
        break;
      case 'display_settings':
        await _fileOps.launchDisplaySettings();
        break;
      case 'entity:rename':
        if (targetPath != null) {
          await _fileOps.renameEntity(targetPath);
        }
        break;
      case 'entity:delete':
        if (targetPath != null) {
          await _fileOps.deleteEntity(targetPath);
        }
        break;
      case 'entity:cut':
        if (targetPath != null) {
          _setClipboard(_collectSelectionPaths(targetPath), isCut: true);
        }
        break;
      case 'entity:copy':
        if (targetPath != null) {
          _setClipboard(_collectSelectionPaths(targetPath), isCut: false);
        }
        break;
      case 'entity:paste':
        await _pasteClipboard(targetPath, clickPos);
        break;
      case 'entity:details':
        if (targetPath != null) {
          await _fileOps.showEntityDetails(targetPath);
        }
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

  void _arrangeIcons(List<String> allEntries) {
    final visible = _applyView(allEntries);
    int col = 0, row = 0;
    const int colCount = 6;
    for (final path in visible) {
      final filename = p.basename(path);
      final target = _gridSystem.offsetForCell(
        _gridSystem.safeInt(col),
        _gridSystem.safeInt(row),
      );
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

  Rect _iconRectForEntry(
    String path,
    int index,
    Map<String, Map<String, double>> positions,
  ) {
    final filename = p.basename(path);
    final posMap = positions[filename];
    final basePos = posMap != null
        ? Offset(posMap['x'] ?? 0, posMap['y'] ?? 0)
        : _gridSystem.getDefaultPosition(index);
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
      // If we clicked an icon that is NOT selected, we don't select it immediately here.
      // We wait for either a drag start (which selects it) or a tap (which selects it).
      // If it IS selected, we definitely don't want to clear selection.

      // Actually, standard behavior:
      // - Mouse down on unselected: select it immediately (and clear others)?
      //   - If we do that, then drag works fine.
      // - Mouse down on selected: DO NOTHING to selection. Wait for drag or up.

      if (!_selectedPaths.contains(hit)) {
        // If not selected, we can select it now, but we must clear others?
        // Yes, usually clicking an unselected item clears others.
        // But if we are about to drag, we want that.
        setState(() {
          _isSelecting = false;
          _selectionStart = null;
          _selectionEnd = null;
          _selectedPaths
            ..clear()
            ..add(hit);
        });
      }
      // If it WAS selected, we do nothing here.
      // If the user just clicks (up/down) on a selected item without dragging,
      // we should clear others on UP (or tap).
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

  List<String> _collectSelectionPaths(String fallbackPath) {
    if (_selectedPaths.isNotEmpty) {
      return _selectedPaths.toList();
    }
    return [fallbackPath];
  }

  void _setClipboard(List<String> paths, {required bool isCut}) {
    if (paths.isEmpty) return;
    setState(() {
      _clipboardPaths
        ..clear()
        ..addAll(paths);
      _clipboardIsCut = isCut;
    });
    final label = paths.length == 1
        ? p.basename(paths.first)
        : '${paths.length} items';
    _showClipboardSnackbar(isCut ? 'Cut $label' : 'Copied $label');
    unawaited(
      context.read<DesktopRepositoryImpl>().setClipboardItems(
        List<String>.from(paths),
        isCut: isCut,
      ),
    );
  }

  Future<void> _pasteClipboard(String? targetPath, Offset clickPos) async {
    if (_clipboardPaths.isEmpty) {
      _fileOps.showUnavailable('Paste');
      return;
    }
    final targetDir = _resolvePasteDirectory(targetPath);
    if (targetDir == null) {
      _fileOps.showUnavailable('Destination');
      return;
    }

    final desktopRoot = _desktopRoot();
    final targetIsDesktop = p.equals(targetDir, desktopRoot);
    context.read<DesktopManagerBloc>().add(
      PasteClipboardEvent(
        sources: List<String>.from(_clipboardPaths),
        isCut: _clipboardIsCut,
        targetDirectory: targetDir,
        targetIsDesktop: targetIsDesktop,
        dropX: targetIsDesktop ? clickPos.dx : null,
        dropY: targetIsDesktop ? clickPos.dy : null,
      ),
    );

    if (_clipboardIsCut) {
      setState(() {
        _clipboardPaths.clear();
        _clipboardIsCut = false;
      });
    }
  }

  String? _resolvePasteDirectory(String? targetPath) {
    if (targetPath == null) {
      return _desktopRoot();
    }
    if (FileSystemEntity.isDirectorySync(targetPath)) {
      return targetPath;
    }
    final parent = p.dirname(targetPath);
    return Directory(parent).existsSync() ? parent : null;
  }

  void _showClipboardSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.black.withOpacity(0.85),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
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
            _showContextMenu(details.globalPosition, targetPath: null);
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
                  _buildDesktopIcon(visibleEntries[i], i),
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

  Widget _buildDesktopIcon(String path, int index) {
    final filename = p.basename(path);
    final posMap = widget.positions[filename];
    final basePosition = posMap != null
        ? Offset(posMap['x']!, posMap['y']!)
        : _gridSystem.getDefaultPosition(index);

    final isDragging = _draggingPath == path;
    final isTargeted =
        _hoveredTargetPath == path &&
        _draggingPath != null &&
        _draggingPath != path;
    final isSelected = _selectedPaths.contains(path);

    Offset position = basePosition;
    if (isDragging && _dragOffset != null) {
      // The leader (the one being dragged directly)
      position = _dragOffset!;
    } else if (isSelected &&
        _draggingPath != null &&
        _initialItemPositions.containsKey(path)) {
      // Follower: calculate delta from leader
      final leaderInitial = _initialItemPositions[_draggingPath];
      final myInitial = _initialItemPositions[path];
      if (leaderInitial != null && myInitial != null && _dragOffset != null) {
        final dx = _dragOffset!.dx - leaderInitial.dx;
        final dy = _dragOffset!.dy - leaderInitial.dy;
        position = myInitial + Offset(dx, dy);
      }
    }

    return DesktopIcon(
      path: path,
      position: position,
      isSelected: isSelected,
      isDragging: isDragging,
      isTargeted: isTargeted,
      onDoubleTap: () =>
          context.read<DesktopManagerBloc>().add(LaunchEntityEvent(path)),
      onTap: () {
        // Handle single tap: clear other selections if we are not holding Ctrl/Shift (not implemented yet)
        // and just select this one.
        // This runs if we didn't drag.
        setState(() {
          _selectedPaths
            ..clear()
            ..add(path);
        });
      },
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
          items: DesktopContextMenuBuilder.buildEntityContextMenuItems(
            path,
            _clipboardPaths.isNotEmpty,
          ),
          targetPath: path,
        );
      },
      onPanStart: (details) {
        setState(() {
          // If dragging something not selected, clear selection and select it
          if (!_selectedPaths.contains(path)) {
            _selectedPaths.clear();
            _selectedPaths.add(path);
          }

          _draggingPath = path;

          // Record initial positions for all selected items
          _initialItemPositions.clear();
          for (final selectedPath in _selectedPaths) {
            final fName = p.basename(selectedPath);
            final pMap = widget.positions[fName];
            // Find index if possible, otherwise 0 (fallback)
            final idx = widget.entries.indexOf(selectedPath);
            final base = pMap != null
                ? Offset(pMap['x']!, pMap['y']!)
                : _gridSystem.getDefaultPosition(idx >= 0 ? idx : 0);
            _initialItemPositions[selectedPath] = base;
          }

          final renderBox =
              _stackKey.currentContext?.findRenderObject() as RenderBox?;
          if (renderBox != null) {
            final localPos = renderBox.globalToLocal(details.globalPosition);
            _dragOffset = localPos - const Offset(45, 55);

            // Calculate drag bounds to keep all items on screen
            if (renderBox.hasSize) {
              final size = renderBox.size;
              final leaderInitial = _initialItemPositions[path] ?? basePosition;

              double minX = -double.infinity;
              double maxX = double.infinity;
              double minY = -double.infinity;
              double maxY = double.infinity;

              for (final selectedPath in _selectedPaths) {
                final initial = _initialItemPositions[selectedPath];
                if (initial == null) continue;

                // 0 <= itemX <= width - 90
                // 0 <= itemY <= height - 110
                // itemPos = initial + (leaderPos - leaderInitial)
                // leaderPos = itemPos - initial + leaderInitial

                // Min X: itemPos >= 0 => leaderPos >= leaderInitial - initial
                final itemMinX = leaderInitial.dx - initial.dx;
                if (itemMinX > minX) minX = itemMinX;

                // Max X: itemPos <= width - 90 => leaderPos <= width - 90 - initial + leaderInitial
                final itemMaxX =
                    size.width - 90 - initial.dx + leaderInitial.dx;
                if (itemMaxX < maxX) maxX = itemMaxX;

                // Min Y
                final itemMinY = leaderInitial.dy - initial.dy;
                if (itemMinY > minY) minY = itemMinY;

                // Max Y
                final itemMaxY =
                    size.height - 110 - initial.dy + leaderInitial.dy;
                if (itemMaxY < maxY) maxY = itemMaxY;
              }

              _minDragX = minX;
              _maxDragX = maxX;
              _minDragY = minY;
              _maxDragY = maxY;
            }
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
            var newOffset = localPos - const Offset(45, 55);

            if (_minDragX != null &&
                _maxDragX != null &&
                _minDragY != null &&
                _maxDragY != null) {
              newOffset = Offset(
                newOffset.dx.clamp(_minDragX!, _maxDragX!),
                newOffset.dy.clamp(_minDragY!, _maxDragY!),
              );
            }

            _dragOffset = newOffset;
            _hoveredTargetPath = _findIconAtPosition(
              localPos,
              widget.positions,
              _applyView(widget.entries),
            );
          });
        }
      },
      onPanEnd: (details) {
        final bloc = context.read<DesktopManagerBloc>();
        Map<String, Map<String, double>> existing = widget.positions;
        final state = bloc.state;
        if (state is DesktopLoaded) {
          existing = state.positions;
        }

        // 1. Check if dropped on another icon (folder/executable)
        if (_hoveredTargetPath != null &&
            !_selectedPaths.contains(_hoveredTargetPath)) {
          // Move all selected items to target
          for (final selectedPath in _selectedPaths) {
            if (selectedPath == _hoveredTargetPath) continue;
            bloc.add(
              MoveFileEvent(
                sourcePath: selectedPath,
                targetPath: _hoveredTargetPath!,
              ),
            );
          }
        } else {
          // 2. Normal grid snap for all selected items
          // We need to calculate the final position for each item
          // Delta calculation:
          final leaderInitial = _initialItemPositions[path];
          // If for some reason we don't have leader initial, abort or fallback
          if (leaderInitial != null && _dragOffset != null) {
            final dx = _dragOffset!.dx - leaderInitial.dx;
            final dy = _dragOffset!.dy - leaderInitial.dy;
            final delta = Offset(dx, dy);

            // We should apply updates in a way that doesn't cause collisions if possible,
            // but for now we just update all of them to their new snapped locations.
            // We might want to update the 'existing' map locally as we go to help findNearestFreeSlot?
            // findNearestFreeSlot uses 'existing' to avoid overlaps.
            // If we move multiple items, we should ideally reserve their new spots.

            // Let's make a temporary mutable copy of existing positions to track new slots
            final Map<String, Map<String, double>> tempPositions =
                Map<String, Map<String, double>>.from(existing);

            for (final selectedPath in _selectedPaths) {
              final initial = _initialItemPositions[selectedPath];
              if (initial == null) continue;

              final rawNewPos = initial + delta;
              final fName = p.basename(selectedPath);

              // Remove old position from temp so we don't collide with ourselves (conceptually)
              // But findNearestFreeSlot checks against 'existing'.
              // If we want to move a group, we should probably clear their old positions from the check
              // or just rely on the fact that they are moving to (hopefully) empty space.

              final target = _gridSystem.findNearestFreeSlot(
                rawNewPos,
                fName,
                tempPositions,
              );

              // Update tempPositions so next item in selection respects this one
              tempPositions[fName] = {'x': target.dx, 'y': target.dy};

              bloc.add(
                UpdatePositionEvent(
                  filename: fName,
                  x: target.dx,
                  y: target.dy,
                ),
              );
            }
          }
        }

        setState(() {
          _draggingPath = null;
          _dragOffset = null;
          _hoveredTargetPath = null;
          _initialItemPositions.clear();
          _minDragX = null;
          _maxDragX = null;
          _minDragY = null;
          _maxDragY = null;
        });
      },
    );
  }
}
