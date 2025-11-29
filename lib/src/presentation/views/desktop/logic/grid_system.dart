import 'dart:ui';

class GridSystem {
  static const double startX = 20.0;
  static const double startY = 20.0;
  static const double cellWidth = 100.0;
  static const double cellHeight = 110.0;

  Offset snapToGrid(Offset raw) {
    final col = ((raw.dx - startX) / cellWidth).round().clamp(0, 10000);
    final row = ((raw.dy - startY) / cellHeight).round().clamp(0, 10000);
    return Offset(
      startX + col * cellWidth,
      startY + row * cellHeight,
    );
  }

  (int col, int row) cellForOffset(Offset offset) {
    final snapped = snapToGrid(offset);
    final col = ((snapped.dx - startX) / cellWidth).round();
    final row = ((snapped.dy - startY) / cellHeight).round();
    return (col, row);
  }

  Offset offsetForCell(int col, int row) {
    return Offset(
      startX + col * cellWidth,
      startY + row * cellHeight,
    );
  }

  bool isCellOccupied(
    Offset candidate,
    Map<String, Map<String, double>> positions,
    String currentFilename,
  ) {
    for (final entry in positions.entries) {
      if (entry.key == currentFilename) continue;
      final pos = entry.value;
      final otherOffset = Offset(pos['x'] ?? 0, pos['y'] ?? 0);
      final otherSnapped = snapToGrid(otherOffset);
      if ((otherSnapped.dx - candidate.dx).abs() < 0.5 &&
          (otherSnapped.dy - candidate.dy).abs() < 0.5) {
        return true;
      }
    }
    return false;
  }

  Offset findNearestFreeSlot(
    Offset desired,
    String filename,
    Map<String, Map<String, double>> positions,
  ) {
    final snappedDesired = snapToGrid(desired);
    if (!isCellOccupied(snappedDesired, positions, filename)) {
      return snappedDesired;
    }

    final (baseCol, baseRow) = cellForOffset(snappedDesired);
    const int maxRadius = 50;
    for (int radius = 1; radius <= maxRadius; radius++) {
      for (int dx = -radius; dx <= radius; dx++) {
        for (int dy = -radius; dy <= radius; dy++) {
          if (dx.abs() != radius && dy.abs() != radius) continue;
          final col = baseCol + dx;
          final row = baseRow + dy;
          if (col < 0 || row < 0) continue;
          final candidate = offsetForCell(col, row);
          if (!isCellOccupied(candidate, positions, filename)) {
            return candidate;
          }
        }
      }
    }
    return snappedDesired;
  }

  Offset getDefaultPosition(int index) {
    const colCount = 6;
    final row = index % colCount;
    final col = index ~/ colCount;
    return Offset(
      startX + (col * cellWidth),
      startY + (row * cellHeight),
    );
  }

  int safeInt(int v) => v < 0 ? 0 : v;
}
