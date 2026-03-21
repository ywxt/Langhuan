import 'package:rinf/rinf.dart';
import 'src/bindings/bindings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

Future<void> main() async {
  await initializeRust(assignRustSignal);
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: LanghuanApp()));
}
