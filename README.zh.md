# 琅嬛 (Langhuan)

一款支持**自定義書源**的跨平台網路小說閱讀器。編寫一個 Lua 腳本，指向任意網站，即可開始閱讀——無需更新應用。

使用 Flutter（UI）、Rust（後端）和 Lua（腳本）構建。

> [English version](README.md)

## 功能

- **基於 Lua 的自定義書源** — 通過 Lua 腳本定義如何從任意網站搜索、獲取和解析小說內容。支持需要登錄的書源（基於 WebView 的認證流程）。
- **緩存管理** — 本地章節緩存，自動清理過期數據；書架中的書籍不會被清理。
- **本地化** — 支持英文和中文。

## 技術棧

| 層級 | 技術                          |
| ---- | ----------------------------- |
| UI   | Flutter + Riverpod + GoRouter |
| 橋接 | flutter_rust_bridge v2        |
| 後端 | Rust + Tokio（Actor 模型）    |
| 腳本 | Lua 5.4（mlua，沙盒化）       |
| HTTP | reqwest + rustls              |

## 項目結構

```
lib/                        # Flutter 前端
├── features/               # 功能模塊（書架、書源、設置）
├── router/                 # GoRouter 路由配置
├── shared/                 # 共享服務、主題、組件
└── l10n/                   # 國際化資源（ARB）

native/langhuan/            # Rust 核心庫（純領域邏輯）
├── src/
│   ├── script/             # Lua 腳本引擎與運行時
│   ├── cache/              # 緩存存儲
│   ├── bookshelf/          # 書架持久化
│   ├── progress/           # 閱讀進度
│   ├── auth/               # 登錄認證
│   └── feed/               # 書源加載與註冊

native/hub/                 # FRB 橋接層 + Actor 系統
├── src/
│   ├── api/                # FRB API（Dart 可調用的公開函數）
│   └── actors/             # 消息傳遞 Actor
```

## 構建

環境要求：

- [Flutter SDK](https://docs.flutter.dev/get-started/install)（≥ 3.11.3）
- [Rust 工具鏈](https://www.rust-lang.org/tools/install)

```bash
# 確認環境
flutter doctor
rustc --version

# 安裝代碼生成工具（僅首次）
cargo install flutter_rust_bridge_codegen

# 生成 Dart ↔ Rust 綁定（首次構建前必須執行）
flutter_rust_bridge_codegen generate

# 運行
flutter run
```

後續修改 Rust API（`native/hub/src/api/` 中的函數）後，需重新執行 `flutter_rust_bridge_codegen generate` 更新綁定。生成的 Dart 代碼位於 `lib/src/rust/`，生成的 Rust 代碼位於 `native/hub/src/frb_generated.rs`——請勿手動編輯這些文件。

## 書源腳本

書源是 Lua 腳本文件，定義了如何從特定網站獲取小說內容。完整的腳本指南、API 參考和示例請見[書源文檔](docs/book-sources/README.md)。

## 許可證

本項目使用 [MIT 許可證](LICENSE) 授權。
