import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'feed_providers.dart';
import 'feed_service.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

sealed class AddFeedState {
  const AddFeedState();
}

class AddFeedIdle extends AddFeedState {
  const AddFeedIdle();
}

class AddFeedLoading extends AddFeedState {
  const AddFeedLoading();
}

class AddFeedPreview extends AddFeedState {
  const AddFeedPreview({required this.preview});
  final FeedPreviewModel preview;
}

class AddFeedInstalling extends AddFeedState {
  const AddFeedInstalling();
}

class AddFeedSuccess extends AddFeedState {
  const AddFeedSuccess();
}

class AddFeedError extends AddFeedState {
  const AddFeedError({required this.message});
  final String message;
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class AddFeedNotifier extends Notifier<AddFeedState> {
  @override
  AddFeedState build() => const AddFeedIdle();

  /// Preview a feed script from a remote [url].
  Future<void> previewFromUrl(String url) async {
    state = const AddFeedLoading();
    final preview = await FeedService.instance.previewFromUrl(url);
    if (preview.hasError) {
      state = AddFeedError(message: preview.error!);
    } else {
      state = AddFeedPreview(preview: preview);
    }
  }

  /// Preview a feed script from raw Lua [content] (local file).
  Future<void> previewFromContent(String content) async {
    state = const AddFeedLoading();
    final preview = await FeedService.instance.previewFromContent(content);
    if (preview.hasError) {
      state = AddFeedError(message: preview.error!);
    } else {
      state = AddFeedPreview(preview: preview);
    }
  }

  /// Confirm installation of the currently previewed feed.
  ///
  /// After a successful install the [feedListProvider] is refreshed so Dart
  /// reflects the updated registry immediately.
  Future<void> confirmInstall() async {
    final current = state;
    if (current is! AddFeedPreview) return;

    state = const AddFeedInstalling();

    final result = await FeedService.instance.installFeed(
      current.preview.requestId,
    );

    if (result.success) {
      // Refresh the feed list so the newly installed feed appears.
      ref.read(feedListProvider.notifier).load();
      state = const AddFeedSuccess();
    } else {
      state = AddFeedError(message: result.error ?? 'unknown error');
    }
  }

  /// Reset back to the idle state (e.g. when the sheet is closed).
  void reset() => state = const AddFeedIdle();
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final addFeedProvider = NotifierProvider<AddFeedNotifier, AddFeedState>(
  AddFeedNotifier.new,
);
