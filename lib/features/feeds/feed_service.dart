import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rinf/rinf.dart';
import 'package:tuple/tuple.dart';

import '../../src/bindings/signals/signals.dart';

// ---------------------------------------------------------------------------
// Domain models (mirrors Rust structs)
// ---------------------------------------------------------------------------

@immutable
class SearchResultModel {
  const SearchResultModel({
    required this.id,
    required this.title,
    required this.author,
    this.coverUrl,
    this.description,
  });

  final String id;
  final String title;
  final String author;
  final String? coverUrl;
  final String? description;
}

@immutable
class ChapterInfoModel {
  const ChapterInfoModel({
    required this.id,
    required this.title,
    required this.index,
  });

  final String id;
  final String title;
  final int index;
}

@immutable
class BookInfoModel {
  const BookInfoModel({
    required this.id,
    required this.title,
    required this.author,
    this.coverUrl,
    this.description,
  });

  final String id;
  final String title;
  final String author;
  final String? coverUrl;
  final String? description;
}

@immutable
class FeedPreviewModel {
  const FeedPreviewModel({
    required this.requestId,
    required this.id,
    required this.name,
    required this.version,
    required this.baseUrl,
    required this.accessDomains,
    this.author,
    this.description,
    this.currentVersion,
  });

  final String requestId;
  final String id;
  final String name;
  final String version;
  final String? author;
  final String? description;
  final String baseUrl;
  final List<String> accessDomains;
  final String? currentVersion;
}

@immutable
class BookshelfItemModel {
  const BookshelfItemModel({
    required this.feedId,
    required this.sourceBookId,
    required this.title,
    required this.author,
    required this.addedAtUnixMs,
    this.coverUrl,
    this.description,
  });

  final String feedId;
  final String sourceBookId;
  final String title;
  final String author;
  final int addedAtUnixMs;
  final String? coverUrl;
  final String? description;

  String get stableId => '$feedId:$sourceBookId';
}

@immutable
class ReadingProgressModel {
  const ReadingProgressModel({
    required this.feedId,
    required this.bookId,
    required this.chapterId,
    required this.paragraphIndex,
    required this.updatedAtMs,
  });

  final String feedId;
  final String bookId;
  final String chapterId;
  final int paragraphIndex;
  final int updatedAtMs;
}

enum FeedAuthStatusModel { loggedIn, loggedOut, expired, unsupported }

@immutable
class FeedAuthEntryModel {
  const FeedAuthEntryModel({required this.url, this.title});

  final String url;
  final String? title;
}

// ---------------------------------------------------------------------------
// FeedService
// ---------------------------------------------------------------------------

/// Wraps Rinf signals into pull-based session APIs.
///
/// Flutter opens a session, then explicitly sends `PullNextRequest` for each
/// next item. Rust only advances feed streams when PullNext is requested.
class FeedService {
  FeedService._();

  static final FeedService instance = FeedService._();

  // -------------------------------------------------------------------------
  // Request ID generation
  // -------------------------------------------------------------------------

  int _counter = 0;

  /// Generate a unique request ID.
  String _nextId() =>
      'req-${DateTime.now().millisecondsSinceEpoch}-${_counter++}';

  // -------------------------------------------------------------------------
  // Pull session: search
  // -------------------------------------------------------------------------

  Future<String> openSearchSession({
    required String feedId,
    required String keyword,
  }) async {
    final sessionId = _nextId();
    final result = await _subscribeAndSend(
      responseStream: OpenSessionResult.rustSignalStream,
      matches: (message) => message.sessionId == sessionId,
      send: () {
        OpenSearchSession(
          sessionId: sessionId,
          feedId: feedId,
          keyword: keyword,
        ).sendSignalToRust();
      },
    );

    final outcome = result.outcome;
    if (outcome is OpenSessionOutcomeError) {
      throw FeedPullException(message: outcome.message);
    }
    return sessionId;
  }

  Future<PullSearchOutcome> pullNextSearchResult(String sessionId) {
    return _subscribeAndSend(
      responseStream: PullSearchResult.rustSignalStream,
      matches: (message) => message.sessionId == sessionId,
      send: () => PullNextRequest(sessionId: sessionId).sendSignalToRust(),
    ).then((message) => message.outcome);
  }

  // -------------------------------------------------------------------------
  // Pull session: chapters
  // -------------------------------------------------------------------------

  Future<String> openChaptersSession({
    required String feedId,
    required String bookId,
  }) async {
    final sessionId = _nextId();
    final result = await _subscribeAndSend(
      responseStream: OpenSessionResult.rustSignalStream,
      matches: (message) => message.sessionId == sessionId,
      send: () {
        OpenChaptersSession(
          sessionId: sessionId,
          feedId: feedId,
          bookId: bookId,
        ).sendSignalToRust();
      },
    );

    final outcome = result.outcome;
    if (outcome is OpenSessionOutcomeError) {
      throw FeedPullException(message: outcome.message);
    }
    return sessionId;
  }

  Future<PullChapterOutcome> pullNextChapterInfo(String sessionId) {
    return _subscribeAndSend(
      responseStream: PullChapterResult.rustSignalStream,
      matches: (message) => message.sessionId == sessionId,
      send: () => PullNextRequest(sessionId: sessionId).sendSignalToRust(),
    ).then((message) => message.outcome);
  }

  // -------------------------------------------------------------------------
  // Book info
  // -------------------------------------------------------------------------

  /// Request detailed information for a single book.
  Future<BookInfoModel> bookInfo({
    required String feedId,
    required String bookId,
  }) {
    return _subscribeAndSendNext(
      responseStream: BookInfoResult.rustSignalStream,
      send: () {
        BookInfoRequest(feedId: feedId, bookId: bookId).sendSignalToRust();
      },
    ).then((message) {
      final outcome = message.outcome;
      if (outcome is BookInfoOutcomeError) {
        throw BookInfoException(message: outcome.message);
      }
      final success = outcome as BookInfoOutcomeSuccess;
      return BookInfoModel(
        id: success.id,
        title: success.title,
        author: success.author,
        coverUrl: success.coverUrl,
        description: success.description,
      );
    });
  }

  // -------------------------------------------------------------------------
  // Pull session: chapter content
  // -------------------------------------------------------------------------

  Future<String> openParagraphsSession({
    required String feedId,
    required String bookId,
    required String chapterId,
  }) async {
    final sessionId = _nextId();
    final result = await _subscribeAndSend(
      responseStream: OpenSessionResult.rustSignalStream,
      matches: (message) => message.sessionId == sessionId,
      send: () {
        OpenParagraphsSession(
          sessionId: sessionId,
          feedId: feedId,
          bookId: bookId,
          chapterId: chapterId,
        ).sendSignalToRust();
      },
    );

    final outcome = result.outcome;
    if (outcome is OpenSessionOutcomeError) {
      throw FeedPullException(message: outcome.message);
    }
    return sessionId;
  }

  Future<PullParagraphOutcome> pullNextParagraph(String sessionId) {
    return _subscribeAndSend(
      responseStream: PullParagraphResult.rustSignalStream,
      matches: (message) => message.sessionId == sessionId,
      send: () => PullNextRequest(sessionId: sessionId).sendSignalToRust(),
    ).then((message) => message.outcome);
  }

  // -------------------------------------------------------------------------
  // Bookshelf
  // -------------------------------------------------------------------------

  Future<BookshelfOperationOutcome> addToBookshelf({
    required String feedId,
    required String sourceBookId,
  }) {
    final requestId = _nextId();
    return _subscribeAndSend(
      responseStream: BookshelfAddResult.rustSignalStream,
      matches: (message) => message.requestId == requestId,
      send: () {
        BookshelfAddRequest(
          requestId: requestId,
          feedId: feedId,
          sourceBookId: sourceBookId,
        ).sendSignalToRust();
      },
    ).then((message) => message.outcome);
  }

  Future<BookshelfOperationOutcome> removeFromBookshelf({
    required String feedId,
    required String sourceBookId,
  }) {
    final requestId = _nextId();
    return _subscribeAndSend(
      responseStream: BookshelfRemoveResult.rustSignalStream,
      matches: (message) => message.requestId == requestId,
      send: () {
        BookshelfRemoveRequest(
          requestId: requestId,
          feedId: feedId,
          sourceBookId: sourceBookId,
        ).sendSignalToRust();
      },
    ).then((message) => message.outcome);
  }

  Future<List<BookshelfItemModel>> listBookshelf() {
    final requestId = _nextId();
    final completer = Completer<List<BookshelfItemModel>>();
    final items = <BookshelfItemModel>[];

    StreamSubscription<RustSignalPack<BookshelfListItem>>? itemSub;
    StreamSubscription<RustSignalPack<BookshelfListEnd>>? endSub;

    itemSub = BookshelfListItem.rustSignalStream
        .where((pack) => pack.message.requestId == requestId)
        .listen((pack) {
          final it = pack.message;
          items.add(
            BookshelfItemModel(
              feedId: it.feedId,
              sourceBookId: it.sourceBookId,
              title: it.title,
              author: it.author,
              coverUrl: it.coverUrl,
              description: it.descriptionSnapshot,
              addedAtUnixMs: it.addedAtUnixMs,
            ),
          );
        });

    endSub = BookshelfListEnd.rustSignalStream
        .where((pack) => pack.message.requestId == requestId)
        .listen((pack) async {
          final outcome = pack.message.outcome;
          await itemSub?.cancel();
          await endSub?.cancel();

          if (outcome is BookshelfListOutcomeFailed) {
            completer.completeError(
              BookshelfOperationException(message: outcome.message),
            );
            return;
          }

          items.sort((a, b) => b.addedAtUnixMs.compareTo(a.addedAtUnixMs));
          completer.complete(items);
        });

    BookshelfListRequest(requestId: requestId).sendSignalToRust();
    return completer.future;
  }

  Future<ReadingProgressModel?> getReadingProgress({
    required String feedId,
    required String bookId,
  }) {
    final requestId = _nextId();
    return _subscribeAndSend(
      responseStream: ReadingProgressGetResult.rustSignalStream,
      matches: (message) => message.requestId == requestId,
      send: () {
        ReadingProgressGetRequest(
          requestId: requestId,
          feedId: feedId,
          bookId: bookId,
        ).sendSignalToRust();
      },
    ).then((message) {
      final outcome = message.outcome;
      if (outcome is ReadingProgressGetOutcomeError) {
        throw ReadingProgressException(message: outcome.message);
      }

      final success = outcome as ReadingProgressGetOutcomeSuccess;
      final item = success.progress;
      if (item == null) {
        return null;
      }

      return ReadingProgressModel(
        feedId: item.feedId,
        bookId: item.bookId,
        chapterId: item.chapterId,
        paragraphIndex: item.paragraphIndex,
        updatedAtMs: item.updatedAtMs,
      );
    });
  }

  Future<void> setReadingProgress({
    required String feedId,
    required String bookId,
    required String chapterId,
    required int paragraphIndex,
    required int updatedAtMs,
  }) {
    final requestId = _nextId();
    return _subscribeAndSend(
      responseStream: ReadingProgressSetResult.rustSignalStream,
      matches: (message) => message.requestId == requestId,
      send: () {
        ReadingProgressSetRequest(
          requestId: requestId,
          feedId: feedId,
          bookId: bookId,
          chapterId: chapterId,
          paragraphIndex: paragraphIndex,
          updatedAtMs: updatedAtMs,
        ).sendSignalToRust();
      },
    ).then((message) {
      final outcome = message.outcome;
      if (outcome is ReadingProgressSetOutcomeError) {
        throw ReadingProgressException(message: outcome.message);
      }
    });
  }

  // -------------------------------------------------------------------------
  // Session close
  // -------------------------------------------------------------------------

  void closeSession(String sessionId) {
    CloseSessionRequest(sessionId: sessionId).sendSignalToRust();
  }

  // -------------------------------------------------------------------------
  // App data directory
  // -------------------------------------------------------------------------

  /// Tell Rust which directory should be used as the app data root.
  ///
  /// Rust will keep feeds under `scripts/` and bookshelf data under
  /// `bookshelf/`, then respond with an [AppDataDirectorySet] signal. If the
  /// registry file does
  /// not exist yet, `success` will be `false` and an error message will be
  /// provided — no crash.
  ///
  /// Returns a [Future] that completes once Rust has finished loading.
  Future<AppDataDirectorySet> setAppDataDirectory(String path) {
    return _subscribeAndSendNext(
      responseStream: AppDataDirectorySet.rustSignalStream,
      send: () => SetAppDataDirectory(path: path).sendSignalToRust(),
    );
  }

  /// Request a list of all feeds currently loaded in Rust.
  ///
  /// Returns a [Future] that completes with the [FeedListResult] once Rust
  /// responds.
  Future<FeedListResult> listFeeds() {
    final requestId = _nextId();
    return _subscribeAndSend(
      responseStream: FeedListResult.rustSignalStream,
      matches: (message) => message.requestId == requestId,
      send: () => ListFeedsRequest(requestId: requestId).sendSignalToRust(),
    );
  }

  // -------------------------------------------------------------------------
  // Feed install
  // -------------------------------------------------------------------------

  /// Request a preview of a feed script from a remote [url].
  ///
  /// Returns a [Future] that resolves to a [FeedPreviewModel] once Rust has
  /// downloaded and parsed the script.  Throws a [FeedPreviewException] on
  /// failure.
  Future<FeedPreviewModel> previewFromUrl(String url) async {
    final requestId = _nextId();
    return _awaitPreview(
      requestId,
      () =>
          PreviewFeedFromUrl(requestId: requestId, url: url).sendSignalToRust(),
    );
  }

  /// Request a preview of a feed script from a local file [path].
  /// Rust reads the file, decodes it as UTF-8, and responds with a
  /// [FeedPreviewModel].  Throws a [FeedPreviewException] on failure.
  Future<FeedPreviewModel> previewFromFile(String path) async {
    final requestId = _nextId();
    return _awaitPreview(
      requestId,
      () => PreviewFeedFromFile(
        requestId: requestId,
        path: path,
      ).sendSignalToRust(),
    );
  }

  /// Confirm installation of a previously previewed feed.
  ///
  /// [requestId] must match the one returned by the preceding preview call.
  /// Returns a [Future] that resolves to the [FeedInstallResult] once Rust
  /// finishes writing the script to disk and updating the current registry.
  Future<FeedInstallResult> installFeed(String requestId) {
    return _subscribeAndSend(
      responseStream: FeedInstallResult.rustSignalStream,
      matches: (message) => message.requestId == requestId,
      send: () => InstallFeedRequest(requestId: requestId).sendSignalToRust(),
    );
  }

  /// Remove an installed feed by [feedId].
  ///
  /// Returns a [Future] that resolves to [FeedRemoveResult] when Rust finishes.
  Future<FeedRemoveResult> removeFeed(String feedId) {
    final requestId = _nextId();
    return _subscribeAndSend(
      responseStream: FeedRemoveResult.rustSignalStream,
      matches: (message) => message.requestId == requestId,
      send: () => RemoveFeedRequest(
        requestId: requestId,
        feedId: feedId,
      ).sendSignalToRust(),
    );
  }

  Future<FeedPreviewModel> _awaitPreview(
    String requestId,
    void Function() send,
  ) {
    return _subscribeAndSend(
      responseStream: FeedPreviewResult.rustSignalStream,
      matches: (message) => message.requestId == requestId,
      send: send,
    ).then((message) {
      final outcome = message.outcome;
      if (outcome is FeedPreviewOutcomeError) {
        throw FeedPreviewException(message: outcome.message);
      }
      final success = outcome as FeedPreviewOutcomeSuccess;
      return FeedPreviewModel(
        requestId: message.requestId,
        id: success.id,
        name: success.name,
        version: success.version,
        author: success.author,
        description: success.description,
        baseUrl: success.baseUrl,
        accessDomains: List.unmodifiable(success.accessDomains),
        currentVersion: success.currentVersion,
      );
    });
  }

  // -------------------------------------------------------------------------
  // Feed auth
  // -------------------------------------------------------------------------

  Future<bool> isFeedAuthSupported(String feedId) {
    final requestId = _nextId();
    return _subscribeAndSend(
      responseStream: FeedAuthCapabilityResult.rustSignalStream,
      matches: (message) => message.requestId == requestId,
      send: () {
        FeedAuthCapabilityRequest(
          requestId: requestId,
          feedId: feedId,
        ).sendSignalToRust();
      },
    ).then((message) {
      final outcome = message.outcome;
      if (outcome is FeedAuthCapabilityOutcomeSupported) {
        return true;
      }
      if (outcome is FeedAuthCapabilityOutcomeUnsupported) {
        return false;
      }
      final error = outcome as FeedAuthCapabilityOutcomeError;
      throw FeedAuthException(message: error.message);
    });
  }

  Future<FeedAuthEntryModel?> getFeedAuthEntry(String feedId) {
    final requestId = _nextId();
    return _subscribeAndSend(
      responseStream: FeedAuthEntryResult.rustSignalStream,
      matches: (message) => message.requestId == requestId,
      send: () {
        FeedAuthEntryRequest(
          requestId: requestId,
          feedId: feedId,
        ).sendSignalToRust();
      },
    ).then((message) {
      final outcome = message.outcome;
      if (outcome is FeedAuthEntryOutcomeSuccess) {
        return FeedAuthEntryModel(url: outcome.url, title: outcome.title);
      }
      if (outcome is FeedAuthEntryOutcomeUnsupported) {
        return null;
      }
      final error = outcome as FeedAuthEntryOutcomeError;
      throw FeedAuthException(message: error.message);
    });
  }

  Future<void> submitFeedAuthPage({
    required String feedId,
    required String currentUrl,
    required String response,
    required List<Tuple2<String, String>> responseHeaders,
    required List<CookieEntry> cookies,
  }) {
    final requestId = _nextId();
    return _subscribeAndSend(
      responseStream: FeedAuthSubmitPageResult.rustSignalStream,
      matches: (message) => message.requestId == requestId,
      send: () {
        FeedAuthSubmitPageRequest(
          requestId: requestId,
          feedId: feedId,
          currentUrl: currentUrl,
          response: response,
          responseHeaders: responseHeaders,
          cookies: cookies,
        ).sendSignalToRust();
      },
    ).then((message) {
      final outcome = message.outcome;
      if (outcome is FeedAuthSubmitPageOutcomeSuccess) {
        return;
      }
      if (outcome is FeedAuthSubmitPageOutcomeUnsupported) {
        throw const FeedAuthException(message: 'feed auth not supported');
      }
      final error = outcome as FeedAuthSubmitPageOutcomeError;
      throw FeedAuthException(message: error.message);
    });
  }

  Future<FeedAuthStatusModel> getFeedAuthStatus(String feedId) {
    final requestId = _nextId();
    return _subscribeAndSend(
      responseStream: FeedAuthStatusResult.rustSignalStream,
      matches: (message) => message.requestId == requestId,
      send: () {
        FeedAuthStatusRequest(
          requestId: requestId,
          feedId: feedId,
        ).sendSignalToRust();
      },
    ).then((message) {
      final outcome = message.outcome;
      if (outcome is FeedAuthStatusOutcomeLoggedIn) {
        return FeedAuthStatusModel.loggedIn;
      }
      if (outcome is FeedAuthStatusOutcomeExpired) {
        return FeedAuthStatusModel.expired;
      }
      if (outcome is FeedAuthStatusOutcomeLoggedOut) {
        return FeedAuthStatusModel.loggedOut;
      }
      final error = outcome as FeedAuthStatusOutcomeError;
      throw FeedAuthException(message: error.message);
    });
  }

  Future<void> clearFeedAuth(String feedId) {
    final requestId = _nextId();
    return _subscribeAndSend(
      responseStream: FeedAuthClearResult.rustSignalStream,
      matches: (message) => message.requestId == requestId,
      send: () {
        FeedAuthClearRequest(
          requestId: requestId,
          feedId: feedId,
        ).sendSignalToRust();
      },
    ).then((message) {
      final outcome = message.outcome;
      if (outcome is FeedAuthClearOutcomeSuccess) {
        return;
      }
      final error = outcome as FeedAuthClearOutcomeError;
      throw FeedAuthException(message: error.message);
    });
  }

  // -------------------------------------------------------------------------
  // Internal helpers
  // -------------------------------------------------------------------------

  Future<T> _subscribeAndSend<T>({
    required Stream<RustSignalPack<T>> responseStream,
    required bool Function(T message) matches,
    required void Function() send,
  }) {
    final future = responseStream
        .where((pack) => matches(pack.message))
        .first
        .then((pack) => pack.message);
    send();
    return future;
  }

  Future<T> _subscribeAndSendNext<T>({
    required Stream<RustSignalPack<T>> responseStream,
    required void Function() send,
  }) {
    final future = responseStream.first.then((pack) => pack.message);
    send();
    return future;
  }
}

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

class FeedPullException implements Exception {
  const FeedPullException({required this.message});

  final String message;

  @override
  String toString() => 'FeedPullException: $message';
}

class FeedPreviewException implements Exception {
  const FeedPreviewException({required this.message});

  final String message;

  @override
  String toString() => 'FeedPreviewException: $message';
}

class BookInfoException implements Exception {
  const BookInfoException({required this.message});

  final String message;

  @override
  String toString() => 'BookInfoException: $message';
}

class BookshelfOperationException implements Exception {
  const BookshelfOperationException({required this.message});

  final String message;

  @override
  String toString() => 'BookshelfOperationException: $message';
}

class ReadingProgressException implements Exception {
  const ReadingProgressException({required this.message});

  final String message;

  @override
  String toString() => 'ReadingProgressException: $message';
}

class FeedAuthException implements Exception {
  const FeedAuthException({required this.message});

  final String message;

  @override
  String toString() => 'FeedAuthException: $message';
}
