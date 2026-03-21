import 'package:flutter/material.dart';

class BookshelfPage extends StatelessWidget {
  const BookshelfPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Bookshelf'), centerTitle: true),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.book, size: 80, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Your Bookshelf', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Your books will appear here',
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
