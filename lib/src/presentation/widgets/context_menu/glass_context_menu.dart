import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

class ContextMenuItem {
  const ContextMenuItem.action({
    required this.id,
    required this.label,
    this.icon,
    this.enabled = true,
    this.children = const [],
    this.isActive = false,
    this.isChecked,
  }) : isDivider = false;

  const ContextMenuItem.divider()
    : id = null,
      label = '',
      icon = null,
      enabled = false,
      children = const [],
      isDivider = true,
      isActive = false,
      isChecked = null;

  final String? id;
  final String label;
  final IconData? icon;
  final bool enabled;
  final List<ContextMenuItem> children;
  final bool isDivider;
  final bool isActive;
  final bool? isChecked;

  bool get hasSubmenu => children.isNotEmpty;
}

class GlassContextMenu extends StatefulWidget {
  const GlassContextMenu({
    super.key,
    required this.anchor,
    required this.items,
    required this.onClose,
    required this.onAction,
  });

  final Offset anchor;
  final List<ContextMenuItem> items;
  final VoidCallback onClose;
  final Future<void> Function(String action) onAction;

  @override
  State<GlassContextMenu> createState() => _GlassContextMenuState();
}

class _GlassContextMenuState extends State<GlassContextMenu> {
  static const double _menuWidth = 240;
  static const double _itemHeight = 38;
  static const double _menuPaddingV = 14;

  ContextMenuItem? _hoveredItem;
  ContextMenuItem? _activeSubmenu;
  Offset? _submenuOffset;
  Timer? _submenuCloseTimer;
  bool _submenuPinned = false;

  @override
  void dispose() {
    _submenuCloseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final estimatedHeight = _estimateHeight(widget.items);

    double left = widget.anchor.dx;
    double top = widget.anchor.dy;

    if (left + _menuWidth > media.size.width - 16) {
      left = media.size.width - _menuWidth - 16;
    }
    if (top + estimatedHeight > media.size.height - 16) {
      top = media.size.height - estimatedHeight - 16;
    }

    left = left.clamp(16.0, media.size.width - _menuWidth - 16.0);
    top = top.clamp(16.0, media.size.height - estimatedHeight - 16.0);

    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            onTap: widget.onClose,
            behavior: HitTestBehavior.opaque,
          ),
          Positioned(left: left, top: top, child: _buildMenu(widget.items)),
          if (_activeSubmenu != null && _submenuOffset != null)
            Positioned(
              left: _submenuOffset!.dx,
              top: _submenuOffset!.dy,
              child: _buildMenu(_activeSubmenu!.children, isSubmenu: true),
            ),
        ],
      ),
    );
  }

  double _estimateHeight(List<ContextMenuItem> items) {
    double height = _menuPaddingV * 2;
    for (final item in items) {
      height += item.isDivider ? 12 : _itemHeight + 4;
    }
    return height;
  }

  Widget _buildMenu(List<ContextMenuItem> items, {bool isSubmenu = false}) {
    const double horizontalPadding = 14;
    final Matrix4 transform = Matrix4.identity()
      ..setEntry(3, 2, 0.0012)
      ..rotateX(isSubmenu ? 0.02 : -0.05)
      ..rotateY(isSubmenu ? -0.03 : 0.05);

    final menuBody = ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 24),
        child: Container(
          width: _menuWidth,
          padding: const EdgeInsets.symmetric(
            vertical: _menuPaddingV,
            horizontal: horizontalPadding,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.18),
                const Color(0xFF0B0B0D).withOpacity(0.82),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.18), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.55),
                blurRadius: 34,
                offset: const Offset(14, 26),
                spreadRadius: -20,
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.12),
                blurRadius: 18,
                offset: const Offset(-10, -10),
                spreadRadius: -12,
              ),
            ],
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [Colors.white.withOpacity(0.06), Colors.transparent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < items.length; i++)
                  items[i].isDivider ? _buildDivider() : _buildTile(items[i]),
              ],
            ),
          ),
        ),
      ),
    );

    return MouseRegion(
      onEnter: (_) => _cancelSubmenuCloseTimer(),
      onExit: (_) {
        if (isSubmenu) {
          _scheduleSubmenuClose();
        }
      },
      child: Transform(
        alignment: Alignment.topLeft,
        transform: transform,
        child: menuBody,
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        height: 1,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white24, Colors.white10, Colors.transparent],
          ),
        ),
      ),
    );
  }

  Widget _buildTile(ContextMenuItem item) {
    final key = GlobalKey();
    final bool isDisabled = !item.enabled;
    final bool isHovered = _hoveredItem == item;
    final Color textColor = isDisabled
        ? Colors.white.withOpacity(0.35)
        : isHovered
        ? Colors.white
        : Colors.white.withOpacity(0.82);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: MouseRegion(
        onEnter: (_) {
          if (_submenuPinned && _activeSubmenu != item) return;
          _handleHover(item, key);
        },
        onExit: (_) {
          if (item.hasSubmenu && !_submenuPinned) {
            _scheduleSubmenuClose();
          }
          if (_hoveredItem == item && !item.hasSubmenu) {
            setState(() {
              _hoveredItem = null;
            });
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: isDisabled
              ? null
              : () async {
                  if (item.hasSubmenu) {
                    if (_submenuPinned && _activeSubmenu == item) {
                      setState(() {
                        _resetSubmenuState();
                      });
                    } else {
                      _handleHover(item, key, pin: true);
                    }
                  } else if (item.id != null) {
                    setState(() {
                      _resetSubmenuState();
                    });
                    await widget.onAction(item.id!);
                  }
                },
          child: AnimatedContainer(
            key: key,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            height: _itemHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isHovered
                  ? Colors.white.withOpacity(0.18)
                  : Colors.white.withOpacity(0.04),
              boxShadow: isHovered
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 18,
                        offset: const Offset(4, 8),
                        spreadRadius: -10,
                      ),
                    ]
                  : null,
              border: isHovered
                  ? Border.all(color: Colors.white.withOpacity(0.24), width: 1)
                  : null,
            ),
            child: Row(
              children: [
                if (item.icon != null)
                  IconOrb(
                    icon: item.icon!,
                    active: item.isActive,
                    disabled: isDisabled,
                    checked: item.isChecked ?? false,
                  ),
                if (item.icon != null) const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: item.isActive
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: textColor,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                if (item.isChecked ?? false)
                  Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: Colors.tealAccent.shade100,
                  ),
                if (item.hasSubmenu)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: Colors.white.withOpacity(isDisabled ? 0.25 : 0.7),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleHover(ContextMenuItem item, GlobalKey key, {bool pin = false}) {
    if (_submenuPinned && !pin && _activeSubmenu != item) {
      return;
    }

    if (pin) {
      _submenuPinned = true;
    }

    _cancelSubmenuCloseTimer();
    setState(() {
      _hoveredItem = item;
      if (!item.hasSubmenu) {
        _submenuPinned = false;
        _activeSubmenu = null;
        _submenuOffset = null;
      }
    });
    if (!item.hasSubmenu) {
      return;
    }

    final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    final overlayState = Overlay.maybeOf(context);
    final overlayBox = overlayState?.context.findRenderObject() as RenderBox?;
    if (renderBox == null || overlayBox == null) return;

    final itemGlobal = renderBox.localToGlobal(Offset.zero);
    final itemLocal = overlayBox.globalToLocal(itemGlobal);
    final submenuLeft = itemLocal.dx + renderBox.size.width - 6;
    double submenuTop = itemLocal.dy - 10;

    final menuHeight = _estimateHeight(item.children);
    final mediaHeight = MediaQuery.of(context).size.height;
    if (submenuTop + menuHeight > mediaHeight - 16) {
      submenuTop = mediaHeight - menuHeight - 16;
    }
    if (submenuTop < 16) submenuTop = 16;

    setState(() {
      _activeSubmenu = item;
      _submenuOffset = Offset(submenuLeft, submenuTop);
    });
  }

  void _scheduleSubmenuClose() {
    if (_submenuPinned) return;
    _submenuCloseTimer?.cancel();
    _submenuCloseTimer = Timer(const Duration(milliseconds: 160), () {
      if (!mounted) return;
      setState(() {
        _resetSubmenuState();
      });
    });
  }

  void _cancelSubmenuCloseTimer() {
    _submenuCloseTimer?.cancel();
    _submenuCloseTimer = null;
  }

  void _resetSubmenuState() {
    _submenuPinned = false;
    _activeSubmenu = null;
    _submenuOffset = null;
    _hoveredItem = null;
  }
}

class IconOrb extends StatelessWidget {
  const IconOrb({
    super.key,
    required this.icon,
    required this.active,
    required this.disabled,
    required this.checked,
  });

  final IconData icon;
  final bool active;
  final bool disabled;
  final bool checked;

  @override
  Widget build(BuildContext context) {
    final Color baseColor = disabled
        ? Colors.white.withOpacity(0.25)
        : active || checked
        ? Colors.tealAccent.shade100
        : Colors.white.withOpacity(0.82);

    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.12),
            Colors.black.withOpacity(0.45),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.22), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(6, 8),
            spreadRadius: -6,
          ),
        ],
      ),
      child: Icon(icon, size: 14, color: baseColor),
    );
  }
}
