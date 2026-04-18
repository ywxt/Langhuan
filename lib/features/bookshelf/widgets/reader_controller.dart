import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Reader position — reported from content views to the parent
// ─────────────────────────────────────────────────────────────────────────────

class ReaderPosition {
  const ReaderPosition({
    required this.chapterId,
    required this.paragraphId,
    this.offset = 0,
  });

  final String chapterId;
  final String paragraphId;
  final double offset;
}

// ─────────────────────────────────────────────────────────────────────────────
// Reader controller
//
// Two-way communication channel between ReaderPage and ChapterContentManager.
//
//   ReaderPage → jumpTo() → ChapterContentManager  (imperative command)
//   ChapterContentManager → reportPosition() → ReaderPage  (position callback)
//
// This is a ChangeNotifier so the content manager can listen for jump commands
// without requiring widget rebuilds.
// ─────────────────────────────────────────────────────────────────────────────

class ReaderController extends ChangeNotifier {
  // ─ Jump command (parent → content manager) ─────────────────────────────

  String? _pendingChapterId;
  String _pendingParagraphId = '';
  double _pendingOffset = 0;

  String? get pendingChapterId => _pendingChapterId;
  String get pendingParagraphId => _pendingParagraphId;
  double get pendingOffset => _pendingOffset;

  void jumpTo({
    required String chapterId,
    String paragraphId = '',
    double offset = 0,
  }) {
    _pendingChapterId = chapterId;
    _pendingParagraphId = paragraphId;
    _pendingOffset = offset;
    notifyListeners();
  }

  void consumeJump() {
    _pendingChapterId = null;
    _pendingParagraphId = '';
    _pendingOffset = 0;
  }

  // ─ Position reporting (content manager → parent) ───────────────────────

  /// External listener for position changes — set by ReaderPage to save
  /// reading progress. The content manager never reads this.
  ValueChanged<ReaderPosition>? onPositionChanged;

  void reportPosition({
    required String chapterId,
    required String paragraphId,
    double offset = 0,
  }) {
    onPositionChanged?.call(ReaderPosition(
      chapterId: chapterId,
      paragraphId: paragraphId,
      offset: offset,
    ));
  }
}
