import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../src/rust/api/types.dart';
import '../../feeds/feed_service.dart' show ParagraphIdStringExt;
import 'chapter_status_block.dart';
import 'paragraph_view.dart';
import 'reader_types.dart';

class VerticalReaderView extends StatelessWidget {
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
    required this.centerKey,
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
  )? onParagraphLongPress;
  final String? selectedChapterId;
  final String? selectedParagraphId;
  final bool Function(ScrollNotification) onScrollNotification;
  final GlobalKey centerKey;
  final GlobalKey prevSliverKey;
  final GlobalKey centerSliverKey;
  final GlobalKey nextSliverKey;
  final String scrollTargetParagraphId;
  final GlobalKey jumpTargetKey;

  static const _chapterGap = 48.0;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: onScrollNotification,
      child: CustomScrollView(
        center: centerKey,
        controller: scrollController,
        slivers: [
          ValueListenableBuilder<ChapterLoadState>(
            valueListenable: prevSlot,
            builder: (_, state, _) => prevChapterId != null
                ? _buildSliver(
                    state,
                    isReversed: true,
                    sliverKey: prevSliverKey,
                  )
                : SliverToBoxAdapter(
                    key: prevSliverKey,
                    child: const SizedBox.shrink()),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
                height: prevChapterId != null ? _chapterGap : 0),
          ),
          SliverToBoxAdapter(
              key: centerKey, child: const SizedBox.shrink()),
          ValueListenableBuilder<ChapterLoadState>(
            valueListenable: centerSlot,
            builder: (_, state, _) => _buildSliver(
              state,
              chapterId: centerChapterId,
              sliverKey: centerSliverKey,
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
                height: nextChapterId != null ? _chapterGap : 0),
          ),
          ValueListenableBuilder<ChapterLoadState>(
            valueListenable: nextSlot,
            builder: (_, state, _) => nextChapterId != null
                ? _buildSliver(
                    state,
                    sliverKey: nextSliverKey,
                  )
                : SliverToBoxAdapter(
                    key: nextSliverKey,
                    child: const SizedBox.shrink()),
          ),
          if (isLast)
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
                  ? () => onRetry(chapterId)
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
              chapterId ?? centerChapterId,
            );
          },
        ),
    };
  }

  Widget _buildParagraph(
      ParagraphContent paragraph, int paraIndex, String chapterId) {
    final paragraphId = paragraph.id.toStringValue();
    final isSelected = selectedChapterId == chapterId &&
        selectedParagraphId == paragraphId;
    final isJumpTarget = paragraphId == scrollTargetParagraphId;

    return Padding(
      key: isJumpTarget ? jumpTargetKey : null,
      padding: EdgeInsets.only(
        left: contentPadding.left,
        right: contentPadding.right,
        top: paraIndex == 0 ? contentPadding.top : 0,
        bottom: LanghuanTheme.spaceMd,
      ),
      child: ParagraphView(
        paragraph: paragraph,
        fontScale: fontScale,
        lineHeight: lineHeight,
        selected: isSelected,
        onLongPress: onParagraphLongPress != null
            ? (rect) => onParagraphLongPress!(
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
