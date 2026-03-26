import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'add_feed_provider.dart';
import 'feed_service.dart';

// ---------------------------------------------------------------------------
// Public entry point called from feeds_page.dart
// ---------------------------------------------------------------------------

void showAddFeedSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _SourcePickerSheet(parentContext: context),
  );
}

// ---------------------------------------------------------------------------
// Layer 1: Source picker (bottom sheet)
// ---------------------------------------------------------------------------

class _SourcePickerSheet extends StatefulWidget {
  const _SourcePickerSheet({required this.parentContext});

  final BuildContext parentContext;

  @override
  State<_SourcePickerSheet> createState() => _SourcePickerSheetState();
}

class _SourcePickerSheetState extends State<_SourcePickerSheet> {
  bool _pickingFile = false;

  void _openUrlDialog() {
    Navigator.of(context).pop();
    if (!widget.parentContext.mounted) return;
    showDialog<void>(
      context: widget.parentContext,
      builder: (_) => const _AddFeedDialog(),
    );
  }

  Future<void> _pickFile() async {
    setState(() => _pickingFile = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.first.bytes;
      if (bytes == null) return;
      final content = String.fromCharCodes(bytes);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (!widget.parentContext.mounted) return;
      showDialog<void>(
        context: widget.parentContext,
        builder: (_) => _AddFeedDialog(initialContent: content),
      );
    } finally {
      if (mounted) setState(() => _pickingFile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              l10n.addFeedTitle,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          _SourceOption(
            icon: Icons.link_rounded,
            label: l10n.addFeedTabUrl,
            colorScheme: colorScheme,
            onTap: _openUrlDialog,
          ),
          const SizedBox(height: 12),
          _SourceOption(
            icon: Icons.folder_open_rounded,
            label: l10n.addFeedTabFile,
            colorScheme: colorScheme,
            onTap: _pickingFile ? null : _pickFile,
            trailing: _pickingFile
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Layer 2: Feed add / preview / install (dialog)
// ---------------------------------------------------------------------------

class _AddFeedDialog extends ConsumerStatefulWidget {
  const _AddFeedDialog({this.initialContent});

  /// When set, the dialog immediately previews this Lua content (file mode).
  final String? initialContent;

  @override
  ConsumerState<_AddFeedDialog> createState() => _AddFeedDialogState();
}

class _AddFeedDialogState extends ConsumerState<_AddFeedDialog> {
  final _urlController = TextEditingController();

  bool get _isFileMode => widget.initialContent != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(addFeedProvider.notifier).reset();
      if (_isFileMode) {
        ref
            .read(addFeedProvider.notifier)
            .previewFromContent(widget.initialContent!);
      }
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _previewFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    await ref.read(addFeedProvider.notifier).previewFromUrl(url);
  }

  Future<void> _install() async {
    await ref.read(addFeedProvider.notifier).confirmInstall();
  }

  void _goBack() {
    ref.read(addFeedProvider.notifier).reset();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final addState = ref.watch(addFeedProvider);

    ref.listen<AddFeedState>(addFeedProvider, (_, next) {
      if (next is AddFeedSuccess && mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.addFeedSuccess)));
      }
    });

    final bool isOperating =
        addState is AddFeedLoading || addState is AddFeedInstalling;

    return PopScope(
      canPop: !isOperating,
      child: AlertDialog(
        title: Text(_dialogTitle(addState, l10n)),
        scrollable: true,
        content: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: KeyedSubtree(
            key: ValueKey(_contentKey(addState)),
            child: _buildContent(addState, l10n, colorScheme),
          ),
        ),
        actions: _buildActions(context, addState, l10n),
      ),
    );
  }

  String _dialogTitle(AddFeedState state, AppLocalizations l10n) =>
      state is AddFeedPreview ? l10n.addFeedPreviewTitle : l10n.addFeedTitle;

  String _contentKey(AddFeedState state) => switch (state) {
    AddFeedIdle() => 'idle',
    AddFeedLoading() => 'loading',
    AddFeedPreview() => 'preview',
    AddFeedInstalling() => 'installing',
    AddFeedSuccess() => 'success',
    AddFeedError() => 'error',
  };

  Widget _buildContent(
    AddFeedState state,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) => switch (state) {
    AddFeedIdle() when !_isFileMode => _UrlInputContent(
      controller: _urlController,
      l10n: l10n,
      onSubmit: _previewFromUrl,
    ),
    AddFeedIdle() ||
    AddFeedLoading() ||
    AddFeedInstalling() ||
    AddFeedSuccess() => const _LoadingContent(),
    AddFeedPreview(:final preview) => _PreviewContent(
      preview: preview,
      colorScheme: colorScheme,
      l10n: l10n,
    ),
    AddFeedError(:final message) => _ErrorContent(
      message: message,
      colorScheme: colorScheme,
    ),
  };

  List<Widget> _buildActions(
    BuildContext context,
    AddFeedState state,
    AppLocalizations l10n,
  ) {
    final mat = MaterialLocalizations.of(context);

    return switch (state) {
      AddFeedIdle() when !_isFileMode => [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(mat.cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _previewFromUrl,
          child: Text(l10n.addFeedUrlPreview),
        ),
      ],
      AddFeedIdle() ||
      AddFeedLoading() ||
      AddFeedInstalling() ||
      AddFeedSuccess() => const [],
      AddFeedPreview() => [
        if (!_isFileMode)
          TextButton(onPressed: _goBack, child: Text(mat.backButtonTooltip)),
        if (_isFileMode)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(mat.cancelButtonLabel),
          ),
        FilledButton(onPressed: _install, child: Text(l10n.addFeedInstall)),
      ],
      AddFeedError() => [
        TextButton(
          onPressed: _isFileMode ? () => Navigator.of(context).pop() : _goBack,
          child: Text(
            _isFileMode ? mat.cancelButtonLabel : mat.backButtonTooltip,
          ),
        ),
      ],
    };
  }
}

class _SourceOption extends StatelessWidget {
  const _SourceOption({
    required this.icon,
    required this.label,
    required this.colorScheme,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final ColorScheme colorScheme;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          child: Row(
            children: [
              Icon(icon, size: 28, color: colorScheme.primary),
              const SizedBox(width: 16),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: colorScheme.onSurface),
              ),
              const Spacer(),
              trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2a — URL text field
// ---------------------------------------------------------------------------

class _UrlInputContent extends StatelessWidget {
  const _UrlInputContent({
    required this.controller,
    required this.l10n,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final AppLocalizations l10n;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: l10n.addFeedUrlHint,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.link_rounded),
        ),
        keyboardType: TextInputType.url,
        autofillHints: const [AutofillHints.url],
        autofocus: true,
        onSubmitted: (_) => onSubmit(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading / installing spinner
// ---------------------------------------------------------------------------

class _LoadingContent extends StatelessWidget {
  const _LoadingContent();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 300,
      height: 100,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

// ---------------------------------------------------------------------------
// Feed preview card
// ---------------------------------------------------------------------------

class _PreviewContent extends StatelessWidget {
  const _PreviewContent({
    required this.preview,
    required this.colorScheme,
    required this.l10n,
  });

  final FeedPreviewModel preview;
  final ColorScheme colorScheme;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Name + version ──
          Row(
            children: [
              Expanded(
                child: Text(
                  preview.name,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Chip(
                label: Text('v${preview.version}'),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          // ── Upgrade banner ──
          if (preview.isUpgrade && preview.currentVersion != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                l10n.addFeedIsUpgrade(preview.currentVersion!, preview.version),
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onTertiaryContainer,
                ),
              ),
            ),
          ],
          if (preview.author != null) ...[
            const SizedBox(height: 4),
            Text(
              preview.author!,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          // ── Base URL ──
          Row(
            children: [
              Icon(Icons.link, size: 14, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  preview.baseUrl,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // ── Domain access ──
          Text(
            l10n.addFeedAllowedDomains,
            style: textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          if (preview.allowedDomains.isEmpty)
            Text(
              l10n.addFeedNoDomainRestriction,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: preview.allowedDomains
                  .map(
                    (d) => Chip(
                      label: Text(d, style: textTheme.labelSmall),
                      backgroundColor: colorScheme.secondaryContainer,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                  .toList(),
            ),
          // ── Description ──
          if (preview.description != null) ...[
            const SizedBox(height: 10),
            Text(
              preview.description!,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error display
// ---------------------------------------------------------------------------

class _ErrorContent extends StatelessWidget {
  const _ErrorContent({required this.message, required this.colorScheme});

  final String message;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
