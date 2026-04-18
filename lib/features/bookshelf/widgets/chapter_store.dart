import 'dart:collection';
import 'package:flutter/foundation.dart';

import '../../../src/rust/api/types.dart';
import '../../feeds/feed_service.dart';
import 'page_breaker.dart';
import 'reader_types.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Chapter store
//
// Replaces the 3-slot sliding window (prev/center/next ValueNotifier) with a
// demand-loaded cache keyed by chapter index.  Reader views ask "give me
// paragraphs for chapter N" — the store returns cached data or kicks off a
// fetch and notifies when ready.
// ─────────────────────────────────────────────────────────────────────────────

class ChapterStore extends ChangeNotifier {
  ChapterStore({
    required this.feedId,
    required this.bookId,
    required this.chapters,
  }) {
    _buildIndexes();
  }

  final String feedId;
  final String bookId;
  final List<ChapterInfoModel> chapters;

  bool _disposed = false;

  // ─ Index helpers ──────────────────────────────────────────────────────────

  late final Map<String, int> _idToSeq; // chapterId → sequential index
  late final Map<int, String> _seqToId; // sequential index → chapterId
  late final int _minSeq;
  late final int _maxSeq;

  /// Ordered list of chapter sequential indices (may have gaps).
  late final List<int> _sortedSeqs;

  void _buildIndexes() {
    _idToSeq = {for (final c in chapters) c.id: c.index};
    _seqToId = {for (final c in chapters) c.index: c.id};
    if (chapters.isEmpty) {
      _minSeq = 0;
      _maxSeq = -1;
      _sortedSeqs = const [];
    } else {
      final seqs = chapters.map((c) => c.index).toList()..sort();
      _sortedSeqs = seqs;
      _minSeq = seqs.first;
      _maxSeq = seqs.last;
    }
  }

  int get chapterCount => chapters.length;
  int get minSeq => _minSeq;
  int get maxSeq => _maxSeq;

  int seqOf(String chapterId) => _idToSeq[chapterId] ?? -1;
  String? idAt(int seq) => _seqToId[seq];

  bool isFirst(int seq) => seq == _minSeq;
  bool isLast(int seq) => seq == _maxSeq;

  /// Returns the next valid sequential index after [seq], or null.
  int? nextSeq(int seq) {
    // Binary search in _sortedSeqs for the first value > seq
    int lo = 0, hi = _sortedSeqs.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_sortedSeqs[mid] <= seq) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo < _sortedSeqs.length ? _sortedSeqs[lo] : null;
  }

  /// Returns the previous valid sequential index before [seq], or null.
  int? prevSeq(int seq) {
    int lo = 0, hi = _sortedSeqs.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_sortedSeqs[mid] < seq) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo > 0 ? _sortedSeqs[lo - 1] : null;
  }

  // ─ Chapter data cache ─────────────────────────────────────────────────────

  /// Loaded paragraph data keyed by chapter sequential index.
  final SplayTreeMap<int, List<ParagraphContent>> _data = SplayTreeMap();

  /// Load state for chapters that are currently loading or failed.
  final Map<int, ChapterLoadState> _states = {};

  /// Maximum cached chapters. Evict furthest from active chapter.
  static const _maxCacheSize = 7;

  /// The chapter index currently considered "active" (for eviction priority).
  int _activeSeq = 0;
  int get activeSeq => _activeSeq;

  /// Returns loaded paragraphs, or null if not yet loaded.
  List<ParagraphContent>? paragraphsAt(int seq) => _data[seq];

  /// Returns the load state for a chapter.
  ChapterLoadState stateAt(int seq) {
    if (_data.containsKey(seq)) return ChapterLoaded(_data[seq]!);
    return _states[seq] ?? const ChapterIdle();
  }

  /// Ensure a chapter is loaded. Returns immediately if cached.
  /// Notifies listeners when loading completes.
  void ensureLoaded(int seq) {
    if (_data.containsKey(seq)) return;
    if (_states[seq] is ChapterLoading) return;
    _loadChapter(seq);
  }

  /// Set the active chapter (used for cache eviction priority and preloading).
  /// Does NOT call notifyListeners — purely bookkeeping.
  void setActive(int seq) {
    final changed = _activeSeq != seq;
    _activeSeq = seq;
    if (changed) _evict();
    // Always preload adjacent chapters, even if activeSeq didn't change.
    final prev = prevSeq(seq);
    final next = nextSeq(seq);
    if (prev != null) ensureLoaded(prev);
    if (next != null) ensureLoaded(next);
  }

  /// Force-reload a chapter (e.g. after retry).
  void reload(int seq) {
    _data.remove(seq);
    _pageCache.remove(seq);
    _states.remove(seq);
    _loadChapter(seq);
  }

  /// Clear all cached data (e.g. when conversion mode changes).
  void clearAll() {
    _data.clear();
    _states.clear();
    _pageCache.clear();
    notifyListeners();
  }

  /// Directly insert paragraphs into the cache (used by content manager
  /// when it fetches the initial center chapter itself).
  void putDirect(int seq, List<ParagraphContent> paragraphs) {
    _data[seq] = paragraphs;
    _pageCache.remove(seq);
    _states.remove(seq);
    _evict();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _loadChapter(int seq) async {
    final chapterId = idAt(seq);
    if (chapterId == null) return;

    _states[seq] = const ChapterLoading();

    try {
      final paragraphs = await FeedService.instance
          .paragraphs(
            feedId: feedId,
            bookId: bookId,
            chapterId: chapterId,
          )
          .toList();

      if (_disposed) return;

      _data[seq] = paragraphs;
      _states.remove(seq);
      _evict(protect: seq);
      notifyListeners();
    } catch (e) {
      if (_disposed) return;

      _states[seq] = ChapterLoadError(
        error: e,
        message: normalizeErrorMessage(e),
      );
      notifyListeners();
    }
  }

  void _evict({int? protect}) {
    if (_data.length <= _maxCacheSize) return;

    final keys = _data.keys.toList()
      ..sort((a, b) =>
          (a - _activeSeq).abs().compareTo((b - _activeSeq).abs()));

    for (int i = _maxCacheSize; i < keys.length; i++) {
      final key = keys[i];
      if (key == protect) continue;
      _data.remove(key);
      _pageCache.remove(key);
    }
  }

  // ─ Computed page cache (for horizontal mode) ─────────────────────────────

  final Map<int, List<PageContent>> _pageCache = {};

  /// Get or compute pages for a chapter. Returns null if paragraphs not loaded.
  List<PageContent>? pagesAt(int seq, PageBreaker breaker) {
    if (!_data.containsKey(seq)) return null;
    final cached = _pageCache[seq];
    if (cached != null) return cached;
    final pages = breaker.computePages(_data[seq]!);
    _pageCache[seq] = pages;
    return pages;
  }

  /// Invalidate page cache (e.g. on font/line-height change).
  void invalidatePages() {
    _pageCache.clear();
  }
}
