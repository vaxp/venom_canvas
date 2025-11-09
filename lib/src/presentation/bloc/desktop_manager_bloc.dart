import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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

  @override
  Future<void> close() {
    _watchSub?.cancel();
    return super.close();
  }
}
