import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/theme/app_theme.dart';

class BookshelfPage extends StatelessWidget {
  const BookshelfPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
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
                  l10n.bookshelfTitle,
                  style: theme.textTheme.headlineLarge,
                ),
              ),
            ),

            // ── Search bar (tap to navigate) ───────────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: LanghuanTheme.spaceLg,
              ),
              sliver: SliverToBoxAdapter(
                child: SearchBar(
                  hintText: l10n.bookshelfSearchHint,
                  leading: Icon(
                    Icons.search,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  onTap: () => context.push('/bookshelf/search'),
                  focusNode: AlwaysDisabledFocusNode(),
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: LanghuanTheme.spaceLg),
            ),

            // ── Content ────────────────────────────────────────────────
            // TODO: Replace with book grid when bookshelf has items
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(theme: theme, l10n: l10n),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme, required this.l10n});

  final ThemeData theme;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LanghuanTheme.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
            ),
            const SizedBox(height: LanghuanTheme.spaceMd),
            Text(
              l10n.bookshelfEmpty,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: LanghuanTheme.spaceSm),
            Text(
              l10n.bookshelfEmptyHint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withAlpha(160),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// A [FocusNode] that is always unfocused so the [SearchBar] only responds
/// to [onTap] without opening the keyboard.
class AlwaysDisabledFocusNode extends FocusNode {
  @override
  bool get hasFocus => false;
}
