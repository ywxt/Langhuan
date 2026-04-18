use serde::{Deserialize, Serialize};

use crate::cache::CACHE_SCHEMA_VERSION;

/// A single bookmark entry for a book.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Bookmark {
    /// Unique identifier for this bookmark (UUIDv4-style string).
    pub id: String,
    pub feed_id: String,
    pub book_id: String,
    pub chapter_id: String,
    pub paragraph_id: String,
    #[serde(default)]
    pub paragraph_name: String,
    #[serde(default)]
    pub paragraph_preview: String,
    /// Optional user-provided label; defaults to an empty string.
    pub label: String,
    pub created_at_ms: i64,
}

/// File format for bookmark persistence (per feed+book pair).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BookmarkFile {
    pub schema_version: u32,
    pub entries: Vec<Bookmark>,
}

impl Default for BookmarkFile {
    fn default() -> Self {
        Self {
            schema_version: CACHE_SCHEMA_VERSION,
            entries: Vec::new(),
        }
    }
}
