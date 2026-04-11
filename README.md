# Langhuan (琅嬛)

A cross-platform web novel reader with **user-defined book sources**. Write a Lua script, point it at any website, and start reading — no app update required.

Built with Flutter (UI), Rust (backend), and Lua (scripting).

> [中文版](README.zh.md)

## Features

- **Lua-based Book Sources** — Define how to search, fetch, and parse novel content from any website via Lua scripts. Supports sources that require login (WebView-based auth flow).
- **Cache Management** — Local chapter caching with automatic stale data cleanup; bookshelf items are preserved.
- **Localization** — English and Chinese.

## Tech Stack

| Layer     | Technology                    |
| --------- | ----------------------------- |
| UI        | Flutter + Riverpod + GoRouter |
| Bridge    | flutter_rust_bridge v2        |
| Backend   | Rust + Tokio (Actor model)    |
| Scripting | Lua 5.4 (mlua, sandboxed)     |
| HTTP      | reqwest + rustls              |

## Project Structure

```
lib/                        # Flutter frontend
├── features/               # Feature modules (bookshelf, feeds, settings)
├── router/                 # GoRouter configuration
├── shared/                 # Shared services, theme, widgets
└── l10n/                   # Localization resources (ARB)

native/langhuan/            # Core Rust library (pure domain logic)
├── src/
│   ├── script/             # Lua script engine & runtime
│   ├── cache/              # Cache storage
│   ├── bookshelf/          # Bookshelf persistence
│   ├── progress/           # Reading progress
│   ├── auth/               # Login & authentication
│   └── feed/               # Feed loading & registry

native/hub/                 # FRB bridge layer + Actor system
├── src/
│   ├── api/                # FRB API (public functions callable from Dart)
│   └── actors/             # Message-passing actors
```

## Building

Prerequisites:

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (≥ 3.11.3)
- [Rust toolchain](https://www.rust-lang.org/tools/install)

```bash
# Verify environment
flutter doctor
rustc --version

# Install the codegen tool (first time only)
cargo install flutter_rust_bridge_codegen

# Generate Dart ↔ Rust bindings (required before the first build)
flutter_rust_bridge_codegen generate

# Run
flutter run
```

When you later modify the Rust API surface (functions in `native/hub/src/api/`), re-run `flutter_rust_bridge_codegen generate` to update the bindings. The generated Dart code lives in `lib/src/rust/` and the generated Rust code in `native/hub/src/frb_generated.rs` — do not edit these files manually.

## Book Source Scripts

Book sources are Lua scripts that define how to fetch novel content from a specific website. See the [book source documentation](docs/book-sources/README.md) for the full scripting guide, API reference, and examples.

## License

This project is licensed under the [MIT License](LICENSE).
