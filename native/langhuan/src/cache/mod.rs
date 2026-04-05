use std::sync::Arc;

use async_stream::stream;
use tokio_stream::StreamExt;

use crate::error::Result;
use crate::feed::{Feed, FeedBookshelfSupport, FeedMeta, FeedStream};
use crate::model::{ChapterInfo, Paragraph};

pub mod models;
pub mod storage;

pub use models::{CACHE_SCHEMA_VERSION, ChapterCacheEntry, ChapterListCacheEntry};
pub use storage::CacheStore;

/// A proxy feed that wraps any [`Feed`] and adds caching for chapter content.
///
/// **Cache-first behavior for paragraphs():**
/// - First attempts to load from cache store
/// - If cache hit: returns cached paragraphs as a stream (no network call)
/// - If cache miss: calls inner feed, streams paragraphs, then persists to cache on completion
///
/// **Other methods** (search, book_info) are passed through without caching.
///
/// # Example
///
/// ```ignore
/// let lua_feed = Arc::new(lua_feed);
/// let cache_store = Arc::new(CacheStore::new(cache_dir));
/// let cached_feed = CachedFeed::new(lua_feed, cache_store);
///
/// // All paragraphs() calls now use cache-first
/// for para in cached_feed.paragraphs("book-001", "ch-001") { ... }
/// ```
pub struct CachedFeed<F: Feed> {
    inner: Arc<F>,
    cache_store: Arc<CacheStore>,
}

impl<F: Feed> CachedFeed<F> {
    /// Wrap an existing feed with caching.
    pub fn new(inner: Arc<F>, cache_store: Arc<CacheStore>) -> Self {
        Self { inner, cache_store }
    }

    /// Get a reference to the inner feed (useful for advanced scenarios).
    pub fn inner(&self) -> &Arc<F> {
        &self.inner
    }

    /// Get a reference to the cache store (useful for cache management).
    pub fn cache_store(&self) -> &Arc<CacheStore> {
        &self.cache_store
    }

    /// Clear cached content for a specific chapter.
    pub async fn clear_chapter_cache(&self, book_id: &str, chapter_id: &str) -> Result<()> {
        self.cache_store
            .clear_chapter(&self.inner.meta().id, book_id, chapter_id)
            .await
    }

    /// Clear cached content for a specific book.
    pub async fn clear_book_cache(&self, book_id: &str) -> Result<()> {
        self.cache_store
            .clear_book(&self.inner.meta().id, book_id)
            .await
    }

    /// Clear all cached content for this feed.
    pub async fn clear_cache(&self) -> Result<()> {
        self.cache_store.clear_feed(&self.inner.meta().id).await
    }

    fn cached_paragraphs<'a>(
        &'a self,
        book_id: &'a str,
        chapter_id: &'a str,
    ) -> FeedStream<'a, Paragraph> {
        let feed_id = self.inner.meta().id.clone();
        let book_id_owned = book_id.to_string();
        let chapter_id_owned = chapter_id.to_string();
        let cache_store = self.cache_store.clone();
        let inner = self.inner.clone();

        Box::pin(stream! {
            match cache_store
                .get_chapter(&feed_id, &book_id_owned, &chapter_id_owned)
                .await
            {
                Ok(Some(entry)) => {
                    tracing::info!(
                        feed_id = %feed_id,
                        book_id = %book_id_owned,
                        chapter_id = %chapter_id_owned,
                        paragraphs = entry.paragraphs.len(),
                        "cache hit for chapter paragraphs"
                    );
                    for para in entry.paragraphs {
                        yield Ok(para);
                    }
                    return;
                }
                Ok(None) => {
                    tracing::debug!(
                        feed_id = %feed_id,
                        book_id = %book_id_owned,
                        chapter_id = %chapter_id_owned,
                        "cache miss, fetching from inner feed"
                    );
                }
                Err(e) => {
                    tracing::warn!(
                        feed_id = %feed_id,
                        book_id = %book_id_owned,
                        chapter_id = %chapter_id_owned,
                        error = %e,
                        "failed to read cache, clearing broken entry and falling back to inner feed"
                    );
                    if let Err(clear_error) = cache_store
                        .clear_chapter(&feed_id, &book_id_owned, &chapter_id_owned)
                        .await
                    {
                        tracing::warn!(
                            feed_id = %feed_id,
                            book_id = %book_id_owned,
                            chapter_id = %chapter_id_owned,
                            error = %clear_error,
                            "failed to clear broken chapter cache"
                        );
                    }
                }
            }

            let mut paragraphs = Vec::new();
            let mut stream = Box::pin(inner.paragraphs(&book_id_owned, &chapter_id_owned));

            while let Some(result) = stream.next().await {
                match result {
                    Ok(para) => {
                        paragraphs.push(para.clone());
                        yield Ok(para);
                    }
                    Err(e) => {
                        tracing::warn!(
                            feed_id = %feed_id,
                            book_id = %book_id_owned,
                            chapter_id = %chapter_id_owned,
                            error = %e,
                            "error fetching paragraphs, not caching"
                        );
                        yield Err(e);
                        return;
                    }
                }
            }

            let entry = ChapterCacheEntry::new(
                feed_id.clone(),
                book_id_owned.clone(),
                chapter_id_owned.clone(),
                paragraphs,
            );
            match cache_store.set_chapter(&entry).await {
                Ok(_) => {
                    tracing::debug!(
                        feed_id = %feed_id,
                        book_id = %book_id_owned,
                        chapter_id = %chapter_id_owned,
                        "successfully cached chapter paragraphs"
                    );
                }
                Err(e) => {
                    tracing::warn!(
                        feed_id = %feed_id,
                        book_id = %book_id_owned,
                        chapter_id = %chapter_id_owned,
                        error = %e,
                        "failed to cache chapter paragraphs, clearing chapter cache entry"
                    );
                    if let Err(clear_error) = cache_store
                        .clear_chapter(&feed_id, &book_id_owned, &chapter_id_owned)
                        .await
                    {
                        tracing::warn!(
                            feed_id = %feed_id,
                            book_id = %book_id_owned,
                            chapter_id = %chapter_id_owned,
                            error = %clear_error,
                            "failed to clear chapter cache after write failure"
                        );
                    }
                }
            }
        })
    }

    fn cached_chapters<'a>(&'a self, book_id: &'a str) -> FeedStream<'a, ChapterInfo> {
        let feed_id = self.inner.meta().id.clone();
        let book_id_owned = book_id.to_string();
        let cache_store = self.cache_store.clone();
        let inner = self.inner.clone();

        Box::pin(stream! {
            match cache_store.get_chapters(&feed_id, &book_id_owned).await {
                Ok(Some(entry)) => {
                    tracing::info!(
                        feed_id = %feed_id,
                        book_id = %book_id_owned,
                        chapters = entry.chapters.len(),
                        "cache hit for chapter list"
                    );
                    for chapter in entry.chapters {
                        yield Ok(chapter);
                    }
                    return;
                }
                Ok(None) => {
                    tracing::debug!(
                        feed_id = %feed_id,
                        book_id = %book_id_owned,
                        "chapter list cache miss, fetching from inner feed"
                    );
                }
                Err(e) => {
                    tracing::warn!(
                        feed_id = %feed_id,
                        book_id = %book_id_owned,
                        error = %e,
                        "failed to read chapter list cache, clearing broken cache and falling back to inner feed"
                    );
                    if let Err(clear_error) = cache_store.clear_chapters(&feed_id, &book_id_owned).await {
                        tracing::warn!(
                            feed_id = %feed_id,
                            book_id = %book_id_owned,
                            error = %clear_error,
                            "failed to clear broken chapter list cache"
                        );
                    }
                }
            }

            let mut chapters = Vec::new();
            let mut stream = Box::pin(inner.chapters(&book_id_owned));

            while let Some(result) = stream.next().await {
                match result {
                    Ok(chapter) => {
                        chapters.push(chapter.clone());
                        yield Ok(chapter);
                    }
                    Err(e) => {
                        tracing::warn!(
                            feed_id = %feed_id,
                            book_id = %book_id_owned,
                            error = %e,
                            "error fetching chapter list, not caching"
                        );
                        yield Err(e);
                        return;
                    }
                }
            }

            let entry = ChapterListCacheEntry::new(feed_id.clone(), book_id_owned.clone(), chapters);
            match cache_store.set_chapters(&entry).await {
                Ok(_) => {
                    tracing::debug!(
                        feed_id = %feed_id,
                        book_id = %book_id_owned,
                        "successfully cached chapter list"
                    );
                }
                Err(e) => {
                    tracing::warn!(
                        feed_id = %feed_id,
                        book_id = %book_id_owned,
                        error = %e,
                        "failed to cache chapter list, clearing chapter list cache entry"
                    );
                    if let Err(clear_error) = cache_store.clear_chapters(&feed_id, &book_id_owned).await {
                        tracing::warn!(
                            feed_id = %feed_id,
                            book_id = %book_id_owned,
                            error = %clear_error,
                            "failed to clear chapter list cache after write failure"
                        );
                    }
                }
            }
        })
    }
}

impl<F: Feed> Feed for CachedFeed<F> {
    fn search<'a>(&'a self, keyword: &'a str) -> FeedStream<'a, crate::model::SearchResult> {
        // Search results are not cached (may change frequently)
        self.inner.search(keyword)
    }

    async fn book_info(&self, id: &str) -> Result<crate::model::BookInfo> {
        // Book info is not cached (assume it's cheap to fetch or relatively static)
        self.inner.book_info(id).await
    }

    fn chapters<'a>(&'a self, book_id: &'a str) -> FeedStream<'a, crate::model::ChapterInfo> {
        self.cached_chapters(book_id)
    }

    fn paragraphs<'a>(&'a self, book_id: &'a str, chapter_id: &'a str) -> FeedStream<'a, Paragraph> {
        self.cached_paragraphs(book_id, chapter_id)
    }

    fn meta(&self) -> &FeedMeta {
        self.inner.meta()
    }
}

impl<F> FeedBookshelfSupport for CachedFeed<F>
where
    F: Feed + FeedBookshelfSupport,
{
    fn bookshelf_capabilities(&self) -> crate::bookshelf::BookshelfCapabilities {
        self.inner.bookshelf_capabilities()
    }
}

#[cfg(test)]
mod tests {
    // Note: Full integration tests for CachedFeed are complex due to the Feed trait.
    // The CacheStore is tested separately in storage.rs with concrete tests.
    // CachedFeed will be tested at the hub/actors level where concrete Feed types are used.
}
