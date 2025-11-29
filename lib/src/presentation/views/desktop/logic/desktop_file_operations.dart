import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../bloc/desktop_manager_bloc.dart';
import 'grid_system.dart';

class DesktopFileOperations {
  final BuildContext context;
  final GridSystem gridSystem;

  DesktopFileOperations({required this.context, required this.gridSystem});

  Future<void> createFolder(String baseDir, Offset clickPos, Map<String, Map<String, double>> positions) async {
    final name = await promptName(
      title: 'New Folder Name',
      initial: 'New Folder',
    );
    final value = name?.trim();
    if (value == null || value.isEmpty) return;

    final uniqueName = ensureUniqueName(baseDir, value, isDirectory: true);
    final dir = Directory(p.join(baseDir, uniqueName));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _afterEntityCreated(dir.path, clickPos, positions);
  }

  Future<void> createDocument(
    String baseDir,
    Offset clickPos, {
    required String suggestedName,
    required String template,
    required Map<String, Map<String, double>> positions,
  }) async {
    final name = await promptName(
      title: 'New Document Name',
      initial: suggestedName,
    );
    final value = name?.trim();
    if (value == null || value.isEmpty) return;

    final uniqueName = ensureUniqueName(baseDir, value, isDirectory: false);
    final file = File(p.join(baseDir, uniqueName));
    if (!file.existsSync()) {
      file.createSync(recursive: true);
    }
    if (template.isNotEmpty) {
      try {
        file.writeAsStringSync(template);
      } catch (_) {}
    }
    _afterEntityCreated(file.path, clickPos, positions);
  }

  void _afterEntityCreated(String entityPath, Offset clickPos, Map<String, Map<String, double>> positions) {
    context.read<DesktopManagerBloc>().add(RefreshDesktopEvent());

    final snapped = gridSystem.findNearestFreeSlot(
      clickPos,
      p.basename(entityPath),
      positions,
    );
    context.read<DesktopManagerBloc>().add(
      UpdatePositionEvent(
        filename: p.basename(entityPath),
        x: snapped.dx,
        y: snapped.dy,
      ),
    );
  }

  Future<void> renameEntity(String targetPath) async {
    final currentName = p.basename(targetPath);
    final newName = await promptName(
      title: 'Rename "$currentName"',
      initial: currentName,
    );
    final trimmed = newName?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == currentName) return;

    context.read<DesktopManagerBloc>().add(
          RenameEntityEvent(sourcePath: targetPath, newName: trimmed),
        );
  }

  Future<void> deleteEntity(String targetPath) async {
    final name = p.basename(targetPath);
    final confirmed = await confirmDelete(name);
    if (!confirmed) return;

    context.read<DesktopManagerBloc>().add(DeleteEntityEvent(path: targetPath));
  }

  Future<bool> confirmDelete(String name) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              backgroundColor: const Color(0xFF23232A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              title: const Text('Delete Item', style: TextStyle(color: Colors.white)),
              content: Text(
                'Are you sure you want to delete "$name"?',
                style: const TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<String?> promptName({
    required String title,
    required String initial,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => _NamePromptDialog(title: title, initial: initial),
    );
  }

  String ensureUniqueName(
    String baseDir,
    String desired, {
    required bool isDirectory,
  }) {
    String candidate = desired;
    String fullPath = p.join(baseDir, candidate);
    if (!entityExists(fullPath)) {
      return candidate;
    }

    final extension = isDirectory ? '' : p.extension(candidate);
    final baseName = extension.isEmpty
        ? candidate
        : candidate.substring(0, candidate.length - extension.length);
    int counter = 1;
    while (entityExists(p.join(baseDir, '$baseName ($counter)$extension'))) {
      counter++;
    }
    return '$baseName ($counter)$extension';
  }

  bool entityExists(String path) {
    return FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.notFound;
  }

  int entitySize(String path) {
    try {
      if (FileSystemEntity.isDirectorySync(path)) {
        return 0;
      }
      return File(path).statSync().size;
    } catch (_) {
      return 0;
    }
  }

  String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    double size = bytes.toDouble();
    int index = 0;
    while (size >= 1024 && index < suffixes.length - 1) {
      size /= 1024;
      index++;
    }
    final value = index == 0 ? size.toStringAsFixed(0) : size.toStringAsFixed(1);
    return '$value ${suffixes[index]}';
  }

  Future<void> showEntityDetails(String path) async {
    try {
      final stat = await FileStat.stat(path);
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      final isDirectory = type == FileSystemEntityType.directory;
      final sizeString = isDirectory ? '—' : formatBytes(stat.size);

      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              backgroundColor: const Color(0xFF23232A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              title: Text(
                p.basename(path),
                style: const TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('Type', isDirectory ? 'Folder' : 'File'),
                  const SizedBox(height: 8),
                  _buildDetailRow('Location', p.dirname(path)),
                  const SizedBox(height: 8),
                  _buildDetailRow('Size', sizeString),
                  const SizedBox(height: 8),
                  _buildDetailRow('Permissions', stat.modeString()),
                  const SizedBox(height: 8),
                  _buildDetailRow('Modified', stat.modified.toLocal().toString()),
                  const SizedBox(height: 8),
                  _buildDetailRow('Accessed', stat.accessed.toLocal().toString()),
                  const SizedBox(height: 8),
                  _buildDetailRow('Changed', stat.changed.toLocal().toString()),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      }
    } catch (_) {
      showUnavailable('Details');
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ],
    );
  }

  void showUnavailable(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature is not available yet.'),
        backgroundColor: Colors.black.withOpacity(0.85),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void openDesktopInFiles(String desktopRoot) {
    try {
      Process.start('xdg-open', [
        desktopRoot,
      ], mode: ProcessStartMode.detached);
    } catch (_) {
      showUnavailable('File manager');
    }
  }

  Future<void> launchDisplaySettings() async {
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
    showUnavailable('Display settings');
  }
}

class _NamePromptDialog extends StatefulWidget {
  final String title;
  final String initial;

  const _NamePromptDialog({required this.title, required this.initial});

  @override
  State<_NamePromptDialog> createState() => _NamePromptDialogState();
}

class _NamePromptDialogState extends State<_NamePromptDialog> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    _focusNode = FocusNode();
    // Explicitly request focus after the build phase
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF23232A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      title: Text(widget.title, style: const TextStyle(color: Colors.white)),
      content: TextField(
        controller: _controller,
        focusNode: _focusNode,
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
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
