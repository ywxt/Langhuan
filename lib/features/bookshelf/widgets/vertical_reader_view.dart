import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../src/rust/api/types.dart';
import '../../feeds/feed_service.dart' show ParagraphIdStringExt;
import 'chapter_status_block.dart';
import 'paragraph_view.dart';
import 'reader_types.dart';

/// Vertical reader built from 3 slivers (prev / center / next) without
/// [CustomScrollView.center].  All slivers flow top-to-bottom so offset 0 is
/// the very top of the prev chapter.
///
/// Chapter slides are handled by [performSlide] which atomically corrects the
/// scroll offset via [ScrollPosition.correctPixels] *before* the next frame
/// paints, eliminating the 1-frame jump that the old center-key approach had.
class VerticalReaderView extends StatefulWidget {
  const VerticalReaderView({
    super.key,
    required this.centerChapterId,
    this.prevChapterId,
    this.nextChapterId,
    required this.prevSlot,
    required this.centerSlot,
    required this.nextSlot,
    required this.scrollController,
    required this.fontScale,
    required this.lineHeight,
    required this.contentPadding,
    required this.onRetry,
    required this.isFirst,
    required this.isLast,
    this.onParagraphLongPress,
    this.selectedChapterId,
    this.selectedParagraphId,
    required this.onScrollNotification,
    required this.prevSliverKey,
    required this.centerSliverKey,
    required this.nextSliverKey,
    this.scrollTargetParagraphId = '',
    required this.jumpTargetKey,
  });

  final String centerChapterId;
  final String? prevChapterId;
  final String? nextChapterId;
  final ValueNotifier<ChapterLoadState> prevSlot;
  final ValueNotifier<ChapterLoadState> centerSlot;
  final ValueNotifier<ChapterLoadState> nextSlot;
  final ScrollController scrollController;
  final double fontScale;
  final double lineHeight;
  final EdgeInsets contentPadding;
  final void Function(String chapterId) onRetry;
  final bool isFirst;
  final bool isLast;
  final void Function(
    String chapterId,
    String paragraphId,
    ParagraphContent paragraph,
    Rect globalRect,
  )?
  onParagraphLongPress;
  final String? selectedChapterId;
  final String? selectedParagraphId;
  final bool Function(ScrollNotification) onScrollNotification;
  final GlobalKey prevSliverKey;
  final GlobalKey centerSliverKey;
  final GlobalKey nextSliverKey;
  final String scrollTargetParagraphId;
  final GlobalKey jumpTargetKey;

  static const chapterGap = 48.0;

  @override
  State<VerticalReaderView> createState() => VerticalReaderViewState();
}

class VerticalReaderViewState extends State<VerticalReaderView> {
  late ChapterLoadState _displayPrevState;
  late ChapterLoadState _displayCenterState;
  late ChapterLoadState _displayNextState;

  // ── Listeners ──────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _displayPrevState = widget.prevSlot.value;
    _displayCenterState = widget.centerSlot.value;
    _displayNextState = widget.nextSlot.value;

    // Keep center live. Freeze prev/next loaded results until chapter slide,
    // but still reflect loading/error states for better retry feedback.
    widget.prevSlot.addListener(_onPrevSlotChanged);
    widget.centerSlot.addListener(_onSlotChanged);
    widget.nextSlot.addListener(_onNextSlotChanged);
  }

  @override
  void dispose() {
    widget.prevSlot.removeListener(_onPrevSlotChanged);
    widget.centerSlot.removeListener(_onSlotChanged);
    widget.nextSlot.removeListener(_onNextSlotChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant VerticalReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.prevSlot != widget.prevSlot) {
      oldWidget.prevSlot.removeListener(_onPrevSlotChanged);
      widget.prevSlot.addListener(_onPrevSlotChanged);
    }

    if (oldWidget.centerSlot != widget.centerSlot) {
      oldWidget.centerSlot.removeListener(_onSlotChanged);
      widget.centerSlot.addListener(_onSlotChanged);
    }

    if (oldWidget.nextSlot != widget.nextSlot) {
      oldWidget.nextSlot.removeListener(_onNextSlotChanged);
      widget.nextSlot.addListener(_onNextSlotChanged);
    }

    final centerChanged = oldWidget.centerChapterId != widget.centerChapterId;
    if (centerChanged || oldWidget.prevSlot != widget.prevSlot) {
      _displayPrevState = widget.prevSlot.value;
    }
    if (centerChanged || oldWidget.nextSlot != widget.nextSlot) {
      _displayNextState = widget.nextSlot.value;
    }
    if (centerChanged) {
      _displayCenterState = widget.centerSlot.value;
    }
  }

  void _onSlotChanged() {
    if (!mounted) return;
    _displayCenterState = widget.centerSlot.value;
    setState(() {});
  }

  void _onPrevSlotChanged() {
    if (!mounted) return;
    _displayPrevState = widget.prevSlot.value;
    setState(() {});
  }

  void _onNextSlotChanged() {
    if (!mounted) return;
    _displayNextState = widget.nextSlot.value;
    setState(() {});
  }

  // ── Public API for ChapterContentManager ───────────────────────────────

  /// Returns the scroll extent of the sliver identified by [key].
  double sliverExtent(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return 0;
    final ro = ctx.findRenderObject();
    if (ro is RenderSliver) {
      return ro.geometry?.scrollExtent ?? 0;
    }
    return 0;
  }

  /// Atomically correct the scroll offset so the viewport stays at the same
  /// visual position after a chapter slide.  Call this *before* setState in
  /// the manager so the correction is applied in the same frame.
  void correctScrollForSlide(double delta) {
    final sc = widget.scrollController;
    if (!sc.hasClients) return;
    final pos = sc.position;
    final corrected = (pos.pixels + delta).clamp(
      // Use 0.0 as lower bound; the framework will clamp again during layout.
      0.0,
      // Use double.infinity as upper bound because the new max extent is
      // unknown until layout.  The framework will clamp again during layout.
      double.infinity,
    );
    pos.correctPixels(corrected);
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final prevState = _displayPrevState;
    final centerState = _displayCenterState;
    final nextState = _displayNextState;

    return NotificationListener<ScrollNotification>(
      onNotification: widget.onScrollNotification,
      child: CustomScrollView(
        controller: widget.scrollController,
        slivers: [
          // ── prev chapter ──
          if (widget.prevChapterId != null)
            _buildSliver(
              prevState,
              chapterId: widget.prevChapterId,
              sliverKey: widget.prevSliverKey,
            )
          else
            SliverToBoxAdapter(
              key: widget.prevSliverKey,
              child: const SizedBox.shrink(),
            ),

          // gap between prev and center
          SliverToBoxAdapter(
            child: SizedBox(
              height: widget.prevChapterId != null
                  ? VerticalReaderView.chapterGap
                  : 0,
            ),
          ),

          // ── center chapter ──
          _buildSliver(
            centerState,
            chapterId: widget.centerChapterId,
            sliverKey: widget.centerSliverKey,
          ),

          // gap between center and next
          SliverToBoxAdapter(
            child: SizedBox(
              height: widget.nextChapterId != null
                  ? VerticalReaderView.chapterGap
                  : 0,
            ),
          ),

          // ── next chapter ──
          if (widget.nextChapterId != null)
            _buildSliver(
              nextState,
              chapterId: widget.nextChapterId,
              sliverKey: widget.nextSliverKey,
            )
          else
            SliverToBoxAdapter(
              key: widget.nextSliverKey,
              child: const SizedBox.shrink(),
            ),

          if (widget.isLast)
            SliverToBoxAdapter(child: _buildEndOfBook(context)),
        ],
      ),
    );
  }

  Widget _buildSliver(
    ChapterLoadState state, {
    String? chapterId,
    GlobalKey? sliverKey,
  }) {
    return switch (state) {
      ChapterIdle() => SliverToBoxAdapter(
        key: sliverKey,
        child: const SizedBox.shrink(),
      ),
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
            onRetry: chapterId != null ? () => widget.onRetry(chapterId) : null,
          ),
        ),
      ),
      ChapterLoaded(:final paragraphs) => SliverList.builder(
        key: sliverKey,
        itemCount: paragraphs.length,
        itemBuilder: (_, i) => _buildParagraph(
          paragraphs[i],
          i,
          chapterId ?? widget.centerChapterId,
        ),
      ),
    };
  }

  Widget _buildParagraph(
    ParagraphContent paragraph,
    int paraIndex,
    String chapterId,
  ) {
    final paragraphId = paragraph.id.toStringValue();
    final isSelected =
        widget.selectedChapterId == chapterId &&
        widget.selectedParagraphId == paragraphId;
    final isJumpTarget = paragraphId == widget.scrollTargetParagraphId;

    return Padding(
      key: isJumpTarget ? widget.jumpTargetKey : null,
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
                chapterId,
                paragraphId,
                paragraph,
                rect,
              )
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
