//! [`FeedActor`] — manages feed stream requests from Dart.
//!
//! # Responsibilities
//! - Accept `SearchRequest`, `ChaptersRequest`, `ChapterContentRequest` from Dart.
//! - Launch each request as an independent async task identified by `request_id`.
//! - Support concurrent in-flight requests (multiple parallel streams).
//! - Accept `FeedCancelRequest` from Dart and abort the matching task.
//! - Emit per-item signals and a terminal `FeedStreamEnd` for every request.
//!
//! # Retry
//! Retry with exponential back-off is handled inside `langhuan::LuaFeed`.
//! The `FeedStreamEnd.retried_count` field reflects the total retry count
//! communicated through the stream items (currently always 0 since retries
//! are transparent to the actor — extend if fine-grained visibility is needed).

use std::collections::HashMap;
use std::sync::Arc;

use langhuan::feed::Feed;
use langhuan::script::engine::ScriptEngine;
use rinf::RustSignal;
use tokio::task::JoinHandle;
use tokio_stream::StreamExt;
use tokio_util::sync::CancellationToken;

use crate::signals::{
    ChapterContentItem, ChapterContentRequest, ChapterInfoItem, ChaptersRequest, FeedCancelRequest,
    FeedStreamEnd, FeedStreamStatus, SearchRequest, SearchResultItem,
};

// ---------------------------------------------------------------------------
// FeedActor
// ---------------------------------------------------------------------------

/// Manages the lifecycle of all in-flight feed streams.
pub struct FeedActor {
    engine: Arc<ScriptEngine>,
    /// Live tasks keyed by `request_id`.  Each entry holds a cancellation
    /// token (to request cooperative shutdown) and a join handle (for cleanup).
    tasks: HashMap<String, (CancellationToken, JoinHandle<()>)>,
}

impl FeedActor {
    pub fn new(engine: ScriptEngine) -> Self {
        Self {
            engine: Arc::new(engine),
            tasks: HashMap::new(),
        }
    }

    // -----------------------------------------------------------------------
    // Entry-point: called from the actor's run loop
    // -----------------------------------------------------------------------

    /// Handle an incoming `SearchRequest` from Dart.
    pub fn handle_search(&mut self, req: SearchRequest) {
        let request_id = req.request_id.clone();
        let token = CancellationToken::new();
        let engine = Arc::clone(&self.engine);
        let child_token = token.clone();

        let handle = tokio::spawn(async move {
            run_search(engine, req, child_token).await;
        });

        self.register_task(request_id, token, handle);
    }

    /// Handle an incoming `ChaptersRequest` from Dart.
    pub fn handle_chapters(&mut self, req: ChaptersRequest) {
        let request_id = req.request_id.clone();
        let token = CancellationToken::new();
        let engine = Arc::clone(&self.engine);
        let child_token = token.clone();

        let handle = tokio::spawn(async move {
            run_chapters(engine, req, child_token).await;
        });

        self.register_task(request_id, token, handle);
    }

    /// Handle an incoming `ChapterContentRequest` from Dart.
    pub fn handle_chapter_content(&mut self, req: ChapterContentRequest) {
        let request_id = req.request_id.clone();
        let token = CancellationToken::new();
        let engine = Arc::clone(&self.engine);
        let child_token = token.clone();

        let handle = tokio::spawn(async move {
            run_chapter_content(engine, req, child_token).await;
        });

        self.register_task(request_id, token, handle);
    }

    /// Cancel the task identified by `request_id`, if it is still running.
    pub fn handle_cancel(&mut self, req: FeedCancelRequest) {
        if let Some((token, _handle)) = self.tasks.remove(&req.request_id) {
            // Signal cooperative cancellation — the task will emit a
            // `FeedStreamEnd { status: "cancelled" }` and exit.
            token.cancel();
        }
    }

    // -----------------------------------------------------------------------
    // Internal helpers
    // -----------------------------------------------------------------------

    fn register_task(
        &mut self,
        request_id: String,
        token: CancellationToken,
        handle: JoinHandle<()>,
    ) {
        // If a previous task with the same id somehow exists, cancel it first.
        if let Some((old_token, _)) = self.tasks.remove(&request_id) {
            old_token.cancel();
        }
        self.tasks.insert(request_id, (token, handle));
    }

    /// Remove tasks that have already finished (keep the map from growing).
    /// Call this periodically or after receiving a request.
    pub fn cleanup_finished(&mut self) {
        self.tasks.retain(|_, (_, handle)| !handle.is_finished());
    }
}

// ---------------------------------------------------------------------------
// Task implementations (run inside `tokio::spawn`)
// ---------------------------------------------------------------------------

/// Emit a [`FeedStreamEnd`] signal with the given status and optional error.
fn emit_end(request_id: &str, status: FeedStreamStatus, error: Option<String>) {
    FeedStreamEnd {
        request_id: request_id.to_owned(),
        status,
        error,
        retried_count: 0,
    }
    .send_signal_to_dart();
}

/// Generic stream driver shared by all three `run_*` functions.
///
/// Drives `stream` to completion, calling `emit_item` for every successful
/// item.  Handles cancellation and per-item errors uniformly.
async fn run_stream<T, F>(
    request_id: String,
    mut stream: langhuan::feed::FeedStream<'_, T>,
    token: CancellationToken,
    mut emit_item: F,
) where
    F: FnMut(T),
{
    loop {
        tokio::select! {
            biased;
            _ = token.cancelled() => {
                emit_end(&request_id, FeedStreamStatus::Cancelled, None);
                return;
            }
            item = stream.next() => {
                match item {
                    None => break,
                    Some(Ok(value)) => emit_item(value),
                    Some(Err(e)) => {
                        emit_end(&request_id, FeedStreamStatus::Failed, Some(e.to_string()));
                        return;
                    }
                }
            }
        }
    }
    emit_end(&request_id, FeedStreamStatus::Completed, None);
}

/// Load the feed script identified by `feed_id` from the engine.
///
/// Currently a placeholder that expects a pre-registered script path
/// (in a real app you would load from storage/assets).  Returns `None`
/// and emits a `failed` end signal if the feed cannot be loaded.
fn load_feed(
    engine: &ScriptEngine,
    feed_id: &str,
    request_id: &str,
) -> Option<langhuan::script::lua_feed::LuaFeed> {
    // TODO: Replace with real script loading from disk / asset store.
    // For now, treat `feed_id` as a file path for development purposes.
    match std::fs::read_to_string(feed_id) {
        Ok(script) => match engine.load_feed(&script) {
            Ok(feed) => Some(feed),
            Err(e) => {
                emit_end(request_id, FeedStreamStatus::Failed, Some(e.to_string()));
                None
            }
        },
        Err(e) => {
            emit_end(
                request_id,
                FeedStreamStatus::Failed,
                Some(format!("cannot load feed script '{}': {}", feed_id, e)),
            );
            None
        }
    }
}

async fn run_search(engine: Arc<ScriptEngine>, req: SearchRequest, token: CancellationToken) {
    let Some(feed) = load_feed(&engine, &req.feed_id, &req.request_id) else {
        return;
    };
    let stream = feed.search(&req.keyword);
    run_stream(req.request_id.clone(), stream, token, |result| {
        SearchResultItem {
            request_id: req.request_id.clone(),
            id: result.id,
            title: result.title,
            author: result.author,
            cover_url: result.cover_url,
            description: result.description,
        }
        .send_signal_to_dart();
    })
    .await;
}

async fn run_chapters(engine: Arc<ScriptEngine>, req: ChaptersRequest, token: CancellationToken) {
    let Some(feed) = load_feed(&engine, &req.feed_id, &req.request_id) else {
        return;
    };
    let stream = feed.chapters(&req.book_id);
    run_stream(req.request_id.clone(), stream, token, |chapter| {
        ChapterInfoItem {
            request_id: req.request_id.clone(),
            id: chapter.id,
            title: chapter.title,
            index: chapter.index,
        }
        .send_signal_to_dart();
    })
    .await;
}

async fn run_chapter_content(
    engine: Arc<ScriptEngine>,
    req: ChapterContentRequest,
    token: CancellationToken,
) {
    let Some(feed) = load_feed(&engine, &req.feed_id, &req.request_id) else {
        return;
    };
    let stream = feed.chapter_content(&req.chapter_id);
    run_stream(req.request_id.clone(), stream, token, |content| {
        ChapterContentItem {
            request_id: req.request_id.clone(),
            title: content.title,
            paragraphs: content.paragraphs,
        }
        .send_signal_to_dart();
    })
    .await;
}
