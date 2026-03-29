import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/theme/app_theme.dart';
import '../../src/bindings/signals/signals.dart';
import 'add_feed_sheet.dart';
import 'feed_providers.dart';

// ---------------------------------------------------------------------------
// FeedsPage — Wise-inspired feed (book source) management
// ---------------------------------------------------------------------------

class FeedsPage extends ConsumerStatefulWidget {
  const FeedsPage({super.key});

  @override
  ConsumerState<FeedsPage> createState() => _FeedsPageState();
}

class _FeedsPageState extends ConsumerState<FeedsPage> {
  final _filterController = TextEditingController();
  String _filterText = '';
  final Set<String> _pendingDeleteIds = <String>{};
  Completer<bool>? _undoCompleter;

  @override
  void initState() {
    super.initState();
    _filterController.addListener(() {
      setState(() => _filterText = _filterController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _filterController.dispose();
    if (_undoCompleter != null && !_undoCompleter!.isCompleted) {
      _undoCompleter!.complete(false);
    }
    super.dispose();
  }

  List<FeedMetaItem> _filtered(List<FeedMetaItem> items) {
    final visible = items
        .where((f) => !_pendingDeleteIds.contains(f.id))
        .toList(growable: false);
    if (_filterText.isEmpty) return visible;
    return visible
        .where(
          (f) =>
              f.name.toLowerCase().contains(_filterText) ||
              f.id.toLowerCase().contains(_filterText),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final feedState = ref.watch(feedListProvider);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    final filtered = _filtered(feedState.items);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => showAddFeedSheet(context),
        tooltip: l10n.addFeedTitle,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Title ──────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                LanghuanTheme.spaceLg,
                LanghuanTheme.spaceLg,
                LanghuanTheme.spaceLg,
                LanghuanTheme.spaceMd,
              ),
              sliver: SliverToBoxAdapter(
                child: Text(
                  l10n.feedsTitle,
                  style: theme.textTheme.headlineLarge,
                ),
              ),
            ),

            // ── Search bar ─────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: LanghuanTheme.spaceLg,
              ),
              sliver: SliverToBoxAdapter(
                child: SearchBar(
                  controller: _filterController,
                  hintText: l10n.feedsSearchHint,
                  leading: Icon(
                    Icons.search,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  trailing: [
                    if (_filterText.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _filterController.clear,
                      ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: LanghuanTheme.spaceMd),
            ),

            // ── Content ────────────────────────────────────────────────
            _buildBody(context, feedState, filtered, theme, l10n),

            // Bottom padding for FAB
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    FeedListState feedState,
    List<FeedMetaItem> filtered,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    // ── Loading ──────────────────────────────────────────────────────────────
    if (feedState.isLoading) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // ── Error ────────────────────────────────────────────────────────────────
    if (feedState.hasError) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
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
                  l10n.feedsLoadError,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: LanghuanTheme.spaceSm),
                Text(
                  feedState.error.toString(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: LanghuanTheme.spaceMd),
                FilledButton.tonal(
                  onPressed: () => ref.read(feedListProvider.notifier).load(),
                  child: Text(l10n.feedsRetry),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── Empty state ──────────────────────────────────────────────────────────
    if (!feedState.hasItems) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(LanghuanTheme.spaceXl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.extension_outlined,
                  size: 56,
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
                ),
                const SizedBox(height: LanghuanTheme.spaceMd),
                Text(
                  l10n.feedsEmpty,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── No filter matches ─────────────────────────────────────────────────────
    if (filtered.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(
            l10n.feedsNoMatch(_filterText),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // ── Feed list (card-style items) ──────────────────────────────────────
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: LanghuanTheme.spaceLg),
      sliver: SliverList.builder(
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final feed = filtered[index];
          final deletingId = feedState.removingFeedId;
          final isDeleting =
              deletingId == feed.id || _pendingDeleteIds.contains(feed.id);
          final isBusy = deletingId != null || _pendingDeleteIds.isNotEmpty;

          return Padding(
            padding: const EdgeInsets.only(bottom: LanghuanTheme.spaceSm),
            child: Dismissible(
              key: ValueKey('feed-${feed.id}'),
              direction: isBusy
                  ? DismissDirection.none
                  : DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(
                  horizontal: LanghuanTheme.spaceLg,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: LanghuanTheme.borderRadiusMd,
                ),
                child: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              confirmDismiss: (_) async {
                final confirmed =
                    await _confirmDelete(context, feed, l10n) == true;
                if (confirmed && context.mounted) {
                  final messenger = ScaffoldMessenger.of(context);
                  _handleDeleteWithUndo(feed, l10n, messenger);
                }
                return false;
              },
              child: _FeedCard(feed: feed, isDeleting: isDeleting),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleDeleteWithUndo(
    FeedMetaItem feed,
    AppLocalizations l10n,
    ScaffoldMessengerState messenger,
  ) async {
    if (!mounted) return;

    setState(() {
      _pendingDeleteIds.add(feed.id);
    });

    final completer = Completer<bool>();
    _undoCompleter = completer;

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.feedDeleteQueued(feed.name)),
        action: SnackBarAction(
          label: l10n.feedDeleteUndo,
          onPressed: () {
            if (!completer.isCompleted) completer.complete(true);
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );

    final timer = Timer(const Duration(seconds: 4), () {
      if (!completer.isCompleted) completer.complete(false);
    });

    final undone = await completer.future;
    timer.cancel();
    _undoCompleter = null;

    if (!mounted) return;

    if (undone) {
      setState(() {
        _pendingDeleteIds.remove(feed.id);
      });
      messenger.clearSnackBars();
      return;
    }

    messenger.clearSnackBars();
    final error = await ref
        .read(feedListProvider.notifier)
        .removeFeed(feedId: feed.id);

    if (!mounted) return;

    setState(() {
      _pendingDeleteIds.remove(feed.id);
    });

    final cur = scaffoldMessengerKey.currentState;

    if (error == null) {
      cur?.clearSnackBars();
      cur?.showSnackBar(
        SnackBar(content: Text(l10n.feedDeleteSuccess(feed.name))),
      );
      return;
    }

    final message = error == 'busy'
        ? l10n.feedDeleteBusy
        : '${l10n.feedDeleteError}: $error';
    cur?.clearSnackBars();
    cur?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool?> _confirmDelete(
    BuildContext context,
    FeedMetaItem feed,
    AppLocalizations l10n,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.feedDeleteConfirmTitle),
        content: Text(l10n.feedDeleteConfirmMessage(feed.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.feedDeleteCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: Text(l10n.feedDeleteConfirm),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Feed card — Wise-style borderless card
// ---------------------------------------------------------------------------

class _FeedCard extends StatelessWidget {
  const _FeedCard({required this.feed, this.isDeleting = false});

  final FeedMetaItem feed;
  final bool isDeleting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasError = feed.error != null;

    return Material(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: LanghuanTheme.borderRadiusMd,
      child: InkWell(
        borderRadius: LanghuanTheme.borderRadiusMd,
        onTap: isDeleting ? null : () => _showFeedDetailSheet(context, feed),
        child: Padding(
          padding: const EdgeInsets.all(LanghuanTheme.spaceMd),
          child: Row(
            children: [
              // ── Avatar ─────────────────────────────────────────────
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: hasError
                      ? theme.colorScheme.errorContainer
                      : theme.colorScheme.primaryContainer,
                  borderRadius: LanghuanTheme.borderRadiusSm,
                ),
                alignment: Alignment.center,
                child: Text(
                  feed.name.isNotEmpty ? feed.name[0].toUpperCase() : '?',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: hasError
                        ? theme.colorScheme.onErrorContainer
                        : theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: LanghuanTheme.spaceMd),

              // ── Text ───────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      feed.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      feed.author != null
                          ? 'v${feed.version} · ${feed.author}'
                          : 'v${feed.version}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // ── Trailing ───────────────────────────────────────────
              if (isDeleting)
                SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                )
              else if (hasError)
                Icon(
                  Icons.error_outline,
                  size: 20,
                  color: theme.colorScheme.error,
                )
              else
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(120),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Feed detail bottom sheet — Wise-style
// ---------------------------------------------------------------------------

void _showFeedDetailSheet(BuildContext context, FeedMetaItem feed) {
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => _FeedDetailSheet(feed: feed),
  );
}

class _FeedDetailSheet extends StatelessWidget {
  const _FeedDetailSheet({required this.feed});

  final FeedMetaItem feed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LanghuanTheme.spaceLg,
          0,
          LanghuanTheme.spaceLg,
          LanghuanTheme.spaceXl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(feed.name, style: theme.textTheme.titleLarge),
            const SizedBox(height: LanghuanTheme.spaceMd),

            if (feed.error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(LanghuanTheme.spaceMd),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: LanghuanTheme.borderRadiusMd,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 18,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: LanghuanTheme.spaceSm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.feedItemLoadError,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            feed.error!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: LanghuanTheme.spaceMd),
            ],

            _MetaRow(
              icon: Icons.label_outline,
              label: l10n.feedDetailId,
              value: feed.id,
            ),
            const SizedBox(height: LanghuanTheme.spaceMd),
            _MetaRow(
              icon: Icons.tag,
              label: l10n.feedDetailVersion,
              value: feed.version,
            ),
            if (feed.author != null) ...[
              const SizedBox(height: LanghuanTheme.spaceMd),
              _MetaRow(
                icon: Icons.person_outline,
                label: l10n.feedDetailAuthor,
                value: feed.author!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: LanghuanTheme.spaceSm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(value, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
