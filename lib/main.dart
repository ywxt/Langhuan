import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rinf/rinf.dart';

import 'app.dart';
import 'features/feeds/feed_service.dart';
import 'src/bindings/bindings.dart';
import 'src/bindings/signals/signals.dart';

void _sendLocale() {
  SetLocale(
    locale: SchedulerBinding.instance.platformDispatcher.locale.toLanguageTag(),
  ).sendSignalToRust();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeRust(assignRustSignal);

  // Send the current system locale to Rust, and keep it updated if the
  // user changes their system language while the app is running.
  _sendLocale();
  SchedulerBinding.instance.platformDispatcher.onLocaleChanged = _sendLocale;

  // Resolve (and create if needed) the scripts directory, then hand it to Rust
  // so that the ScriptRegistry is loaded before the UI is shown.  We don't
  // await the Future: if the directory is empty the registry load will return
  // an error that Rust reports gracefully; the app is still usable.
  final docsDir = await getApplicationDocumentsDirectory();
  final scriptsDir = Directory('${docsDir.path}/scripts');
  await scriptsDir.create(recursive: true);

  runApp(const ProviderScope(child: LanghuanApp()));

  // Load feeds async after the UI is up so the app doesn't block on startup.
  // On any compile error, surface it as a SnackBar.
  () async {
    final result = await FeedService.instance.setScriptDirectory(
      scriptsDir.path,
    );
    if (!result.success) {
      debugPrint('Feed load error: ${result.error}');
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Feed load error'),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }();
}
