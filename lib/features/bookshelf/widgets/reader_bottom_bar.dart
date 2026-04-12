import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../../feeds/feed_service.dart';

/// Bottom bar shown in the reader when the user taps the screen.
///
/// Displays chapter progress and prev/next navigation buttons.
class ReaderBottomBar extends StatelessWidget {
  const ReaderBottomBar({
    super.key,
    required this.chapters,
    required this.currentIndex,
    required this.isSwitchingChapter,
    required this.onPrevious,
    required this.onNext,
    required this.onOpenToc,
    required this.onOpenInterface,
    required this.onOpenSettings,
  });

  final List<ChapterInfoModel> chapters;
  final int currentIndex;
  final bool isSwitchingChapter;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onOpenToc;
  final VoidCallback onOpenInterface;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canGoPrev = currentIndex > 0;
    final canGoNext = currentIndex >= 0 && currentIndex < chapters.length - 1;
    final chapterProgress = chapters.isEmpty
        ? 0.0
        : ((currentIndex < 0 ? 0 : currentIndex + 1) / chapters.length).clamp(
            0.0,
            1.0,
          );

    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainer,
      padding: EdgeInsets.fromLTRB(0, 0, 0, bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (chapters.isNotEmpty) ...[
            Text(
              l10n.readerChapterProgress(
                currentIndex < 0 ? 0 : currentIndex + 1,
                chapters.length,
              ),
              style: Theme.of(context).textTheme.labelSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 1),
          ],
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(32),
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: const VisualDensity(
                      horizontal: -2,
                      vertical: -2,
                    ),
                    iconSize: 18,
                  ),
                  onPressed:
                      (chapters.isEmpty || !canGoPrev || isSwitchingChapter)
                      ? null
                      : onPrevious,
                  icon: const Icon(Icons.chevron_left),
                  label: Text(
                    l10n.readerPrevChapter,
                    style: Theme.of(context).textTheme.labelSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: SizedBox(
                  height: 4,
                  child: LinearProgressIndicator(value: chapterProgress),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(32),
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: const VisualDensity(
                      horizontal: -2,
                      vertical: -2,
                    ),
                    iconSize: 18,
                  ),
                  onPressed:
                      (chapters.isEmpty || !canGoNext || isSwitchingChapter)
                      ? null
                      : onNext,
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.chevron_right),
                  label: Text(
                    l10n.readerNextChapter,
                    style: Theme.of(context).textTheme.labelSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Row(
            children: [
              Expanded(
                child: _buildWideActionButton(
                  context: context,
                  icon: Icons.list,
                  text: l10n.readerToc,
                  onPressed: onOpenToc,
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _buildWideActionButton(
                  context: context,
                  icon: Icons.tune,
                  text: l10n.readerInterface,
                  onPressed: onOpenInterface,
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _buildWideActionButton(
                  context: context,
                  icon: Icons.settings,
                  text: l10n.readerSettings,
                  onPressed: onOpenSettings,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWideActionButton({
    required BuildContext context,
    required IconData icon,
    required String text,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 68,
      child: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size.fromHeight(68),
          padding: const EdgeInsets.symmetric(vertical: 1),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
          shape: RoundedRectangleBorder(
            borderRadius: LanghuanTheme.borderRadiusMd,
          ),
        ),
        onPressed: onPressed,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24),
            const SizedBox(height: 1),
            Text(text, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}
