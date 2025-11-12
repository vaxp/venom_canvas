import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../domain/repositories/desktop_repository.dart';

part 'desktop_manager_event.dart';
part 'desktop_manager_state.dart';

class DesktopManagerBloc extends Bloc<DesktopManagerEvent, DesktopManagerState> {
  final DesktopRepository repository;
  StreamSubscription<void>? _watchSub;

  DesktopManagerBloc({required this.repository}) : super(DesktopInitial()) {
    on<LoadDesktopEvent>(_onLoad);
    on<RefreshDesktopEvent>(_onRefresh);
    on<LaunchEntityEvent>(_onLaunch);
    on<SetWallpaperEvent>(_onSetWallpaper);
    on<UpdatePositionEvent>(_onUpdatePosition);
    on<DropFilesEvent>(_onDropFiles);
    on<MoveFileEvent>(_onMoveFile);
    on<RenameEntityEvent>(_onRenameEntity);
    on<DeleteEntityEvent>(_onDeleteEntity);
    on<PasteClipboardEvent>(_onPasteClipboard);
  }

  Future<void> _onLoad(LoadDesktopEvent event, Emitter<DesktopManagerState> emit) async {
    emit(DesktopLoading());
    try {
      await repository.init();
      // start watching repository changes and trigger refreshes after init
      _watchSub?.cancel();
      _watchSub = repository.watchDesktop().listen((_) => add(RefreshDesktopEvent()));
      final entries = await repository.listEntries();
      final wallpaper = await repository.readWallpaperPath();
      final positions = await repository.readLayout();
      emit(DesktopLoaded(entries: entries, wallpaperPath: wallpaper, positions: positions));
    } catch (e) {
      emit(DesktopError(e.toString()));
    }
  }

  Future<void> _onRefresh(RefreshDesktopEvent event, Emitter<DesktopManagerState> emit) async {
    try {
      final entries = await repository.listEntries();
      final wallpaper = await repository.readWallpaperPath();
      final positions = await repository.readLayout();
      emit(DesktopLoaded(entries: entries, wallpaperPath: wallpaper, positions: positions));
    } catch (e) {
      emit(DesktopError(e.toString()));
    }
  }

  Future<void> _onLaunch(LaunchEntityEvent event, Emitter<DesktopManagerState> emit) async {
    await repository.launchEntity(event.path);
  }

  Future<void> _onSetWallpaper(SetWallpaperEvent event, Emitter<DesktopManagerState> emit) async {
    await repository.saveWallpaperPath(event.path);
    final current = state;
    if (current is DesktopLoaded) {
      emit(DesktopLoaded(entries: current.entries, wallpaperPath: event.path, positions: current.positions));
    } else {
      add(RefreshDesktopEvent());
    }
  }

  Future<void> _onUpdatePosition(UpdatePositionEvent event, Emitter<DesktopManagerState> emit) async {
    final current = state;
    if (current is DesktopLoaded) {
      final updated = Map<String, Map<String, double>>.from(current.positions);
      updated[event.filename] = {'x': event.x, 'y': event.y};
      await repository.saveLayout(updated);
      emit(DesktopLoaded(entries: current.entries, wallpaperPath: current.wallpaperPath, positions: updated));
    }
  }

  Future<void> _onDropFiles(DropFilesEvent event, Emitter<DesktopManagerState> emit) async {
    final current = state;
    if (current is DesktopLoaded) {
      final updated = Map<String, Map<String, double>>.from(current.positions);
      for (int i = 0; i < event.paths.length; i++) {
        final src = event.paths[i];
        final dest = await repository.copyFileToDesktop(src);
        if (dest != null) {
          final filename = dest.split(RegExp(r"/|\\")).last;
          updated[filename] = {'x': event.dropX + i * 20.0, 'y': event.dropY + i * 20.0};
        }
      }
      await repository.saveLayout(updated);
      final entries = await repository.listEntries();
      emit(DesktopLoaded(entries: entries, wallpaperPath: current.wallpaperPath, positions: updated));
    }
  }

  Future<void> _onMoveFile(MoveFileEvent event, Emitter<DesktopManagerState> emit) async {
    try {
      String targetDir;
      if (FileSystemEntity.isDirectorySync(event.targetPath)) {
        targetDir = event.targetPath;
      } else {
        targetDir = p.dirname(event.targetPath);
      }
      await repository.moveFile(event.sourcePath, targetDir);
      final current = state;
      if (current is DesktopLoaded) {
        final entries = await repository.listEntries();
        final positions = await repository.readLayout();
        emit(DesktopLoaded(entries: entries, wallpaperPath: current.wallpaperPath, positions: positions));
      }
    } catch (_) {
      add(RefreshDesktopEvent());
    }
  }

  Future<void> _onRenameEntity(RenameEntityEvent event, Emitter<DesktopManagerState> emit) async {
    final current = state;
    if (current is! DesktopLoaded) return;
    final newPath = await repository.renameEntity(event.sourcePath, event.newName);
    if (newPath == null) {
      add(RefreshDesktopEvent());
      return;
    }

    final updatedEntries = current.entries
        .map((entry) => entry == event.sourcePath ? newPath : entry)
        .toList(growable: false);

    final updatedPositions = Map<String, Map<String, double>>.from(current.positions);
    final oldKey = p.basename(event.sourcePath);
    final newKey = p.basename(newPath);
    final coords = updatedPositions.remove(oldKey);
    if (coords != null) {
      updatedPositions[newKey] = coords;
    }

    emit(DesktopLoaded(
      entries: updatedEntries,
      wallpaperPath: current.wallpaperPath,
      positions: updatedPositions,
    ));
  }

  Future<void> _onDeleteEntity(DeleteEntityEvent event, Emitter<DesktopManagerState> emit) async {
    final current = state;
    if (current is! DesktopLoaded) return;
    final deleted = await repository.deleteEntity(event.path);
    if (!deleted) {
      add(RefreshDesktopEvent());
      return;
    }

    final updatedEntries = current.entries.where((entry) => entry != event.path).toList(growable: false);
    final updatedPositions = Map<String, Map<String, double>>.from(current.positions)
      ..remove(p.basename(event.path));

    emit(DesktopLoaded(
      entries: updatedEntries,
      wallpaperPath: current.wallpaperPath,
      positions: updatedPositions,
    ));
  }

  Future<void> _onPasteClipboard(PasteClipboardEvent event, Emitter<DesktopManagerState> emit) async {
    final current = state;
    if (current is! DesktopLoaded) return;

    final updatedPositions = Map<String, Map<String, double>>.from(current.positions);
    final List<String> resultPaths = [];
    bool anyChange = false;

    for (final source in event.sources) {
      if (event.isCut) {
        final moved = await repository.moveFile(source, event.targetDirectory);
        if (moved != null) {
          resultPaths.add(moved);
          anyChange = true;
          if (!event.targetIsDesktop) {
            updatedPositions.remove(p.basename(source));
          }
        }
      } else {
        final copied = await repository.copyEntity(source, event.targetDirectory);
        if (copied != null) {
          resultPaths.add(copied);
          anyChange = true;
        }
      }
    }

    if (!anyChange) {
      add(RefreshDesktopEvent());
      return;
    }

    bool positionsChanged = false;
    if (event.targetIsDesktop) {
      final baseX = event.dropX ?? 40.0;
      final baseY = event.dropY ?? 40.0;
      for (int i = 0; i < resultPaths.length; i++) {
        final filename = p.basename(resultPaths[i]);
        updatedPositions[filename] = {
          'x': baseX + i * 20.0,
          'y': baseY + i * 20.0,
        };
      }
      positionsChanged = true;
    } else if (event.isCut) {
      positionsChanged = true;
    }

    if (positionsChanged) {
      await repository.saveLayout(updatedPositions);
    }

    final entries = await repository.listEntries();
    final wallpaper = await repository.readWallpaperPath();
    final positions =
        positionsChanged ? updatedPositions : current.positions;

    emit(DesktopLoaded(
      entries: entries,
      wallpaperPath: wallpaper,
      positions: positions,
    ));
  }

  @override
  Future<void> close() {
    _watchSub?.cancel();
    return super.close();
  }
}
