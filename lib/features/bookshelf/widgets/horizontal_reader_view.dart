import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../src/rust/api/types.dart';
import 'chapter_status_block.dart';
import 'chapter_store.dart';
import 'page_breaker.dart';
import 'page_content_view.dart';
import 'reader_types.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Horizontal reader view — flat page list with stable index tracking
//
// Uses PageView.builder with a flat page list built from ChapterStore data.
// When chapters load and the list grows, we track what the user is currently
// viewing (chapterSeq + localPageIndex) and translate that back to the new
// flat index so the PageController stays on the same logical page.
// ─────────────────────────────────────────────────────────────────────────────

class HorizontalReaderView extends StatefulWidget {
  const HorizontalReaderView({
    super.key,
    required this.store,
    required this.activeChapterSeq,
    required this.fontScale,
    required this.lineHeight,
    required this.contentPadding,
    required this.onPositionUpdate,
    required this.onRetry,
    this.initialParagraphIndex = 0,
    this.initialFromEnd = false,
    this.onJumpRegistered,
    this.onParagraphLongPress,
    this.selectedChapterId,
    this.selectedParagraphIndex,
  });

  final ChapterStore store;
  final int activeChapterSeq;
  final double fontScale;
  final double lineHeight;
  final EdgeInsets contentPadding;
  final void Function(String chapterId, int paragraphIndex, double offset)
      onPositionUpdate;
  final void Function(String chapterId) onRetry;
  final int initialParagraphIndex;
  final bool initialFromEnd;
  final ValueChanged<void Function(int, double)>? onJumpRegistered;
  final void Function(
    String chapterId,
    int paragraphIndex,
    ParagraphContent paragraph,
    Rect globalRect,
  )? onParagraphLongPress;
  final String? selectedChapterId;
  final int? selectedParagraphIndex;

  @override
  State<HorizontalReaderView> createState() => _HorizontalReaderViewState();
}

class _HorizontalReaderViewState extends State<HorizontalReaderView> {
  late PageController _pageController;
  bool _initialized = false;

  PageBreaker? _breaker;

  List<_FlatPageEntry> _flatPages = [];

  /// Track what the user is currently viewing so we can find it again
  /// after the flat page list is rebuilt.
  int? _currentChapterSeq;
  int _currentLocalPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    widget.onJumpRegistered?.call(_jumpToPosition);
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _breaker = _createBreaker();
    _rebuildFlatPages();
    if (!_initialized) {
      _initialized = true;
      final initialPage = _computeInitialPage();
      _pageController.dispose();
      _pageController = PageController(initialPage: initialPage);
      // Initialise current tracking
      if (initialPage >= 0 && initialPage < _flatPages.length) {
        final entry = _flatPages[initialPage];
        _currentChapterSeq = entry.chapterSeq;
        _currentLocalPage = entry.localIndex ?? 0;
      }
    }
  }

  @override
  void didUpdateWidget(covariant HorizontalReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onStoreChanged);
      widget.store.addListener(_onStoreChanged);
    }

    if (oldWidget.fontScale != widget.fontScale ||
        oldWidget.lineHeight != widget.lineHeight ||
        oldWidget.contentPadding != widget.contentPadding) {
      _breaker = _createBreaker();
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (!mounted) return;

    _rebuildFlatPages();

    // Find the same logical page in the new list using tracked position.
    if (_currentChapterSeq != null && _pageController.hasClients) {
      final currentPage = _pageController.page?.round() ?? 0;
      final newIndex = _findPageIndex(_currentChapterSeq!, _currentLocalPage);
      if (newIndex != null && newIndex != currentPage) {
        // Jump without animation to maintain position.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageController.hasClients) {
            _pageController.jumpToPage(newIndex);
          }
        });
      }
    }

    setState(() {});
  }

  /// Find the flat index for a given (chapterSeq, localPageIndex).
  int? _findPageIndex(int chapterSeq, int localPage) {
    for (int i = 0; i < _flatPages.length; i++) {
      final e = _flatPages[i];
      if (e.kind == _FlatPageKind.page &&
          e.chapterSeq == chapterSeq &&
          e.localIndex == localPage) {
        return i;
      }
    }
    return null;
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

  // ─ Flat page list construction ────────────────────────────────────────

  /// Maximum number of chapters to walk in each direction from the active
  /// chapter.  Must be less than ChapterStore._maxCacheSize / 2 to avoid the
  /// evict-refetch infinite loop.
  static const _maxChapterWalk = 3;

  void _rebuildFlatPages() {
    if (_breaker == null) {
      _flatPages = [];
      return;
    }

    final store = widget.store;
    final entries = <_FlatPageEntry>[];

    // Walk backward from active chapter to build pages for prev chapters.
    // We collect chapters in reverse order (nearest-first), then reverse the
    // whole list so the earliest chapter comes first.  Within each chapter
    // we add pages in *reverse* order so the final global reverse restores
    // the correct per-chapter page order (0, 1, 2, …).
    final prevEntries = <_FlatPageEntry>[];
    int? seq = store.prevSeq(widget.activeChapterSeq);
    int prevWalked = 0;
    while (seq != null) {
      final state = store.stateAt(seq);
      if (state is ChapterLoaded) {
        final pages = store.pagesAt(seq, _breaker!);
        if (pages != null && pages.isNotEmpty) {
          for (int i = pages.length - 1; i >= 0; i--) {
            prevEntries
                .add(_FlatPageEntry.page(seq, i, pages[i], store.idAt(seq)!));
          }
        }
        prevWalked++;
        if (prevWalked >= _maxChapterWalk) {
          final prev = store.prevSeq(seq);
          if (prev != null) {
            prevEntries.add(_FlatPageEntry.loading(prev));
          }
          break;
        }
      } else if (state is ChapterLoading) {
        prevEntries.add(_FlatPageEntry.loading(seq));
        break;
      } else if (state is ChapterLoadError) {
        prevEntries.add(_FlatPageEntry.error(seq, state.message));
        break;
      } else {
        store.ensureLoaded(seq);
        prevEntries.add(_FlatPageEntry.loading(seq));
        break;
      }
      seq = store.prevSeq(seq);
    }

    // Reverse so earliest chapter comes first, and pages within each
    // chapter are now in the correct ascending order.
    entries.addAll(prevEntries.reversed);

    // Active chapter
    seq = widget.activeChapterSeq;
    final activeState = store.stateAt(seq);
    if (activeState is ChapterLoaded) {
      final pages = store.pagesAt(seq, _breaker!);
      if (pages != null && pages.isNotEmpty) {
        for (int i = 0; i < pages.length; i++) {
          entries
              .add(_FlatPageEntry.page(seq, i, pages[i], store.idAt(seq)!));
        }
      }
    }

    // Walk forward from active chapter
    seq = store.nextSeq(widget.activeChapterSeq);
    int fwdWalked = 0;
    while (seq != null) {
      final state = store.stateAt(seq);
      if (state is ChapterLoaded) {
        final pages = store.pagesAt(seq, _breaker!);
        if (pages != null && pages.isNotEmpty) {
          for (int i = 0; i < pages.length; i++) {
            entries
                .add(_FlatPageEntry.page(seq, i, pages[i], store.idAt(seq)!));
          }
        }
        fwdWalked++;
        if (fwdWalked >= _maxChapterWalk) {
          final next = store.nextSeq(seq);
          if (next != null) {
            entries.add(_FlatPageEntry.loading(next));
          }
          break;
        }
      } else if (state is ChapterLoading) {
        entries.add(_FlatPageEntry.loading(seq));
        break;
      } else if (state is ChapterLoadError) {
        entries.add(_FlatPageEntry.error(seq, state.message));
        break;
      } else {
        store.ensureLoaded(seq);
        entries.add(_FlatPageEntry.loading(seq));
        break;
      }
      seq = store.nextSeq(seq);
    }

    // End of book sentinel
    if (entries.isNotEmpty && entries.last.kind == _FlatPageKind.page) {
      final lastSeq = entries.last.chapterSeq;
      if (lastSeq != null && store.isLast(lastSeq)) {
        entries.add(_FlatPageEntry.endOfBook());
      }
    }

    _flatPages = entries;
  }

  int _computeInitialPage() {
    if (_flatPages.isEmpty) return 0;

    // Find the first page of the active chapter
    int activeStart = 0;
    for (int i = 0; i < _flatPages.length; i++) {
      if (_flatPages[i].kind == _FlatPageKind.page &&
          _flatPages[i].chapterSeq == widget.activeChapterSeq) {
        activeStart = i;
        break;
      }
    }

    if (widget.initialFromEnd) {
      int lastActive = activeStart;
      for (int i = activeStart; i < _flatPages.length; i++) {
        if (_flatPages[i].kind == _FlatPageKind.page &&
            _flatPages[i].chapterSeq == widget.activeChapterSeq) {
          lastActive = i;
        } else {
          break;
        }
      }
      return lastActive;
    }

    if (widget.initialParagraphIndex > 0 && _breaker != null) {
      final pages =
          widget.store.pagesAt(widget.activeChapterSeq, _breaker!);
      if (pages != null && pages.isNotEmpty) {
        final localPage = PageBreaker.pageForParagraph(
          pages,
          widget.initialParagraphIndex,
        );
        return activeStart + localPage;
      }
    }

    return activeStart;
  }

  void _jumpToPosition(int paragraphIndex, double _) {
    if (!_pageController.hasClients || _breaker == null) return;
    final pages =
        widget.store.pagesAt(widget.activeChapterSeq, _breaker!);
    if (pages == null || pages.isEmpty) return;
    final localPage = PageBreaker.pageForParagraph(pages, paragraphIndex);
    final target =
        _findPageIndex(widget.activeChapterSeq, localPage);
    if (target != null) {
      _pageController.jumpToPage(target);
    }
  }

  // ─ Page change tracking ───────────────────────────────────────────────

  void _onPageChanged(int index) {
    if (index < 0 || index >= _flatPages.length) return;
    final entry = _flatPages[index];

    // Always track what we're viewing
    if (entry.kind == _FlatPageKind.page) {
      _currentChapterSeq = entry.chapterSeq;
      _currentLocalPage = entry.localIndex ?? 0;

      final chapterId = entry.chapterId!;
      final page = entry.page!;
      final seq = entry.chapterSeq!;

      widget.store.setActive(seq);

      widget.onPositionUpdate(
        chapterId,
        page.firstParagraphIndex,
        0,
      );
    } else if (entry.kind == _FlatPageKind.loading &&
        entry.chapterSeq != null) {
      // Ensure loading chapters get triggered when scrolled into view.
      widget.store.ensureLoaded(entry.chapterSeq!);
    }
  }

  // ─ Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_flatPages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return PageView.builder(
      controller: _pageController,
      itemCount: _flatPages.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) {
        if (index < 0 || index >= _flatPages.length) {
          return const SizedBox.shrink();
        }
        final entry = _flatPages[index];

        return switch (entry.kind) {
          _FlatPageKind.page => _buildPage(context, entry),
          _FlatPageKind.loading => _buildLoadingPage(entry),
          _FlatPageKind.error => Center(
              child: ChapterStatusBlock(
                kind: ChapterStatusBlockKind.error,
                message: entry.errorMessage,
                onRetry: () {
                  final chapterId =
                      widget.store.idAt(entry.chapterSeq!);
                  if (chapterId != null) widget.onRetry(chapterId);
                },
              ),
            ),
          _FlatPageKind.endOfBook => _buildEndOfBook(context),
        };
      },
    );
  }

  Widget _buildPage(BuildContext context, _FlatPageEntry entry) {
    final chapterId = entry.chapterId!;
    final isSelectedChapter = widget.selectedChapterId == chapterId;

    return Padding(
      padding: widget.contentPadding,
      child: PageContentView(
        page: entry.page!,
        fontScale: widget.fontScale,
        lineHeight: widget.lineHeight,
        selectedParagraphIndex:
            isSelectedChapter ? widget.selectedParagraphIndex : null,
        onParagraphLongPress: widget.onParagraphLongPress != null
            ? (paragraphIndex, paragraph, rect) =>
                widget.onParagraphLongPress!(
                    chapterId, paragraphIndex, paragraph, rect)
            : null,
      ),
    );
  }

  Widget _buildLoadingPage(_FlatPageEntry entry) {
    return const Center(
      child: ChapterStatusBlock(kind: ChapterStatusBlockKind.loading),
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

// ─────────────────────────────────────────────────────────────────────────────
// Flat page entry — one entry per PageView slot
// ─────────────────────────────────────────────────────────────────────────────

enum _FlatPageKind { page, loading, error, endOfBook }

class _FlatPageEntry {
  _FlatPageEntry._({
    required this.kind,
    this.chapterSeq,
    this.localIndex,
    this.page,
    this.chapterId,
    this.errorMessage,
  });

  factory _FlatPageEntry.page(
    int seq,
    int localIndex,
    PageContent page,
    String chapterId,
  ) =>
      _FlatPageEntry._(
        kind: _FlatPageKind.page,
        chapterSeq: seq,
        localIndex: localIndex,
        page: page,
        chapterId: chapterId,
      );

  factory _FlatPageEntry.loading(int seq) => _FlatPageEntry._(
        kind: _FlatPageKind.loading,
        chapterSeq: seq,
      );

  factory _FlatPageEntry.error(int seq, String message) => _FlatPageEntry._(
        kind: _FlatPageKind.error,
        chapterSeq: seq,
        errorMessage: message,
      );

  factory _FlatPageEntry.endOfBook() => _FlatPageEntry._(
        kind: _FlatPageKind.endOfBook,
      );

  final _FlatPageKind kind;
  final int? chapterSeq;
  final int? localIndex;
  final PageContent? page;
  final String? chapterId;
  final String? errorMessage;
}
