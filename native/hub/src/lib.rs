//! This `hub` crate is the
//! entry point of the Rust logic.

#[macro_use]
extern crate rust_i18n;

rust_i18n::i18n!("locales", fallback = "en");

mod actors;
mod logging;
mod signals;

use actors::create_actors;
use rinf::{dart_shutdown, write_interface};
use tokio::spawn;

#[cfg(target_os = "android")]
use jni::JNIEnv;
#[cfg(target_os = "android")]
use jni::objects::JObject;

// Uncomment below to target the web.
// use tokio_with_wasm::alias as tokio;

write_interface!();

#[cfg(target_os = "android")]
#[unsafe(export_name = "Java_org_eu_ywxt_langhuan_MainActivity_initRustlsVerifier")]
pub extern "system" fn init_rustls_verifier(mut env: JNIEnv, _activity: JObject, context: JObject) {
    rustls_platform_verifier::android::init_with_env(&mut env, context)
        .expect("failed to initialize rustls-platform-verifier");
}

// You can go with any async library, not just `tokio`.
#[tokio::main(flavor = "current_thread")]
async fn main() {
    logging::init();
    tracing::info!("hub runtime starting");

    tracing::info!("spawning actor system");
    spawn(create_actors());

    // Keep the main function running until Dart shutdown.
    dart_shutdown().await;
    tracing::info!("hub runtime stopped");
}
/// Produce a locale-aware error string for a [`langhuan::error::Error`] using
/// the global rust-i18n locale set by the `SetLocale` signal handler.
fn localize_error(e: &langhuan::error::Error) -> String {
    use langhuan::error::Error;
    match e {
        Error::Lua(inner) => t!("error.lua", error = inner).to_string(),
        Error::Http(inner) => t!("error.http", error = inner).to_string(),
        Error::MissingFunction { name } => t!("error.missing_function", name = name).to_string(),
        Error::InvalidFeed { message } => t!("error.invalid_feed", message = message).to_string(),
        Error::ScriptParse { line, message } => {
            t!("error.script_parse", line = line, message = message).to_string()
        }
        Error::RegistryNotFound(inner) => t!("error.registry_not_found", error = inner).to_string(),
        Error::RegistryParse { message } => {
            t!("error.registry_parse", message = message).to_string()
        }
        Error::FeedNotFound { id } => t!("error.feed_not_found", id = id).to_string(),
        Error::DuplicateFeedId { id } => t!("error.duplicate_feed_id", id = id).to_string(),
        Error::DomainNotAllowed { url, allowed } => t!(
            "error.domain_not_allowed",
            url = url,
            allowed = join(allowed.iter().map(|s| s.as_str()), ", ")
        )
        .to_string(),
        Error::RegistryWrite(msg) => t!("error.registry_write", error = msg).to_string(),
        Error::Storage {
            kind,
            operation,
            message,
        } => t!(
            "error.storage",
            target = localize_storage_kind(*kind),
            operation = localize_storage_operation(*operation),
            message = message
        )
        .to_string(),
        Error::Format {
            kind,
            operation,
            message,
        } => t!(
            "error.format",
            target = localize_format_kind(*kind),
            operation = localize_format_operation(*operation),
            message = message
        )
        .to_string(),
        Error::CacheSchemaMismatch {
            feed_id,
            book_id,
            chapter_id,
            cached_version,
            expected_version,
        } => t!(
            "error.cache_schema_mismatch",
            feed_id = feed_id,
            book_id = book_id,
            chapter_id = chapter_id,
            cached_version = cached_version,
            expected_version = expected_version
        )
        .to_string(),
        Error::CacheKeyMismatch {
            expected_feed_id,
            expected_book_id,
            expected_chapter_id,
            actual_feed_id,
            actual_book_id,
            actual_chapter_id,
        } => t!(
            "error.cache_key_mismatch",
            expected_feed_id = expected_feed_id,
            expected_book_id = expected_book_id,
            expected_chapter_id = expected_chapter_id,
            actual_feed_id = actual_feed_id,
            actual_book_id = actual_book_id,
            actual_chapter_id = actual_chapter_id,
        )
        .to_string(),
    }
}

fn localize_storage_kind(kind: langhuan::error::StorageKind) -> String {
    use langhuan::error::StorageKind;

    match kind {
        StorageKind::Bookshelf => t!("error_target.bookshelf").to_string(),
        StorageKind::ReadingProgress => t!("error_target.reading_progress").to_string(),
        StorageKind::ChapterCache => t!("error_target.chapter_cache").to_string(),
    }
}

fn localize_storage_operation(operation: langhuan::error::StorageOperation) -> String {
    use langhuan::error::StorageOperation;

    match operation {
        StorageOperation::Read => t!("error_operation.read").to_string(),
        StorageOperation::Write => t!("error_operation.write").to_string(),
        StorageOperation::CreateDir => t!("error_operation.create_dir").to_string(),
        StorageOperation::RemoveFile => t!("error_operation.remove_file").to_string(),
        StorageOperation::RemoveDir => t!("error_operation.remove_dir").to_string(),
    }
}

fn localize_format_kind(kind: langhuan::error::FormatKind) -> String {
    use langhuan::error::FormatKind;

    match kind {
        FormatKind::Bookshelf => t!("error_target.bookshelf_file").to_string(),
        FormatKind::ReadingProgress => t!("error_target.reading_progress_file").to_string(),
        FormatKind::ChapterCache => t!("error_target.chapter_cache_file").to_string(),
    }
}

fn localize_format_operation(operation: langhuan::error::FormatOperation) -> String {
    use langhuan::error::FormatOperation;

    match operation {
        FormatOperation::Serialize => t!("error_operation.serialize").to_string(),
        FormatOperation::Deserialize => t!("error_operation.deserialize").to_string(),
    }
}

fn join<'a>(mut iter: impl Iterator<Item = &'a str>, joiner: &str) -> String {
    let mut joined = String::new();

    if let Some(item) = iter.next() {
        joined.push_str(item);
    }

    for item in iter {
        joined.push_str(joiner);
        joined.push_str(item);
    }

    joined
}
