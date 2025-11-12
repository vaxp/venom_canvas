part of 'desktop_manager_bloc.dart';

abstract class DesktopManagerEvent extends Equatable {
  const DesktopManagerEvent();
  @override
  List<Object?> get props => [];
}

class LoadDesktopEvent extends DesktopManagerEvent {}

class RefreshDesktopEvent extends DesktopManagerEvent {}

class LaunchEntityEvent extends DesktopManagerEvent {
  final String path;
  const LaunchEntityEvent(this.path);
  @override
  List<Object?> get props => [path];
}

class SetWallpaperEvent extends DesktopManagerEvent {
  final String path;
  const SetWallpaperEvent(this.path);
  @override
  List<Object?> get props => [path];
}

class UpdatePositionEvent extends DesktopManagerEvent {
  final String filename;
  final double x;
  final double y;
  const UpdatePositionEvent({required this.filename, required this.x, required this.y});
  @override
  List<Object?> get props => [filename, x, y];
}

class DropFilesEvent extends DesktopManagerEvent {
  final List<String> paths;
  final double dropX;
  final double dropY;
  const DropFilesEvent({required this.paths, required this.dropX, required this.dropY});
  @override
  List<Object?> get props => [paths, dropX, dropY];
}

class MoveFileEvent extends DesktopManagerEvent {
  final String sourcePath;
  final String targetPath;
  const MoveFileEvent({required this.sourcePath, required this.targetPath});
  @override
  List<Object?> get props => [sourcePath, targetPath];
}

class RenameEntityEvent extends DesktopManagerEvent {
  final String sourcePath;
  final String newName;
  const RenameEntityEvent({required this.sourcePath, required this.newName});
  @override
  List<Object?> get props => [sourcePath, newName];
}

class DeleteEntityEvent extends DesktopManagerEvent {
  final String path;
  const DeleteEntityEvent({required this.path});
  @override
  List<Object?> get props => [path];
}

class PasteClipboardEvent extends DesktopManagerEvent {
  final List<String> sources;
  final bool isCut;
  final String targetDirectory;
  final bool targetIsDesktop;
  final double? dropX;
  final double? dropY;

  const PasteClipboardEvent({
    required this.sources,
    required this.isCut,
    required this.targetDirectory,
    required this.targetIsDesktop,
    this.dropX,
    this.dropY,
  });

  @override
  List<Object?> get props => [
        sources,
        isCut,
        targetDirectory,
        targetIsDesktop,
        dropX,
        dropY,
      ];
}
