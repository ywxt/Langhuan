import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../src/rust/api/types.dart';
import '../../feeds/feed_service.dart' show ParagraphIdStringExt;
import 'chapter_status_block.dart';
import 'paragraph_view.dart';
import 'reader_types.dart';

class VerticalReaderView extends StatefulWidget {
  const VerticalReaderView({
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
    this.initialOffset = 0,
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
  final double initialOffset;
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
  State<VerticalReaderView> createState() => _VerticalReaderViewState();
}

class _VerticalReaderViewState extends State<VerticalReaderView> {
  static const _chapterGap = 48.0;

  late ScrollController _scrollController;
  final GlobalKey _centerKey = GlobalKey();
  final GlobalKey _prevSliverKey = GlobalKey();
  final GlobalKey _centerSliverKey = GlobalKey();
  final GlobalKey _nextSliverKey = GlobalKey();

  bool _jumpInProgress = false;
  String _reportedChapterId = '';

  String _scrollTargetParagraphId = '';
  final GlobalKey _jumpTargetKey = GlobalKey();
  int _ensureRetries = 0;
  static const _maxEnsureRetries = 10;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _reportedChapterId = widget.centerChapterId;
    widget.onJumpRegistered?.call(_jumpToPosition);
    _scheduleInitialScroll();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant VerticalReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.centerChapterId != widget.centerChapterId) {
      _reportedChapterId = widget.centerChapterId;
      _jumpInProgress = true;

      final oldOffset =
          _scrollController.hasClients ? _scrollController.offset : 0.0;
      final oldCenterExt = _sliverExtent(_centerSliverKey);
      final oldPrevExt = _sliverExtent(_prevSliverKey);
      final wasForward = oldWidget.nextChapterId == widget.centerChapterId;
      final wasBackward = oldWidget.prevChapterId == widget.centerChapterId;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) {
          _jumpInProgress = false;
          return;
        }

        final double delta;
        if (wasForward) {
          delta = -(oldCenterExt + _chapterGap);
        } else if (wasBackward) {
          delta = oldPrevExt + _chapterGap;
        } else {
          _scrollController.jumpTo(0);
          _jumpInProgress = false;
          return;
        }

        final target = oldOffset + delta;
        final pos = _scrollController.position;
        _scrollController
            .jumpTo(target.clamp(pos.minScrollExtent, pos.maxScrollExtent));
        _jumpInProgress = false;
      });
    }
  }

  // ─ Sliver extent helper ───────────────────────────────────────────────

  double _sliverExtent(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return 0;
    final renderObject = ctx.findRenderObject();
    if (renderObject is RenderSliver) {
      return renderObject.geometry?.scrollExtent ?? 0;
    }
    return 0;
  }

  // ─ Initial scroll ─────────────────────────────────────────────────────

  void _scheduleInitialScroll() {
    if (widget.initialParagraphId.isNotEmpty) {
      _scrollTargetParagraphId = widget.initialParagraphId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureTargetVisible();
      });
    } else if (widget.initialOffset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToOffset(widget.initialOffset);
      });
    }
  }

  void _scrollToOffset(double offset) {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(offset.clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    ));
  }

  void _ensureTargetVisible() {
    if (!mounted || !_scrollController.hasClients) return;
    final ctx = _jumpTargetKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignment: 0.0, duration: Duration.zero);
      setState(() => _scrollTargetParagraphId = '');
      _jumpInProgress = false;
      _ensureRetries = 0;
      return;
    }

    if (++_ensureRetries > _maxEnsureRetries) {
      setState(() => _scrollTargetParagraphId = '');
      _jumpInProgress = false;
      _ensureRetries = 0;
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureTargetVisible();
    });
  }

  void _jumpToPosition(String paragraphId, double offset) {
    _jumpInProgress = true;
    _ensureRetries = 0;
    if (paragraphId.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToOffset(offset);
        _jumpInProgress = false;
      });
      return;
    }
    _scrollTargetParagraphId = paragraphId;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureTargetVisible();
    });
  }

  // ─ Scroll notifications ───────────────────────────────────────────────

  bool _onScrollNotification(ScrollNotification n) {
    if (_jumpInProgress || !_scrollController.hasClients) return false;

    if (n is ScrollUpdateNotification) {
      _reportPosition();
    }

    if (n is ScrollEndNotification) {
      _reportPosition();
      _detectChapter();
    }

    return false;
  }

  void _reportPosition() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final centerExt = _sliverExtent(_centerSliverKey);

    if (centerExt <= 0) return;

    final centerState = widget.centerSlot.value;
    if (centerState is! ChapterLoaded) return;
    final paragraphs = centerState.paragraphs;
    if (paragraphs.isEmpty) return;

    // offset is relative to center anchor: 0 = top of center sliver
    // Only report when viewport is within center chapter range
    if (offset < 0 || offset > centerExt) return;

    final ratio = (offset / centerExt).clamp(0.0, 1.0);
    final paraIdx =
        (ratio * paragraphs.length).floor().clamp(0, paragraphs.length - 1);
    widget.onPositionUpdate(
      widget.centerChapterId,
      paragraphs[paraIdx].id.toStringValue(),
      offset,
    );
  }

  void _detectChapter() {
    if (!_scrollController.hasClients) return;

    final vpHeight = _scrollController.position.viewportDimension;
    final vpCenter = _scrollController.offset + vpHeight / 2;
    final centerExt = _sliverExtent(_centerSliverKey);

    if (vpCenter >= 0 && vpCenter < centerExt) {
      _reportedChapterId = widget.centerChapterId;
      return;
    }

    if (vpCenter >= centerExt + _chapterGap && widget.nextChapterId != null) {
      if (_reportedChapterId != widget.nextChapterId) {
        _reportedChapterId = widget.nextChapterId!;
        widget.onChapterBoundary?.call(1);
      }
      return;
    }

    if (vpCenter < 0 && widget.prevChapterId != null) {
      if (_reportedChapterId != widget.prevChapterId) {
        _reportedChapterId = widget.prevChapterId!;
        widget.onChapterBoundary?.call(-1);
      }
      return;
    }
  }

  // ─ Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: CustomScrollView(
        center: _centerKey,
        controller: _scrollController,
        slivers: [
          if (widget.prevChapterId != null)
            ValueListenableBuilder<ChapterLoadState>(
              valueListenable: widget.prevSlot,
              builder: (_, state, _) => _buildSliver(
                state,
                isReversed: true,
                sliverKey: _prevSliverKey,
              ),
            ),
          if (widget.prevChapterId != null)
            const SliverToBoxAdapter(
                child: SizedBox(height: _chapterGap)),
          SliverToBoxAdapter(
              key: _centerKey, child: const SizedBox.shrink()),
          ValueListenableBuilder<ChapterLoadState>(
            valueListenable: widget.centerSlot,
            builder: (_, state, _) => _buildSliver(
              state,
              chapterId: widget.centerChapterId,
              sliverKey: _centerSliverKey,
            ),
          ),
          if (widget.nextChapterId != null)
            const SliverToBoxAdapter(
                child: SizedBox(height: _chapterGap)),
          if (widget.nextChapterId != null)
            ValueListenableBuilder<ChapterLoadState>(
              valueListenable: widget.nextSlot,
              builder: (_, state, _) => _buildSliver(
                state,
                sliverKey: _nextSliverKey,
              ),
            ),
          if (widget.isLast)
            SliverToBoxAdapter(child: _buildEndOfBook(context)),
        ],
      ),
    );
  }

  Widget _buildSliver(
    ChapterLoadState state, {
    bool isReversed = false,
    String? chapterId,
    GlobalKey? sliverKey,
  }) {
    return switch (state) {
      ChapterIdle() =>
        SliverToBoxAdapter(key: sliverKey, child: const SizedBox.shrink()),
      ChapterLoading() => SliverToBoxAdapter(
          key: sliverKey,
          child: const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ChapterLoadError(:final message) => SliverToBoxAdapter(
          key: sliverKey,
          child: SizedBox(
            height: 300,
            child: ChapterStatusBlock(
              kind: ChapterStatusBlockKind.error,
              message: message,
              onRetry: chapterId != null
                  ? () => widget.onRetry(chapterId)
                  : null,
            ),
          ),
        ),
      ChapterLoaded(:final paragraphs) => SliverList.builder(
          key: sliverKey,
          itemCount: paragraphs.length,
          itemBuilder: (_, i) {
            final idx = isReversed ? paragraphs.length - 1 - i : i;
            return _buildParagraph(
              paragraphs[idx],
              idx,
              chapterId ?? widget.centerChapterId,
            );
          },
        ),
    };
  }

  Widget _buildParagraph(
      ParagraphContent paragraph, int paraIndex, String chapterId) {
    final paragraphId = paragraph.id.toStringValue();
    final isSelected = widget.selectedChapterId == chapterId &&
        widget.selectedParagraphId == paragraphId;
    final isJumpTarget = paragraphId == _scrollTargetParagraphId;

    return Padding(
      key: isJumpTarget ? _jumpTargetKey : null,
      padding: EdgeInsets.only(
        left: widget.contentPadding.left,
        right: widget.contentPadding.right,
        top: paraIndex == 0 ? widget.contentPadding.top : 0,
        bottom: LanghuanTheme.spaceMd,
      ),
      child: ParagraphView(
        paragraph: paragraph,
        fontScale: widget.fontScale,
        lineHeight: widget.lineHeight,
        selected: isSelected,
        onLongPress: widget.onParagraphLongPress != null
            ? (rect) => widget.onParagraphLongPress!(
                chapterId, paragraphId, paragraph, rect)
            : null,
      ),
    );
  }

  Widget _buildEndOfBook(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LanghuanTheme.spaceXl),
      child: Center(
        child: Text(
          l10n.readerEndOfBook,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}
