use std::path::PathBuf;

use crate::error::{Error, FormatKind, FormatOperation, Result, StorageKind, StorageOperation};
use crate::util::fs::write_atomic;

use super::models::{Bookmark, BookmarkFile};

#[derive(Debug)]
pub struct BookmarkStore {
    base_dir: PathBuf,
    file: BookmarkFile,
}

impl BookmarkStore {
    pub async fn open(base_dir: impl Into<PathBuf>) -> Result<Self> {
        let base_dir = base_dir.into();
        let path = base_dir.join("bookmarks.json");

        let file = if !path.exists() {
            BookmarkFile::default()
        } else {
            let content = tokio::fs::read_to_string(&path).await.map_err(|e| {
                Error::storage(StorageKind::Bookmark, StorageOperation::Read, e.to_string())
            })?;

            serde_json::from_str::<BookmarkFile>(&content).map_err(|e| {
                Error::format(
                    FormatKind::Bookmark,
                    FormatOperation::Deserialize,
                    e.to_string(),
                )
            })?
        };

        Ok(Self { base_dir, file })
    }

    fn bookmark_path(&self) -> PathBuf {
        self.base_dir.join("bookmarks.json")
    }

    async fn save_file(&self, file: &BookmarkFile) -> Result<()> {
        let path = self.bookmark_path();
        if let Some(parent) = path.parent() {
            tokio::fs::create_dir_all(parent).await.map_err(|e| {
                Error::storage(
                    StorageKind::Bookmark,
                    StorageOperation::CreateDir,
                    e.to_string(),
                )
            })?;
        }

        let content = serde_json::to_string_pretty(file).map_err(|e| {
            Error::format(
                FormatKind::Bookmark,
                FormatOperation::Serialize,
                e.to_string(),
            )
        })?;

        write_atomic(&path, &content).await.map_err(|e| {
            Error::storage(StorageKind::Bookmark, StorageOperation::Write, e.to_string())
        })?;

        Ok(())
    }

    /// List all bookmarks for a specific book.
    pub async fn list_bookmarks(
        &self,
        feed_id: &str,
        book_id: &str,
    ) -> Result<Vec<Bookmark>> {
        let result: Vec<Bookmark> = self
            .file
            .entries
            .iter()
            .filter(|e| e.feed_id == feed_id && e.book_id == book_id)
            .cloned()
            .collect();
        Ok(result)
    }

    /// Add a bookmark. Returns the stored bookmark.
    pub async fn add_bookmark(&mut self, bookmark: Bookmark) -> Result<Bookmark> {
        self.file.entries.push(bookmark.clone());
        let snapshot = self.file.clone();
        self.save_file(&snapshot).await?;
        Ok(bookmark)
    }

    /// Remove a bookmark by id. Returns true if it was found and removed.
    pub async fn remove_bookmark(&mut self, id: &str) -> Result<bool> {
        let before = self.file.entries.len();
        self.file.entries.retain(|e| e.id != id);
        let removed = self.file.entries.len() < before;
        if removed {
            let snapshot = self.file.clone();
            self.save_file(&snapshot).await?;
        }
        Ok(removed)
    }
}

#[cfg(test)]
mod tests {
    use tempfile::TempDir;

    use super::*;

    fn make_bookmark(id: &str, feed_id: &str, book_id: &str, chapter_id: &str) -> Bookmark {
        Bookmark {
            id: id.to_string(),
            feed_id: feed_id.to_string(),
            book_id: book_id.to_string(),
            chapter_id: chapter_id.to_string(),
            paragraph_index: 5,
            paragraph_name: "Paragraph 6".to_string(),
            paragraph_preview: "preview text".to_string(),
            label: "test".to_string(),
            created_at_ms: 1_700_000_000_000,
        }
    }

    #[tokio::test]
    async fn test_add_and_list() {
        let dir = TempDir::new().unwrap();
        let mut store = BookmarkStore::open(dir.path()).await.unwrap();

        let bm = make_bookmark("bm-1", "feed-a", "book-1", "ch-1");
        store.add_bookmark(bm.clone()).await.unwrap();

        let list = store.list_bookmarks("feed-a", "book-1").await.unwrap();
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].id, "bm-1");
    }

    #[tokio::test]
    async fn test_remove() {
        let dir = TempDir::new().unwrap();
        let mut store = BookmarkStore::open(dir.path()).await.unwrap();

        store.add_bookmark(make_bookmark("bm-1", "feed-a", "book-1", "ch-1")).await.unwrap();
        store.add_bookmark(make_bookmark("bm-2", "feed-a", "book-1", "ch-2")).await.unwrap();

        let removed = store.remove_bookmark("bm-1").await.unwrap();
        assert!(removed);

        let list = store.list_bookmarks("feed-a", "book-1").await.unwrap();
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].id, "bm-2");
    }

    #[tokio::test]
    async fn test_persistence() {
        let dir = TempDir::new().unwrap();
        {
            let mut store = BookmarkStore::open(dir.path()).await.unwrap();
            store.add_bookmark(make_bookmark("bm-1", "feed-a", "book-1", "ch-1")).await.unwrap();
        }
        // Reopen and check persistence.
        let store = BookmarkStore::open(dir.path()).await.unwrap();
        let list = store.list_bookmarks("feed-a", "book-1").await.unwrap();
        assert_eq!(list.len(), 1);
    }
}
