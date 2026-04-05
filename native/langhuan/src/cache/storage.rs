use std::path::PathBuf;

use toml;

use crate::error::{
    CacheKeyMismatchError, CacheSchemaMismatchError, Error, FormatKind,
    FormatOperation, Result, StorageKind, StorageOperation,
};
use crate::util::fs::write_atomic;
use crate::util::path_key::encode_path_component;

use super::models::{
    ChapterCacheEntry, ChapterListCacheEntry, CACHE_SCHEMA_VERSION,
};

/// Cache storage for chapter content.
///
/// Organizes cached chapters by
/// `<cache_dir>/<encoded_feed_id>/<encoded_book_id>/<encoded_chapter_id>.toml`.
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

    fn feed_dir(&self, feed_id: &str) -> PathBuf {
        self.cache_dir.join(encode_path_component(feed_id))
    }

    fn book_dir(&self, feed_id: &str, book_id: &str) -> PathBuf {
        self.feed_dir(feed_id).join(encode_path_component(book_id))
    }

    /// Get the path for a cached chapter entry.
    fn chapter_cache_path(&self, feed_id: &str, book_id: &str, chapter_id: &str) -> PathBuf {
        self.book_dir(feed_id, book_id)
            .join(format!("{}.toml", encode_path_component(chapter_id)))
    }

    fn chapter_list_path(&self, feed_id: &str, book_id: &str) -> PathBuf {
        self.book_dir(feed_id, book_id).join("_chapters.toml")
    }

    /// Load a chapter list from cache.
    ///
    /// Returns `Ok(None)` when the chapter list is not cached. Returns `Err`
    /// when an existing cache file cannot be read, parsed, or validated.
    pub async fn get_chapters(&self, feed_id: &str, book_id: &str) -> Result<Option<ChapterListCacheEntry>> {
        let path = self.chapter_list_path(feed_id, book_id);

        if !path.exists() {
            tracing::debug!(
                feed_id = %feed_id,
                book_id = %book_id,
                "chapter list not in cache"
            );
            return Ok(None);
        }

        match tokio::fs::read_to_string(&path).await {
            Ok(content) => match toml::from_str::<ChapterListCacheEntry>(&content) {
                Ok(entry) => {
                    if entry.schema_version != CACHE_SCHEMA_VERSION {
                        return Err(Error::CacheSchemaMismatch {
                            details: Box::new(CacheSchemaMismatchError {
                                feed_id: feed_id.to_string(),
                                book_id: book_id.to_string(),
                                chapter_id: "_chapters".to_string(),
                                cached_version: entry.schema_version,
                                expected_version: CACHE_SCHEMA_VERSION,
                            }),
                        });
                    }
                    if entry.feed_id != feed_id || entry.book_id != book_id {
                        return Err(Error::CacheKeyMismatch {
                            details: Box::new(CacheKeyMismatchError {
                                expected_feed_id: feed_id.to_string(),
                                expected_book_id: book_id.to_string(),
                                expected_chapter_id: "_chapters".to_string(),
                                actual_feed_id: entry.feed_id,
                                actual_book_id: entry.book_id,
                                actual_chapter_id: "_chapters".to_string(),
                            }),
                        });
                    }

                    tracing::debug!(
                        feed_id = %feed_id,
                        book_id = %book_id,
                        chapters = entry.chapters.len(),
                        "loaded chapter list from cache"
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
                    "chapter list cache disappeared while reading"
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

    /// Save a chapter list to cache using atomic writes.
    pub async fn set_chapters(&self, entry: &ChapterListCacheEntry) -> Result<()> {
        let path = self.chapter_list_path(&entry.feed_id, &entry.book_id);

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
            chapters = entry.chapters.len(),
            "cached chapter list"
        );

        Ok(())
    }

    /// Clear cached chapter list for a specific book under a feed.
    pub async fn clear_chapters(&self, feed_id: &str, book_id: &str) -> Result<()> {
        let path = self.chapter_list_path(feed_id, book_id);
        if path.exists() {
            tokio::fs::remove_file(&path)
                .await
                .map_err(|e| Error::Storage {
                    kind: StorageKind::ChapterCache,
                    operation: StorageOperation::RemoveFile,
                    message: e.to_string(),
                })?;
        }

        tracing::debug!(feed_id = %feed_id, book_id = %book_id, "cleared chapter list cache");
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
                            details: Box::new(CacheSchemaMismatchError {
                                feed_id: feed_id.to_string(),
                                book_id: book_id.to_string(),
                                chapter_id: chapter_id.to_string(),
                                cached_version: entry.schema_version,
                                expected_version: CACHE_SCHEMA_VERSION,
                            }),
                        });
                    }
                    if entry.feed_id != feed_id
                        || entry.book_id != book_id
                        || entry.chapter_id != chapter_id
                    {
                        return Err(Error::CacheKeyMismatch {
                            details: Box::new(CacheKeyMismatchError {
                                expected_feed_id: feed_id.to_string(),
                                expected_book_id: book_id.to_string(),
                                expected_chapter_id: chapter_id.to_string(),
                                actual_feed_id: entry.feed_id,
                                actual_book_id: entry.book_id,
                                actual_chapter_id: entry.chapter_id,
                            }),
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
        }

        tracing::debug!(
            feed_id = %feed_id,
            book_id = %book_id,
            chapter_id = %chapter_id,
            "cleared chapter cache"
        );
        Ok(())
    }

    /// Clear all chapter cache for a specific book under a feed.
    pub async fn clear_book(&self, feed_id: &str, book_id: &str) -> Result<()> {
        let book_dir = self.book_dir(feed_id, book_id);
        if book_dir.exists() {
            tokio::fs::remove_dir_all(&book_dir)
                .await
                .map_err(|e| Error::Storage {
                    kind: StorageKind::ChapterCache,
                    operation: StorageOperation::RemoveDir,
                    message: e.to_string(),
                })?;
        }

        tracing::debug!(
            feed_id = %feed_id,
            book_id = %book_id,
            "cleared book cache"
        );
        Ok(())
    }

    /// Clear all cache for a feed.
    pub async fn clear_feed(&self, feed_id: &str) -> Result<()> {
        let feed_dir = self.feed_dir(feed_id);
        if feed_dir.exists() {
            tokio::fs::remove_dir_all(&feed_dir)
                .await
                .map_err(|e| Error::Storage {
                    kind: StorageKind::ChapterCache,
                    operation: StorageOperation::RemoveDir,
                    message: e.to_string(),
                })?;
        }

        tracing::debug!(feed_id = %feed_id, "cleared feed cache");
        Ok(())
    }

    /// Get cache directory path (useful for testing/management).
    pub fn cache_dir(&self) -> &PathBuf {
        &self.cache_dir
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
    async fn test_cache_chapter_list_roundtrip() {
        let temp_dir = TempDir::new().unwrap();
        let store = CacheStore::new(temp_dir.path());

        let entry = ChapterListCacheEntry::new(
            "feed-a".to_string(),
            "book-1".to_string(),
            vec![],
        );

        store.set_chapters(&entry).await.unwrap();

        let loaded = store
            .get_chapters("feed-a", "book-1")
            .await
            .unwrap()
            .expect("expected stored chapter list");

        assert_eq!(loaded.feed_id, "feed-a");
        assert_eq!(loaded.book_id, "book-1");
    }

    #[tokio::test]
    async fn test_clear_chapters() {
        let temp_dir = TempDir::new().unwrap();
        let store = CacheStore::new(temp_dir.path());

        let entry = ChapterListCacheEntry::new(
            "feed-a".to_string(),
            "book-1".to_string(),
            vec![],
        );

        store.set_chapters(&entry).await.unwrap();
        assert!(store.get_chapters("feed-a", "book-1").await.unwrap().is_some());

        store.clear_chapters("feed-a", "book-1").await.unwrap();
        assert!(store.get_chapters("feed-a", "book-1").await.unwrap().is_none());
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
