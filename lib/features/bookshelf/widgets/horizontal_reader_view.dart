import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../src/rust/api/types.dart';
import 'chapter_status_block.dart';
import 'page_breaker.dart';
import 'page_content_view.dart';

class HorizontalReaderView extends StatefulWidget {
  const HorizontalReaderView({
    super.key,
    required this.currentPage,
    this.prevPage,
    this.nextPage,
    required this.isFirstPage,
    required this.isLastPage,
    required this.fontScale,
    required this.lineHeight,
    required this.contentPadding,
    required this.onNextPage,
    required this.onPrevPage,
    required this.centerChapterId,
    this.prevError,
    this.nextError,
    this.onRetryPrev,
    this.onRetryNext,
    this.onParagraphLongPress,
    this.selectedChapterId,
    this.selectedParagraphId,
  });

  final PageContent? currentPage;
  final PageContent? prevPage;
  final PageContent? nextPage;
  final bool isFirstPage;
  final bool isLastPage;
  final double fontScale;
  final double lineHeight;
  final EdgeInsets contentPadding;
  final VoidCallback onNextPage;
  final VoidCallback onPrevPage;
  final String centerChapterId;
  final String? prevError;
  final String? nextError;
  final VoidCallback? onRetryPrev;
  final VoidCallback? onRetryNext;
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
  State<HorizontalReaderView> createState() => _HorizontalReaderViewState();
}

class _HorizontalReaderViewState extends State<HorizontalReaderView>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  /// Pixel offset of the 3-page strip. 0 = center visible.
  /// Driven by drag or animation. Updated via ValueNotifier to avoid rebuild.
  final ValueNotifier<double> _offset = ValueNotifier(0);

  bool _isDragging = false;
  bool _isSettling = false;

  /// Frozen snapshot — only updated when idle (not dragging / settling).
  PageContent? _snapCurrent;
  PageContent? _snapPrev;
  PageContent? _snapNext;
  bool _snapIsFirst = false;
  bool _snapIsLast = false;
  String? _snapPrevError;
  String? _snapNextError;

  /// Direction the settle animation is heading: -1 next, 0 snap-back, 1 prev.
  int _settleDir = 0;

  /// True after settle animation completes but before the next build syncs
  /// the new props. Keeps [_busy] true so the snapshot stays frozen until
  /// the parent rebuild delivers the new page content.
  bool _pendingSettle = false;

  // Tween endpoints for the current settle animation.
  double _tweenStart = 0;
  double _tweenEnd = 0;

  static const _swipeFraction = 0.25;
  static const _velocityThreshold = 300.0; // px/s

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this)
      ..addListener(_onAnimTick)
      ..addStatusListener(_onAnimStatus);
    _syncSnapshot();
  }

  @override
  void dispose() {
    _anim.dispose();
    _offset.dispose();
    super.dispose();
  }

  bool get _busy => _isDragging || _isSettling || _pendingSettle;

  void _syncSnapshot() {
    _snapCurrent = widget.currentPage;
    _snapPrev = widget.prevPage;
    _snapNext = widget.nextPage;
    _snapIsFirst = widget.isFirstPage;
    _snapIsLast = widget.isLastPage;
    _snapPrevError = widget.prevError;
    _snapNextError = widget.nextError;
  }

  bool get _canGoPrev =>
      _snapPrev != null || !_snapIsFirst || _snapPrevError != null;
  bool get _canGoNext =>
      _snapNext != null || !_snapIsLast || _snapNextError != null;

  // ─ Gesture handling ───────────────────────────────────────────────────

  void _onDragStart(DragStartDetails _) {
    if (_isSettling) {
      _anim.stop();
      _isSettling = false;
    }
    _isDragging = true;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    var next = _offset.value + details.delta.dx;
    if (!_canGoPrev && next > 0) next = 0;
    if (!_canGoNext && next < 0) next = 0;
    _offset.value = next;
  }

  void _onDragEnd(DragEndDetails details, double pageWidth) {
    _isDragging = false;

    final velocity = details.primaryVelocity ?? 0;
    final fraction = _offset.value / pageWidth;

    int dir = 0;
    if (velocity > _velocityThreshold && _canGoPrev) {
      dir = 1;
    } else if (velocity < -_velocityThreshold && _canGoNext) {
      dir = -1;
    } else if (fraction > _swipeFraction && _canGoPrev) {
      dir = 1;
    } else if (fraction < -_swipeFraction && _canGoNext) {
      dir = -1;
    }

    _settleDir = dir;
    _animateTo(dir * pageWidth, pageWidth);
  }

  void _animateTo(double target, double pageWidth) {
    _tweenStart = _offset.value;
    _tweenEnd = target;

    final distance = (target - _tweenStart).abs();
    final ms = (distance / pageWidth * 300).clamp(100.0, 350.0);

    _anim.duration = Duration(milliseconds: ms.toInt());
    // Set _isSettling AFTER reset so the dismissed status from reset()
    // doesn't trigger _onSettleComplete.
    _anim.reset();
    _isSettling = true;
    _anim.forward();
  }

  void _onAnimTick() {
    // Lerp between start and end using easeOut curve applied to controller value.
    final t = Curves.easeOut.transform(_anim.value);
    _offset.value = _tweenStart + (_tweenEnd - _tweenStart) * t;
  }

  void _onAnimStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      if (_isSettling) _onSettleComplete();
    }
  }

  void _onSettleComplete() {
    _isSettling = false;

    final dir = _settleDir;
    _settleDir = 0;

    if (dir == 0) {
      // Snap-back: no page change, just reset offset.
      _offset.value = 0;
      return;
    }

    // Page turn: keep the offset at the final position (±pageWidth) so the
    // old snapshot stays visually in place. Mark _pendingSettle so _busy
    // remains true until the parent rebuild delivers new props.
    _pendingSettle = true;

    if (dir == 1) {
      widget.onPrevPage();
    } else {
      widget.onNextPage();
    }
    // Parent calls setState → next build sees _pendingSettle, syncs snapshot,
    // resets offset to 0 atomically.
  }

  // ─ Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Sync snapshot when idle. When _pendingSettle is true, the parent just
    // delivered new props after a page turn — sync the snapshot and reset
    // offset to 0 in the same build frame so there's no visual flash.
    if (!_busy) {
      _syncSnapshot();
    } else if (_pendingSettle) {
      _pendingSettle = false;
      _syncSnapshot();
      _offset.value = 0;
    }

    if (_snapCurrent == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final pageWidth = constraints.maxWidth;

        final prevChild = _buildSlot(_snapPrev, isPrev: true);
        final currentChild = _buildCurrentPage(context);
        final nextChild = _buildSlot(_snapNext, isNext: true);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: (d) => _onDragEnd(d, pageWidth),
          child: ClipRect(
            child: ValueListenableBuilder<double>(
              valueListenable: _offset,
              builder: (context, offset, _) {
                return Stack(
                  children: [
                    Positioned(
                      left: offset - pageWidth,
                      top: 0,
                      bottom: 0,
                      width: pageWidth,
                      child: prevChild,
                    ),
                    Positioned(
                      left: offset,
                      top: 0,
                      bottom: 0,
                      width: pageWidth,
                      child: currentChild,
                    ),
                    Positioned(
                      left: offset + pageWidth,
                      top: 0,
                      bottom: 0,
                      width: pageWidth,
                      child: nextChild,
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildCurrentPage(BuildContext context) {
    final isSelectedChapter =
        widget.selectedChapterId == widget.centerChapterId;

    return Padding(
      padding: widget.contentPadding,
      child: PageContentView(
        page: _snapCurrent!,
        fontScale: widget.fontScale,
        lineHeight: widget.lineHeight,
        selectedParagraphId: isSelectedChapter
            ? widget.selectedParagraphId
            : null,
        onParagraphLongPress: widget.onParagraphLongPress != null
            ? (paragraphId, paragraph, rect) => widget.onParagraphLongPress!(
                widget.centerChapterId,
                paragraphId,
                paragraph,
                rect,
              )
            : null,
      ),
    );
  }

  Widget _buildSlot(
    PageContent? page, {
    bool isPrev = false,
    bool isNext = false,
  }) {
    if (page == null) {
      if (isPrev && _snapIsFirst) {
        return const SizedBox.shrink();
      }
      if (isNext && _snapIsLast) {
        return _buildEndOfBook(context);
      }
      final error = isPrev ? _snapPrevError : _snapNextError;
      final onRetry = isPrev ? widget.onRetryPrev : widget.onRetryNext;
      if (error != null) {
        return Center(
          child: ChapterStatusBlock(
            kind: ChapterStatusBlockKind.error,
            message: error,
            onRetry: onRetry,
          ),
        );
      }
      return const Center(
        child: ChapterStatusBlock(kind: ChapterStatusBlockKind.loading),
      );
    }
    return Padding(
      padding: widget.contentPadding,
      child: PageContentView(
        page: page,
        fontScale: widget.fontScale,
        lineHeight: widget.lineHeight,
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
