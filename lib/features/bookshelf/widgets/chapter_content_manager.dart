import 'dart:async';

import 'package:flutter/material.dart';

import '../../../src/rust/api/types.dart';
import '../../feeds/feed_service.dart';
import '../reader_settings_provider.dart';
import 'chapter_status_block.dart';
import 'horizontal_reader_view.dart';
import 'reader_controller.dart';
import 'reader_types.dart';
import 'vertical_reader_view.dart';

class ChapterContentManager extends StatefulWidget {
  const ChapterContentManager({
    super.key,
    required this.feedId,
    required this.bookId,
    required this.chapters,
    required this.controller,
    required this.mode,
    required this.fontScale,
    required this.lineHeight,
    required this.contentPadding,
    required this.chineseConversion,
    this.onParagraphLongPress,
    this.selectedChapterId,
    this.selectedParagraphId,
  });

  final String feedId;
  final String bookId;
  final List<ChapterInfoModel> chapters;
  final ReaderController controller;
  final ReaderMode mode;
  final double fontScale;
  final double lineHeight;
  final EdgeInsets contentPadding;
  final ChineseConversionMode chineseConversion;
  final void Function(
    String chapterId,
    String paragraphId,
    ParagraphContent paragraph,
    Rect globalRect,
  )? onParagraphLongPress;
  final String? selectedChapterId;
  final String? selectedParagraphId;

  @override
  State<ChapterContentManager> createState() => _ChapterContentManagerState();
}

class _ChapterContentManagerState extends State<ChapterContentManager> {
  final ValueNotifier<ChapterLoadState> _prevSlot =
      ValueNotifier(const ChapterIdle());
  final ValueNotifier<ChapterLoadState> _centerSlot =
      ValueNotifier(const ChapterLoading());
  final ValueNotifier<ChapterLoadState> _nextSlot =
      ValueNotifier(const ChapterIdle());

  final Map<String, List<ParagraphContent>> _cache = {};
  static const _maxCacheSize = 5;

  late String _centerChapterId;
  int _jumpGeneration = 0;
  String _pendingJumpParagraphId = '';
  double _pendingJumpOffset = 0;
  bool _pendingFromEnd = false;

  String _lastReportedParagraphId = '';
  double _lastReportedOffset = 0;

  void Function(String paragraphId, double offset)? _onViewJump;

  int _loadGeneration = 0;
  bool _centerReady = false;

  // ─ Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    final startId = widget.controller.pendingChapterId ??
        (widget.chapters.isNotEmpty ? widget.chapters.first.id : '');
    _centerChapterId = startId;
    _pendingJumpParagraphId = widget.controller.pendingParagraphId;
    _pendingJumpOffset = widget.controller.pendingOffset;
    widget.controller.consumeJump();
    widget.controller.addListener(_onJumpCommand);

    _initCenter();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onJumpCommand);
    _prevSlot.dispose();
    _centerSlot.dispose();
    _nextSlot.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChapterContentManager oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onJumpCommand);
      widget.controller.addListener(_onJumpCommand);
    }

    final sourceChanged = oldWidget.feedId != widget.feedId ||
        oldWidget.bookId != widget.bookId ||
        oldWidget.chapters != widget.chapters;

    if (sourceChanged) {
      _centerChapterId =
          widget.chapters.isNotEmpty ? widget.chapters.first.id : '';
      _cache.clear();
      _centerReady = false;
      _initCenter();
      return;
    }

    if (oldWidget.chineseConversion != widget.chineseConversion) {
      _pendingJumpParagraphId = _lastReportedParagraphId;
      _pendingJumpOffset = 0;
      _pendingFromEnd = false;
      _jumpGeneration++;
      _cache.clear();
      _centerReady = false;
      _initCenter();
      return;
    }

    if (oldWidget.mode != widget.mode) {
      _pendingJumpParagraphId = _lastReportedParagraphId;
      _pendingJumpOffset = _lastReportedOffset;
      _pendingFromEnd = false;
      _jumpGeneration++;
      setState(() {});
    }

    if (oldWidget.fontScale != widget.fontScale ||
        oldWidget.lineHeight != widget.lineHeight) {
      _pendingJumpParagraphId = _lastReportedParagraphId;
      _pendingJumpOffset = 0;
      _pendingFromEnd = false;
      _jumpGeneration++;
      setState(() {});
    }
  }

  // ─ Index helpers ────────────────────────────────────────────────────────

  int _idxOf(String chapterId) {
    final idx = widget.chapters.indexWhere((c) => c.id == chapterId);
    return idx >= 0 ? idx : 0;
  }

  String? _prevId([String? centerId]) {
    final idx = _idxOf(centerId ?? _centerChapterId);
    return idx > 0 ? widget.chapters[idx - 1].id : null;
  }

  String? _nextId([String? centerId]) {
    final idx = _idxOf(centerId ?? _centerChapterId);
    return idx < widget.chapters.length - 1
        ? widget.chapters[idx + 1].id
        : null;
  }

  bool get _isFirst => _idxOf(_centerChapterId) == 0;
  bool get _isLast => _idxOf(_centerChapterId) == widget.chapters.length - 1;

  // ─ LRU cache ──────────────────────────────────────────────────────────

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
    for (final k in keys) {
      if (_cache.length <= _maxCacheSize) break;
      if (!keep.contains(k)) _cache.remove(k);
    }
  }

  ChapterLoadState _resolveSlot(String? chapterId) {
    if (chapterId == null) return const ChapterIdle();
    if (_cache.containsKey(chapterId)) {
      return ChapterLoaded(_cache[chapterId]!);
    }
    return const ChapterIdle();
  }

  // ─ Async loading ──────────────────────────────────────────────────────

  Future<void> _initCenter() async {
    final gen = ++_loadGeneration;

    _prevSlot.value = const ChapterIdle();
    _centerSlot.value = const ChapterLoading();
    _nextSlot.value = const ChapterIdle();
    setState(() {});

    await _loadSlot(_centerChapterId, _centerSlot, gen);
    if (!mounted || gen != _loadGeneration) return;

    _centerReady = true;
    setState(() {});

    _loadAdjacent(gen);
  }

  Future<void> _loadSlot(
    String chapterId,
    ValueNotifier<ChapterLoadState> slot,
    int gen,
  ) async {
    if (_cache.containsKey(chapterId)) {
      slot.value = ChapterLoaded(_cache[chapterId]!);
      return;
    }
    slot.value = const ChapterLoading();
    try {
      final paragraphs = await FeedService.instance
          .paragraphs(
            feedId: widget.feedId,
            bookId: widget.bookId,
            chapterId: chapterId,
          )
          .toList();
      if (!mounted || gen != _loadGeneration) return;
      _putCache(chapterId, paragraphs);
      slot.value = ChapterLoaded(paragraphs);
    } catch (e) {
      if (!mounted || gen != _loadGeneration) return;
      slot.value =
          ChapterLoadError(error: e, message: normalizeErrorMessage(e));
    }
  }

  void _loadAdjacent(int gen) {
    final prev = _prevId();
    final next = _nextId();
    if (prev != null) _loadSlot(prev, _prevSlot, gen);
    if (next != null) _loadSlot(next, _nextSlot, gen);
  }

  // ─ Position update callback ───────────────────────────────────────────

  void _onPositionUpdate(String chapterId, String paragraphId, double offset) {
    _lastReportedParagraphId = paragraphId;
    _lastReportedOffset = offset;

    widget.controller.reportPosition(
      chapterId: chapterId,
      paragraphId: paragraphId,
      offset: offset,
    );

    if (chapterId != _centerChapterId) {
      final centerIdx = _idxOf(_centerChapterId);
      final reportedIdx = _idxOf(chapterId);
      final direction = reportedIdx > centerIdx ? 1 : -1;
      _performSlide(direction);
    }
  }

  // ─ Retry callback ─────────────────────────────────────────────────────

  void _onRetry(String chapterId) {
    final gen = _loadGeneration;
    if (chapterId == _centerChapterId) {
      _loadSlot(chapterId, _centerSlot, gen);
    } else if (chapterId == _prevId()) {
      _loadSlot(chapterId, _prevSlot, gen);
    } else if (chapterId == _nextId()) {
      _loadSlot(chapterId, _nextSlot, gen);
    }
  }

  // ─ Window slide ───────────────────────────────────────────────────────

  void _performSlide(int direction) {
    final newCenterId = direction > 0 ? _nextId() : _prevId();
    if (newCenterId == null) return;

    _centerChapterId = newCenterId;
    _pendingFromEnd = direction < 0;
    _pendingJumpParagraphId = '';
    _pendingJumpOffset = 0;

    widget.controller.reportPosition(
      chapterId: newCenterId,
      paragraphId: '',
      offset: 0,
    );

    _centerSlot.value = _cache.containsKey(newCenterId)
        ? ChapterLoaded(_cache[newCenterId]!)
        : const ChapterLoading();
    _prevSlot.value = _resolveSlot(_prevId());
    _nextSlot.value = _resolveSlot(_nextId());

    setState(() {});

    _loadAdjacent(_loadGeneration);
  }

  // ─ Chapter boundary callback ──────────────────────────────────────────

  void _onChapterBoundary(int direction) {
    _performSlide(direction);
  }

  // ─ Jump command ───────────────────────────────────────────────────────

  void _onJumpCommand() {
    final targetId = widget.controller.pendingChapterId;
    if (targetId == null) return;

    final paragraphId = widget.controller.pendingParagraphId;
    final offset = widget.controller.pendingOffset;
    widget.controller.consumeJump();

    if (targetId == _centerChapterId && _centerReady) {
      if (_onViewJump != null) {
        _onViewJump!.call(paragraphId, offset);
        return;
      }
      _pendingJumpParagraphId = paragraphId;
      _pendingJumpOffset = offset;
      _pendingFromEnd = false;
      _jumpGeneration++;
      setState(() {});
      return;
    }

    _centerChapterId = targetId;
    _pendingJumpParagraphId = paragraphId;
    _pendingJumpOffset = offset;
    _pendingFromEnd = false;

    widget.controller.reportPosition(
      chapterId: targetId,
      paragraphId: paragraphId,
      offset: offset,
    );

    if (_cache.containsKey(targetId)) {
      _centerSlot.value = ChapterLoaded(_cache[targetId]!);
      _prevSlot.value = _resolveSlot(_prevId());
      _nextSlot.value = _resolveSlot(_nextId());
      _centerReady = true;
      setState(() {});
      _loadAdjacent(_loadGeneration);
    } else {
      _jumpGeneration++;
      _centerReady = false;
      _initCenter();
    }
  }

  // ─ Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_centerReady) {
      return const Center(child: CircularProgressIndicator());
    }

    final centerState = _centerSlot.value;
    if (centerState is ChapterLoadError) {
      return Center(
        child: ChapterStatusBlock(
          kind: ChapterStatusBlockKind.error,
          message: centerState.message,
          onRetry: () => _onRetry(_centerChapterId),
        ),
      );
    }

    final initialParagraphId = _pendingJumpParagraphId;
    final initialOffset = _pendingJumpOffset;
    final initialFromEnd = _pendingFromEnd;

    _consumePending();

    if (widget.mode == ReaderMode.verticalScroll) {
      return VerticalReaderView(
        key: ValueKey('v-$_jumpGeneration'),
        centerChapterId: _centerChapterId,
        prevChapterId: _prevId(),
        nextChapterId: _nextId(),
        prevSlot: _prevSlot,
        centerSlot: _centerSlot,
        nextSlot: _nextSlot,
        fontScale: widget.fontScale,
        lineHeight: widget.lineHeight,
        contentPadding: widget.contentPadding,
        onPositionUpdate: _onPositionUpdate,
        onRetry: _onRetry,
        isFirst: _isFirst,
        isLast: _isLast,
        initialParagraphId: initialParagraphId,
        initialOffset: initialOffset,
        onJumpRegistered: (fn) => _onViewJump = fn,
        onParagraphLongPress: widget.onParagraphLongPress,
        selectedChapterId: widget.selectedChapterId,
        selectedParagraphId: widget.selectedParagraphId,
        onChapterBoundary: _onChapterBoundary,
      );
    }

    return HorizontalReaderView(
      key: ValueKey('h-$_jumpGeneration'),
      centerChapterId: _centerChapterId,
      prevChapterId: _prevId(),
      nextChapterId: _nextId(),
      prevSlot: _prevSlot,
      centerSlot: _centerSlot,
      nextSlot: _nextSlot,
      fontScale: widget.fontScale,
      lineHeight: widget.lineHeight,
      contentPadding: widget.contentPadding,
      onPositionUpdate: _onPositionUpdate,
      onRetry: _onRetry,
      isFirst: _isFirst,
      isLast: _isLast,
      initialParagraphId: initialParagraphId,
      initialFromEnd: initialFromEnd,
      onJumpRegistered: (fn) => _onViewJump = fn,
      onParagraphLongPress: widget.onParagraphLongPress,
      selectedChapterId: widget.selectedChapterId,
      selectedParagraphId: widget.selectedParagraphId,
      onChapterBoundary: _onChapterBoundary,
    );
  }

  void _consumePending() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingJumpParagraphId = '';
      _pendingJumpOffset = 0;
      _pendingFromEnd = false;
    });
  }
}
