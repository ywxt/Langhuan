use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Paginated result (internal implementation detail)
// ---------------------------------------------------------------------------

/// A page of results with an opaque cursor for fetching the next page.
///
/// This type is used internally by [`LuaFeed`] to drive pagination.  Callers
/// of the public [`Feed`] trait never see `Page` — they receive a stream of
/// individual items instead.
///
/// `next_cursor` is determined entirely by the Lua feed script:
/// - `None` means this is the last page.
/// - `Some(cursor)` is an opaque value passed back to the next `*_request`
///   call. It can be a page number, a URL, a token, a table — whatever the
///   script needs.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Page<T, C = String> {
    /// The items on this page.
    pub items: Vec<T>,
    /// An opaque cursor for the next page, or `None` if this is the last page.
    pub next_cursor: Option<C>,
}

// ---------------------------------------------------------------------------
// Domain models
// ---------------------------------------------------------------------------

/// A single search result returned by a feed.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResult {
    /// Unique identifier for the book within this feed.
    pub id: String,
    /// Title of the book.
    pub title: String,
    /// Author of the book.
    pub author: String,
    /// URL to a cover image, if available.
    #[serde(default)]
    pub cover_url: Option<String>,
    /// A short description or summary, if available.
    #[serde(default)]
    pub description: Option<String>,
}

impl SearchResult {
    pub fn id(&self) -> &str {
        &self.id
    }
}

/// Detailed information about a book.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BookInfo {
    /// Unique identifier for the book within this feed.
    pub id: String,
    /// Title of the book.
    pub title: String,
    /// Author of the book.
    pub author: String,
    /// URL to a cover image, if available.
    #[serde(default)]
    pub cover_url: Option<String>,
    /// A short description or summary, if available.
    #[serde(default)]
    pub description: Option<String>,
}

/// An entry in a book's table of contents.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChapterInfo {
    /// Unique identifier for the chapter within this feed.
    pub id: String,
    /// Title of the chapter.
    pub title: String,
}

impl ChapterInfo {
    pub fn id(&self) -> &str {
        &self.id
    }
}

/// A single content unit in a chapter, emitted as part of a paragraphs stream.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Paragraph {
    /// The chapter title (typically emitted first).
    Title { id: String, text: String },
    /// A text paragraph.
    Text { id: String, content: String },
    /// An image.
    Image {
        id: String,
        url: String,
        #[serde(default)]
        alt: Option<String>,
    },
}

impl Paragraph {
    pub fn id(&self) -> &str {
        match self {
            Paragraph::Title { id, .. }
            | Paragraph::Text { id, .. }
            | Paragraph::Image { id, .. } => id,
        }
    }
}
