use std::path::PathBuf;

use toml;

use crate::error::{
    Error, FormatKind, FormatOperation, Result, StorageKind, StorageOperation,
};
use crate::util::fs::write_atomic;

use super::models::{ChapterCacheEntry, ProgressFile, ReadingProgress, CACHE_SCHEMA_VERSION};

/// Cache storage for chapter content.
///
/// Organizes cached chapters by `<cache_dir>/<feed_id>/<book_id>/<chapter_id>.toml`.
/// Each entry is stored as a TOML file containing paragraphs and metadata.
#[derive(Debug, Clone)]
pub struct CacheStore {
    cache_dir: PathBuf,
}

impl CacheStore {
    /// Create a new cache store with the given base directory.
    pub fn new(cache_dir: impl Into<PathBuf>) -> Self {
        Self {
            cache_dir: cache_dir.into(),
        }
    }

    /// Get the path for a cached chapter entry.
    fn chapter_cache_path(&self, feed_id: &str, book_id: &str, chapter_id: &str) -> PathBuf {
        self.cache_dir
            .join(feed_id)
            .join(book_id)
            .join(format!("{}.toml", chapter_id))
    }

    fn progress_path(&self) -> PathBuf {
        self.cache_dir.join("progress.toml")
    }

    async fn load_progress_file(&self) -> Result<ProgressFile> {
        let path = self.progress_path();
        if !path.exists() {
            return Ok(ProgressFile::default());
        }

        let content = tokio::fs::read_to_string(&path)
            .await
            .map_err(|e| Error::Storage {
                kind: StorageKind::ReadingProgress,
                operation: StorageOperation::Read,
                message: e.to_string(),
            })?;

        toml::from_str::<ProgressFile>(&content)
            .map_err(|e| Error::Format {
                kind: FormatKind::ReadingProgress,
                operation: FormatOperation::Deserialize,
                message: e.to_string(),
            })
    }

    async fn save_progress_file(&self, file: &ProgressFile) -> Result<()> {
        let path = self.progress_path();
        if let Some(parent) = path.parent() {
            tokio::fs::create_dir_all(parent)
                .await
                .map_err(|e| Error::Storage {
                    kind: StorageKind::ReadingProgress,
                    operation: StorageOperation::CreateDir,
                    message: e.to_string(),
                })?;
        }

        let content = toml::to_string(file)
            .map_err(|e| Error::Format {
                kind: FormatKind::ReadingProgress,
                operation: FormatOperation::Serialize,
                message: e.to_string(),
            })?;
        write_atomic(&path, &content).await?;
        Ok(())
    }

    /// Load a chapter from cache.
    ///
    /// Returns `Ok(None)` when the chapter is not cached. Returns `Err` when an
    /// existing cache file cannot be read, parsed, or validated.
    pub async fn get_chapter(
        &self,
        feed_id: &str,
        book_id: &str,
        chapter_id: &str,
    ) -> Result<Option<ChapterCacheEntry>> {
        let path = self.chapter_cache_path(feed_id, book_id, chapter_id);

        if !path.exists() {
            tracing::debug!(
                feed_id = %feed_id,
                book_id = %book_id,
                chapter_id = %chapter_id,
                "chapter not in cache"
            );
            return Ok(None);
        }

        match tokio::fs::read_to_string(&path).await {
            Ok(content) => match toml::from_str::<ChapterCacheEntry>(&content) {
                Ok(entry) => {
                    if entry.schema_version != CACHE_SCHEMA_VERSION {
                        return Err(Error::CacheSchemaMismatch {
                            feed_id: feed_id.to_string(),
                            book_id: book_id.to_string(),
                            chapter_id: chapter_id.to_string(),
                            cached_version: entry.schema_version,
                            expected_version: CACHE_SCHEMA_VERSION,
                        });
                    }
                    if entry.feed_id != feed_id
                        || entry.book_id != book_id
                        || entry.chapter_id != chapter_id
                    {
                        return Err(Error::CacheKeyMismatch {
                            expected_feed_id: feed_id.to_string(),
                            expected_book_id: book_id.to_string(),
                            expected_chapter_id: chapter_id.to_string(),
                            actual_feed_id: entry.feed_id,
                            actual_book_id: entry.book_id,
                            actual_chapter_id: entry.chapter_id,
                        });
                    }
                    tracing::debug!(
                        feed_id = %feed_id,
                        book_id = %book_id,
                        chapter_id = %chapter_id,
                        paragraphs = entry.paragraphs.len(),
                        "loaded chapter from cache"
                    );
                    Ok(Some(entry))
                }
                Err(e) => Err(Error::Format {
                    kind: FormatKind::ChapterCache,
                    operation: FormatOperation::Deserialize,
                    message: e.to_string(),
                }),
            },
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                tracing::debug!(
                    feed_id = %feed_id,
                    book_id = %book_id,
                    chapter_id = %chapter_id,
                    "chapter cache disappeared while reading"
                );
                Ok(None)
            }
            Err(e) => Err(Error::Storage {
                kind: StorageKind::ChapterCache,
                operation: StorageOperation::Read,
                message: e.to_string(),
            }),
        }
    }

    /// Save a chapter to cache using atomic writes.
    pub async fn set_chapter(&self, entry: &ChapterCacheEntry) -> Result<()> {
        let path = self.chapter_cache_path(&entry.feed_id, &entry.book_id, &entry.chapter_id);

        // Ensure parent directory exists
        if let Some(parent) = path.parent() {
            tokio::fs::create_dir_all(parent)
                .await
                .map_err(|e| Error::Storage {
                    kind: StorageKind::ChapterCache,
                    operation: StorageOperation::CreateDir,
                    message: e.to_string(),
                })?;
        }

        let content = toml::to_string(entry)
            .map_err(|e| Error::Format {
                kind: FormatKind::ChapterCache,
                operation: FormatOperation::Serialize,
                message: e.to_string(),
            })?;
        write_atomic(&path, &content)
            .await
            .map_err(|e| Error::Storage {
                kind: StorageKind::ChapterCache,
                operation: StorageOperation::Write,
                message: e.to_string(),
            })?;

        tracing::debug!(
            feed_id = %entry.feed_id,
            book_id = %entry.book_id,
            chapter_id = %entry.chapter_id,
            paragraphs = entry.paragraphs.len(),
            "cached chapter paragraphs"
        );

        Ok(())
    }

    /// Clear cache for a specific chapter.
    pub async fn clear_chapter(&self, feed_id: &str, book_id: &str, chapter_id: &str) -> Result<()> {
        let path = self.chapter_cache_path(feed_id, book_id, chapter_id);
        if path.exists() {
            tokio::fs::remove_file(&path)
                .await
                .map_err(|e| Error::Storage {
                    kind: StorageKind::ChapterCache,
                    operation: StorageOperation::RemoveFile,
                    message: e.to_string(),
                })?;
            tracing::debug!(
                feed_id = %feed_id,
                book_id = %book_id,
                chapter_id = %chapter_id,
                "cleared chapter cache"
            );
        }
        Ok(())
    }

    /// Clear all chapter cache for a specific book under a feed.
    pub async fn clear_book(&self, feed_id: &str, book_id: &str) -> Result<()> {
        let book_dir = self.cache_dir.join(feed_id).join(book_id);
        if book_dir.exists() {
            tokio::fs::remove_dir_all(&book_dir)
                .await
                .map_err(|e| Error::Storage {
                    kind: StorageKind::ChapterCache,
                    operation: StorageOperation::RemoveDir,
                    message: e.to_string(),
                })?;
            tracing::debug!(
                feed_id = %feed_id,
                book_id = %book_id,
                "cleared book cache"
            );
        }
        Ok(())
    }

    /// Clear all cache for a feed.
    pub async fn clear_feed(&self, feed_id: &str) -> Result<()> {
        let feed_dir = self.cache_dir.join(feed_id);
        if feed_dir.exists() {
            tokio::fs::remove_dir_all(&feed_dir)
                .await
                .map_err(|e| Error::Storage {
                    kind: StorageKind::ChapterCache,
                    operation: StorageOperation::RemoveDir,
                    message: e.to_string(),
                })?;
            tracing::debug!(feed_id = %feed_id, "cleared feed cache");
        }
        Ok(())
    }

    /// Get cache directory path (useful for testing/management).
    pub fn cache_dir(&self) -> &PathBuf {
        &self.cache_dir
    }

    pub async fn get_reading_progress(
        &self,
        feed_id: &str,
        book_id: &str,
    ) -> Result<Option<ReadingProgress>> {
        let file = self.load_progress_file().await?;
        Ok(file
            .entries
            .into_iter()
            .find(|entry| entry.feed_id == feed_id && entry.book_id == book_id))
    }

    pub async fn set_reading_progress(&self, progress: ReadingProgress) -> Result<()> {
        let mut file = self.load_progress_file().await?;
        if let Some(existing) = file
            .entries
            .iter_mut()
            .find(|entry| entry.feed_id == progress.feed_id && entry.book_id == progress.book_id)
        {
            *existing = progress;
        } else {
            file.entries.push(progress);
        }

        self.save_progress_file(&file).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[tokio::test]
    async fn test_cache_hit_and_miss() {
        let temp_dir = TempDir::new().unwrap();
        let store = CacheStore::new(temp_dir.path());

        let feed_id = "test-feed";
        let book_id = "book-001";
        let chapter_id = "ch-001";

        // Before caching: should be None
        let result = store.get_chapter(feed_id, book_id, chapter_id).await.unwrap();
        assert!(result.is_none());

        // Create and cache an entry
        let entry = ChapterCacheEntry::new(
            feed_id.to_string(),
            book_id.to_string(),
            chapter_id.to_string(),
            vec![],
        );
        store.set_chapter(&entry).await.unwrap();

        // After caching: should get it back
        let cached = store.get_chapter(feed_id, book_id, chapter_id).await.unwrap();
        assert!(cached.is_some());
        assert_eq!(cached.unwrap().feed_id, feed_id);
    }

    #[tokio::test]
    async fn test_clear_chapter() {
        let temp_dir = TempDir::new().unwrap();
        let store = CacheStore::new(temp_dir.path());

        let feed_id = "test-feed";
        let book_id = "book-001";
        let chapter_id = "ch-001";

        // Cache an entry
        let entry = ChapterCacheEntry::new(
            feed_id.to_string(),
            book_id.to_string(),
            chapter_id.to_string(),
            vec![],
        );
        store.set_chapter(&entry).await.unwrap();

        // Verify it's cached
        let cached = store.get_chapter(feed_id, book_id, chapter_id).await.unwrap();
        assert!(cached.is_some());

        // Clear it
        store.clear_chapter(feed_id, book_id, chapter_id).await.unwrap();

        // Should be gone
        let result = store.get_chapter(feed_id, book_id, chapter_id).await.unwrap();
        assert!(result.is_none());
    }

    #[tokio::test]
    async fn test_set_and_get_reading_progress() {
        let temp_dir = TempDir::new().unwrap();
        let store = CacheStore::new(temp_dir.path());

        let progress = ReadingProgress {
            feed_id: "feed-a".to_string(),
            book_id: "book-1".to_string(),
            chapter_id: "chapter-10".to_string(),
            paragraph_index: 12,
            scroll_offset: 328.5,
            updated_at_ms: 1_712_345_678_000,
        };

        store.set_reading_progress(progress.clone()).await.unwrap();

        let loaded = store
            .get_reading_progress("feed-a", "book-1")
            .await
            .unwrap()
            .expect("expected stored progress");

        assert_eq!(loaded.chapter_id, "chapter-10");
        assert_eq!(loaded.paragraph_index, 12);
    }

    #[tokio::test]
    async fn test_clear_book() {
        let temp_dir = TempDir::new().unwrap();
        let store = CacheStore::new(temp_dir.path());

        let first = ChapterCacheEntry::new(
            "test-feed".to_string(),
            "book-001".to_string(),
            "ch-001".to_string(),
            vec![],
        );
        let second = ChapterCacheEntry::new(
            "test-feed".to_string(),
            "book-001".to_string(),
            "ch-002".to_string(),
            vec![],
        );

        store.set_chapter(&first).await.unwrap();
        store.set_chapter(&second).await.unwrap();

        store.clear_book("test-feed", "book-001").await.unwrap();

        assert!(store.get_chapter("test-feed", "book-001", "ch-001").await.unwrap().is_none());
        assert!(store.get_chapter("test-feed", "book-001", "ch-002").await.unwrap().is_none());
    }

    #[tokio::test]
    async fn test_get_chapter_returns_error_for_invalid_cache() {
        let temp_dir = TempDir::new().unwrap();
        let store = CacheStore::new(temp_dir.path());
        let path = store.chapter_cache_path("test-feed", "book-001", "ch-001");

        tokio::fs::create_dir_all(path.parent().unwrap()).await.unwrap();
        write_atomic(&path, "not valid toml").await.unwrap();

        let error = store
            .get_chapter("test-feed", "book-001", "ch-001")
            .await
            .expect_err("invalid cache should return an error");

        assert!(matches!(
            error,
            Error::Format {
                kind: FormatKind::ChapterCache,
                operation: FormatOperation::Deserialize,
                ..
            }
        ));
    }
}
