// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => '瀾幻';

  @override
  String get navBookshelf => '書架';

  @override
  String get navFeeds => '書源';

  @override
  String get navProfile => '我的';

  @override
  String get bookshelfTitle => '書架';

  @override
  String get bookshelfEmpty => '你的書籍將顯示在這裡';

  @override
  String get bookshelfSearchHint => '搜索書籍…';

  @override
  String get searchTitle => '搜索';

  @override
  String get searchHintNoFeed => '請先選擇書源…';

  @override
  String searchHintWithFeed(String feedName) {
    return '在 $feedName 中搜索…';
  }

  @override
  String get searchCancel => '取消';

  @override
  String get searchClear => '清除';

  @override
  String get searchEmptyPrompt => '輸入關鍵詞開始搜索';

  @override
  String searchNoResults(String keyword) {
    return '「$keyword」無搜索結果';
  }

  @override
  String get searchError => '搜索出錯';

  @override
  String get searchRetry => '重試';

  @override
  String get searchLoadingMore => '加載更多…';

  @override
  String get feedsTitle => '書源';

  @override
  String get feedsSearchHint => '搜索書源…';

  @override
  String get feedsEmpty => '暫無書源\n請將腳本文件放入 scripts 文件夾';

  @override
  String feedsNoMatch(String keyword) {
    return '未找到匹配的書源「$keyword」';
  }

  @override
  String get feedsLoadError => '加載書源失敗';

  @override
  String get feedsRetry => '重試';

  @override
  String get feedDetailId => 'ID';

  @override
  String get feedDetailVersion => '版本';

  @override
  String get feedDetailAuthor => '作者';

  @override
  String get feedDetailTooltip => '詳情';

  @override
  String get feedSelectorNoFeeds => '暫無書源，請先在「書源」頁面添加腳本';

  @override
  String get profileTitle => '我的';

  @override
  String get profileSubtitle => '管理你的帳號設置';

  @override
  String get errorSomethingWrong => '出現錯誤';
}
