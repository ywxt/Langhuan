import 'package:flutter/material.dart';
import 'package:tuple/tuple.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/theme/app_theme.dart';
import '../../src/bindings/signals/signals.dart' show CookieEntry;
import 'feed_service.dart';

class FeedAuthPage extends StatefulWidget {
  const FeedAuthPage({super.key, required this.feedId});

  final String feedId;

  @override
  State<FeedAuthPage> createState() => _FeedAuthPageState();
}

class _FeedAuthPageState extends State<FeedAuthPage> {
  late final WebViewController _controller;
  bool _isSubmitting = false;
  bool _isLoadingEntry = true;
  String? _error;
  FeedAuthEntryModel? _entry;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    _loadEntry();
  }

  Future<void> _loadEntry() async {
    setState(() {
      _isLoadingEntry = true;
      _error = null;
    });

    try {
      final entry = await FeedService.instance.getFeedAuthEntry(widget.feedId);
      if (!mounted) return;

      if (entry == null) {
        final l10n = AppLocalizations.of(context);
        setState(() {
          _error = l10n.feedAuthNotSupported;
          _isLoadingEntry = false;
        });
        return;
      }

      _entry = entry;
      await _controller.loadRequest(Uri.parse(entry.url));
      if (!mounted) return;

      setState(() {
        _isLoadingEntry = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoadingEntry = false;
      });
    }
  }

  Future<void> _submitPage() async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final currentUrl = await _controller.currentUrl() ?? _entry?.url ?? '';
      final htmlRaw = await _controller.runJavaScriptReturningResult(
        'document.documentElement.outerHTML',
      );

      final html = _normalizeJsStringResult(htmlRaw);
      final cookiesRaw = await _controller.runJavaScriptReturningResult(
        'document.cookie',
      );
      final cookies = _normalizeJsStringResult(cookiesRaw);
      final structuredCookies = _parseCookieHeader(cookies);

      await FeedService.instance.submitFeedAuthPage(
        feedId: widget.feedId,
        currentUrl: currentUrl,
        response: html,
        responseHeaders: const <Tuple2<String, String>>[],
        cookies: structuredCookies,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  String _normalizeJsStringResult(Object value) {
    final text = value.toString();
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      return text
          .substring(1, text.length - 1)
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\"', '"');
    }
    return text;
  }

  List<CookieEntry> _parseCookieHeader(String cookieHeader) {
    if (cookieHeader.trim().isEmpty) {
      return const [];
    }

    return cookieHeader
        .split(';')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .map((item) {
          final idx = item.indexOf('=');
          if (idx <= 0) {
            return CookieEntry(name: item, value: '');
          }
          return CookieEntry(
            name: item.substring(0, idx).trim(),
            value: item.substring(idx + 1).trim(),
          );
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.feedAuthPageTitle),
        actions: [
          TextButton(
            onPressed: _isSubmitting || _isLoadingEntry ? null : _submitPage,
            child: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.feedAuthDone),
          ),
          const SizedBox(width: LanghuanTheme.spaceSm),
        ],
      ),
      body: _isLoadingEntry
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(LanghuanTheme.spaceLg),
                child: Text(_error!),
              ),
            )
          : WebViewWidget(controller: _controller),
    );
  }
}
