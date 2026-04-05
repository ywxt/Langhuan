import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/error_state.dart';
import '../../src/bindings/signals/signals.dart';
import '../feeds/feed_providers.dart';
import '../feeds/feed_service.dart';

enum _ReaderMode { verticalScroll, horizontalPaging }

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({
    super.key,
    required this.feedId,
    required this.bookId,
    required this.chapterId,
  });

  final String feedId;
  final String bookId;
  final String chapterId;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  static const double _swipeVelocityThreshold = 220;
  static const Duration _progressSaveDebounce = Duration(seconds: 1);
  static const Duration _controlsAutoHideDelay = Duration(seconds: 3);

  String? _currentChapterId;
  bool _isSwitchingChapter = false;
  bool _restoredPosition = false;
  bool _showBottomBar = false;

  _ReaderMode _readerMode = _ReaderMode.verticalScroll;

  int _horizontalParagraphIndex = 0;
  List<ParagraphContent> _latestContentItems = const [];
  late final ScrollController _scrollController;
  late final PageController _pageController;
  late final ReadingProgressNotifier _readingProgressNotifier;
  Timer? _saveTimer;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    _readingProgressNotifier = ref.read(readingProgressProvider.notifier);
    _scrollController = ScrollController()..addListener(_onScroll);
    _pageController = PageController();
    _currentChapterId = widget.chapterId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureLoaded();
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _controlsTimer?.cancel();
    unawaited(_saveReadingProgress(updateProviderState: false));
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_readerMode != _ReaderMode.verticalScroll) return;
    if (!_scrollController.hasClients) return;
    _scheduleSaveProgress();
  }

  void _onPageChanged(int index) {
    if (_readerMode != _ReaderMode.horizontalPaging) return;
    _horizontalParagraphIndex = index;
    _scheduleSaveProgress();
  }

  void _scheduleSaveProgress() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_progressSaveDebounce, () {
      if (!mounted) return;
      unawaited(_saveReadingProgress(updateProviderState: true));
    });
  }

  void _toggleBottomBar() {
    setState(() {
      _showBottomBar = !_showBottomBar;
    });

    _controlsTimer?.cancel();
    if (_showBottomBar) {
      _controlsTimer = Timer(_controlsAutoHideDelay, () {
        if (!mounted) return;
        setState(() {
          _showBottomBar = false;
        });
      });
    }
  }

  int _estimateParagraphIndex(int totalItems) {
    if (totalItems <= 1) {
      return 0;
    }

    if (_readerMode == _ReaderMode.horizontalPaging) {
      return _horizontalParagraphIndex.clamp(0, totalItems - 1);
    }

    if (!_scrollController.hasClients) {
      return 0;
    }

    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent <= 0) {
      return 0;
    }

    final ratio = (_scrollController.offset / maxExtent).clamp(0.0, 1.0);
    return (ratio * (totalItems - 1)).round();
  }

  Future<void> _saveReadingProgress({required bool updateProviderState}) async {
    final chapterId = _currentChapterId;
    if (chapterId == null || chapterId.isEmpty) {
      return;
    }

    final items = _latestContentItems;
    final paragraphIndex = _estimateParagraphIndex(items.length);
    final scrollOffset = _readerMode == _ReaderMode.verticalScroll
        ? (_scrollController.hasClients ? _scrollController.offset : 0.0)
        : paragraphIndex.toDouble();

    if (updateProviderState) {
      await _readingProgressNotifier.save(
        feedId: widget.feedId,
        bookId: widget.bookId,
        chapterId: chapterId,
        paragraphIndex: paragraphIndex,
        scrollOffset: scrollOffset,
      );
      return;
    }

    await FeedService.instance.setReadingProgress(
      feedId: widget.feedId,
      bookId: widget.bookId,
      chapterId: chapterId,
      paragraphIndex: paragraphIndex,
      scrollOffset: scrollOffset,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _ensureLoaded() async {
    if (widget.feedId.isEmpty ||
        widget.bookId.isEmpty ||
        widget.chapterId.isEmpty) {
      return;
    }

    final chaptersState = ref.read(chaptersProvider);
    if (chaptersState.bookId != widget.bookId || chaptersState.items.isEmpty) {
      await ref
          .read(chaptersProvider.notifier)
          .load(feedId: widget.feedId, bookId: widget.bookId);
    }

    await ref
        .read(readingProgressProvider.notifier)
        .load(feedId: widget.feedId, bookId: widget.bookId);

    final progress = ref.read(readingProgressProvider).progress;
    if (progress != null && progress.chapterId.isNotEmpty) {
      _currentChapterId = progress.chapterId;
    }

    final chapterId = _currentChapterId;
    if (chapterId == null || chapterId.isEmpty) {
      return;
    }

    await ref
        .read(chapterContentProvider.notifier)
        .load(
          feedId: widget.feedId,
          bookId: widget.bookId,
          chapterId: chapterId,
        );

    final currentItems = ref.read(chapterContentProvider).items;
    _latestContentItems = currentItems;
    _restoreReadingPosition(progress, currentItems.length, chapterId);
  }

  void _restoreReadingPosition(
    ReadingProgressModel? progress,
    int totalItems,
    String chapterId,
  ) {
    if (_restoredPosition ||
        progress == null ||
        progress.chapterId != chapterId) {
      return;
    }

    _restoredPosition = true;
    final targetParagraph = progress.paragraphIndex.clamp(
      0,
      totalItems <= 0 ? 0 : totalItems - 1,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_readerMode == _ReaderMode.horizontalPaging) {
        _horizontalParagraphIndex = targetParagraph;
        if (_pageController.hasClients) {
          _pageController.jumpToPage(targetParagraph);
        }
      } else if (_scrollController.hasClients) {
        final maxExtent = _scrollController.position.maxScrollExtent;
        final target = progress.scrollOffset.clamp(0.0, maxExtent);
        _scrollController.jumpTo(target);
      }
    });
  }

  Future<void> _switchReaderMode(_ReaderMode nextMode, int totalItems) async {
    if (nextMode == _readerMode) return;

    if (_readerMode == _ReaderMode.verticalScroll) {
      _horizontalParagraphIndex = _estimateParagraphIndex(totalItems);
    }

    setState(() {
      _readerMode = nextMode;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (_readerMode == _ReaderMode.horizontalPaging) {
        final target = _horizontalParagraphIndex.clamp(
          0,
          totalItems <= 0 ? 0 : totalItems - 1,
        );
        _horizontalParagraphIndex = target;
        if (_pageController.hasClients) {
          _pageController.jumpToPage(target);
        }
      } else {
        if (!_scrollController.hasClients || totalItems <= 1) return;
        final ratio = _horizontalParagraphIndex / (totalItems - 1);
        final target = _scrollController.position.maxScrollExtent * ratio;
        _scrollController.jumpTo(
          target.clamp(0.0, _scrollController.position.maxScrollExtent),
        );
      }
    });
  }

  int _currentChapterIndex(List<ChapterInfoModel> chapters) {
    final chapterId = _currentChapterId;
    if (chapterId == null) return -1;
    return chapters.indexWhere((c) => c.id == chapterId);
  }

  Future<void> _jumpToChapter(
    BuildContext context,
    List<ChapterInfoModel> chapters,
    int targetIndex,
  ) async {
    if (_isSwitchingChapter) return;

    final l10n = AppLocalizations.of(context);
    if (targetIndex < 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.readerAtFirstChapter)));
      return;
    }
    if (targetIndex >= chapters.length) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.readerAtLastChapter)));
      return;
    }

    final contentState = ref.read(chapterContentProvider);
    if (contentState.isLoading) {
      return;
    }

    final target = chapters[targetIndex];

    await _saveReadingProgress(updateProviderState: true);
    _restoredPosition = false;
    _horizontalParagraphIndex = 0;

    _isSwitchingChapter = true;
    setState(() {
      _currentChapterId = target.id;
    });
    try {
      await ref
          .read(chapterContentProvider.notifier)
          .load(
            feedId: widget.feedId,
            bookId: widget.bookId,
            chapterId: target.id,
          );
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    } finally {
      _isSwitchingChapter = false;
    }
  }

  Future<void> _onHorizontalDragEnd(
    BuildContext context,
    DragEndDetails details,
    List<ChapterInfoModel> chapters,
  ) async {
    if (_readerMode != _ReaderMode.verticalScroll) {
      return;
    }

    final v = details.primaryVelocity ?? 0;
    if (v.abs() < _swipeVelocityThreshold) return;

    final idx = _currentChapterIndex(chapters);
    if (idx < 0) return;

    if (v < 0) {
      await _jumpToChapter(context, chapters, idx + 1);
    } else {
      await _jumpToChapter(context, chapters, idx - 1);
    }
  }

  List<Widget> _buildParagraphs(
    BuildContext context,
    List<ParagraphContent> items,
  ) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];

    for (final item in items) {
      if (item is ParagraphContentTitle) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: LanghuanTheme.spaceMd),
            child: Text(
              item.text,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
          ),
        );
        continue;
      }

      if (item is ParagraphContentText) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: LanghuanTheme.spaceMd),
            child: Text(
              item.content,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.8),
            ),
          ),
        );
        continue;
      }

      if (item is ParagraphContentImage) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: LanghuanTheme.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: LanghuanTheme.borderRadiusMd,
                  child: Image.network(
                    item.url,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    },
                    errorBuilder: (_, _, _) => const AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Center(child: Icon(Icons.broken_image_outlined)),
                    ),
                  ),
                ),
                if (item.alt != null && item.alt!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: LanghuanTheme.spaceSm),
                    child: Text(
                      item.alt!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        );
      }
    }

    return widgets;
  }

  Widget _buildHorizontalPage(BuildContext context, ParagraphContent item) {
    final theme = Theme.of(context);

    Widget content;
    if (item is ParagraphContentTitle) {
      content = Text(
        item.text,
        style: theme.textTheme.headlineSmall,
        textAlign: TextAlign.center,
      );
    } else if (item is ParagraphContentText) {
      content = Text(
        item.content,
        style: theme.textTheme.bodyLarge?.copyWith(height: 1.8),
      );
    } else if (item is ParagraphContentImage) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: LanghuanTheme.borderRadiusMd,
            child: Image.network(
              item.url,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Center(child: CircularProgressIndicator()),
                );
              },
              errorBuilder: (_, _, _) => const AspectRatio(
                aspectRatio: 16 / 9,
                child: Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
          if (item.alt != null && item.alt!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: LanghuanTheme.spaceSm),
              child: Text(
                item.alt!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      );
    } else {
      content = const SizedBox.shrink();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        LanghuanTheme.spaceLg,
        LanghuanTheme.spaceLg,
        LanghuanTheme.spaceLg,
        LanghuanTheme.space2xl,
      ),
      child: content,
    );
  }

  Widget _buildBottomBar(
    BuildContext context,
    List<ChapterInfoModel> chapters,
    int currentIdx,
  ) {
    final l10n = AppLocalizations.of(context);
    final canGoPrev = currentIdx > 0;
    final canGoNext = currentIdx >= 0 && currentIdx < chapters.length - 1;
    final chapterProgress = chapters.isEmpty
        ? 0.0
        : ((currentIdx < 0 ? 0 : currentIdx + 1) / chapters.length).clamp(
            0.0,
            1.0,
          );

    return SafeArea(
      top: false,
      child: Container(
        color: Theme.of(context).colorScheme.surfaceContainer,
        padding: const EdgeInsets.fromLTRB(
          LanghuanTheme.spaceMd,
          LanghuanTheme.spaceSm,
          LanghuanTheme.spaceMd,
          LanghuanTheme.spaceMd,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (chapters.isNotEmpty) ...[
              Text(
                l10n.readerChapterProgress(
                  currentIdx < 0 ? 0 : currentIdx + 1,
                  chapters.length,
                ),
                style: Theme.of(context).textTheme.labelMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: LanghuanTheme.spaceXs),
              LinearProgressIndicator(value: chapterProgress),
              const SizedBox(height: LanghuanTheme.spaceSm),
            ],
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed:
                        (chapters.isEmpty || !canGoPrev || _isSwitchingChapter)
                        ? null
                        : () =>
                              _jumpToChapter(context, chapters, currentIdx - 1),
                    icon: const Icon(Icons.chevron_left),
                    label: Text(l10n.readerPrevChapter),
                  ),
                ),
                const SizedBox(width: LanghuanTheme.spaceSm),
                Expanded(
                  child: TextButton.icon(
                    onPressed:
                        (chapters.isEmpty || !canGoNext || _isSwitchingChapter)
                        ? null
                        : () =>
                              _jumpToChapter(context, chapters, currentIdx + 1),
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.chevron_right),
                    label: Text(l10n.readerNextChapter),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chaptersState = ref.watch(chaptersProvider);
    final contentState = ref.watch(chapterContentProvider);
    _latestContentItems = contentState.items;

    if (widget.feedId.isEmpty ||
        widget.bookId.isEmpty ||
        widget.chapterId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.readerTitle)),
        body: EmptyState(
          icon: Icons.info_outline,
          title: l10n.readerMissingParams,
        ),
      );
    }

    final chapters = chaptersState.items;
    final currentIdx = _currentChapterIndex(chapters);
    final chapterTitle = currentIdx >= 0
        ? chapters[currentIdx].title
        : l10n.readerTitle;

    Widget contentBody;
    if (contentState.isLoading && contentState.items.isEmpty) {
      contentBody = const Center(child: CircularProgressIndicator());
    } else if (contentState.hasError && contentState.items.isEmpty) {
      contentBody = ErrorState(
        title: l10n.readerLoadError,
        message: contentState.error.toString(),
        onRetry: () => ref.read(chapterContentProvider.notifier).retry(),
        retryLabel: l10n.bookDetailRetry,
      );
    } else if (contentState.items.isEmpty) {
      contentBody = EmptyState(
        icon: Icons.menu_book_outlined,
        title: l10n.readerEmpty,
      );
    } else if (_readerMode == _ReaderMode.verticalScroll) {
      final paragraphWidgets = _buildParagraphs(context, contentState.items);
      contentBody = ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(
          LanghuanTheme.spaceLg,
          LanghuanTheme.spaceLg,
          LanghuanTheme.spaceLg,
          LanghuanTheme.space2xl,
        ),
        itemCount: paragraphWidgets.length,
        itemBuilder: (context, index) => paragraphWidgets[index],
      );
    } else {
      contentBody = PageView.builder(
        controller: _pageController,
        itemCount: contentState.items.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) {
          return _buildHorizontalPage(context, contentState.items[index]);
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(chapterTitle),
        actions: [
          PopupMenuButton<_ReaderMode>(
            initialValue: _readerMode,
            onSelected: (mode) =>
                _switchReaderMode(mode, contentState.items.length),
            itemBuilder: (context) => [
              PopupMenuItem<_ReaderMode>(
                value: _ReaderMode.verticalScroll,
                child: const Text('上下滑動'),
              ),
              PopupMenuItem<_ReaderMode>(
                value: _ReaderMode.horizontalPaging,
                child: const Text('左右翻頁'),
              ),
            ],
            icon: const Icon(Icons.swap_horiz),
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _toggleBottomBar,
        onHorizontalDragEnd: (d) => _onHorizontalDragEnd(context, d, chapters),
        child: Stack(
          children: [
            Positioned.fill(child: contentBody),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !_showBottomBar,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 180),
                  offset: _showBottomBar ? Offset.zero : const Offset(0, 1),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: _showBottomBar ? 1 : 0,
                    child: _buildBottomBar(context, chapters, currentIdx),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
