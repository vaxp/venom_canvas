part of 'desktop_manager_bloc.dart';

abstract class DesktopManagerState extends Equatable {
  const DesktopManagerState();
  @override
  List<Object?> get props => [];
}

class DesktopInitial extends DesktopManagerState {}

class DesktopLoading extends DesktopManagerState {}

class DesktopLoaded extends DesktopManagerState {
  final List<String> entries;
  final String wallpaperPath;
  final Map<String, Map<String, double>> positions;

  const DesktopLoaded({required this.entries, required this.wallpaperPath, required this.positions});

  @override
  List<Object?> get props => [entries, wallpaperPath, positions];
}

class DesktopError extends DesktopManagerState {
  final String message;
  const DesktopError(this.message);
  @override
  List<Object?> get props => [message];
}
