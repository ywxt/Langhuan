import 'package:flutter/material.dart';

import '../../feeds/feed_service.dart';
import 'chapter_window_manager.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BaseReaderView — shared widget props
// ─────────────────────────────────────────────────────────────────────────────

/// Abstract base widget for reader views.
/// Holds all shared constructor parameters, including optional book info
/// used for boundary rendering (book info card, end-of-book message).
abstract class BaseReaderView extends StatefulWidget {
  const BaseReaderView({
    super.key,
    required this.feedId,
    required this.bookId,
    required this.chapters,
    required this.initialChapterId,
    required this.initialParagraphIndex,
    required this.contentPadding,
    required this.onChapterChanged,
    required this.onParagraphChanged,
    this.bookTitle,
    this.bookAuthor,
    this.bookCoverUrl,
    this.bookDescription,
  });

  final String feedId;
  final String bookId;
  final List<ChapterInfoModel> chapters;
  final String initialChapterId;
  final int initialParagraphIndex;
  final EdgeInsets contentPadding;
  final ValueChanged<String> onChapterChanged;
  final ValueChanged<int> onParagraphChanged;

  /// Optional book metadata for boundary UI.
  final String? bookTitle;
  final String? bookAuthor;
  final String? bookCoverUrl;
  final String? bookDescription;
}

// ─────────────────────────────────────────────────────────────────────────────
// BaseReaderViewState — shared state logic via Template Method
// ─────────────────────────────────────────────────────────────────────────────

/// Abstract base state implementing shared chapter-window logic.
///
/// Uses the Template Method pattern: lifecycle, preloading, chapter tracking,
/// and eviction callbacks are handled here. Subclasses implement the
/// view-specific parts (controller, cache/page building, position restore,
/// boundary rendering, and [build]).
abstract class BaseReaderViewState<T extends BaseReaderView> extends State<T>
    with ChapterWindowManager<T> {
  // ─ Shared tracking state (library-private; mutate via helpers below)
  String? _currentVisibleChapterId;

  // ─ Shared boundary helpers ────────────────────────────────────────────────

  /// True when the first loaded chapter is chapter index 0 (book start).
  bool get isAtBookStart =>
      loadedSlots.isNotEmpty && loadedSlots.first.chapterIndex == 0;

  /// True when the last loaded chapter is the final chapter.
  bool get isAtBookEnd =>
      loadedSlots.isNotEmpty &&
      loadedSlots.last.chapterIndex == widget.chapters.length - 1;

  /// Whether a top boundary should currently be shown.
  /// True whenever any chapters are loaded — either book info (at ch 0)
  /// or a loading spinner (older chapter not yet loaded).
  bool get hasTopBoundary => loadedSlots.isNotEmpty;

  /// Whether a bottom boundary should currently be shown.
  /// True whenever any chapters are loaded — either end-of-book (at last ch)
  /// or a loading spinner (newer chapter not yet loaded).
  bool get hasBottomBoundary => loadedSlots.isNotEmpty;

  // ─ Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    initChapterWindow(
      chapters: widget.chapters,
      feedId: widget.feedId,
      bookId: widget.bookId,
    );
    initController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initialize();
    });
  }

  @override
  void dispose() {
    disposeController();
    disposeChapterWindow();
    super.dispose();
  }

  // ─ Template methods ───────────────────────────────────────────────────────

  Future<void> _initialize() async {
    await loadInitial(widget.initialChapterId);
    if (mounted) {
      onInitialLoadComplete();
      restoreInitialPosition();
    }
  }

  /// Trigger preload of adjacent chapters when approaching a view boundary.
  /// The threshold check is delegated to [isApproachingEnd] / [isApproachingStart].
  void preloadIfApproachingBoundary() {
    if (isApproachingEnd() && hasNewerUnloaded) {
      final nextIdx = loadedSlots.last.chapterIndex + 1;
      if (nextIdx < widget.chapters.length) {
        loadChapter(widget.chapters[nextIdx].id).catchError((_) {});
      }
    }
    if (isApproachingStart() && hasOlderUnloaded) {
      final prevIdx = loadedSlots.first.chapterIndex - 1;
      if (prevIdx >= 0) {
        loadChapter(widget.chapters[prevIdx].id).catchError((_) {});
      }
    }
  }

  /// Call from the position listener when a chapter becomes visible.
  /// Fires [widget.onChapterChanged] and [setCurrentChapter] only on change.
  void handleChapterBecameVisible(String chapterId) {
    if (_currentVisibleChapterId != chapterId) {
      _currentVisibleChapterId = chapterId;
      setCurrentChapter(chapterId);
      widget.onChapterChanged(chapterId);
    }
  }

  /// Update the tracked paragraph index and fire [widget.onParagraphChanged].
  void updateParagraphIndex(int index) {
    widget.onParagraphChanged(index);
  }

  // ─ ChapterWindowManager callbacks (template) ─────────────────────────────

  @override
  void onChapterLoaded(ChapterSlot slot) {
    if (mounted) {
      onSlotLoaded(slot);
      setState(() {});
    }
  }

  @override
  void onChaptersEvicted(ChapterSlot slot, bool fromTop) {
    if (mounted) {
      onSlotEvicted(slot, fromTop);
      setState(() {});
    }
  }

  // ─ Abstract methods (subclass must implement) ─────────────────────────────

  /// Create and attach the view controller (ScrollController / PageController).
  void initController();

  /// Dispose and detach the view controller.
  void disposeController();

  /// Called after the initial chapter window loads.
  /// Subclass should rebuild its cache/page array and call setState as needed.
  void onInitialLoadComplete();

  /// Restore the scroll/page position to [widget.initialParagraphIndex].
  void restoreInitialPosition();

  /// Return true when the view is near its trailing edge (triggers next-chapter preload).
  bool isApproachingEnd();

  /// Return true when the view is near its leading edge (triggers prev-chapter preload).
  bool isApproachingStart();

  /// Called from [onChapterLoaded] before setState. Rebuild cache/page array.
  void onSlotLoaded(ChapterSlot slot);

  /// Called from [onChaptersEvicted] before setState. Rebuild and adjust offset.
  void onSlotEvicted(ChapterSlot slot, bool fromTop);
}
