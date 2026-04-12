import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/error_state.dart';
import '../../src/rust/api/types.dart';
import '../feeds/feed_service.dart';
import 'bookmark_provider.dart';
import 'book_providers.dart';
import 'reader_settings_provider.dart';
import 'reading_progress_provider.dart';
import 'widgets/chapter_content_manager.dart';
import 'widgets/reader_bottom_bar.dart';
import 'widgets/reader_types.dart';

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({
    super.key,
    required this.feedId,
    required this.bookId,
    required this.chapterId,
    this.paragraphIndex = 0,
  });

  final String feedId;
  final String bookId;
  final String chapterId;
  final int paragraphIndex;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  // ─ Loading and error state
  bool _isLoadingInitial = false;
  Object? _loadError;

  // ─ Chapter and progress state
  String? _currentChapterId;
  List<ChapterInfoModel> _chapters = const [];
  int _currentParagraphIndex = 0;
  double _currentParagraphOffset = 0;
  final Map<String, List<ParagraphContent>> _loadedParagraphsByChapter = {};

  // ─ UI state
  bool _showControls = false;
  bool _isRefreshingChapter = false;
  int _contentReloadNonce = 0;

  // ─ Controllers and notifiers
  late final ReadingProgressNotifier _readingProgressNotifier;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    _readingProgressNotifier = ref.read(readingProgressProvider.notifier);
    _currentChapterId = widget.chapterId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureLoaded();
    });
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _onChapterParagraphsReady(
    String chapterId,
    List<ParagraphContent> paragraphs,
  ) {
    _loadedParagraphsByChapter[chapterId] = paragraphs;
  }

  void _onChapterChanged(String chapterId) {
    if (_currentChapterId != chapterId) {
      setState(() {
        _currentChapterId = chapterId;
      });
    }
    _saveReadingProgressNow();
  }

  void _jumpToChapter(String chapterId) {
    _jumpToLocation(chapterId: chapterId, paragraphIndex: 0);
  }

  void _jumpToLocation({
    required String chapterId,
    required int paragraphIndex,
  }) {
    if (_currentChapterId == chapterId &&
        _currentParagraphIndex == paragraphIndex) {
      return;
    }
    setState(() {
      _currentChapterId = chapterId;
      _currentParagraphIndex = paragraphIndex;
      _currentParagraphOffset = 0;
    });
    _saveReadingProgressNow();
  }

  void _onParagraphChanged(int paragraphIndex) {
    _currentParagraphIndex = paragraphIndex;
    _saveReadingProgressNow();
  }

  void _onParagraphOffsetChanged(double offset) {
    _currentParagraphOffset = offset;
    _saveReadingProgressNow();
  }

  void _saveReadingProgressNow() {
    if (!mounted) return;
    unawaited(_saveReadingProgress());
  }

  Future<void> _saveReadingProgress() async {
    final chapterId = _currentChapterId;
    if (chapterId == null || chapterId.isEmpty) return;

    await _readingProgressNotifier.save(
      feedId: widget.feedId,
      bookId: widget.bookId,
      chapterId: chapterId,
      paragraphIndex: _currentParagraphIndex,
    );
  }

  Future<void> _ensureLoaded() async {
    if (widget.feedId.isEmpty || widget.bookId.isEmpty) return;

    setState(() {
      _isLoadingInitial = true;
      _loadError = null;
    });

    try {
      final chapters = await _loadChaptersSnapshot();
      final progress = await FeedService.instance.getReadingProgress(
        feedId: widget.feedId,
        bookId: widget.bookId,
      );
      // Load book info in background — boundary widgets will update reactively.
      unawaited(
        ref
            .read(bookInfoProvider.notifier)
            .load(feedId: widget.feedId, bookId: widget.bookId),
      );
      unawaited(
        ref
            .read(bookmarkProvider.notifier)
            .load(feedId: widget.feedId, bookId: widget.bookId),
      );
      final resolvedChapterId = _resolveInitialChapterId(chapters, progress);
      // Use router paragraph if the router specified a chapter and it matches,
      // otherwise fall back to saved reading progress.
      int initialParagraphIndex;
      if (widget.chapterId.isNotEmpty &&
          widget.chapterId == resolvedChapterId &&
          widget.paragraphIndex > 0) {
        initialParagraphIndex = widget.paragraphIndex;
      } else if (progress != null && progress.chapterId == resolvedChapterId) {
        initialParagraphIndex = progress.paragraphIndex;
      } else {
        initialParagraphIndex = 0;
      }

      if (!mounted) return;

      setState(() {
        _chapters = chapters;
        _currentChapterId = resolvedChapterId;
        _currentParagraphIndex = initialParagraphIndex;
        _currentParagraphOffset = 0;
        _isLoadingInitial = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingInitial = false;
        _loadError = error;
      });
    }
  }

  Future<List<ChapterInfoModel>> _loadChaptersSnapshot() async {
    final cached = ref.read(chaptersProvider);
    if (cached.feedId == widget.feedId &&
        cached.bookId == widget.bookId &&
        cached.items.isNotEmpty) {
      return cached.items;
    }

    return FeedService.instance
        .chapters(feedId: widget.feedId, bookId: widget.bookId)
        .toList();
  }

  String _resolveInitialChapterId(
    List<ChapterInfoModel> chapters,
    ReadingProgressModel? progress,
  ) {
    if (widget.chapterId.isNotEmpty &&
        chapters.any((chapter) => chapter.id == widget.chapterId)) {
      return widget.chapterId;
    }

    if (progress != null &&
        progress.chapterId.isNotEmpty &&
        chapters.any((chapter) => chapter.id == progress.chapterId)) {
      return progress.chapterId;
    }

    if (chapters.isNotEmpty) {
      return chapters.first.id;
    }

    return '';
  }

  int _currentChapterIndex(String? chapterId) {
    if (chapterId == null) return -1;
    return _chapters.indexWhere((c) => c.id == chapterId);
  }

  Future<void> _refreshCurrentChapter() async {
    final chapterId = _currentChapterId;
    if (chapterId == null || chapterId.isEmpty) return;
    if (_isRefreshingChapter) return;

    setState(() {
      _isRefreshingChapter = true;
    });
    try {
      await FeedService.instance
          .paragraphs(
            feedId: widget.feedId,
            bookId: widget.bookId,
            chapterId: chapterId,
            forceRefresh: true,
          )
          .drain<void>();
      if (!mounted) return;
      setState(() {
        _contentReloadNonce++;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingChapter = false;
        });
      }
    }
  }

  Future<void> _addBookmark() async {
    final chapterId = _currentChapterId;
    if (chapterId == null || chapterId.isEmpty) return;

    final snapshot = await _buildBookmarkSnapshot(
      chapterId: chapterId,
      paragraphIndex: _currentParagraphIndex,
    );

    final created = await ref
        .read(bookmarkProvider.notifier)
        .add(
          feedId: widget.feedId,
          bookId: widget.bookId,
          chapterId: chapterId,
          paragraphIndex: _currentParagraphIndex,
          paragraphName: snapshot.name,
          paragraphPreview: snapshot.preview,
        );
    if (!mounted || created == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).readerBookmarkAdded)),
    );
  }

  Future<void> _addBookmarkWithCustomLabel() async {
    final l10n = AppLocalizations.of(context);
    final chapterId = _currentChapterId;
    if (chapterId == null || chapterId.isEmpty) return;

    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.readerBookmarkLabelTitle),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 40,
            decoration: InputDecoration(hintText: l10n.readerBookmarkLabelHint),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(MaterialLocalizations.of(context).saveButtonLabel),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (label == null) return;

    final snapshot = await _buildBookmarkSnapshot(
      chapterId: chapterId,
      paragraphIndex: _currentParagraphIndex,
    );

    final created = await ref
        .read(bookmarkProvider.notifier)
        .add(
          feedId: widget.feedId,
          bookId: widget.bookId,
          chapterId: chapterId,
          paragraphIndex: _currentParagraphIndex,
          paragraphName: snapshot.name,
          paragraphPreview: snapshot.preview,
          label: label,
        );
    if (!mounted || created == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.readerBookmarkAdded)));
  }

  Future<void> _openBookmarkSheet() async {
    final l10n = AppLocalizations.of(context);
    await ref
        .read(bookmarkProvider.notifier)
        .load(feedId: widget.feedId, bookId: widget.bookId);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        String keyword = '';
        return Consumer(
          builder: (context, ref, _) {
            return StatefulBuilder(
              builder: (context, setModalState) {
                final bookmarks = ref.watch(bookmarkProvider).items;
                final filtered = bookmarks
                    .where((item) {
                      if (keyword.isEmpty) return true;
                      final lower = keyword.toLowerCase();
                      final chapterIndex = _chapters.indexWhere(
                        (c) => c.id == item.chapterId,
                      );
                      final chapterTitle = chapterIndex >= 0
                          ? _chapters[chapterIndex].title
                          : item.chapterId;
                      final label = item.label;
                      return chapterTitle.toLowerCase().contains(lower) ||
                          label.toLowerCase().contains(lower) ||
                          item.chapterId.toLowerCase().contains(lower);
                    })
                    .toList(growable: false);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        LanghuanTheme.spaceLg,
                        0,
                        LanghuanTheme.spaceLg,
                        LanghuanTheme.spaceSm,
                      ),
                      child: TextField(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: l10n.readerSearchBookmarksHint,
                        ),
                        onChanged: (value) {
                          setModalState(() {
                            keyword = value.trim();
                          });
                        },
                      ),
                    ),
                    if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(LanghuanTheme.spaceLg),
                        child: Center(child: Text(l10n.readerNoBookmarks)),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            final chapterIndex = _chapters.indexWhere(
                              (c) => c.id == item.chapterId,
                            );
                            final chapterTitle = chapterIndex >= 0
                                ? _chapters[chapterIndex].title
                                : item.chapterId;
                            final label = item.label.trim();
                            final paragraphName =
                                item.paragraphName.trim().isEmpty
                                ? l10n.readerBookmarkParagraph(
                                    item.paragraphIndex + 1,
                                  )
                                : item.paragraphName.trim();
                            final preview = item.paragraphPreview.trim();
                            return ListTile(
                              title: Text(chapterTitle),
                              subtitle: Text(
                                label.isEmpty
                                    ? '$paragraphName\n$preview'
                                    : '$label · $paragraphName\n$preview',
                              ),
                              isThreeLine: true,
                              onTap: () {
                                Navigator.of(context).pop();
                                _jumpToLocation(
                                  chapterId: item.chapterId,
                                  paragraphIndex: item.paragraphIndex,
                                );
                              },
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  await ref
                                      .read(bookmarkProvider.notifier)
                                      .remove(item.id);
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(
                                    this.context,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(l10n.readerBookmarkRemoved),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<({String name, String preview})> _buildBookmarkSnapshot({
    required String chapterId,
    required int paragraphIndex,
  }) async {
    final l10n = AppLocalizations.of(context);
    final paragraphs = _loadedParagraphsByChapter[chapterId];
    if (paragraphs == null || paragraphs.isEmpty) {
      return (
        name: l10n.readerBookmarkParagraph(paragraphIndex + 1),
        preview: '',
      );
    }
    return (
      name: _paragraphName(paragraphs, paragraphIndex, l10n),
      preview: _paragraphPreview(paragraphs, paragraphIndex),
    );
  }

  String _paragraphName(
    List<ParagraphContent> paragraphs,
    int paragraphIndex,
    AppLocalizations l10n,
  ) {
    if (paragraphs.isEmpty) {
      return l10n.readerBookmarkParagraph(paragraphIndex + 1);
    }

    final safeIndex = paragraphIndex.clamp(0, paragraphs.length - 1);
    final current = paragraphs[safeIndex];
    if (current is ParagraphContent_Title && current.text.trim().isNotEmpty) {
      return current.text.trim();
    }

    for (int i = safeIndex; i >= 0; i--) {
      final p = paragraphs[i];
      if (p is ParagraphContent_Title && p.text.trim().isNotEmpty) {
        return p.text.trim();
      }
    }

    return l10n.readerBookmarkParagraph(safeIndex + 1);
  }

  String _paragraphPreview(
    List<ParagraphContent> paragraphs,
    int paragraphIndex,
  ) {
    if (paragraphs.isEmpty) return '';
    final safeIndex = paragraphIndex.clamp(0, paragraphs.length - 1);

    for (int i = safeIndex; i < paragraphs.length; i++) {
      final p = paragraphs[i];
      if (p is ParagraphContent_Text && p.content.trim().isNotEmpty) {
        return _truncatePreview(p.content.trim());
      }
    }

    return '';
  }

  String _truncatePreview(String text) {
    if (text.length <= 80) return text;
    return '${text.substring(0, 80)}...';
  }

  Future<void> _openTocSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        String keyword = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = _chapters
                .where((chapter) {
                  if (keyword.isEmpty) return true;
                  final lower = keyword.toLowerCase();
                  return chapter.title.toLowerCase().contains(lower) ||
                      chapter.id.toLowerCase().contains(lower);
                })
                .toList(growable: false);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    LanghuanTheme.spaceLg,
                    0,
                    LanghuanTheme.spaceLg,
                    LanghuanTheme.spaceSm,
                  ),
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: l10n.readerSearchTocHint,
                    ),
                    onChanged: (value) {
                      setModalState(() {
                        keyword = value.trim();
                      });
                    },
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final chapter = filtered[index];
                      final chapterIndex = _chapters.indexWhere(
                        (c) => c.id == chapter.id,
                      );
                      return ListTile(
                        selected: chapter.id == _currentChapterId,
                        leading: Text('${chapterIndex + 1}'),
                        title: Text(chapter.title),
                        onTap: () {
                          Navigator.of(context).pop();
                          _jumpToChapter(chapter.id);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openInterfaceSheet() async {
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(readerSettingsProvider);
          final notifier = ref.read(readerSettingsProvider.notifier);

          return StatefulBuilder(
            builder: (context, setModalState) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(LanghuanTheme.spaceLg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.readerInterface,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: LanghuanTheme.spaceMd),
                    SegmentedButton<ReaderMode>(
                      segments: [
                        ButtonSegment(
                          value: ReaderMode.verticalScroll,
                          label: Text(l10n.readerModeVertical),
                          icon: const Icon(Icons.swap_vert),
                        ),
                        ButtonSegment(
                          value: ReaderMode.horizontalPaging,
                          label: Text(l10n.readerModeHorizontal),
                          icon: const Icon(Icons.swap_horiz),
                        ),
                      ],
                      selected: {settings.mode},
                      onSelectionChanged: (set) {
                        notifier.setMode(set.first);
                        setModalState(() {});
                      },
                    ),
                    const SizedBox(height: LanghuanTheme.spaceMd),
                    Text('Font ${settings.fontScale.toStringAsFixed(2)}x'),
                    Slider(
                      value: settings.fontScale,
                      min: 0.8,
                      max: 1.8,
                      divisions: 10,
                      onChanged: (v) {
                        notifier.setFontScale(v);
                        setModalState(() {});
                      },
                    ),
                    const SizedBox(height: LanghuanTheme.spaceSm),
                    Text(
                      'Line Height ${settings.lineHeight.toStringAsFixed(2)}',
                    ),
                    Slider(
                      value: settings.lineHeight,
                      min: 1.2,
                      max: 2.4,
                      divisions: 12,
                      onChanged: (v) {
                        notifier.setLineHeight(v);
                        setModalState(() {});
                      },
                    ),
                    const SizedBox(height: LanghuanTheme.spaceMd),
                    Wrap(
                      spacing: LanghuanTheme.spaceSm,
                      children: [
                        ChoiceChip(
                          label: Text(l10n.readerThemeSystem),
                          selected:
                              settings.themeMode == ReaderThemeMode.system,
                          onSelected: (_) {
                            notifier.setThemeMode(ReaderThemeMode.system);
                            setModalState(() {});
                          },
                        ),
                        ChoiceChip(
                          label: Text(l10n.readerThemeLight),
                          selected: settings.themeMode == ReaderThemeMode.light,
                          onSelected: (_) {
                            notifier.setThemeMode(ReaderThemeMode.light);
                            setModalState(() {});
                          },
                        ),
                        ChoiceChip(
                          label: Text(l10n.readerThemeDark),
                          selected: settings.themeMode == ReaderThemeMode.dark,
                          onSelected: (_) {
                            notifier.setThemeMode(ReaderThemeMode.dark);
                            setModalState(() {});
                          },
                        ),
                        ChoiceChip(
                          label: Text(l10n.readerThemeSepia),
                          selected: settings.themeMode == ReaderThemeMode.sepia,
                          onSelected: (_) {
                            notifier.setThemeMode(ReaderThemeMode.sepia);
                            setModalState(() {});
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openSettingsSheet() async {
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(LanghuanTheme.spaceLg),
        child: Text(l10n.readerSettingPlaceholder),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(readerSettingsProvider);
    final baseTheme = Theme.of(context);
    final readerTheme = resolveReaderTheme(baseTheme, settings.themeMode);

    if (widget.feedId.isEmpty || widget.bookId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.readerTitle)),
        body: EmptyState(
          icon: Icons.info_outline,
          title: l10n.readerMissingParams,
        ),
      );
    }

    if (_isLoadingInitial) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.readerTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null && _chapters.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.readerTitle)),
        body: ErrorState(
          title: l10n.readerLoadError,
          message: _loadError.toString(),
          onRetry: _ensureLoaded,
          retryLabel: l10n.bookDetailRetry,
        ),
      );
    }

    if (_chapters.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.readerTitle)),
        body: EmptyState(
          icon: Icons.menu_book_outlined,
          title: l10n.readerEmpty,
        ),
      );
    }

    final currentIdx = _currentChapterIndex(_currentChapterId);
    final chapterTitle = currentIdx >= 0
        ? _chapters[currentIdx].title
        : l10n.readerTitle;

    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;
    final bottomPadding = mediaQuery.padding.bottom;
    final theme = readerTheme;
    final brightness = theme.brightness;
    final overlayStyle = brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Theme(
        data: readerTheme,
        child: Scaffold(
          extendBody: true,
          extendBodyBehindAppBar: true,
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _toggleControls,
            child: Stack(
              children: [
                // Content area
                Positioned.fill(
                  child: ChapterContentManager(
                    key: ValueKey('reader-content-$_contentReloadNonce'),
                    feedId: widget.feedId,
                    bookId: widget.bookId,
                    chapters: _chapters,
                    initialChapterId: _currentChapterId ?? _chapters.first.id,
                    initialParagraphIndex: _currentParagraphIndex,
                    initialParagraphOffset: _currentParagraphOffset,
                    readerMode: settings.mode,
                    fontScale: settings.fontScale,
                    lineHeight: settings.lineHeight,
                    contentPadding: EdgeInsets.fromLTRB(
                      LanghuanTheme.spaceLg,
                      topPadding + LanghuanTheme.spaceLg,
                      LanghuanTheme.spaceLg,
                      bottomPadding + LanghuanTheme.space2xl,
                    ),
                    onChapterChanged: _onChapterChanged,
                    onParagraphChanged: _onParagraphChanged,
                    onParagraphOffsetChanged: _onParagraphOffsetChanged,
                    onChapterParagraphsReady: _onChapterParagraphsReady,
                  ),
                ),

                // ─ Top bar overlay
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 180),
                      offset: _showControls ? Offset.zero : const Offset(0, -1),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: _showControls ? 1 : 0,
                        child: Container(
                          color: theme.colorScheme.surfaceContainer,
                          padding: EdgeInsets.only(top: topPadding),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                              Expanded(
                                child: Text(
                                  chapterTitle,
                                  style: theme.textTheme.titleMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              GestureDetector(
                                onLongPress: _addBookmarkWithCustomLabel,
                                child: IconButton(
                                  icon: const Icon(Icons.bookmark_add_outlined),
                                  tooltip: l10n.readerBookmarkAddHint,
                                  onPressed: _addBookmark,
                                ),
                              ),
                              IconButton(
                                icon: _isRefreshingChapter
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.refresh),
                                tooltip: l10n.readerRefreshChapter,
                                onPressed: _isRefreshingChapter
                                    ? null
                                    : _refreshCurrentChapter,
                              ),
                              IconButton(
                                icon: const Icon(Icons.bookmarks_outlined),
                                tooltip: l10n.readerBookmarks,
                                onPressed: _openBookmarkSheet,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // ─ Bottom bar overlay
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 180),
                      offset: _showControls ? Offset.zero : const Offset(0, 1),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: _showControls ? 1 : 0,
                        child: ReaderBottomBar(
                          chapters: _chapters,
                          currentIndex: currentIdx,
                          isSwitchingChapter: _isRefreshingChapter,
                          onPrevious: () {
                            if (currentIdx > 0) {
                              _jumpToChapter(_chapters[currentIdx - 1].id);
                            }
                          },
                          onNext: () {
                            if (currentIdx < _chapters.length - 1) {
                              _jumpToChapter(_chapters[currentIdx + 1].id);
                            }
                          },
                          onOpenToc: _openTocSheet,
                          onOpenInterface: _openInterfaceSheet,
                          onOpenSettings: _openSettingsSheet,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
