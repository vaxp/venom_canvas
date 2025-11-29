import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:flutter_svg/flutter_svg.dart';

class DesktopIcon extends StatefulWidget {
  final String path;
  final Offset position;
  final bool isSelected;
  final bool isDragging;
  final bool isTargeted;
  final VoidCallback onDoubleTap;
  final Function(TapUpDetails) onSecondaryTapUp;
  final Function(DragStartDetails) onPanStart;
  final Function(DragUpdateDetails) onPanUpdate;
  final Function(DragEndDetails) onPanEnd;

  const DesktopIcon({
    super.key,
    required this.path,
    required this.position,
    required this.isSelected,
    required this.isDragging,
    required this.isTargeted,
    required this.onDoubleTap,
    required this.onSecondaryTapUp,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  @override
  State<DesktopIcon> createState() => _DesktopIconState();
}

class _DesktopIconState extends State<DesktopIcon> {
  ImageProvider? _thumbnail;
  bool _isLoadingThumbnail = false;

  static final Set<String> _availableFolderIcons = {
    'pictures',
    'bookmark',
    'cloud',
    'code',
    'desktop',
    'documents',
    'download',
    'downloads',
    'dropbox',
    'folder-torrent',
    'folder-vault',
    'folder-vbox',
    'folder-videos',
    'folder-wine',
    'folder',
    'games',
    'git',
    'github',
    'home',
    'html',
    'images',
    'inkscape',
    'music',
    'open',
    'projects',
    'public',
    'root',
    'snap',
    'stack',
    'steam',
    'temp',
    'templates',
    'trash-full',
    'trash',
  };

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant DesktopIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    if (_thumbnail != null || _isLoadingThumbnail) return;
    
    // Don't load thumbnails for directories
    if (FileSystemEntity.isDirectorySync(widget.path)) return;

    _isLoadingThumbnail = true;
    final ext = p.extension(widget.path).toLowerCase();
    ImageProvider? provider;

    try {
      if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext)) {
        provider = ResizeImage(
          FileImage(File(widget.path)),
          width: 128,
          policy: ResizeImagePolicy.fit,
        );
      } else if (['.mp4', '.mkv', '.avi', '.mov', '.webm'].contains(ext)) {
        final thumbPath = await VideoThumbnail.thumbnailFile(
          video: widget.path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 128,
          quality: 50,
        );
        if (thumbPath != null) {
          provider = ResizeImage(FileImage(File(thumbPath)), width: 128);
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _thumbnail = provider;
        _isLoadingThumbnail = false;
      });
    }
  }

  static final Map<String, String> _fileIconMap = {
    // Images
    '.png': 'image-png',
    '.jpg': 'image-jpeg',
    '.jpeg': 'image-jpeg',
    '.svg': 'image-svg+xml',
    '.webp': 'image-webp',
    '.gif': 'image-x-generic',
    '.ico': 'image-x-generic',
    '.tiff': 'image-x-generic',
    '.bmp': 'image-x-generic',

    // Video
    '.mp4': 'video-x-generic',
    '.mkv': 'video-x-generic',
    '.avi': 'video-x-generic',
    '.mov': 'video-x-generic',
    '.webm': 'video-x-generic',
    '.flv': 'application-x-flash-video',
    '.wmv': 'video-x-generic',

    // Audio
    '.mp3': 'audio-x-generic',
    '.wav': 'audio-x-generic',
    '.ogg': 'audio-x-generic',
    '.flac': 'audio-x-generic',
    '.m4a': 'audio-x-generic',
    '.aac': 'audio-x-generic',

    // Documents
    '.pdf': 'application-pdf',
    '.doc': 'application-vnd.ms-word',
    '.docx': 'application-vnd.ms-word',
    '.xls': 'application-vnd.ms-excel',
    '.xlsx': 'application-vnd.ms-excel',
    '.ppt': 'application-vnd.ms-powerpoint',
    '.pptx': 'application-vnd.ms-powerpoint',
    '.odt': 'application-vnd.oasis.opendocument.text',
    '.ods': 'application-vnd.oasis.opendocument.spreadsheet',
    '.odp': 'application-vnd.oasis.opendocument.presentation',
    '.rtf': 'text-richtext',
    '.txt': 'text-x-generic',
    '.md': 'text-markdown',
    '.csv': 'text-csv',
    '.xml': 'text-xml',
    '.json': 'application-json',
    '.yaml': 'application-x-yaml',
    '.yml': 'application-x-yaml',
    '.html': 'text-html',
    '.htm': 'text-html',
    '.css': 'text-css',

    // Code
    '.c': 'text-x-c',
    '.cpp': 'text-x-cpp',
    '.h': 'text-x-chdr',
    '.hpp': 'text-x-c++hdr',
    '.py': 'text-x-python',
    '.java': 'text-x-java',
    '.js': 'text-x-javascript',
    '.ts': 'text-x-typescript',
    '.dart': 'text-x-script', // Fallback as no specific dart icon found
    '.go': 'text-x-go',
    '.rs': 'text-rust',
    '.php': 'text-x-php',
    '.rb': 'text-x-ruby',
    '.sh': 'application-x-shellscript',
    '.bash': 'application-x-shellscript',
    '.sql': 'text-x-sql',
    '.lua': 'text-x-lua',
    '.pl': 'application-x-perl',
    '.kt': 'text-x-kotlin',
    '.swift': 'text-x-script',

    // Archives
    '.zip': 'application-x-zip',
    '.tar': 'application-x-tar',
    '.gz': 'application-x-gzip',
    '.rar': 'application-x-rar',
    '.7z': 'package-x-generic',
    '.deb': 'application-x-deb',
    '.rpm': 'application-x-rpm',
    '.iso': 'application-x-cd-image',

    // Executables
    '.exe': 'application-x-ms-dos-executable',
    '.msi': 'application-x-ms-dos-executable',
    '.apk': 'application-apk',
    '.appimage': 'application-vnd.appimage',
    '.flatpak': 'application-vnd.flatpak',
    '.snap': 'application-vnd.snap',
    '.jar': 'application-x-java-archive',
  };

  Widget _buildIcon(String path, double size, Color color) {
    if (FileSystemEntity.isDirectorySync(path)) {
      final name = p.basename(path).toLowerCase();
      String iconName = 'folder';
      
      if (_availableFolderIcons.contains(name)) {
        iconName = name;
      } else if (name == 'videos' && _availableFolderIcons.contains('folder-videos')) {
        iconName = 'folder-videos';
      } else if (_availableFolderIcons.contains('folder-$name')) {
        iconName = 'folder-$name';
      }
      
      return SvgPicture.asset(
        'assets/folder_icons/$iconName.svg',
        width: size,
        height: size,
      );
    }

    final ext = p.extension(path).toLowerCase();
    String? iconName;

    if (path.endsWith('.desktop')) {
      iconName = 'application-x-executable';
    } else {
      iconName = _fileIconMap[ext];
    }

    // Fallback logic
    if (iconName == null) {
       if (ext.isEmpty) {
         iconName = 'text-x-generic'; // Assume text for no extension files like 'LICENSE'
       } else {
         iconName = 'unknown';
       }
    }

    // Check if we need to fallback to IconData if SVG not found (though we assume SVGs exist for mapped items)
    // For safety, we can wrap in a try-catch or just rely on the asset existing.
    // Given the large list, we should be good. 
    // However, if 'application-x-desktop' is missing, we might want a fallback.
    
    // Let's use a helper to return the SvgPicture
    return SvgPicture.asset(
      'assets/mimes/$iconName.svg',
      width: size,
      height: size,
      placeholderBuilder: (context) => Icon(
        Icons.insert_drive_file_rounded,
        size: size,
        color: color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filename = p.basename(widget.path);
    final displayName = filename.endsWith('.desktop')
        ? filename.replaceAll('.desktop', '')
        : filename;

    return AnimatedPositioned(
      duration: widget.isDragging
          ? const Duration(milliseconds: 0)
          : const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      left: widget.position.dx,
      top: widget.position.dy,
      child: GestureDetector(
        onSecondaryTapUp: widget.onSecondaryTapUp,
        onPanStart: widget.onPanStart,
        onPanUpdate: widget.onPanUpdate,
        onPanEnd: widget.onPanEnd,
        onDoubleTap: widget.onDoubleTap,
        child: Container(
          width: 90,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: widget.isTargeted
                ? Colors.teal.withOpacity(0.3)
                : widget.isSelected
                ? Colors.white.withOpacity(0.1)
                : Colors.transparent,
            border: widget.isTargeted
                ? Border.all(color: Colors.teal, width: 2)
                : widget.isSelected
                ? Border.all(
                    color: Colors.tealAccent.withOpacity(0.7),
                    width: 1.2,
                  )
                : null,
          ),
          child: Opacity(
            opacity: widget.isDragging ? 0.3 : 1.0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _thumbnail != null
                      ? Image(
                          key: ValueKey('thumb-$filename'),
                          image: _thumbnail!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        )
                      : KeyedSubtree(
                          key: ValueKey('icon-$filename'),
                          child: _buildIcon(
                            widget.path,
                            48,
                            widget.isSelected
                                ? Colors.white
                                : Colors.white.withOpacity(0.9),
                          ),
                        ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: widget.isSelected
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
                      fontWeight: widget.isSelected
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
}
