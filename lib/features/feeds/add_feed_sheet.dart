import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/theme/app_theme.dart';
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
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result == null || result.files.isEmpty) return;
      final path = result.files.first.path;
      if (path == null) return;
      if (!mounted) return;
      Navigator.of(context).pop();
      if (!widget.parentContext.mounted) return;
      showDialog<void>(
        context: widget.parentContext,
        builder: (_) => _AddFeedDialog(initialPath: path),
      );
    } finally {
      if (mounted) setState(() => _pickingFile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LanghuanTheme.spaceLg,
        0,
        LanghuanTheme.spaceLg,
        LanghuanTheme.spaceXl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: LanghuanTheme.spaceMd),
            child: Text(l10n.addFeedTitle, style: theme.textTheme.titleLarge),
          ),
          _SourceOption(
            icon: Icons.link_rounded,
            label: l10n.addFeedTabUrl,
            subtitle: l10n.addFeedTabUrlDesc,
            onTap: _openUrlDialog,
          ),
          _SourceOption(
            icon: Icons.folder_open_rounded,
            label: l10n.addFeedTabFile,
            subtitle: l10n.addFeedTabFileDesc,
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
  const _AddFeedDialog({this.initialPath});

  /// When set, Rust will read and preview the script at this file path.
  final String? initialPath;

  @override
  ConsumerState<_AddFeedDialog> createState() => _AddFeedDialogState();
}

class _AddFeedDialogState extends ConsumerState<_AddFeedDialog> {
  final _urlController = TextEditingController();

  bool get _isFileMode => widget.initialPath != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(addFeedProvider.notifier).reset();
      if (_isFileMode) {
        ref.read(addFeedProvider.notifier).previewFromFile(widget.initialPath!);
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
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: LanghuanTheme.borderRadiusMd,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: LanghuanTheme.spaceMd,
          horizontal: LanghuanTheme.spaceSm,
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: theme.colorScheme.primary),
            const SizedBox(width: LanghuanTheme.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: LanghuanTheme.spaceXs),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing ??
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(120),
                ),
          ],
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
    final theme = Theme.of(context);

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
                child: Text(preview.name, style: theme.textTheme.titleMedium),
              ),
              const SizedBox(width: LanghuanTheme.spaceSm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: LanghuanTheme.spaceSm,
                  vertical: LanghuanTheme.spaceXs,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: LanghuanTheme.borderRadiusSm,
                ),
                child: Text(
                  'v${preview.version}',
                  style: theme.textTheme.labelMedium,
                ),
              ),
            ],
          ),
          // ── Upgrade banner ──
          if (preview.isUpgrade && preview.currentVersion != null) ...[
            const SizedBox(height: LanghuanTheme.spaceSm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: LanghuanTheme.spaceSm,
                vertical: LanghuanTheme.spaceXs,
              ),
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer,
                borderRadius: LanghuanTheme.borderRadiusSm,
              ),
              child: Text(
                l10n.addFeedIsUpgrade(preview.currentVersion!, preview.version),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onTertiaryContainer,
                ),
              ),
            ),
          ],
          if (preview.author != null) ...[
            const SizedBox(height: LanghuanTheme.spaceXs),
            Text(
              preview.author!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: LanghuanTheme.spaceMd),
          Divider(color: colorScheme.outline),
          const SizedBox(height: LanghuanTheme.spaceMd),
          // ── Base URL ──
          Row(
            children: [
              Icon(Icons.link, size: 14, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: LanghuanTheme.spaceXs),
              Expanded(
                child: Text(
                  preview.baseUrl,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: LanghuanTheme.spaceMd),
          // ── Domain access ──
          Text(
            l10n.addFeedAllowedDomains,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: LanghuanTheme.spaceSm),
          if (preview.allowedDomains.isEmpty)
            Text(
              l10n.addFeedNoDomainRestriction,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            Wrap(
              spacing: LanghuanTheme.spaceSm,
              runSpacing: LanghuanTheme.spaceXs,
              children: preview.allowedDomains
                  .map(
                    (d) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: LanghuanTheme.spaceSm,
                        vertical: LanghuanTheme.spaceXs,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: LanghuanTheme.borderRadiusSm,
                      ),
                      child: Text(d, style: theme.textTheme.labelMedium),
                    ),
                  )
                  .toList(),
            ),
          // ── Description ──
          if (preview.description != null) ...[
            const SizedBox(height: LanghuanTheme.spaceMd),
            Text(
              preview.description!,
              style: theme.textTheme.bodyMedium?.copyWith(
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
    final theme = Theme.of(context);

    return Container(
      width: 300,
      padding: const EdgeInsets.all(LanghuanTheme.spaceMd),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: LanghuanTheme.borderRadiusMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
          const SizedBox(width: LanghuanTheme.spaceSm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
