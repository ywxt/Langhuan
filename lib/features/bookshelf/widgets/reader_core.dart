import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../src/rust/api/types.dart';
import '../../feeds/feed_service.dart';
import 'reader_types.dart';

typedef ChapterParagraphLoader =
    Future<List<ParagraphContent>> Function(String chapterId);

enum ReaderJumpStatus { success, notFound, timeout, cancelled }

class ReaderJumpOutcome {
  const ReaderJumpOutcome({required this.status, required this.chapterId});

  final ReaderJumpStatus status;
  final String chapterId;
}

class ReaderCoreSnapshot {
  const ReaderCoreSnapshot({
    required this.centerChapterId,
    required this.prevChapterId,
    required this.nextChapterId,
    required this.prevSlot,
    required this.centerSlot,
    required this.nextSlot,
    required this.isFirst,
    required this.isLast,
    required this.generation,
    this.lastJumpOutcome,
  });

  final String centerChapterId;
  final String? prevChapterId;
  final String? nextChapterId;
  final ChapterLoadState prevSlot;
  final ChapterLoadState centerSlot;
  final ChapterLoadState nextSlot;
  final bool isFirst;
  final bool isLast;
  final int generation;
  final ReaderJumpOutcome? lastJumpOutcome;
}

class ReaderCore extends ChangeNotifier {
  ReaderCore({
    required ChapterParagraphLoader loader,
    required String Function(Object error) normalizeError,
  }) : _loader = loader,
       _normalizeError = normalizeError;

  static const _maxCacheSize = 5;
  static const _chapterLoadTimeout = Duration(seconds: 20);
  static const _enableDebugLogs = bool.fromEnvironment(
    'READER_DEBUG_LOGS',
    defaultValue: false,
  );

  final ChapterParagraphLoader _loader;
  final String Function(Object error) _normalizeError;

  String _feedId = '';
  String _bookId = '';
  List<ChapterInfoModel> _chapters = const [];

  final Map<String, List<ParagraphContent>> _cache = {};

  String _centerChapterId = '';
  ChapterLoadState _prevSlot = const ChapterIdle();
  ChapterLoadState _centerSlot = const ChapterLoading();
  ChapterLoadState _nextSlot = const ChapterIdle();
  bool _centerReady = false;
  int _loadGeneration = 0;

  String _pendingJumpParagraphId = '';
  double _pendingJumpParagraphOffset = 0;
  bool _pendingFromEnd = false;
  ReaderJumpOutcome? _lastJumpOutcome;

  ValueChanged<ReaderJumpOutcome>? onJumpOutcome;

  void _log(String message) {
    if (!kDebugMode || !_enableDebugLogs) return;
    debugPrint('[ReaderCore] $message');
  }

  String get feedId => _feedId;
  String get bookId => _bookId;
  List<ChapterInfoModel> get chapters => _chapters;
  String get centerChapterId => _centerChapterId;
  bool get centerReady => _centerReady;
  int get loadGeneration => _loadGeneration;
  String get pendingJumpParagraphId => _pendingJumpParagraphId;
  double get pendingJumpParagraphOffset => _pendingJumpParagraphOffset;
  bool get pendingFromEnd => _pendingFromEnd;
  ReaderJumpOutcome? get lastJumpOutcome => _lastJumpOutcome;

  ChapterLoadState get prevSlot => _prevSlot;
  ChapterLoadState get centerSlot => _centerSlot;
  ChapterLoadState get nextSlot => _nextSlot;

  bool get isFirst => _idxOf(_centerChapterId) == 0;
  bool get isLast => _idxOf(_centerChapterId) == _chapters.length - 1;

  String? get prevChapterId => _prevId();
  String? get nextChapterId => _nextId();

  ReaderCoreSnapshot get snapshot => ReaderCoreSnapshot(
    centerChapterId: _centerChapterId,
    prevChapterId: _prevId(),
    nextChapterId: _nextId(),
    prevSlot: _prevSlot,
    centerSlot: _centerSlot,
    nextSlot: _nextSlot,
    isFirst: isFirst,
    isLast: isLast,
    generation: _loadGeneration,
    lastJumpOutcome: _lastJumpOutcome,
  );

  void setSource({
    required String feedId,
    required String bookId,
    required List<ChapterInfoModel> chapters,
    required String initialChapterId,
    String initialParagraphId = '',
    double initialParagraphOffset = 0,
    bool clearCache = true,
  }) {
    _feedId = feedId;
    _bookId = bookId;
    _chapters = chapters;
    _centerChapterId = initialChapterId;
    _pendingJumpParagraphId = initialParagraphId;
    _pendingJumpParagraphOffset = initialParagraphOffset;
    _pendingFromEnd = false;
    _lastJumpOutcome = null;

    if (clearCache) {
      _cache.clear();
    }

    _prevSlot = const ChapterIdle();
    _centerSlot = const ChapterLoading();
    _nextSlot = const ChapterIdle();
    _centerReady = false;
    _log(
      'setSource feed=$feedId book=$bookId center=$_centerChapterId '
      'pendingParagraph=$_pendingJumpParagraphId pendingOffset=$_pendingJumpParagraphOffset '
      'clearCache=$clearCache chapters=${_chapters.length}',
    );
    notifyListeners();
  }

  Future<void> initCenter() async {
    final gen = ++_loadGeneration;
    _log('initCenter start gen=$gen center=$_centerChapterId');
    _prevSlot = const ChapterIdle();
    _centerSlot = const ChapterLoading();
    _nextSlot = const ChapterIdle();
    notifyListeners();

    await _loadSlot(_centerChapterId, _setCenterSlot, gen);
    if (gen != _loadGeneration) {
      _log('initCenter discarded gen=$gen activeGen=$_loadGeneration');
      return;
    }

    _centerReady = true;
    _log('initCenter ready gen=$gen center=$_centerChapterId');
    notifyListeners();
    unawaited(_loadAdjacent(gen));
  }

  Future<void> retry(String chapterId) async {
    final gen = _loadGeneration;
    _log('retry chapter=$chapterId gen=$gen center=$_centerChapterId');
    if (chapterId == _centerChapterId) {
      await _loadSlot(chapterId, _setCenterSlot, gen);
      return;
    }
    if (chapterId == _prevId()) {
      await _loadSlot(chapterId, _setPrevSlot, gen);
      return;
    }
    if (chapterId == _nextId()) {
      await _loadSlot(chapterId, _setNextSlot, gen);
    }
  }

  Future<void> jumpTo({
    required String chapterId,
    String paragraphId = '',
    double paragraphOffset = 0,
  }) async {
    _log(
      'jumpTo request chapter=$chapterId paragraph=$paragraphId '
      'offset=$paragraphOffset',
    );
    _centerChapterId = chapterId;
    _pendingJumpParagraphId = paragraphId;
    _pendingJumpParagraphOffset = paragraphOffset;
    _pendingFromEnd = false;

    if (_cache.containsKey(chapterId)) {
      _log('jumpTo hit cache chapter=$chapterId');
      _setCenterSlot(ChapterLoaded(_cache[chapterId]!));
      _setPrevSlot(_resolveSlot(_prevId()));
      _setNextSlot(_resolveSlot(_nextId()));
      _centerReady = true;
      notifyListeners();
      unawaited(_loadAdjacent(_loadGeneration));
      return;
    }

    _centerReady = false;
    _log('jumpTo miss cache chapter=$chapterId -> initCenter');
    notifyListeners();
    await initCenter();
  }

  Future<void> slideToNext() async {
    await _performSlide(1);
  }

  Future<void> slideToPrev() async {
    await _performSlide(-1);
  }

  void consumePendingJump() {
    _log(
      'consumePendingJump paragraph=$_pendingJumpParagraphId '
      'offset=$_pendingJumpParagraphOffset fromEnd=$_pendingFromEnd',
    );
    _pendingJumpParagraphId = '';
    _pendingJumpParagraphOffset = 0;
    _pendingFromEnd = false;
  }

  void reportJumpOutcome(ReaderJumpStatus status, {String? chapterId}) {
    _lastJumpOutcome = ReaderJumpOutcome(
      status: status,
      chapterId: chapterId ?? _centerChapterId,
    );
    onJumpOutcome?.call(_lastJumpOutcome!);
    _log('jumpOutcome status=$status chapter=${chapterId ?? _centerChapterId}');
    notifyListeners();
  }

  void setPendingFromEnd(bool value) {
    _log('setPendingFromEnd value=$value');
    _pendingFromEnd = value;
  }

  void setPendingJumpPosition({
    required String paragraphId,
    required double paragraphOffset,
  }) {
    _log(
      'setPendingJumpPosition paragraph=$paragraphId offset=$paragraphOffset',
    );
    _pendingJumpParagraphId = paragraphId;
    _pendingJumpParagraphOffset = paragraphOffset;
    _pendingFromEnd = false;
  }

  List<ParagraphContent>? cachedParagraphs(String chapterId) =>
      _cache[chapterId];

  @visibleForTesting
  int get cacheSize => _cache.length;

  @visibleForTesting
  bool hasCachedChapter(String chapterId) => _cache.containsKey(chapterId);

  Future<void> _performSlide(int direction) async {
    final newCenterId = direction > 0 ? _nextId() : _prevId();
    if (newCenterId == null) {
      _log('slide ignored direction=$direction (no target chapter)');
      return;
    }

    _log(
      'slide start direction=$direction oldCenter=$_centerChapterId '
      'newCenter=$newCenterId gen=$_loadGeneration',
    );

    _centerChapterId = newCenterId;
    _pendingFromEnd = direction < 0;
    _pendingJumpParagraphId = '';
    _pendingJumpParagraphOffset = 0;

    _setCenterSlot(
      _cache.containsKey(newCenterId)
          ? ChapterLoaded(_cache[newCenterId]!)
          : const ChapterLoading(),
    );
    _setPrevSlot(_resolveSlot(_prevId()));
    _setNextSlot(_resolveSlot(_nextId()));
    notifyListeners();

    if (!_cache.containsKey(newCenterId)) {
      _log('slide center chapter not cached: $newCenterId');
      await _loadSlot(newCenterId, _setCenterSlot, _loadGeneration);
    }
    unawaited(_loadAdjacent(_loadGeneration));
    _log('slide complete center=$_centerChapterId gen=$_loadGeneration');
  }

  Future<void> _loadSlot(
    String chapterId,
    void Function(ChapterLoadState state) applyState,
    int gen,
  ) async {
    if (chapterId.isEmpty) return;
    _log(
      'loadSlot start chapter=$chapterId gen=$gen activeGen=$_loadGeneration',
    );
    if (_cache.containsKey(chapterId)) {
      _log('loadSlot cache hit chapter=$chapterId');
      applyState(ChapterLoaded(_cache[chapterId]!));
      notifyListeners();
      return;
    }

    applyState(const ChapterLoading());
    notifyListeners();

    try {
      final paragraphs = await _loader(chapterId).timeout(
        _chapterLoadTimeout,
        onTimeout: () {
          throw TimeoutException(
            'Chapter load timed out after ${_chapterLoadTimeout.inSeconds}s',
          );
        },
      );
      if (gen != _loadGeneration) {
        _log(
          'loadSlot stale result ignored chapter=$chapterId gen=$gen '
          'activeGen=$_loadGeneration',
        );
        return;
      }
      _putCache(chapterId, paragraphs);
      applyState(ChapterLoaded(paragraphs));
      _log(
        'loadSlot success chapter=$chapterId paragraphs=${paragraphs.length}',
      );
      notifyListeners();
    } catch (e) {
      if (gen != _loadGeneration) {
        _log(
          'loadSlot stale error ignored chapter=$chapterId gen=$gen '
          'activeGen=$_loadGeneration',
        );
        return;
      }
      applyState(ChapterLoadError(error: e, message: _normalizeError(e)));
      _log('loadSlot error chapter=$chapterId error=${_normalizeError(e)}');
      notifyListeners();
    }
  }

  Future<void> _loadAdjacent(int gen) async {
    final prev = _prevId();
    final next = _nextId();
    _log(
      'loadAdjacent gen=$gen prev=$prev next=$next center=$_centerChapterId',
    );
    if (prev != null) {
      await _loadSlot(prev, _setPrevSlot, gen);
    }
    if (next != null) {
      await _loadSlot(next, _setNextSlot, gen);
    }
  }

  int _idxOf(String chapterId) {
    final idx = _chapters.indexWhere((c) => c.id == chapterId);
    return idx >= 0 ? idx : 0;
  }

  String? _prevId([String? centerId]) {
    final idx = _idxOf(centerId ?? _centerChapterId);
    return idx > 0 ? _chapters[idx - 1].id : null;
  }

  String? _nextId([String? centerId]) {
    final idx = _idxOf(centerId ?? _centerChapterId);
    return idx < _chapters.length - 1 ? _chapters[idx + 1].id : null;
  }

  void _putCache(String chapterId, List<ParagraphContent> paragraphs) {
    _cache.remove(chapterId);
    _cache[chapterId] = paragraphs;
    if (_cache.length <= _maxCacheSize) return;

    final keep = <String>{
      _centerChapterId,
      if (_prevId() != null) _prevId()!,
      if (_nextId() != null) _nextId()!,
    };

    final keys = _cache.keys.toList();
    for (final key in keys) {
      if (_cache.length <= _maxCacheSize) break;
      if (!keep.contains(key)) {
        _cache.remove(key);
      }
    }
  }

  ChapterLoadState _resolveSlot(String? chapterId) {
    if (chapterId == null) return const ChapterIdle();
    if (_cache.containsKey(chapterId)) {
      return ChapterLoaded(_cache[chapterId]!);
    }
    return const ChapterIdle();
  }

  void _setPrevSlot(ChapterLoadState state) {
    _prevSlot = state;
  }

  void _setCenterSlot(ChapterLoadState state) {
    _centerSlot = state;
  }

  void _setNextSlot(ChapterLoadState state) {
    _nextSlot = state;
  }
}
