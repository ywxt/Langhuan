import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/bindings/signals/signals.dart';
import 'feed_service.dart';

// ---------------------------------------------------------------------------
// Search state
// ---------------------------------------------------------------------------

class SearchState {
  const SearchState({
    this.keyword = '',
    this.items = const [],
    this.isLoading = false,
    this.error,
    this.requestId,
  });

  final String keyword;
  final List<SearchResultModel> items;
  final bool isLoading;
  final Object? error;

  /// Non-null while a stream request is in flight.
  final String? requestId;

  bool get hasError => error != null;
  bool get hasItems => items.isNotEmpty;
  bool get isIdle => !isLoading && !hasError;

  SearchState copyWith({
    String? keyword,
    List<SearchResultModel>? items,
    bool? isLoading,
    Object? Function()? error,
    String? Function()? requestId,
  }) {
    return SearchState(
      keyword: keyword ?? this.keyword,
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: error != null ? error() : this.error,
      requestId: requestId != null ? requestId() : this.requestId,
    );
  }
}

class SearchNotifier extends Notifier<SearchState> {
  int _runToken = 0;

  @override
  SearchState build() => const SearchState();

  Future<void> search({required String feedId, required String keyword}) async {
    await _cancelCurrent();
    final runToken = ++_runToken;

    state = SearchState(keyword: keyword, isLoading: true);

    try {
      final sessionId = await FeedService.instance.openSearchSession(
        feedId: feedId,
        keyword: keyword,
      );
      if (runToken != _runToken) {
        FeedService.instance.closeSession(sessionId);
        return;
      }

      state = state.copyWith(requestId: () => sessionId);

      while (runToken == _runToken) {
        final outcome = await FeedService.instance.pullNextSearchResult(
          sessionId,
        );
        if (outcome is PullSearchOutcomeItem) {
          state = state.copyWith(
            items: [
              ...state.items,
              SearchResultModel(
                id: outcome.id,
                title: outcome.title,
                author: outcome.author,
                coverUrl: outcome.coverUrl,
                description: outcome.description,
              ),
            ],
          );
          continue;
        }
        if (outcome is PullSearchOutcomeEnd) {
          break;
        }
        final error = outcome as PullSearchOutcomeError;
        throw FeedPullException(message: error.message);
      }

      if (runToken == _runToken) {
        state = state.copyWith(isLoading: false, requestId: () => null);
      }
    } catch (err) {
      if (runToken == _runToken) {
        state = state.copyWith(
          isLoading: false,
          error: () => err,
          requestId: () => null,
        );
      }
    }
  }

  Future<void> cancelAndClear() async {
    await _cancelCurrent();
    state = const SearchState();
  }

  Future<void> retry({required String feedId}) async {
    if (state.keyword.isEmpty) return;
    await search(feedId: feedId, keyword: state.keyword);
  }

  Future<void> _cancelCurrent() async {
    final id = state.requestId;
    if (id != null) {
      FeedService.instance.closeSession(id);
    }
    _runToken++;
    state = state.copyWith(requestId: () => null, isLoading: false);
  }
}

final searchProvider = NotifierProvider<SearchNotifier, SearchState>(
  SearchNotifier.new,
);
