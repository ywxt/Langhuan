import 'package:flutter/material.dart';

class FeedsPage extends StatelessWidget {
  const FeedsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Feeds'), centerTitle: true),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.rss_feed, size: 80, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Your Feeds', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Latest updates will appear here',
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
