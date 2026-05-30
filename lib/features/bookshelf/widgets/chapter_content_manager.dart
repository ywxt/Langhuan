import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../src/rust/api/types.dart';
import '../../feeds/feed_service.dart';
import 'chapter_status_block.dart';
import 'horizontal_reader_view.dart';
import 'page_breaker.dart';
import 'reader_controller.dart';
import 'reader_types.dart';

class ChapterContentManager extends StatefulWidget {
  const ChapterContentManager({
    super.key,
    required this.feedId,
    required this.bookId,
    required this.chapters,
    required this.controller,
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
  static const _enableReaderDebugLogs = bool.fromEnvironment(
    'READER_DEBUG_LOGS',
    defaultValue: false,
  );

  void _logReaderCore(String message) {
    if (!kDebugMode || !_enableReaderDebugLogs) return;
    debugPrint('[ReaderCore] $message');
  }

  void _logReaderManager(String message) {
    if (!kDebugMode || !_enableReaderDebugLogs) return;
    debugPrint('[ReaderManager] $message');
  }

  String _slotLabel(ValueNotifier<ChapterLoadState> slot) {
    if (identical(slot, _prevSlot)) return 'prev';
    if (identical(slot, _centerSlot)) return 'center';
    if (identical(slot, _nextSlot)) return 'next';
    return 'unknown';
  }

  void _emitCoreChanged(String reason) {
    final prev = _prevSlot.value.runtimeType;
    final center = _centerSlot.value.runtimeType;
    final next = _nextSlot.value.runtimeType;
    _logReaderManager(
      'coreChanged reason=$reason center=$_centerChapterId '
      'prev=$prev centerSlot=$center next=$next gen=$_loadGeneration',
    );
  }

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
  bool _pendingFromEnd = false;

  String _lastReportedParagraphId = '';

  int _loadGeneration = 0;
  bool _centerReady = false;

  PageBreaker? _breaker;
  Size _lastPageSize = Size.zero;
  List<PageContent> _hCenterPages = [];
  List<PageContent> _hPrevPages = [];
  List<PageContent> _hNextPages = [];
  int _currentPageIndex = 0;

  @override
  void initState() {
    super.initState();

    final startId =
        widget.controller.pendingChapterId ??
        (widget.chapters.isNotEmpty ? widget.chapters.first.id : '');
    _centerChapterId = startId;
    _pendingJumpParagraphId = widget.controller.pendingParagraphId;
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
      _pendingFromEnd = false;
      _cache.clear();
      _centerReady = false;
      _breaker = null;
      _initCenter();
      return;
    }

    if (oldWidget.fontScale != widget.fontScale ||
        oldWidget.lineHeight != widget.lineHeight) {
      _pendingJumpParagraphId = _lastReportedParagraphId;
      _pendingFromEnd = false;
      _breaker = null;
      _lastPageSize = Size.zero;
      setState(() {});
    }
  }

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

  Future<void> _initCenter() async {
    final gen = ++_loadGeneration;
    _logReaderManager(
      'coreChanged reason=initCenter:start center=$_centerChapterId gen=$gen',
    );

    _prevSlot.value = const ChapterIdle();
    _centerSlot.value = const ChapterLoading();
    _nextSlot.value = const ChapterIdle();
    _emitCoreChanged('initCenter:slotsReset');
    setState(() {});

    await _loadSlot(_centerChapterId, _centerSlot, gen);
    if (!mounted || gen != _loadGeneration) return;

    _centerReady = true;
    _emitCoreChanged('initCenter:centerReady');

    _ensureBreaker();
    _rebuildHorizontalPages();
    _resolveHorizontalPendingJump();

    setState(() {});
    _loadAdjacent(gen);
  }

  Future<void> _loadSlot(
    String chapterId,
    ValueNotifier<ChapterLoadState> slot,
    int gen,
  ) async {
    final slotName = _slotLabel(slot);
    _logReaderCore(
      'loadSlot start chapter=$chapterId slot=$slotName gen=$gen activeGen=$_loadGeneration',
    );
    if (_cache.containsKey(chapterId)) {
      slot.value = ChapterLoaded(_cache[chapterId]!);
      _logReaderCore('loadSlot cacheHit chapter=$chapterId slot=$slotName');
      _emitCoreChanged('loadSlot:cacheHit:$slotName');
      return;
    }
    slot.value = const ChapterLoading();
    _emitCoreChanged('loadSlot:loading:$slotName');
    try {
      final paragraphs = await FeedService.instance
          .paragraphs(
            feedId: widget.feedId,
            bookId: widget.bookId,
            chapterId: chapterId,
          )
          .toList();
      if (!mounted || gen != _loadGeneration) {
        _logReaderCore(
          'loadSlot staleResult chapter=$chapterId slot=$slotName '
          'gen=$gen activeGen=$_loadGeneration mounted=$mounted',
        );
        return;
      }
      _putCache(chapterId, paragraphs);
      slot.value = ChapterLoaded(paragraphs);
      _logReaderCore(
        'loadSlot success chapter=$chapterId slot=$slotName paragraphs=${paragraphs.length}',
      );
      _emitCoreChanged('loadSlot:loaded:$slotName');

      _rebuildHorizontalPages();
      if (slot == _centerSlot && _pendingJumpParagraphId.isNotEmpty) {
        _resolveHorizontalPendingJump();
      }
      setState(() {});
    } catch (e) {
      if (!mounted || gen != _loadGeneration) {
        _logReaderCore(
          'loadSlot staleError chapter=$chapterId slot=$slotName '
          'gen=$gen activeGen=$_loadGeneration mounted=$mounted',
        );
        return;
      }
      slot.value = ChapterLoadError(
        error: e,
        message: normalizeErrorMessage(e),
      );
      _logReaderCore(
        'loadSlot error chapter=$chapterId slot=$slotName error=${normalizeErrorMessage(e)}',
      );
      _emitCoreChanged('loadSlot:error:$slotName');
      setState(() {});
    }
  }

  void _loadAdjacent(int gen) {
    final prev = _prevId();
    final next = _nextId();
    _logReaderCore(
      'loadAdjacent gen=$gen center=$_centerChapterId prev=$prev next=$next',
    );
    if (prev != null) _loadSlot(prev, _prevSlot, gen);
    if (next != null) _loadSlot(next, _nextSlot, gen);
  }

  void _onPositionUpdate(String chapterId, String paragraphId, double offset) {
    _lastReportedParagraphId = paragraphId;

    widget.controller.reportPosition(
      chapterId: chapterId,
      paragraphId: paragraphId,
      paragraphOffset: offset,
    );
  }

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

  void _performSlide(int direction) {
    final newCenterId = direction > 0 ? _nextId() : _prevId();
    if (newCenterId == null) return;

    _centerChapterId = newCenterId;
    _pendingFromEnd = direction < 0;
    _pendingJumpParagraphId = '';

    widget.controller.reportPosition(
      chapterId: newCenterId,
      paragraphId: '',
      paragraphOffset: 0,
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

    if (!_cache.containsKey(newCenterId)) {
      _loadSlot(newCenterId, _centerSlot, _loadGeneration);
    }
    _loadAdjacent(_loadGeneration);
  }

  void _onJumpCommand() {
    final targetId = widget.controller.pendingChapterId;
    if (targetId == null) return;

    final paragraphId = widget.controller.pendingParagraphId;
    final offset = widget.controller.pendingOffset;
    widget.controller.consumeJump();

    if (targetId == _centerChapterId && _centerReady) {
      if (_hCenterPages.isNotEmpty && paragraphId.isNotEmpty) {
        _currentPageIndex = PageBreaker.pageForParagraph(
          _hCenterPages,
          paragraphId,
        );
      } else {
        _currentPageIndex = 0;
      }
      _onPositionUpdate(_centerChapterId, paragraphId, offset);
      _reportCurrentHorizontalPosition();
      setState(() {});
      return;
    }

    _centerChapterId = targetId;
    _pendingJumpParagraphId = paragraphId;
    _pendingFromEnd = false;

    widget.controller.reportPosition(
      chapterId: targetId,
      paragraphId: paragraphId,
      paragraphOffset: offset,
    );

    if (_cache.containsKey(targetId)) {
      _centerSlot.value = ChapterLoaded(_cache[targetId]!);
      _prevSlot.value = _resolveSlot(_prevId());
      _nextSlot.value = _resolveSlot(_nextId());
      _centerReady = true;

      _rebuildHorizontalPages();
      _resolveHorizontalPendingJump();

      setState(() {});
      _loadAdjacent(_loadGeneration);
    } else {
      _centerReady = false;
      _initCenter();
    }
  }

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
}
