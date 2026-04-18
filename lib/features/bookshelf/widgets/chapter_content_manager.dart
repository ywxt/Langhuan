import 'dart:async';

import 'package:flutter/material.dart';

import '../../../src/rust/api/types.dart';
import '../../feeds/feed_service.dart';
import '../reader_settings_provider.dart';
import 'chapter_status_block.dart';
import 'chapter_store.dart';
import 'horizontal_reader_view.dart';
import 'reader_controller.dart';
import 'reader_types.dart';
import 'vertical_reader_view.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Chapter content manager
//
// Owns a ChapterStore and orchestrates the reader views.
// No more sliding window — the store loads chapters on demand and the
// reader views use virtual infinite scroll to index into the store.
//
// setState is called for:
//   1. Initial center chapter load completion
//   2. Jump commands (chapter switch)
//   3. Mode/font/conversion changes from didUpdateWidget
//   4. Store notifications (chapter data arrived)
// ─────────────────────────────────────────────────────────────────────────────

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
  )? onParagraphLongPress;
  final String? selectedChapterId;
  final String? selectedParagraphId;

  @override
  State<ChapterContentManager> createState() => _ChapterContentManagerState();
}

class _ChapterContentManagerState extends State<ChapterContentManager> {
  late ChapterStore _store;

  late int _activeSeq;

  bool _centerReady = false;

  Object? _centerError;
  String? _centerErrorMessage;

  int _initGeneration = 0;

  int _jumpGeneration = 0;

  String _pendingJumpParagraphId = '';
  double _pendingJumpOffset = 0;
  bool _pendingFromEnd = false;

  String _lastReportedParagraphId = '';
  double _lastReportedOffset = 0;

  void Function(String paragraphId, double offset)? _onViewJump;

  // ─ Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _store = ChapterStore(
      feedId: widget.feedId,
      bookId: widget.bookId,
      chapters: widget.chapters,
    );
    _store.addListener(_onStoreChanged);

    final startId = widget.controller.pendingChapterId ??
        (widget.chapters.isNotEmpty ? widget.chapters.first.id : '');
    _activeSeq = _store.seqOf(startId);
    _pendingJumpParagraphId = widget.controller.pendingParagraphId;
    _pendingJumpOffset = widget.controller.pendingOffset;
    widget.controller.consumeJump();
    widget.controller.addListener(_onJumpCommand);

    _initCenter();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onJumpCommand);
    _store.removeListener(_onStoreChanged);
    _store.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChapterContentManager oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onJumpCommand);
      widget.controller.addListener(_onJumpCommand);
    }

    final sourceChanged = oldWidget.feedId != widget.feedId ||
        oldWidget.bookId != widget.bookId ||
        oldWidget.chapters != widget.chapters;

    if (sourceChanged) {
      _store.removeListener(_onStoreChanged);
      _store.dispose();
      _store = ChapterStore(
        feedId: widget.feedId,
        bookId: widget.bookId,
        chapters: widget.chapters,
      );
      _store.addListener(_onStoreChanged);
      _centerReady = false;
      _centerError = null;
      _activeSeq = widget.chapters.isNotEmpty
          ? _store.seqOf(widget.chapters.first.id)
          : 0;
      _initCenter();
      return;
    }

    // Mode change: preserve current position and rebuild
    if (oldWidget.mode != widget.mode) {
      _pendingJumpParagraphId = _lastReportedParagraphId;
      _pendingJumpOffset = _lastReportedOffset;
      _pendingFromEnd = false;
      _jumpGeneration++;
      setState(() {});
    }

    // Font/line-height change: invalidate page cache, rebuild
    if (oldWidget.fontScale != widget.fontScale ||
        oldWidget.lineHeight != widget.lineHeight) {
      _store.invalidatePages();
      _pendingJumpParagraphId = _lastReportedParagraphId;
      _pendingJumpOffset = 0;
      _pendingFromEnd = false;
      _jumpGeneration++;
      setState(() {});
    }

    // Conversion mode change: clear all cached data and reload
    if (oldWidget.chineseConversion != widget.chineseConversion) {
      _store.clearAll();
      _centerReady = false;
      _centerError = null;
      _pendingJumpParagraphId = _lastReportedParagraphId;
      _pendingJumpOffset = 0;
      _pendingFromEnd = false;
      _jumpGeneration++;
      _initCenter();
    }
  }

  // ─ Store listener ───────────────────────────────────────────────────────

  void _onStoreChanged() {
    if (!mounted) return;
    setState(() {});
  }

  // ─ Initial center load ──────────────────────────────────────────────────

  Future<void> _initCenter() async {
    final chapterId = _store.idAt(_activeSeq);
    if (chapterId == null || chapterId.isEmpty) {
      setState(() => _centerReady = true);
      return;
    }

    final gen = ++_initGeneration;

    // If already cached, skip fetch.
    if (_store.paragraphsAt(_activeSeq) != null) {
      if (!mounted || gen != _initGeneration) return;
      _store.setActive(_activeSeq);
      setState(() {
        _centerReady = true;
        _centerError = null;
        _centerErrorMessage = null;
      });
      _consumePending();
      return;
    }

    setState(() {
      _centerReady = false;
      _centerError = null;
    });

    try {
      final paragraphs = await FeedService.instance
          .paragraphs(
            feedId: widget.feedId,
            bookId: widget.bookId,
            chapterId: chapterId,
          )
          .toList();

      if (!mounted || gen != _initGeneration) return;

      _store.putDirect(_activeSeq, paragraphs);
      _store.setActive(_activeSeq);

      setState(() {
        _centerReady = true;
        _centerError = null;
        _centerErrorMessage = null;
      });

      _consumePending();
    } catch (e) {
      if (!mounted || gen != _initGeneration) return;
      setState(() {
        _centerReady = true;
        _centerError = e;
        _centerErrorMessage = normalizeErrorMessage(e);
      });
    }
  }

  void _consumePending() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingJumpParagraphId = '';
      _pendingJumpOffset = 0;
      _pendingFromEnd = false;
    });
  }

  // ─ Position update callback from reader views ──────────────────────────

  void _onPositionUpdate(String chapterId, String paragraphId, double offset) {
    _lastReportedParagraphId = paragraphId;
    _lastReportedOffset = offset;

    // Update active chapter if it changed.
    final seq = _store.seqOf(chapterId);
    if (seq != _activeSeq && seq >= _store.minSeq) {
      _activeSeq = seq;
      _store.setActive(seq);
    }

    widget.controller.reportPosition(
      chapterId: chapterId,
      paragraphId: paragraphId,
      offset: offset,
    );
  }

  // ─ Retry callback ─────────────────────────────────────────────────────

  void _onRetry(String chapterId) {
    final seq = _store.seqOf(chapterId);
    if (seq < 0) return;

    if (seq == _activeSeq && _centerError != null) {
      setState(() {
        _centerReady = false;
        _centerError = null;
        _centerErrorMessage = null;
      });
      _initCenter();
      return;
    }

    _store.reload(seq);
  }

  // ─ Jump command from controller ────────────────────────────────────────

  void _onJumpCommand() {
    final targetId = widget.controller.pendingChapterId;
    if (targetId == null) return;

    final paragraphId = widget.controller.pendingParagraphId;
    final offset = widget.controller.pendingOffset;
    widget.controller.consumeJump();

    final targetSeq = _store.seqOf(targetId);

    if (targetSeq == _activeSeq) {
      // Same chapter: try in-place jump
      if (_onViewJump != null) {
        _onViewJump!.call(paragraphId, offset);
        return;
      }
      _pendingJumpParagraphId = paragraphId;
      _pendingJumpOffset = offset;
      _pendingFromEnd = false;
      _jumpGeneration++;
      setState(() {});
      return;
    }

    // Different chapter: re-center
    _activeSeq = targetSeq;
    _pendingJumpParagraphId = paragraphId;
    _pendingJumpOffset = offset;
    _pendingFromEnd = false;
    _centerError = null;
    _centerErrorMessage = null;
    _jumpGeneration++;

    widget.controller.reportPosition(
      chapterId: targetId,
      paragraphId: paragraphId,
      offset: offset,
    );

    if (_store.paragraphsAt(targetSeq) != null) {
      _store.setActive(targetSeq);
      _centerReady = true;
      setState(() {});
      _consumePending();
    } else {
      _centerReady = false;
      setState(() {});
      _initCenter();
    }
  }

  // ─ Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_centerReady) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_centerError != null) {
      return Center(
        child: ChapterStatusBlock(
          kind: ChapterStatusBlockKind.error,
          message: _centerErrorMessage,
          onRetry: () => _onRetry(_store.idAt(_activeSeq) ?? ''),
        ),
      );
    }

    final activeId = _store.idAt(_activeSeq);
    if (activeId == null || activeId.isEmpty) {
      return const SizedBox.shrink();
    }

    final initialParagraphId = _pendingJumpParagraphId;
    final initialOffset = _pendingJumpOffset;
    final initialFromEnd = _pendingFromEnd;

    if (widget.mode == ReaderMode.verticalScroll) {
      return VerticalReaderView(
        key: ValueKey('v-$_jumpGeneration'),
        store: _store,
        activeChapterSeq: _activeSeq,
        fontScale: widget.fontScale,
        lineHeight: widget.lineHeight,
        contentPadding: widget.contentPadding,
        onPositionUpdate: _onPositionUpdate,
        onRetry: _onRetry,
        initialParagraphId: initialParagraphId,
        initialOffset: initialOffset,
        onJumpRegistered: (fn) => _onViewJump = fn,
        onParagraphLongPress: widget.onParagraphLongPress,
        selectedChapterId: widget.selectedChapterId,
        selectedParagraphId: widget.selectedParagraphId,
      );
    }

    return HorizontalReaderView(
      key: ValueKey('h-$_jumpGeneration'),
      store: _store,
      activeChapterSeq: _activeSeq,
      fontScale: widget.fontScale,
      lineHeight: widget.lineHeight,
      contentPadding: widget.contentPadding,
      onPositionUpdate: _onPositionUpdate,
      onRetry: _onRetry,
      initialParagraphId: initialParagraphId,
      initialFromEnd: initialFromEnd,
      onJumpRegistered: (fn) => _onViewJump = fn,
      onParagraphLongPress: widget.onParagraphLongPress,
      selectedChapterId: widget.selectedChapterId,
      selectedParagraphId: widget.selectedParagraphId,
    );
  }
}
