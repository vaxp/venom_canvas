abstract class DesktopRepository {
  /// Initialize any required paths or resources. Should be called before other methods.
  Future<void> init();

  /// List absolute paths of entries present on the desktop.
  Future<List<String>> listEntries();

  /// Read persisted wallpaper path (or empty string).
  Future<String> readWallpaperPath();

  /// Save wallpaper path to persistent config.
  Future<void> saveWallpaperPath(String path);

  /// Open / launch a file-system entity by absolute path.
  Future<void> launchEntity(String path);

  /// Read saved layout positions. Returns a map filename -> {"x": double, "y": double}
  Future<Map<String, Map<String, double>>> readLayout();

  /// Save layout positions.
  Future<void> saveLayout(Map<String, Map<String, double>> positions);

  /// Copy or move an external file into the desktop directory. Returns destination path.
  Future<String?> copyFileToDesktop(String srcPath);

  /// Move a file to a target directory. Returns the new path if successful.
  Future<String?> moveFile(String sourcePath, String targetDir);

  /// Watch for filesystem changes on the desktop. Emits a value whenever something changes.
  Stream<void> watchDesktop();
}
