import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';

class BookshelfPage extends StatelessWidget {
  const BookshelfPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.bookshelfTitle),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SearchBar(
              hintText: l10n.bookshelfSearchHint,
              leading: const Icon(Icons.search),
              onTap: () => context.push('/bookshelf/search'),
              // Entry point only — keyboard input is disabled.
              focusNode: AlwaysDisabledFocusNode(),
            ),
          ),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.book, size: 80, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(l10n.bookshelfTitle, style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              l10n.bookshelfEmpty,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
