import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../src/rust/api/types.dart';
import '../../feeds/feed_service.dart';
import '../reader_settings_provider.dart';
import 'chapter_status_block.dart';
import 'horizontal_reader_view.dart';
import 'page_breaker.dart';
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
  )?
  onParagraphLongPress;
  final String? selectedChapterId;
  final String? selectedParagraphId;

  @override
  State<ChapterContentManager> createState() => _ChapterContentManagerState();
}

class _ChapterContentManagerState extends State<ChapterContentManager> {
  // ─ Chapter slot state ────────────────────────────────────────────────────
  final ValueNotifier<ChapterLoadState> _prevSlot = ValueNotifier(
    const ChapterIdle(),
  );
  final ValueNotifier<ChapterLoadState> _centerSlot = ValueNotifier(
    const ChapterLoading(),
  );
  final ValueNotifier<ChapterLoadState> _nextSlot = ValueNotifier(
    const ChapterIdle(),
  );

  final Map<String, List<ParagraphContent>> _cache = {};
  static const _maxCacheSize = 5;

  late String _centerChapterId;
  String _pendingJumpParagraphId = '';
  double _pendingJumpOffset = 0;
  bool _pendingFromEnd = false;

  String _lastReportedParagraphId = '';
  double _lastReportedOffset = 0;

  int _loadGeneration = 0;
  bool _centerReady = false;

  // ─ Horizontal mode state ─────────────────────────────────────────────────
  PageBreaker? _breaker;
  Size _lastPageSize = Size.zero;
  List<PageContent> _hCenterPages = [];
  List<PageContent> _hPrevPages = [];
  List<PageContent> _hNextPages = [];
  int _currentPageIndex = 0;

  // ─ Vertical mode state ───────────────────────────────────────────────────
  static const _chapterGap = 48.0;
  late ScrollController _verticalScrollController;
  final GlobalKey _centerKey = GlobalKey();
  final GlobalKey _prevSliverKey = GlobalKey();
  final GlobalKey _centerSliverKey = GlobalKey();
  final GlobalKey _nextSliverKey = GlobalKey();
  bool _verticalJumpInProgress = false;
  String _verticalReportedChapterId = '';
  String _scrollTargetParagraphId = '';
  final GlobalKey _jumpTargetKey = GlobalKey();
  int _ensureRetries = 0;
  static const _maxEnsureRetries = 10;

  // ─ Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _verticalScrollController = ScrollController();

    final startId =
        widget.controller.pendingChapterId ??
        (widget.chapters.isNotEmpty ? widget.chapters.first.id : '');
    _centerChapterId = startId;
    _verticalReportedChapterId = startId;
    _pendingJumpParagraphId = widget.controller.pendingParagraphId;
    _pendingJumpOffset = widget.controller.pendingOffset;
    widget.controller.consumeJump();
    widget.controller.addListener(_onJumpCommand);

    _initCenter();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onJumpCommand);
    _verticalScrollController.dispose();
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

    final sourceChanged =
        oldWidget.feedId != widget.feedId ||
        oldWidget.bookId != widget.bookId ||
        oldWidget.chapters != widget.chapters;

    if (sourceChanged) {
      _centerChapterId = widget.chapters.isNotEmpty
          ? widget.chapters.first.id
          : '';
      _cache.clear();
      _centerReady = false;
      _breaker = null;
      _hCenterPages = [];
      _hPrevPages = [];
      _hNextPages = [];
      _currentPageIndex = 0;
      _initCenter();
      return;
    }

    if (oldWidget.chineseConversion != widget.chineseConversion) {
      _pendingJumpParagraphId = _lastReportedParagraphId;
      _pendingJumpOffset = 0;
      _pendingFromEnd = false;
      _cache.clear();
      _centerReady = false;
      _breaker = null;
      _initCenter();
      return;
    }

    if (oldWidget.mode != widget.mode) {
      _pendingJumpParagraphId = _lastReportedParagraphId;
      _pendingJumpOffset = _lastReportedOffset;
      _pendingFromEnd = false;
      if (widget.mode == ReaderMode.horizontalPaging) {
        _breaker = null;
        _lastPageSize = Size.zero;
      } else {
        _breaker = null;
        _hCenterPages = [];
        _hPrevPages = [];
        _hNextPages = [];
      }
      setState(() {});
    }

    if (oldWidget.fontScale != widget.fontScale ||
        oldWidget.lineHeight != widget.lineHeight) {
      _pendingJumpParagraphId = _lastReportedParagraphId;
      _pendingJumpOffset = 0;
      _pendingFromEnd = false;
      if (widget.mode == ReaderMode.horizontalPaging) {
        _breaker = null;
        _lastPageSize = Size.zero;
      }
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

    if (widget.mode == ReaderMode.horizontalPaging) {
      _ensureBreaker();
      _rebuildHorizontalPages();
      _resolveHorizontalPendingJump();
    }

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

      if (widget.mode == ReaderMode.horizontalPaging) {
        _rebuildHorizontalPages();
        if (slot == _centerSlot && _pendingJumpParagraphId.isNotEmpty) {
          _resolveHorizontalPendingJump();
        }
        setState(() {});
      }
    } catch (e) {
      if (!mounted || gen != _loadGeneration) return;
      slot.value = ChapterLoadError(
        error: e,
        message: normalizeErrorMessage(e),
      );
      if (widget.mode == ReaderMode.horizontalPaging) {
        setState(() {});
      }
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

    if (widget.mode == ReaderMode.verticalScroll) {
      _performVerticalSlide(direction, newCenterId);
      return;
    }

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

    _rebuildHorizontalPages();
    if (direction < 0 && _hCenterPages.isNotEmpty) {
      _currentPageIndex = _hCenterPages.length - 1;
    } else {
      _currentPageIndex = 0;
    }
    _reportCurrentHorizontalPosition();

    setState(() {});

    // If center chapter is not cached, load it (otherwise it stays Loading forever).
    if (!_cache.containsKey(newCenterId)) {
      _loadSlot(newCenterId, _centerSlot, _loadGeneration);
    }
    _loadAdjacent(_loadGeneration);
  }

  // ─ Jump command ───────────────────────────────────────────────────────

  void _onJumpCommand() {
    final targetId = widget.controller.pendingChapterId;
    if (targetId == null) return;

    final paragraphId = widget.controller.pendingParagraphId;
    final offset = widget.controller.pendingOffset;
    widget.controller.consumeJump();

    if (targetId == _centerChapterId && _centerReady) {
      if (widget.mode == ReaderMode.horizontalPaging) {
        if (_hCenterPages.isNotEmpty && paragraphId.isNotEmpty) {
          _currentPageIndex = PageBreaker.pageForParagraph(
            _hCenterPages,
            paragraphId,
          );
        } else {
          _currentPageIndex = 0;
        }
        _reportCurrentHorizontalPosition();
        setState(() {});
        return;
      }
      // Vertical mode: jump within current chapter
      _verticalJumpToPosition(paragraphId, offset);
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

      if (widget.mode == ReaderMode.horizontalPaging) {
        _rebuildHorizontalPages();
        _resolveHorizontalPendingJump();
      }

      setState(() {});
      _loadAdjacent(_loadGeneration);
    } else {
      _centerReady = false;
      _initCenter();
    }
  }

  // ─ Horizontal mode helpers ────────────────────────────────────────────

  void _ensureBreaker() {
    final size = MediaQuery.sizeOf(context);
    final pageSize = Size(
      size.width - widget.contentPadding.horizontal,
      size.height - widget.contentPadding.vertical,
    );
    if (_breaker != null && _lastPageSize == pageSize) return;
    _lastPageSize = pageSize;
    _breaker = _createBreaker(context);
  }

  PageBreaker _createBreaker(BuildContext context) {
    final theme = Theme.of(context);
    final bodyLarge = theme.textTheme.bodyLarge?.copyWith(
      fontSize: (theme.textTheme.bodyLarge?.fontSize ?? 16) * widget.fontScale,
      height: widget.lineHeight,
    );
    final headlineSmall = theme.textTheme.headlineSmall?.copyWith(
      fontSize:
          (theme.textTheme.headlineSmall?.fontSize ?? 24) * widget.fontScale,
    );
    final size = MediaQuery.sizeOf(context);
    final pageSize = Size(
      size.width - widget.contentPadding.horizontal,
      size.height - widget.contentPadding.vertical,
    );
    return PageBreaker(
      pageSize: pageSize,
      textStyle: bodyLarge ?? const TextStyle(),
      titleStyle: headlineSmall ?? const TextStyle(),
      paragraphSpacing: LanghuanTheme.spaceMd,
      imageHeight: pageSize.width * 9 / 16,
      textDirection: Directionality.of(context),
    );
  }

  void _rebuildHorizontalPages() {
    if (_breaker == null) return;

    final centerState = _centerSlot.value;
    _hCenterPages =
        (centerState is ChapterLoaded && centerState.paragraphs.isNotEmpty)
        ? _breaker!.computePages(centerState.paragraphs)
        : [];

    final prevState = _prevSlot.value;
    _hPrevPages =
        (prevState is ChapterLoaded && prevState.paragraphs.isNotEmpty)
        ? _breaker!.computePages(prevState.paragraphs)
        : [];

    final nextState = _nextSlot.value;
    _hNextPages =
        (nextState is ChapterLoaded && nextState.paragraphs.isNotEmpty)
        ? _breaker!.computePages(nextState.paragraphs)
        : [];

    if (_hCenterPages.isNotEmpty) {
      _currentPageIndex = _currentPageIndex.clamp(0, _hCenterPages.length - 1);
    }
  }

  void _resolveHorizontalPendingJump() {
    if (_pendingJumpParagraphId.isNotEmpty && _hCenterPages.isNotEmpty) {
      _currentPageIndex = PageBreaker.pageForParagraph(
        _hCenterPages,
        _pendingJumpParagraphId,
      );
      _pendingJumpParagraphId = '';
    } else if (_pendingFromEnd && _hCenterPages.isNotEmpty) {
      _currentPageIndex = _hCenterPages.length - 1;
      _pendingFromEnd = false;
    }
  }

  void _onHorizontalNextPage() {
    if (_hCenterPages.isEmpty) return;

    if (_currentPageIndex < _hCenterPages.length - 1) {
      _currentPageIndex++;
      _reportCurrentHorizontalPosition();
      setState(() {});
    } else if (_nextId() != null) {
      _performSlide(1);
    }
  }

  void _onHorizontalPrevPage() {
    if (_hCenterPages.isEmpty) return;

    if (_currentPageIndex > 0) {
      _currentPageIndex--;
      _reportCurrentHorizontalPosition();
      setState(() {});
    } else if (_prevId() != null) {
      _performSlide(-1);
    }
  }

  void _reportCurrentHorizontalPosition() {
    if (_hCenterPages.isEmpty) return;
    final page = _hCenterPages[_currentPageIndex];
    _onPositionUpdate(_centerChapterId, page.firstParagraphId, 0);
  }

  PageContent? _resolvePrevPage() {
    if (_currentPageIndex > 0) {
      return _hCenterPages[_currentPageIndex - 1];
    }
    if (_hPrevPages.isNotEmpty) return _hPrevPages.last;
    return null;
  }

  PageContent? _resolveNextPage() {
    if (_hCenterPages.isNotEmpty &&
        _currentPageIndex < _hCenterPages.length - 1) {
      return _hCenterPages[_currentPageIndex + 1];
    }
    if (_hNextPages.isNotEmpty) return _hNextPages.first;
    return null;
  }

  // ─ Vertical mode helpers ──────────────────────────────────────────────

  double _sliverExtent(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return 0;
    final renderObject = ctx.findRenderObject();
    if (renderObject is RenderSliver) {
      return renderObject.geometry?.scrollExtent ?? 0;
    }
    return 0;
  }

  void _performVerticalSlide(int direction, String newCenterId) {
    final oldCenterExt = _sliverExtent(_centerSliverKey);
    final oldPrevExt = _sliverExtent(_prevSliverKey);
    final oldOffset = _verticalScrollController.hasClients
        ? _verticalScrollController.offset
        : 0.0;

    _centerChapterId = newCenterId;
    _verticalReportedChapterId = newCenterId;
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

    _verticalJumpInProgress = true;
    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_verticalScrollController.hasClients) {
        _verticalJumpInProgress = false;
        return;
      }

      final double delta;
      if (direction > 0) {
        delta = -(oldCenterExt + _chapterGap);
      } else {
        delta = oldPrevExt + _chapterGap;
      }

      final target = oldOffset + delta;
      final pos = _verticalScrollController.position;
      _verticalScrollController.jumpTo(
        target.clamp(pos.minScrollExtent, pos.maxScrollExtent),
      );
      _verticalJumpInProgress = false;
    });

    _loadAdjacent(_loadGeneration);
  }

  bool _onVerticalScrollNotification(ScrollNotification n) {
    if (_verticalJumpInProgress || !_verticalScrollController.hasClients) {
      return false;
    }

    if (n is ScrollUpdateNotification) {
      _verticalReportPosition();
    }

    if (n is ScrollEndNotification) {
      _verticalReportPosition();
      _verticalDetectChapter();
    }

    return false;
  }

  void _verticalReportPosition() {
    if (!_verticalScrollController.hasClients) return;
    final offset = _verticalScrollController.offset;
    final centerExt = _sliverExtent(_centerSliverKey);

    if (centerExt <= 0) return;

    final centerState = _centerSlot.value;
    if (centerState is! ChapterLoaded) return;
    final paragraphs = centerState.paragraphs;
    if (paragraphs.isEmpty) return;

    if (offset < 0 || offset > centerExt) return;

    final ratio = (offset / centerExt).clamp(0.0, 1.0);
    final paraIdx = (ratio * paragraphs.length).floor().clamp(
      0,
      paragraphs.length - 1,
    );
    _onPositionUpdate(
      _centerChapterId,
      paragraphs[paraIdx].id.toStringValue(),
      offset,
    );
  }

  void _verticalDetectChapter() {
    if (!_verticalScrollController.hasClients) return;

    final vpHeight = _verticalScrollController.position.viewportDimension;
    final vpCenter = _verticalScrollController.offset + vpHeight / 2;
    final centerExt = _sliverExtent(_centerSliverKey);

    if (vpCenter >= 0 && vpCenter < centerExt) {
      _verticalReportedChapterId = _centerChapterId;
      return;
    }

    if (vpCenter >= centerExt + _chapterGap && _nextId() != null) {
      if (_verticalReportedChapterId != _nextId()) {
        _verticalReportedChapterId = _nextId()!;
        _performSlide(1);
      }
      return;
    }

    if (vpCenter < 0 && _prevId() != null) {
      if (_verticalReportedChapterId != _prevId()) {
        _verticalReportedChapterId = _prevId()!;
        _performSlide(-1);
      }
      return;
    }
  }

  void _verticalJumpToPosition(String paragraphId, double offset) {
    _verticalJumpInProgress = true;
    _ensureRetries = 0;
    if (paragraphId.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_verticalScrollController.hasClients) {
          _verticalScrollController.jumpTo(
            offset.clamp(
              _verticalScrollController.position.minScrollExtent,
              _verticalScrollController.position.maxScrollExtent,
            ),
          );
        }
        _verticalJumpInProgress = false;
      });
      return;
    }
    _scrollTargetParagraphId = paragraphId;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureTargetVisible();
    });
  }

  void _ensureTargetVisible() {
    if (!mounted || !_verticalScrollController.hasClients) return;
    final ctx = _jumpTargetKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignment: 0.0, duration: Duration.zero);
      setState(() => _scrollTargetParagraphId = '');
      _verticalJumpInProgress = false;
      _ensureRetries = 0;
      return;
    }

    if (++_ensureRetries > _maxEnsureRetries) {
      setState(() => _scrollTargetParagraphId = '');
      _verticalJumpInProgress = false;
      _ensureRetries = 0;
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureTargetVisible();
    });
  }

  void _scheduleVerticalInitialScroll() {
    if (_pendingJumpParagraphId.isNotEmpty) {
      _verticalJumpToPosition(_pendingJumpParagraphId, 0);
      _pendingJumpParagraphId = '';
    } else if (_pendingJumpOffset > 0) {
      _verticalJumpToPosition('', _pendingJumpOffset);
      _pendingJumpOffset = 0;
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

    if (widget.mode == ReaderMode.horizontalPaging) {
      _ensureBreaker();
      if (_hCenterPages.isEmpty && centerState is ChapterLoaded) {
        _rebuildHorizontalPages();
        _resolveHorizontalPendingJump();
      }

      final prevState = _prevSlot.value;
      final nextState = _nextSlot.value;

      return HorizontalReaderView(
        currentPage: _hCenterPages.isNotEmpty
            ? _hCenterPages[_currentPageIndex]
            : null,
        prevPage: _resolvePrevPage(),
        nextPage: _resolveNextPage(),
        isFirstPage: _currentPageIndex == 0 && _isFirst,
        isLastPage:
            _currentPageIndex ==
                (_hCenterPages.isEmpty ? 0 : _hCenterPages.length - 1) &&
            _isLast,
        fontScale: widget.fontScale,
        lineHeight: widget.lineHeight,
        contentPadding: widget.contentPadding,
        onNextPage: _onHorizontalNextPage,
        onPrevPage: _onHorizontalPrevPage,
        centerChapterId: _centerChapterId,
        prevError: prevState is ChapterLoadError ? prevState.message : null,
        nextError: nextState is ChapterLoadError ? nextState.message : null,
        onRetryPrev: _prevId() != null ? () => _onRetry(_prevId()!) : null,
        onRetryNext: _nextId() != null ? () => _onRetry(_nextId()!) : null,
        onParagraphLongPress: widget.onParagraphLongPress,
        selectedChapterId: widget.selectedChapterId,
        selectedParagraphId: widget.selectedParagraphId,
      );
    }

    // Vertical mode
    if (_pendingJumpParagraphId.isNotEmpty || _pendingJumpOffset > 0) {
      _scheduleVerticalInitialScroll();
    }

    return VerticalReaderView(
      centerChapterId: _centerChapterId,
      prevChapterId: _prevId(),
      nextChapterId: _nextId(),
      prevSlot: _prevSlot,
      centerSlot: _centerSlot,
      nextSlot: _nextSlot,
      scrollController: _verticalScrollController,
      fontScale: widget.fontScale,
      lineHeight: widget.lineHeight,
      contentPadding: widget.contentPadding,
      onRetry: _onRetry,
      isFirst: _isFirst,
      isLast: _isLast,
      onParagraphLongPress: widget.onParagraphLongPress,
      selectedChapterId: widget.selectedChapterId,
      selectedParagraphId: widget.selectedParagraphId,
      onScrollNotification: _onVerticalScrollNotification,
      centerKey: _centerKey,
      prevSliverKey: _prevSliverKey,
      centerSliverKey: _centerSliverKey,
      nextSliverKey: _nextSliverKey,
      scrollTargetParagraphId: _scrollTargetParagraphId,
      jumpTargetKey: _jumpTargetKey,
    );
  }
}
