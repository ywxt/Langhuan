import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rinf/rinf.dart';

import 'app.dart';
import 'features/feeds/feed_service.dart';
import 'src/bindings/bindings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeRust(assignRustSignal);

  // Resolve (and create if needed) the scripts directory, then hand it to Rust
  // so that the ScriptRegistry is loaded before the UI is shown.  We don't
  // await the Future: if the directory is empty the registry load will return
  // an error that Rust reports gracefully; the app is still usable.
  final docsDir = await getApplicationDocumentsDirectory();
  final scriptsDir = Directory('${docsDir.path}/scripts');
  await scriptsDir.create(recursive: true);
  FeedService.instance.setScriptDirectory(scriptsDir.path).ignore();

  runApp(const ProviderScope(child: LanghuanApp()));
}
