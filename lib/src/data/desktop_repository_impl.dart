import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/repositories/desktop_repository.dart';

class DesktopRepositoryImpl implements DesktopRepository {
  late final Directory desktopDir;
  late final String configDirPath;
  late final File layoutFile;
  late final File configFile;
  late String wallpaperPath;
  Stream<void>? _watchStream;

  @override
  Future<void> init() async {
    final home = Platform.environment['HOME'] ?? Directory.current.path;
    desktopDir = Directory(p.join(home, 'Desktop'));
    configDirPath = p.join(home, '.config', 'venom');
    final configDir = Directory(configDirPath);
    if (!configDir.existsSync()) configDir.createSync(recursive: true);
    layoutFile = File(p.join(configDirPath, 'desktop_layout.json'));
    configFile = File(p.join(configDirPath, 'venom.json'));
    wallpaperPath = p.join(configDirPath, 'wallpaper.jpg');
    if (!desktopDir.existsSync()) desktopDir.createSync(recursive: true);
    // Try to read wallpaper from config if present
    try {
      if (configFile.existsSync()) {
        final data = jsonDecode(configFile.readAsStringSync());
        wallpaperPath = data['wallpaper'] ?? wallpaperPath;
      }
    } catch (_) {}
    // prepare watch stream
    _watchStream = desktopDir.watch().map((_) => null).asBroadcastStream();
  }

  @override
  Future<List<String>> listEntries() async {
    try {
      final currentFiles = desktopDir.listSync().toList();
      return currentFiles.map((e) => e.path).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<Map<String, Map<String, double>>> readLayout() async {
    try {
      if (!layoutFile.existsSync()) return {};
      final json = jsonDecode(layoutFile.readAsStringSync()) as Map<String, dynamic>;
      return json.map((k, v) => MapEntry(k, {
            'x': (v['x'] as num).toDouble(),
            'y': (v['y'] as num).toDouble()
          }));
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> saveLayout(Map<String, Map<String, double>> positions) async {
    try {
      final json = positions.map((k, v) => MapEntry(k, {'x': v['x'], 'y': v['y']}));
      layoutFile.writeAsStringSync(jsonEncode(json));
    } catch (_) {}
  }

  @override
  Future<String?> copyFileToDesktop(String srcPath) async {
    try {
      final destPath = p.join(desktopDir.path, p.basename(srcPath));
      if (srcPath == destPath) return destPath;
      try {
        await File(srcPath).rename(destPath);
      } catch (_) {
        await File(srcPath).copy(destPath);
      }
      return destPath;
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<void> watchDesktop() {
    return _watchStream ??= desktopDir.watch().map((_) => null).asBroadcastStream();
  }

  @override
  Future<void> launchEntity(String path) async {
    try {
      if (path.endsWith('.desktop')) {
        final file = File(path);
        final content = await file.readAsString();
        final execMatch = RegExp(r'^Exec=(.*)\r?\n*', multiLine: true).firstMatch(content);
        if (execMatch != null) {
          String cmd = execMatch.group(1)!.trim();
          cmd = cmd.replaceAll(RegExp(r' %[fFuUicwk]'), '');
          await Process.start('sh', ['-c', cmd], mode: ProcessStartMode.detached);
          return;
        }
      }
      await Process.start('xdg-open', [path], mode: ProcessStartMode.detached);
    } catch (_) {}
  }

  @override
  Future<String> readWallpaperPath() async {
    return wallpaperPath;
  }

  @override
  Future<void> saveWallpaperPath(String path) async {
    try {
      configFile.writeAsStringSync(jsonEncode({'wallpaper': path}));
      wallpaperPath = path;
    } catch (_) {}
  }
}
