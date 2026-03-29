import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:langhuan/rust_init.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/theme/app_theme.dart';
import '../../src/bindings/signals/signals.dart';
import '../feeds/feed_providers.dart';
import '../feeds/feed_service.dart';

// ---------------------------------------------------------------------------
// SearchPage — Wise-inspired book search
// ---------------------------------------------------------------------------

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  List<FeedMetaItem> _visibleFeeds(FeedListState feedState) {
    return feedState.items
        .where((feed) => feed.error == null)
        .toList(growable: false);
  }

  FeedMetaItem? _effectiveSelectedFeed({
    required List<FeedMetaItem> visibleFeeds,
    required FeedMetaItem? selectedFeed,
  }) {
    if (visibleFeeds.isEmpty) return null;
    if (selectedFeed == null) return visibleFeeds.first;

    for (final feed in visibleFeeds) {
      if (feed.id == selectedFeed.id) {
        return feed;
      }
    }
    return visibleFeeds.first;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearch() {
    final bootstrap = ref.read(scriptDirectorySetProvider);
    final bootstrapReady = bootstrap.asData?.value.success ?? false;
    if (!bootstrapReady) return;

    final feedState = ref.read(feedListProvider);
    final selectedFeed = ref.read(selectedFeedProvider);
    final effectiveSelectedFeed = _effectiveSelectedFeed(
      visibleFeeds: _visibleFeeds(feedState),
      selectedFeed: selectedFeed,
    );
    if (effectiveSelectedFeed == null) return;

    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;
    ref
        .read(searchProvider.notifier)
        .search(feedId: effectiveSelectedFeed.id, keyword: keyword);
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = ref.watch(scriptDirectorySetProvider);
    final bootstrapReady = bootstrap.asData?.value.success ?? false;
    final feedState = ref.watch(feedListProvider);
    final selectedFeed = ref.watch(selectedFeedProvider);
    final visibleFeeds = _visibleFeeds(feedState);
    final effectiveSelectedFeed = _effectiveSelectedFeed(
      visibleFeeds: visibleFeeds,
      selectedFeed: selectedFeed,
    );
    final searchState = ref.watch(searchProvider);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    if (effectiveSelectedFeed?.id != selectedFeed?.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (effectiveSelectedFeed == null) {
          ref.read(selectedFeedProvider.notifier).clear();
        } else {
          ref.read(selectedFeedProvider.notifier).select(effectiveSelectedFeed);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.searchTitle)),
      body: Column(
        children: [
          // ── Search bar ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LanghuanTheme.spaceLg,
              LanghuanTheme.spaceSm,
              LanghuanTheme.spaceLg,
              LanghuanTheme.spaceSm,
            ),
            child: SearchBar(
              controller: _searchController,
              focusNode: _searchFocusNode,
              hintText: effectiveSelectedFeed == null
                  ? l10n.searchHintNoFeed
                  : l10n.searchHintWithFeed(effectiveSelectedFeed.name),
              enabled: effectiveSelectedFeed != null && bootstrapReady,
              leading: Icon(
                Icons.search,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              trailing: [
                if (searchState.isLoading)
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: l10n.searchCancel,
                    onPressed: () =>
                        ref.read(searchProvider.notifier).cancelAndClear(),
                  )
                else if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: l10n.searchClear,
                    onPressed: () {
                      _searchController.clear();
                      ref.read(searchProvider.notifier).cancelAndClear();
                    },
                  ),
              ],
              onSubmitted: (_) => _onSearch(),
            ),
          ),

          // ── Feed selector (horizontal chip row) ──────────────────────
          _FeedSelector(
            feedState: feedState,
            visibleFeeds: visibleFeeds,
            selectedFeed: effectiveSelectedFeed,
          ),

          // ── Loading indicator ──────────────────────────────────────────
          if (searchState.isLoading)
            const LinearProgressIndicator()
          else
            const SizedBox(height: 2), // Reserve space
          // ── Search results ─────────────────────────────────────────────
          Expanded(
            child: _buildResults(
              context,
              searchState,
              effectiveSelectedFeed,
              theme,
              l10n,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(
    BuildContext context,
    SearchState searchState,
    dynamic selectedFeed,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    if (searchState.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(LanghuanTheme.spaceXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error.withAlpha(160),
              ),
              const SizedBox(height: LanghuanTheme.spaceMd),
              Text(
                l10n.searchError,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: LanghuanTheme.spaceSm),
              Text(
                searchState.error.toString(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: LanghuanTheme.spaceMd),
              FilledButton.tonal(
                onPressed: selectedFeed == null
                    ? null
                    : () => ref
                          .read(searchProvider.notifier)
                          .retry(feedId: selectedFeed.id),
                child: Text(l10n.searchRetry),
              ),
            ],
          ),
        ),
      );
    }

    if (!searchState.isLoading && !searchState.hasItems) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
            ),
            const SizedBox(height: LanghuanTheme.spaceMd),
            Text(
              searchState.keyword.isEmpty
                  ? l10n.searchEmptyPrompt
                  : l10n.searchNoResults(searchState.keyword),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Results list — card-style items with spacing
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: LanghuanTheme.spaceLg,
        vertical: LanghuanTheme.spaceSm,
      ),
      itemCount: searchState.items.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: LanghuanTheme.spaceSm),
          child: _SearchResultCard(item: searchState.items[index]),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Feed selector (horizontal chip row)
// ---------------------------------------------------------------------------

class _FeedSelector extends ConsumerWidget {
  const _FeedSelector({
    required this.feedState,
    required this.visibleFeeds,
    required this.selectedFeed,
  });

  final FeedListState feedState;
  final List<FeedMetaItem> visibleFeeds;
  final FeedMetaItem? selectedFeed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    if (feedState.isLoading) {
      return const SizedBox(
        height: 48,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (visibleFeeds.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LanghuanTheme.spaceLg,
          vertical: LanghuanTheme.spaceSm,
        ),
        child: Text(
          l10n.feedSelectorNoFeeds,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: LanghuanTheme.spaceLg - 4,
          vertical: LanghuanTheme.spaceSm,
        ),
        itemCount: visibleFeeds.length,
        itemBuilder: (context, index) {
          final feed = visibleFeeds[index];
          final isSelected = selectedFeed?.id == feed.id;
          return Padding(
            padding: const EdgeInsets.only(right: LanghuanTheme.spaceSm),
            child: ChoiceChip(
              label: Text(
                feed.name,
                style: TextStyle(
                  color: isSelected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                ),
              ),
              selected: isSelected,
              onSelected: (_) =>
                  ref.read(selectedFeedProvider.notifier).select(feed),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search result card — Wise-style borderless card
// ---------------------------------------------------------------------------

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({required this.item});

  final SearchResultModel item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: LanghuanTheme.borderRadiusMd,
      child: InkWell(
        borderRadius: LanghuanTheme.borderRadiusMd,
        onTap: () {
          // TODO: navigate to book detail page
        },
        child: Padding(
          padding: const EdgeInsets.all(LanghuanTheme.spaceMd),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Book cover ─────────────────────────────────────────
              ClipRRect(
                borderRadius: LanghuanTheme.borderRadiusSm,
                child: item.coverUrl != null
                    ? Image.network(
                        item.coverUrl!,
                        width: 48,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _CoverPlaceholder(),
                      )
                    : _CoverPlaceholder(),
              ),
              const SizedBox(width: LanghuanTheme.spaceMd),

              // ── Text content ───────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: LanghuanTheme.spaceXs),
                    Text(
                      item.author,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.description != null) ...[
                      const SizedBox(height: LanghuanTheme.spaceXs),
                      Text(
                        item.description!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withAlpha(
                            180,
                          ),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              // ── Chevron ────────────────────────────────────────────
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant.withAlpha(120),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 48,
      height: 64,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: LanghuanTheme.borderRadiusSm,
      ),
      child: Icon(
        Icons.menu_book_outlined,
        size: 24,
        color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
      ),
    );
  }
}
