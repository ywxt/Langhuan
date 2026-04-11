//! [`StreamActor`] — manages pull-based feed sessions from Dart.
//!
//! `PullNextRequest` is the only operation that advances feed streams.

use std::collections::HashMap;
use std::sync::Arc;

use async_trait::async_trait;
use langhuan::cache::CachedFeed;
use langhuan::feed::Feed;
use langhuan::model::{ChapterInfo, Paragraph, SearchResult};
use langhuan::script::lua::LuaFeed;
use messages::prelude::{Actor, Address, Context, Notifiable};
use rinf::{DartSignal, RustSignal};
use tokio::sync::{mpsc, oneshot};
use tokio::task::{AbortHandle, JoinSet};
use tokio_stream::StreamExt;

use crate::localize_error;
use crate::signals::{
    BookInfoOutcome, BookInfoRequest, BookInfoResult, CloseSessionRequest, OpenChaptersSession,
    OpenParagraphsSession, OpenSearchSession, OpenSessionOutcome, OpenSessionResult,
    ParagraphContent, PullChapterOutcome, PullChapterResult, PullNextRequest,
    PullParagraphOutcome, PullParagraphResult, PullSearchOutcome, PullSearchResult,
};

use super::registry_actor::{GetFeed, RegistryActor};

#[derive(Clone, Copy)]
enum SessionType {
    Search,
    Chapters,
    Paragraphs,
}

enum PullTrigger {
    Next(oneshot::Sender<PullReply>),
}

enum PullReply {
    SearchItem(SearchResult),
    ChapterItem(ChapterInfo),
    ParagraphItem(Paragraph),
    End,
    Error { message: String },
}

struct PullSession {
    session_type: SessionType,
    trigger_tx: mpsc::Sender<PullTrigger>,
    abort_handle: AbortHandle,
}

/// Manages the lifecycle of all in-flight pull sessions.
pub struct StreamActor {
    registry_addr: Address<RegistryActor>,
    sessions: HashMap<String, PullSession>,
    _owned_tasks: JoinSet<()>,
}

impl Actor for StreamActor {}

impl StreamActor {
    pub fn new(self_addr: Address<Self>, registry_addr: Address<RegistryActor>) -> Self {
        let mut _owned_tasks = JoinSet::new();
        _owned_tasks.spawn(Self::listen_to_open_search(self_addr.clone()));
        _owned_tasks.spawn(Self::listen_to_open_chapters(self_addr.clone()));
        _owned_tasks.spawn(Self::listen_to_open_paragraphs(self_addr.clone()));
        _owned_tasks.spawn(Self::listen_to_pull_next(self_addr.clone()));
        _owned_tasks.spawn(Self::listen_to_close(self_addr.clone()));
        _owned_tasks.spawn(Self::listen_to_book_info(self_addr));

        Self {
            registry_addr,
            sessions: HashMap::new(),
            _owned_tasks,
        }
    }

    async fn do_open_search(&mut self, req: OpenSearchSession) {
        tracing::debug!(session_id = %req.session_id, feed_id = %req.feed_id, "open search session");

        let feed = match self.resolve_feed_result(&req.feed_id).await {
            Ok(feed) => feed,
            Err(message) => {
                OpenSessionResult {
                    session_id: req.session_id,
                    outcome: OpenSessionOutcome::Error { message },
                }
                .send_signal_to_dart();
                return;
            }
        };

        let session_id = req.session_id;
        self.replace_existing_session(&session_id);

        let (trigger_tx, mut trigger_rx) = mpsc::channel::<PullTrigger>(1);
        let task = tokio::spawn(async move {
            let mut stream = feed.search(&req.keyword);
            while let Some(PullTrigger::Next(reply_tx)) = trigger_rx.recv().await {
                let reply = match stream.next().await {
                    Some(Ok(item)) => PullReply::SearchItem(item),
                    Some(Err(e)) => PullReply::Error {
                        message: localize_error(&e),
                    },
                    None => PullReply::End,
                };
                let terminal = matches!(reply, PullReply::End | PullReply::Error { .. });
                let _ = reply_tx.send(reply);
                if terminal {
                    break;
                }
            }
        });

        self.sessions.insert(
            session_id.clone(),
            PullSession {
                session_type: SessionType::Search,
                trigger_tx,
                abort_handle: task.abort_handle(),
            },
        );

        OpenSessionResult {
            session_id,
            outcome: OpenSessionOutcome::Ok,
        }
        .send_signal_to_dart();
    }

    async fn do_open_chapters(&mut self, req: OpenChaptersSession) {
        tracing::debug!(session_id = %req.session_id, feed_id = %req.feed_id, book_id = %req.book_id, "open chapters session");

        let feed = match self.resolve_feed_result(&req.feed_id).await {
            Ok(feed) => feed,
            Err(message) => {
                OpenSessionResult {
                    session_id: req.session_id,
                    outcome: OpenSessionOutcome::Error { message },
                }
                .send_signal_to_dart();
                return;
            }
        };

        let session_id = req.session_id;
        self.replace_existing_session(&session_id);

        let (trigger_tx, mut trigger_rx) = mpsc::channel::<PullTrigger>(1);
        let task = tokio::spawn(async move {
            let mut stream = feed.chapters(&req.book_id);
            while let Some(PullTrigger::Next(reply_tx)) = trigger_rx.recv().await {
                let reply = match stream.next().await {
                    Some(Ok(item)) => PullReply::ChapterItem(item),
                    Some(Err(e)) => PullReply::Error {
                        message: localize_error(&e),
                    },
                    None => PullReply::End,
                };
                let terminal = matches!(reply, PullReply::End | PullReply::Error { .. });
                let _ = reply_tx.send(reply);
                if terminal {
                    break;
                }
            }
        });

        self.sessions.insert(
            session_id.clone(),
            PullSession {
                session_type: SessionType::Chapters,
                trigger_tx,
                abort_handle: task.abort_handle(),
            },
        );

        OpenSessionResult {
            session_id,
            outcome: OpenSessionOutcome::Ok,
        }
        .send_signal_to_dart();
    }

    async fn do_open_paragraphs(&mut self, req: OpenParagraphsSession) {
        tracing::debug!(session_id = %req.session_id, feed_id = %req.feed_id, book_id = %req.book_id, chapter_id = %req.chapter_id, "open paragraphs session");

        let feed = match self.resolve_feed_result(&req.feed_id).await {
            Ok(feed) => feed,
            Err(message) => {
                OpenSessionResult {
                    session_id: req.session_id,
                    outcome: OpenSessionOutcome::Error { message },
                }
                .send_signal_to_dart();
                return;
            }
        };

        let session_id = req.session_id;
        self.replace_existing_session(&session_id);

        let (trigger_tx, mut trigger_rx) = mpsc::channel::<PullTrigger>(1);
        let task = tokio::spawn(async move {
            let mut stream = feed.paragraphs(&req.book_id, &req.chapter_id);
            while let Some(PullTrigger::Next(reply_tx)) = trigger_rx.recv().await {
                let reply = match stream.next().await {
                    Some(Ok(item)) => PullReply::ParagraphItem(item),
                    Some(Err(e)) => PullReply::Error {
                        message: localize_error(&e),
                    },
                    None => PullReply::End,
                };
                let terminal = matches!(reply, PullReply::End | PullReply::Error { .. });
                let _ = reply_tx.send(reply);
                if terminal {
                    break;
                }
            }
        });

        self.sessions.insert(
            session_id.clone(),
            PullSession {
                session_type: SessionType::Paragraphs,
                trigger_tx,
                abort_handle: task.abort_handle(),
            },
        );

        OpenSessionResult {
            session_id,
            outcome: OpenSessionOutcome::Ok,
        }
        .send_signal_to_dart();
    }

    async fn do_pull_next(&mut self, req: PullNextRequest) {
        tracing::debug!(session_id = %req.session_id, "pull next");

        let Some(session) = self.sessions.get(&req.session_id) else {
            return;
        };

        let session_type = session.session_type;
        let trigger_tx = session.trigger_tx.clone();

        let (reply_tx, reply_rx) = oneshot::channel::<PullReply>();
        if trigger_tx.send(PullTrigger::Next(reply_tx)).await.is_err() {
            self.sessions.remove(&req.session_id);
            return;
        }

        let reply = match reply_rx.await {
            Ok(reply) => reply,
            Err(_) => {
                self.sessions.remove(&req.session_id);
                return;
            }
        };

        let terminal = matches!(reply, PullReply::End | PullReply::Error { .. });
        self.emit_pull_reply(&req.session_id, session_type, reply);
        if terminal {
            self.sessions.remove(&req.session_id);
        }
    }

    fn do_close_session(&mut self, req: CloseSessionRequest) {
        tracing::debug!(session_id = %req.session_id, "close session");
        if let Some(session) = self.sessions.remove(&req.session_id) {
            session.abort_handle.abort();
        }
    }

    async fn do_book_info(&mut self, req: BookInfoRequest) -> BookInfoResult {
        tracing::debug!(feed_id = %req.feed_id, book_id = %req.book_id, "book info");
        match self.resolve_feed_result(&req.feed_id).await {
            Ok(feed) => run_book_info(&feed, req).await,
            Err(message) => BookInfoResult {
                outcome: BookInfoOutcome::Error { message },
            },
        }
    }

    fn replace_existing_session(&mut self, session_id: &str) {
        if let Some(existing) = self.sessions.remove(session_id) {
            existing.abort_handle.abort();
        }
    }

    fn emit_pull_reply(&self, session_id: &str, session_type: SessionType, reply: PullReply) {
        match (session_type, reply) {
            (SessionType::Search, PullReply::SearchItem(item)) => PullSearchResult {
                session_id: session_id.to_owned(),
                outcome: PullSearchOutcome::Item {
                    id: item.id,
                    title: item.title,
                    author: item.author,
                    cover_url: item.cover_url,
                    description: item.description,
                },
            }
            .send_signal_to_dart(),
            (SessionType::Search, PullReply::End) => PullSearchResult {
                session_id: session_id.to_owned(),
                outcome: PullSearchOutcome::End,
            }
            .send_signal_to_dart(),
            (SessionType::Search, PullReply::Error { message }) => PullSearchResult {
                session_id: session_id.to_owned(),
                outcome: PullSearchOutcome::Error { message },
            }
            .send_signal_to_dart(),

            (SessionType::Chapters, PullReply::ChapterItem(item)) => PullChapterResult {
                session_id: session_id.to_owned(),
                outcome: PullChapterOutcome::Item {
                    id: item.id,
                    title: item.title,
                    index: item.index,
                },
            }
            .send_signal_to_dart(),
            (SessionType::Chapters, PullReply::End) => PullChapterResult {
                session_id: session_id.to_owned(),
                outcome: PullChapterOutcome::End,
            }
            .send_signal_to_dart(),
            (SessionType::Chapters, PullReply::Error { message }) => PullChapterResult {
                session_id: session_id.to_owned(),
                outcome: PullChapterOutcome::Error { message },
            }
            .send_signal_to_dart(),

            (SessionType::Paragraphs, PullReply::ParagraphItem(paragraph)) => {
                let paragraph = match paragraph {
                    Paragraph::Title { text } => ParagraphContent::Title { text },
                    Paragraph::Text { content } => ParagraphContent::Text { content },
                    Paragraph::Image { url, alt } => ParagraphContent::Image { url, alt },
                };
                PullParagraphResult {
                    session_id: session_id.to_owned(),
                    outcome: PullParagraphOutcome::Item { paragraph },
                }
                .send_signal_to_dart();
            }
            (SessionType::Paragraphs, PullReply::End) => PullParagraphResult {
                session_id: session_id.to_owned(),
                outcome: PullParagraphOutcome::End,
            }
            .send_signal_to_dart(),
            (SessionType::Paragraphs, PullReply::Error { message }) => PullParagraphResult {
                session_id: session_id.to_owned(),
                outcome: PullParagraphOutcome::Error { message },
            }
            .send_signal_to_dart(),

            (SessionType::Search, PullReply::ChapterItem(_))
            | (SessionType::Search, PullReply::ParagraphItem(_))
            | (SessionType::Chapters, PullReply::SearchItem(_))
            | (SessionType::Chapters, PullReply::ParagraphItem(_))
            | (SessionType::Paragraphs, PullReply::SearchItem(_))
            | (SessionType::Paragraphs, PullReply::ChapterItem(_)) => {}
        }
    }

    async fn resolve_feed_result(
        &mut self,
        feed_id: &str,
    ) -> Result<Arc<CachedFeed<LuaFeed>>, String> {
        let result = self
            .registry_addr
            .send(GetFeed {
                feed_id: feed_id.to_owned(),
            })
            .await;

        match result {
            Ok(Ok(feed)) => Ok(feed),
            Ok(Err(e)) => Err(e.to_string()),
            Err(e) => Err(format!("internal error: {e}")),
        }
    }
}

#[async_trait]
impl Notifiable<OpenSearchSession> for StreamActor {
    async fn notify(&mut self, msg: OpenSearchSession, _: &Context<Self>) {
        self.do_open_search(msg).await;
    }
}

#[async_trait]
impl Notifiable<OpenChaptersSession> for StreamActor {
    async fn notify(&mut self, msg: OpenChaptersSession, _: &Context<Self>) {
        self.do_open_chapters(msg).await;
    }
}

#[async_trait]
impl Notifiable<OpenParagraphsSession> for StreamActor {
    async fn notify(&mut self, msg: OpenParagraphsSession, _: &Context<Self>) {
        self.do_open_paragraphs(msg).await;
    }
}

#[async_trait]
impl Notifiable<PullNextRequest> for StreamActor {
    async fn notify(&mut self, msg: PullNextRequest, _: &Context<Self>) {
        self.do_pull_next(msg).await;
    }
}

#[async_trait]
impl Notifiable<CloseSessionRequest> for StreamActor {
    async fn notify(&mut self, msg: CloseSessionRequest, _: &Context<Self>) {
        self.do_close_session(msg);
    }
}

#[async_trait]
impl Notifiable<BookInfoRequest> for StreamActor {
    async fn notify(&mut self, msg: BookInfoRequest, _: &Context<Self>) {
        self.do_book_info(msg).await.send_signal_to_dart();
    }
}

impl StreamActor {
    async fn listen_to_open_search(mut self_addr: Address<Self>) {
        let receiver = OpenSearchSession::get_dart_signal_receiver();
        while let Some(signal_pack) = receiver.recv().await {
            let _ = self_addr.notify(signal_pack.message).await;
        }
    }

    async fn listen_to_open_chapters(mut self_addr: Address<Self>) {
        let receiver = OpenChaptersSession::get_dart_signal_receiver();
        while let Some(signal_pack) = receiver.recv().await {
            let _ = self_addr.notify(signal_pack.message).await;
        }
    }

    async fn listen_to_open_paragraphs(mut self_addr: Address<Self>) {
        let receiver = OpenParagraphsSession::get_dart_signal_receiver();
        while let Some(signal_pack) = receiver.recv().await {
            let _ = self_addr.notify(signal_pack.message).await;
        }
    }

    async fn listen_to_pull_next(mut self_addr: Address<Self>) {
        let receiver = PullNextRequest::get_dart_signal_receiver();
        while let Some(signal_pack) = receiver.recv().await {
            let _ = self_addr.notify(signal_pack.message).await;
        }
    }

    async fn listen_to_close(mut self_addr: Address<Self>) {
        let receiver = CloseSessionRequest::get_dart_signal_receiver();
        while let Some(signal_pack) = receiver.recv().await {
            let _ = self_addr.notify(signal_pack.message).await;
        }
    }

    async fn listen_to_book_info(mut self_addr: Address<Self>) {
        let receiver = BookInfoRequest::get_dart_signal_receiver();
        while let Some(signal_pack) = receiver.recv().await {
            let _ = self_addr.notify(signal_pack.message).await;
        }
    }
}

async fn run_book_info(feed: &CachedFeed<LuaFeed>, req: BookInfoRequest) -> BookInfoResult {
    let outcome = match feed.book_info(&req.book_id).await {
        Ok(info) => BookInfoOutcome::Success {
            id: info.id,
            title: info.title,
            author: info.author,
            cover_url: info.cover_url,
            description: info.description,
        },
        Err(e) => BookInfoOutcome::Error {
            message: localize_error(&e),
        },
    };

    BookInfoResult { outcome }
}
