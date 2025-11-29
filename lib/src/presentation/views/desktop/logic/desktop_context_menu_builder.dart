import 'package:flutter/material.dart';
import '../../../../core/enums/sort_mode.dart';

import '../../../widgets/context_menu/glass_context_menu.dart';

class DesktopContextMenuBuilder {
  static List<ContextMenuItem> buildDesktopContextMenuItems({
    required SortMode sortMode,
    required bool showHidden,
    required bool canPaste,
  }) {
    return [
      ContextMenuItem.action(
        id: 'new_folder',
        icon: Icons.create_new_folder_rounded,
        label: 'New Folder',
      ),
      ContextMenuItem.action(
        id: 'new_document',
        icon: Icons.note_add_rounded,
        label: 'New Document',
        children: const [
          ContextMenuItem.action(
            id: 'new_document:c',
            icon: Icons.code_rounded,
            label: 'C',
          ),
          ContextMenuItem.action(
            id: 'new_document:cpp',
            icon: Icons.developer_mode_rounded,
            label: 'C++',
          ),
          ContextMenuItem.action(
            id: 'new_document:dart',
            icon: Icons.flutter_dash_rounded,
            label: 'Dart',
          ),
          ContextMenuItem.action(
            id: 'new_document:markdown',
            icon: Icons.article_outlined,
            label: 'Markdown',
          ),
          ContextMenuItem.action(
            id: 'new_document:python',
            icon: Icons.developer_board_rounded,
            label: 'Python',
          ),
          ContextMenuItem.action(
            id: 'new_document:text',
            icon: Icons.description_rounded,
            label: 'Text',
          ),
        ],
      ),
      const ContextMenuItem.divider(),
      ContextMenuItem.action(
        id: 'paste',
        icon: Icons.content_paste_rounded,
        label: 'Paste',
        enabled: canPaste,
      ),
      ContextMenuItem.action(
        id: 'select_all',
        icon: Icons.select_all_rounded,
        label: 'Select All',
      ),
      const ContextMenuItem.divider(),
      ContextMenuItem.action(
        id: 'arrange_icons',
        icon: Icons.auto_awesome_mosaic_rounded,
        label: 'Arrange Icons',
      ),
      ContextMenuItem.action(
        id: 'arrange_by',
        icon: Icons.sort_rounded,
        label: 'Arrange By...',
        children: [
          ContextMenuItem.action(
            id: 'arrange_keep',
            icon: Icons.grid_on_rounded,
            label: 'Keep Arranged',
          ),
          ContextMenuItem.action(
            id: 'arrange_stack_type',
            icon: Icons.layers_rounded,
            label: 'Keep Stacked by Type',
            enabled: false,
          ),
          ContextMenuItem.action(
            id: 'sort_special',
            icon: Icons.storage_rounded,
            label: 'Sort Home/Drives/Trash',
            enabled: false,
          ),
          ContextMenuItem.action(
            id: 'sort_name',
            icon: Icons.sort_by_alpha_rounded,
            label: 'Sort by Name',
            isActive: sortMode == SortMode.nameAsc,
          ),
          ContextMenuItem.action(
            id: 'sort_name_desc',
            icon: Icons.sort_by_alpha_outlined,
            label: 'Sort by Name Descending',
            isActive: sortMode == SortMode.nameDesc,
          ),
          ContextMenuItem.action(
            id: 'sort_modified',
            icon: Icons.access_time_rounded,
            label: 'Sort by Modified Time',
            isActive: sortMode == SortMode.modifiedDesc,
          ),
          ContextMenuItem.action(
            id: 'sort_type',
            icon: Icons.category_rounded,
            label: 'Sort by Type',
            isActive: sortMode == SortMode.type,
          ),
          ContextMenuItem.action(
            id: 'sort_size',
            icon: Icons.bar_chart_rounded,
            label: 'Sort by Size',
            isActive: sortMode == SortMode.sizeDesc,
          ),
          ContextMenuItem.action(
            id: 'toggle_hidden',
            icon: showHidden
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
            label: showHidden ? 'Hide Hidden Files' : 'Show Hidden Files',
            isChecked: showHidden,
          ),
        ],
      ),
      const ContextMenuItem.divider(),
      ContextMenuItem.action(
        id: 'show_desktop_files',
        icon: Icons.folder_open_rounded,
        label: 'Show Desktop in Files',
      ),
      ContextMenuItem.action(
        id: 'open_terminal',
        icon: Icons.terminal_rounded,
        label: 'Open in Terminal',
      ),
      ContextMenuItem.action(
        id: 'change_background',
        icon: Icons.wallpaper_rounded,
        label: 'Change Background...',
      ),
      ContextMenuItem.action(
        id: 'desktop_icons_settings',
        icon: Icons.grid_view_rounded,
        label: 'Desktop Icons Settings',
      ),
      ContextMenuItem.action(
        id: 'display_settings',
        icon: Icons.monitor_rounded,
        label: 'Display Settings',
      ),
    ];
  }

  static List<ContextMenuItem> buildEntityContextMenuItems(String path, bool canPaste) {
    return [
      ContextMenuItem.action(
        id: 'entity:rename',
        icon: Icons.drive_file_rename_outline,
        label: 'Rename',
      ),
      ContextMenuItem.action(
        id: 'entity:delete',
        icon: Icons.delete_rounded,
        label: 'Delete',
      ),
      const ContextMenuItem.divider(),
      ContextMenuItem.action(
        id: 'entity:cut',
        icon: Icons.content_cut_rounded,
        label: 'Cut',
      ),
      ContextMenuItem.action(
        id: 'entity:copy',
        icon: Icons.content_copy_rounded,
        label: 'Copy',
      ),
      ContextMenuItem.action(
        id: 'entity:paste',
        icon: Icons.content_paste_rounded,
        label: 'Paste',
        enabled: canPaste,
      ),
      const ContextMenuItem.divider(),
      ContextMenuItem.action(
        id: 'entity:details',
        icon: Icons.info_outline,
        label: 'Details',
      ),
    ];
  }
}
