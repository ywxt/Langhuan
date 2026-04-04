use serde::{Deserialize, Serialize};

use crate::model::Paragraph;

pub const CACHE_SCHEMA_VERSION: u32 = 1;

/// Reading progress entry for a book chapter
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReadingProgress {
    pub feed_id: String,
    pub book_id: String,
    pub chapter_id: String,
    pub paragraph_index: usize,
    pub scroll_offset: f64,
    pub updated_at_ms: i64,
}

/// Cached chapter content with metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChapterCacheEntry {
    pub feed_id: String,
    pub book_id: String,
    pub chapter_id: String,
    pub paragraphs: Vec<Paragraph>,
    pub cached_at_ms: i64,
    pub schema_version: u32,
}

impl ChapterCacheEntry {
    /// Create a new cache entry with current timestamp
    pub fn new(
        feed_id: String,
        book_id: String,
        chapter_id: String,
        paragraphs: Vec<Paragraph>,
    ) -> Self {
        use std::time::{SystemTime, UNIX_EPOCH};
        let now_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0);

        Self {
            feed_id,
            book_id,
            chapter_id,
            paragraphs,
            cached_at_ms: now_ms,
            schema_version: CACHE_SCHEMA_VERSION,
        }
    }
}

/// File format for progress cache (TOML-compatible structure)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProgressFile {
    pub schema_version: u32,
    pub entries: Vec<ReadingProgress>,
}

impl Default for ProgressFile {
    fn default() -> Self {
        Self {
            schema_version: CACHE_SCHEMA_VERSION,
            entries: Vec::new(),
        }
    }
}
