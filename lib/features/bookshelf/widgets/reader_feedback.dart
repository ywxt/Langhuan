import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

void showReaderToast(BuildContext context, String message) {
  final theme = Theme.of(context);
  Fluttertoast.showToast(
    msg: message,
    backgroundColor: theme.colorScheme.onSurface,
    textColor: theme.colorScheme.surface,
    fontSize: 14,
  );
}
