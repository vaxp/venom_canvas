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
  Future<String?> moveFile(String sourcePath, String targetDir) async {
    try {
      final targetDirEntity = Directory(targetDir);
      if (!targetDirEntity.existsSync()) return null;
      final basename = p.basename(sourcePath);
      final destPath = p.join(targetDir, basename);
      if (sourcePath == destPath) return destPath;
      final sourceEntity = FileSystemEntity.typeSync(sourcePath);
      if (sourceEntity == FileSystemEntityType.notFound) return null;
      try {
        if (sourceEntity == FileSystemEntityType.directory) {
          await Directory(sourcePath).rename(destPath);
        } else {
          await File(sourcePath).rename(destPath);
        }
        return destPath;
      } catch (_) {
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<void> watchDesktop() {
    return _watchStream ??= desktopDir.watch().map((_) => null).asBroadcastStream();
  }

  @override
  Future<String?> renameEntity(String sourcePath, String newName) async {
    try {
      final trimmed = newName.trim();
      if (trimmed.isEmpty) return null;

      final currentType = FileSystemEntity.typeSync(sourcePath, followLinks: false);
      if (currentType == FileSystemEntityType.notFound) return null;

      final dirPath = p.dirname(sourcePath);
      final safeName = p.basename(trimmed);
      final desiredPath = p.join(dirPath, safeName);

      String targetPath;
      if (desiredPath == sourcePath) {
        targetPath = sourcePath;
      } else {
        targetPath = _resolveUniquePath(dirPath, safeName, originalPath: sourcePath);
      }

      String? resultPath;
      if (currentType == FileSystemEntityType.directory) {
        resultPath = (await Directory(sourcePath).rename(targetPath)).path;
      } else {
        resultPath = (await File(sourcePath).rename(targetPath)).path;
      }

      _renameLayoutEntry(p.basename(sourcePath), p.basename(resultPath));
      return resultPath;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> deleteEntity(String path) async {
    try {
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) return false;

      if (type == FileSystemEntityType.directory) {
        await Directory(path).delete(recursive: true);
      } else {
        await File(path).delete();
      }

      _removeLayoutEntry(p.basename(path));
      return true;
    } catch (_) {
      return false;
    }
  }

  String _resolveUniquePath(String dirPath, String desiredName, {String? originalPath}) {
    String candidateName = desiredName;
    String candidatePath = p.join(dirPath, candidateName);
    if (candidatePath == originalPath) return candidatePath;

    final extension = p.extension(candidateName);
    final baseName = extension.isEmpty
        ? candidateName
        : candidateName.substring(0, candidateName.length - extension.length);
    int counter = 1;
    while (FileSystemEntity.typeSync(candidatePath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      final nextName = extension.isEmpty
          ? '$baseName ($counter)'
          : '$baseName ($counter)$extension';
      candidatePath = p.join(dirPath, nextName);
      if (candidatePath == originalPath) {
        return candidatePath;
      }
      counter++;
    }
    return candidatePath;
  }

  void _renameLayoutEntry(String oldKey, String newKey) {
    try {
      if (!layoutFile.existsSync()) return;
      final json = jsonDecode(layoutFile.readAsStringSync());
      if (json is! Map<String, dynamic>) return;
      if (!json.containsKey(oldKey)) return;
      final value = json.remove(oldKey);
      json[newKey] = value;
      layoutFile.writeAsStringSync(jsonEncode(json));
    } catch (_) {}
  }

  void _removeLayoutEntry(String key) {
    try {
      if (!layoutFile.existsSync()) return;
      final json = jsonDecode(layoutFile.readAsStringSync());
      if (json is! Map<String, dynamic>) return;
      if (!json.containsKey(key)) return;
      json.remove(key);
      layoutFile.writeAsStringSync(jsonEncode(json));
    } catch (_) {}
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
