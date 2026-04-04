use std::sync::Once;

use tracing_subscriber::EnvFilter;

#[cfg(any(target_os = "android", target_os = "ios"))]
use tracing_subscriber::layer::SubscriberExt;
#[cfg(any(target_os = "android", target_os = "ios"))]
use tracing_subscriber::util::SubscriberInitExt;

static INIT_LOGGING: Once = Once::new();

/// Initialize platform-specific tracing output once per process.
pub fn init() {
    INIT_LOGGING.call_once(|| {
        init_platform_logging();
        tracing::debug!("Rust tracing initialized");
    });
}

fn default_filter() -> EnvFilter {
    EnvFilter::try_from_default_env().unwrap_or_else(|_| {
        // Default to project-focused logs; keep dependency noise at warn.
        EnvFilter::new("hub=debug,langhuan=debug,warn")
    })
}

#[cfg(target_os = "android")]
fn init_platform_logging() {
    let android_layer = paranoid_android::layer("langhuan");
    tracing_subscriber::registry()
        .with(default_filter())
        .with(android_layer)
        .init();
}

#[cfg(target_os = "ios")]
fn init_platform_logging() {
    let oslog_layer = tracing_oslog::OsLogger::new("org.eu.ywxt.langhuan", "hub");
    tracing_subscriber::registry()
        .with(default_filter())
        .with(oslog_layer)
        .init();
}

#[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
fn init_platform_logging() {
    let _ = tracing_subscriber::fmt()
        .with_env_filter(default_filter())
        .with_target(true)
        .with_line_number(true)
        .with_thread_ids(true)
        .try_init();
}

#[cfg(not(any(
    target_os = "android",
    target_os = "ios",
    target_os = "linux",
    target_os = "windows",
    target_os = "macos"
)))]
fn init_platform_logging() {
    let _ = tracing_subscriber::fmt()
        .with_env_filter(default_filter())
        .with_ansi(false)
        .compact()
        .try_init();
}
