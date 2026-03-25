import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../feeds/feed_providers.dart';
import '../feeds/feed_service.dart';

// ---------------------------------------------------------------------------
// SearchPage — book search page
// ---------------------------------------------------------------------------

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Auto-focus the search bar when the page opens.
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
    final feedId = ref.read(selectedFeedProvider)?.id;
    if (feedId == null) return;
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;
    ref.read(searchProvider.notifier).search(feedId: feedId, keyword: keyword);
  }

  @override
  Widget build(BuildContext context) {
    final feedState = ref.watch(feedListProvider);
    final selectedFeed = ref.watch(selectedFeedProvider);
    final searchState = ref.watch(searchProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.searchTitle), centerTitle: true),
      body: Column(
        children: [
          // ── Feed selector (horizontal chip row) ──────────────────────
          _FeedSelector(feedState: feedState, selectedFeed: selectedFeed),

          const Divider(height: 1),

          // ── Search bar ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SearchBar(
              controller: _searchController,
              focusNode: _searchFocusNode,
              hintText: selectedFeed == null
                  ? l10n.searchHintNoFeed
                  : l10n.searchHintWithFeed(selectedFeed.name),
              enabled: selectedFeed != null,
              leading: const Icon(Icons.search),
              trailing: [
                if (searchState.isLoading)
                  IconButton(
                    icon: const Icon(Icons.cancel_outlined),
                    tooltip: l10n.searchCancel,
                    onPressed: () =>
                        ref.read(searchProvider.notifier).cancelAndClear(),
                  )
                else if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
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

          // ── Loading indicator ──────────────────────────────────────────
          if (searchState.isLoading) const LinearProgressIndicator(),

          // ── Search results ─────────────────────────────────────────────
          Expanded(
            child: _buildResults(
              context,
              searchState,
              selectedFeed,
              colorScheme,
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
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    if (searchState.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: colorScheme.error),
              const SizedBox(height: 12),
              Text(
                l10n.searchError,
                style: TextStyle(
                  color: colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                searchState.error.toString(),
                style: TextStyle(color: colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
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
              size: 64,
              color: colorScheme.onSurfaceVariant.withAlpha(100),
            ),
            const SizedBox(height: 16),
            Text(
              searchState.keyword.isEmpty
                  ? l10n.searchEmptyPrompt
                  : l10n.searchNoResults(searchState.keyword),
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    // Results list
    return ListView.separated(
      itemCount: searchState.items.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        return _SearchResultTile(item: searchState.items[index]);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Feed selector (horizontal chip row)
// ---------------------------------------------------------------------------

class _FeedSelector extends ConsumerWidget {
  const _FeedSelector({required this.feedState, required this.selectedFeed});

  final FeedListState feedState;
  final dynamic selectedFeed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    if (feedState.isLoading) {
      return const SizedBox(
        height: 56,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (!feedState.hasItems) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          l10n.feedSelectorNoFeeds,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    return SizedBox(
      height: 56,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: feedState.items.length,
        itemBuilder: (context, index) {
          final feed = feedState.items[index];
          final isSelected = selectedFeed?.id == feed.id;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(feed.name),
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
// Search result list tile
// ---------------------------------------------------------------------------

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.item});

  final SearchResultModel item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: item.coverUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                item.coverUrl!,
                width: 40,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.menu_book, size: 40),
              ),
            )
          : const Icon(Icons.menu_book, size: 40),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${item.author}${item.description != null ? '\n${item.description}' : ''}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: item.description != null,
      onTap: () {
        // TODO: navigate to book detail page
      },
    );
  }
}
