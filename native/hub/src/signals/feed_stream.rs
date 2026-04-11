use rinf::{DartSignal, RustSignal, SignalPiece};
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Pull-based session signals (Dart → Rust)
// ---------------------------------------------------------------------------

/// Open a pull-based search session.
/// Rust spawns a background task that holds the `FeedStream` but does **not**
/// advance it until a [`PullNextRequest`] arrives.
#[derive(Deserialize, DartSignal)]
pub struct OpenSearchSession {
    pub session_id: String,
    pub feed_id: String,
    pub keyword: String,
}

/// Open a pull-based chapters session.
#[derive(Deserialize, DartSignal)]
pub struct OpenChaptersSession {
    pub session_id: String,
    pub feed_id: String,
    pub book_id: String,
}

/// Open a pull-based paragraphs (chapter content) session.
#[derive(Deserialize, DartSignal)]
pub struct OpenParagraphsSession {
    pub session_id: String,
    pub feed_id: String,
    pub book_id: String,
    pub chapter_id: String,
}

/// Pull the next item from an open session.
/// Rust calls `stream.next()` exactly once and replies with the corresponding
/// `Pull*Result` signal.
#[derive(Deserialize, DartSignal)]
pub struct PullNextRequest {
    pub session_id: String,
}

/// Close (and abort) an open session.
#[derive(Deserialize, DartSignal)]
pub struct CloseSessionRequest {
    pub session_id: String,
}

// ---------------------------------------------------------------------------
// Pull-based session signals (Rust → Dart)
// ---------------------------------------------------------------------------

/// Outcome of pulling the next search result.
#[derive(Serialize, SignalPiece)]
pub enum PullSearchOutcome {
    Item {
        id: String,
        title: String,
        author: String,
        cover_url: Option<String>,
        description: Option<String>,
    },
    End,
    Error {
        message: String,
    },
}

#[derive(Serialize, RustSignal)]
pub struct PullSearchResult {
    pub session_id: String,
    pub outcome: PullSearchOutcome,
}

/// Outcome of pulling the next chapter info.
#[derive(Serialize, SignalPiece)]
pub enum PullChapterOutcome {
    Item {
        id: String,
        title: String,
        index: u32,
    },
    End,
    Error {
        message: String,
    },
}

#[derive(Serialize, RustSignal)]
pub struct PullChapterResult {
    pub session_id: String,
    pub outcome: PullChapterOutcome,
}

/// Paragraph content types (shared by pull result).
#[derive(Serialize, SignalPiece)]
pub enum ParagraphContent {
    Title { text: String },
    Text { content: String },
    Image { url: String, alt: Option<String> },
}

/// Outcome of pulling the next paragraph.
#[derive(Serialize, SignalPiece)]
pub enum PullParagraphOutcome {
    Item { paragraph: ParagraphContent },
    End,
    Error { message: String },
}

#[derive(Serialize, RustSignal)]
pub struct PullParagraphResult {
    pub session_id: String,
    pub outcome: PullParagraphOutcome,
}

// ---------------------------------------------------------------------------
// Book info (unchanged — already request-response)
// ---------------------------------------------------------------------------

/// Request detailed information for a single book.
#[derive(Deserialize, DartSignal)]
pub struct BookInfoRequest {
    pub feed_id: String,
    pub book_id: String,
}

#[derive(Serialize, SignalPiece)]
pub enum BookInfoOutcome {
    Success {
        id: String,
        title: String,
        author: String,
        cover_url: Option<String>,
        description: Option<String>,
    },
    Error {
        message: String,
    },
}

#[derive(Serialize, RustSignal)]
pub struct BookInfoResult {
    pub outcome: BookInfoOutcome,
}

// ---------------------------------------------------------------------------
// Session open acknowledgement (Rust → Dart)
// ---------------------------------------------------------------------------

/// Outcome of opening a session.
#[derive(Serialize, SignalPiece)]
pub enum OpenSessionOutcome {
    /// Session created successfully, ready for [`PullNextRequest`].
    Ok,
    /// Failed to open (e.g. feed not found).
    Error { message: String },
}

#[derive(Serialize, RustSignal)]
pub struct OpenSessionResult {
    pub session_id: String,
    pub outcome: OpenSessionOutcome,
}
