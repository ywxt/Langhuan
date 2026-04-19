import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../src/rust/api/types.dart';
import 'chapter_status_block.dart';
import 'page_breaker.dart';
import 'page_content_view.dart';
import 'reader_types.dart';

class HorizontalReaderView extends StatefulWidget {
  const HorizontalReaderView({
    super.key,
    required this.centerChapterId,
    this.prevChapterId,
    this.nextChapterId,
    required this.prevSlot,
    required this.centerSlot,
    required this.nextSlot,
    required this.fontScale,
    required this.lineHeight,
    required this.contentPadding,
    required this.onPositionUpdate,
    required this.onRetry,
    required this.isFirst,
    required this.isLast,
    this.initialParagraphId = '',
    this.initialFromEnd = false,
    this.onJumpRegistered,
    this.onParagraphLongPress,
    this.selectedChapterId,
    this.selectedParagraphId,
    this.onChapterBoundary,
  });

  final String centerChapterId;
  final String? prevChapterId;
  final String? nextChapterId;
  final ValueNotifier<ChapterLoadState> prevSlot;
  final ValueNotifier<ChapterLoadState> centerSlot;
  final ValueNotifier<ChapterLoadState> nextSlot;
  final double fontScale;
  final double lineHeight;
  final EdgeInsets contentPadding;
  final void Function(String chapterId, String paragraphId, double offset)
      onPositionUpdate;
  final void Function(String chapterId) onRetry;
  final bool isFirst;
  final bool isLast;
  final String initialParagraphId;
  final bool initialFromEnd;
  final ValueChanged<void Function(String, double)>? onJumpRegistered;
  final void Function(
    String chapterId,
    String paragraphId,
    ParagraphContent paragraph,
    Rect globalRect,
  )? onParagraphLongPress;
  final String? selectedChapterId;
  final String? selectedParagraphId;
  final void Function(int direction)? onChapterBoundary;

  @override
  State<HorizontalReaderView> createState() => _HorizontalReaderViewState();
}

class _HorizontalReaderViewState extends State<HorizontalReaderView> {
  late PageController _pageController;
  bool _initialized = false;

  PageBreaker? _breaker;
  List<PageContent> _pages = [];

  int _contentOffset = 0;

  bool _prevTriggered = false;
  bool _nextTriggered = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    widget.onJumpRegistered?.call(_jumpToPosition);
    widget.centerSlot.addListener(_onCenterSlotChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _breaker = _createBreaker();
    _rebuildPages();
    if (!_initialized) {
      _initialized = true;
      final initialPage = _computeInitialPage();
      _pageController.dispose();
      _pageController = PageController(initialPage: initialPage);
    }
  }

  @override
  void didUpdateWidget(covariant HorizontalReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.centerSlot != widget.centerSlot) {
      oldWidget.centerSlot.removeListener(_onCenterSlotChanged);
      widget.centerSlot.addListener(_onCenterSlotChanged);
    }

    if (oldWidget.centerChapterId != widget.centerChapterId) {
      _prevTriggered = false;
      _nextTriggered = false;
      _rebuildPages();
      final targetPage = widget.initialFromEnd && _pages.isNotEmpty
          ? _contentOffset + _pages.length - 1
          : _contentOffset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(targetPage);
        }
      });
      return;
    }

    if (oldWidget.fontScale != widget.fontScale ||
        oldWidget.lineHeight != widget.lineHeight ||
        oldWidget.contentPadding != widget.contentPadding) {
      _breaker = _createBreaker();
      _rebuildPages();
    }
  }

  @override
  void dispose() {
    widget.centerSlot.removeListener(_onCenterSlotChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _onCenterSlotChanged() {
    if (!mounted) return;
    final hadPages = _pages.isNotEmpty;
    _rebuildPages();
    setState(() {});
    if (!hadPages && _pages.isNotEmpty) {
      final initialPage = _computeInitialPage();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(initialPage);
        }
      });
    }
  }

  PageBreaker _createBreaker() {
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

  List<ParagraphContent>? get _centerParagraphs {
    final state = widget.centerSlot.value;
    if (state is ChapterLoaded) return state.paragraphs;
    return null;
  }

  bool get _hasPrevious => widget.prevChapterId != null;
  bool get _hasNext => widget.nextChapterId != null;

  void _rebuildPages() {
    final paragraphs = _centerParagraphs;
    if (_breaker == null || paragraphs == null || paragraphs.isEmpty) {
      _pages = [];
      _contentOffset = _hasPrevious ? 1 : 0;
      return;
    }
    _pages = _breaker!.computePages(paragraphs);
    _contentOffset = _hasPrevious ? 1 : 0;
  }

  int get _totalPageCount {
    int count = _pages.length;
    if (_hasPrevious) count++;
    if (_hasNext) count++;
    if (!_hasNext) count++;
    return count;
  }

  int _computeInitialPage() {
    if (_pages.isEmpty) return 0;

    if (widget.initialFromEnd) {
      return _contentOffset + _pages.length - 1;
    }

    if (widget.initialParagraphId.isNotEmpty && _breaker != null) {
      final localPage =
          PageBreaker.pageForParagraph(_pages, widget.initialParagraphId);
      return _contentOffset + localPage;
    }

    return _contentOffset;
  }

  void _jumpToPosition(String paragraphId, double _) {
    if (!_pageController.hasClients || _breaker == null || _pages.isEmpty) {
      return;
    }
    final localPage = PageBreaker.pageForParagraph(_pages, paragraphId);
    final target = _contentOffset + localPage;
    _pageController.jumpToPage(target);
  }

  // ─ Page change tracking ───────────────────────────────────────────────

  void _onPageChanged(int index) {
    if (index < 0 || index >= _totalPageCount) return;

    if (_hasPrevious && index == 0 && !_prevTriggered) {
      _prevTriggered = true;
      widget.onChapterBoundary?.call(-1);
      return;
    }

    final contentEnd = _contentOffset + _pages.length;
    if (_hasNext && index >= contentEnd && !_nextTriggered) {
      _nextTriggered = true;
      widget.onChapterBoundary?.call(1);
      return;
    }

    final contentIdx = index - _contentOffset;
    if (contentIdx >= 0 && contentIdx < _pages.length) {
      final page = _pages[contentIdx];
      widget.onPositionUpdate(
        widget.centerChapterId,
        page.firstParagraphId,
        0,
      );
    }
  }

  // ─ Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_pages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return PageView.builder(
      controller: _pageController,
      itemCount: _totalPageCount,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) {
        if (_hasPrevious && index == 0) {
          return const Center(
            child: ChapterStatusBlock(kind: ChapterStatusBlockKind.loading),
          );
        }

        final contentEnd = _contentOffset + _pages.length;
        if (index >= contentEnd) {
          if (_hasNext) {
            return const Center(
              child: ChapterStatusBlock(kind: ChapterStatusBlockKind.loading),
            );
          }
          return _buildEndOfBook(context);
        }

        final contentIdx = index - _contentOffset;
        if (contentIdx < 0 || contentIdx >= _pages.length) {
          return const SizedBox.shrink();
        }
        return _buildPage(context, contentIdx);
      },
    );
  }

  Widget _buildPage(BuildContext context, int pageIdx) {
    final isSelectedChapter =
        widget.selectedChapterId == widget.centerChapterId;

    return Padding(
      padding: widget.contentPadding,
      child: PageContentView(
        page: _pages[pageIdx],
        fontScale: widget.fontScale,
        lineHeight: widget.lineHeight,
        selectedParagraphId:
            isSelectedChapter ? widget.selectedParagraphId : null,
        onParagraphLongPress: widget.onParagraphLongPress != null
            ? (paragraphId, paragraph, rect) =>
                widget.onParagraphLongPress!(
                    widget.centerChapterId, paragraphId, paragraph, rect)
            : null,
      ),
    );
  }

  Widget _buildEndOfBook(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Text(
        l10n.readerEndOfBook,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
