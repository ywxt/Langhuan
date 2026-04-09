use std::path::{Path, PathBuf};
use std::sync::Arc;

use async_trait::async_trait;
use langhuan::auth::AuthStore;
use langhuan::cache::CachedFeed;
use langhuan::feed::{AuthPageContext, AuthStatus, CookieEntry as FeedCookieEntry, FeedAuthFlow};
use langhuan::script::lua::LuaFeed;
use messages::prelude::{Actor, Address, Context, Handler, Notifiable};
use rinf::{DartSignal, RustSignal};
use tokio::task::JoinSet;

use crate::localize_error;
use crate::signals::{
    FeedAuthCapabilityOutcome, FeedAuthCapabilityRequest, FeedAuthCapabilityResult,
    FeedAuthClearOutcome, FeedAuthClearRequest, FeedAuthClearResult, FeedAuthEntryOutcome,
    FeedAuthEntryRequest, FeedAuthEntryResult, FeedAuthStatusOutcome, FeedAuthStatusRequest,
    FeedAuthStatusResult, FeedAuthSubmitPageOutcome, FeedAuthSubmitPageRequest,
    FeedAuthSubmitPageResult,
};

use super::app_data_actor::InitializeAppDataDirectory;
use super::registry_actor::{GetFeed, GetFeedIds, RegistryActor};

/// Dedicated actor for feed auth/login responsibilities.
pub struct LoginActor {
    registry_addr: Address<RegistryActor>,
    auth_dir: Option<PathBuf>,
    auth_store: Option<AuthStore>,
    _owned_tasks: JoinSet<()>,
}

impl Actor for LoginActor {}

impl LoginActor {
    pub fn new(self_addr: Address<Self>, registry_addr: Address<RegistryActor>) -> Self {
        let mut _owned_tasks = JoinSet::new();
        _owned_tasks.spawn(Self::listen_to_auth_capability(self_addr.clone()));
        _owned_tasks.spawn(Self::listen_to_auth_entry(self_addr.clone()));
        _owned_tasks.spawn(Self::listen_to_auth_submit_page(self_addr.clone()));
        _owned_tasks.spawn(Self::listen_to_auth_status(self_addr.clone()));
        _owned_tasks.spawn(Self::listen_to_auth_clear(self_addr));

        Self {
            registry_addr,
            auth_dir: None,
            auth_store: None,
            _owned_tasks,
        }
    }

    async fn initialize_app_data_directory(&mut self, path: &str) -> Result<(), String> {
        if self.auth_dir.is_some() {
            return Err(t!("error.registry_reload_not_supported").to_string());
        }

        let base_dir = Path::new(path);
        let auth_dir = base_dir.join("auth");

        tokio::fs::create_dir_all(&auth_dir)
            .await
            .map_err(|e| e.to_string())?;

        self.auth_store = Some(AuthStore::open(auth_dir.clone()).await.map_err(|e| localize_error(&e))?);
        self.auth_dir = Some(auth_dir);

        self.hydrate_all_feeds().await?;
        Ok(())
    }

    async fn hydrate_all_feeds(&mut self) -> Result<(), String> {
        let feed_ids = match self.registry_addr.send(GetFeedIds).await {
            Ok(Ok(ids)) => ids,
            Ok(Err(err)) => return Err(err.to_string()),
            Err(err) => return Err(format!("internal error: {err}")),
        };

        for feed_id in feed_ids {
            let feed = self.resolve_feed(&feed_id).await?;
            self.hydrate_feed_auth(&feed_id, &feed).await?;
        }

        Ok(())
    }

    async fn resolve_feed(&mut self, feed_id: &str) -> Result<Arc<CachedFeed<LuaFeed>>, String> {
        match self
            .registry_addr
            .send(GetFeed {
                feed_id: feed_id.to_owned(),
            })
            .await
        {
            Ok(Ok(feed)) => Ok(feed),
            Ok(Err(err)) => Err(err.to_string()),
            Err(err) => Err(format!("internal error: {err}")),
        }
    }

    fn auth_store(&self) -> Result<&AuthStore, String> {
        self.auth_store
            .as_ref()
            .ok_or_else(|| t!("error.app_data_dir_not_set").to_string())
    }

    fn auth_store_mut(&mut self) -> Result<&mut AuthStore, String> {
        self.auth_store
            .as_mut()
            .ok_or_else(|| t!("error.app_data_dir_not_set").to_string())
    }

    async fn hydrate_feed_auth(
        &self,
        feed_id: &str,
        feed: &CachedFeed<LuaFeed>,
    ) -> Result<(), String> {
        let Some(support) = feed.supports_auth() else {
            return Ok(());
        };

        let auth_store = self.auth_store()?;
        let auth_info = auth_store
            .get_auth_info(feed_id)
            .await
            .map_err(|e| localize_error(&e))?;
        feed.set_auth_info(&support, auth_info)
            .map_err(|e| localize_error(&e))
    }

    async fn do_auth_capability(&mut self, req: FeedAuthCapabilityRequest) -> FeedAuthCapabilityResult {
        let outcome = match self.resolve_feed(&req.feed_id).await {
            Ok(feed) => {
                if feed.supports_auth().is_some() {
                    FeedAuthCapabilityOutcome::Supported
                } else {
                    FeedAuthCapabilityOutcome::Unsupported
                }
            }
            Err(message) => FeedAuthCapabilityOutcome::Error { message },
        };

        FeedAuthCapabilityResult {
            request_id: req.request_id,
            outcome,
        }
    }

    async fn do_auth_entry(&mut self, req: FeedAuthEntryRequest) -> FeedAuthEntryResult {
        let outcome = match self.resolve_feed(&req.feed_id).await {
            Ok(feed) => match feed.supports_auth() {
                Some(support) => match feed.auth_entry(&support) {
                    Ok(entry) => FeedAuthEntryOutcome::Success {
                    url: entry.url,
                    title: entry.title,
                },
                    Err(e) => FeedAuthEntryOutcome::Error {
                        message: localize_error(&e),
                    },
                },
                None => FeedAuthEntryOutcome::Unsupported,
            },
            Err(message) => FeedAuthEntryOutcome::Error { message },
        };

        FeedAuthEntryResult {
            request_id: req.request_id,
            outcome,
        }
    }

    async fn do_auth_submit_page(&mut self, req: FeedAuthSubmitPageRequest) -> FeedAuthSubmitPageResult {
        let outcome = match self.resolve_feed(&req.feed_id).await {
            Ok(feed) => {
                let Some(support) = feed.supports_auth() else {
                    return FeedAuthSubmitPageResult {
                        request_id: req.request_id,
                        outcome: FeedAuthSubmitPageOutcome::Unsupported,
                    };
                };

                let page = AuthPageContext {
                    current_url: req.current_url,
                    response: req.response.into(),
                    response_headers: req.response_headers,
                    cookies: req
                        .cookies
                        .into_iter()
                        .map(|item| FeedCookieEntry {
                            name: item.name,
                            value: item.value,
                            domain: item.domain,
                            path: item.path,
                            expires: item.expires,
                            secure: item.secure,
                            http_only: item.http_only,
                            same_site: item.same_site,
                        })
                        .collect(),
                };

                match feed.parse_auth(&support, &page) {
                    Ok(auth_info) => {
                        let store = match self.auth_store_mut() {
                            Ok(store) => store,
                            Err(message) => {
                                return FeedAuthSubmitPageResult {
                                    request_id: req.request_id,
                                    outcome: FeedAuthSubmitPageOutcome::Error { message },
                                };
                            }
                        };

                        match store.set_auth_info(&req.feed_id, auth_info.clone()).await {
                            Ok(()) => match feed.set_auth_info(&support, Some(auth_info)) {
                                Ok(()) => FeedAuthSubmitPageOutcome::Success,
                                Err(e) => FeedAuthSubmitPageOutcome::Error {
                                    message: localize_error(&e),
                                },
                            },
                            Err(e) => FeedAuthSubmitPageOutcome::Error {
                                message: localize_error(&e),
                            },
                        }
                    }
                    Err(e) => FeedAuthSubmitPageOutcome::Error {
                        message: localize_error(&e),
                    },
                }
            }
            Err(message) => FeedAuthSubmitPageOutcome::Error { message },
        };

        FeedAuthSubmitPageResult {
            request_id: req.request_id,
            outcome,
        }
    }

    async fn do_auth_status(&mut self, req: FeedAuthStatusRequest) -> FeedAuthStatusResult {
        let outcome = match self.resolve_feed(&req.feed_id).await {
            Ok(feed) => {
                if let Err(message) = self.hydrate_feed_auth(&req.feed_id, &feed).await {
                    FeedAuthStatusOutcome::Error { message }
                } else {
                    match feed.supports_auth() {
                        Some(support) => match feed.auth_status(&support).await {
                            Ok(AuthStatus::LoggedIn) => FeedAuthStatusOutcome::LoggedIn,
                            Ok(AuthStatus::Expired) => FeedAuthStatusOutcome::Expired,
                            Ok(AuthStatus::LoggedOut) => FeedAuthStatusOutcome::LoggedOut,
                            Err(e) => FeedAuthStatusOutcome::Error {
                                message: localize_error(&e),
                            },
                        },
                        None => FeedAuthStatusOutcome::Error {
                            message: "feed auth is not supported".to_string(),
                        },
                    }
                }
            }
            Err(message) => FeedAuthStatusOutcome::Error { message },
        };

        FeedAuthStatusResult {
            request_id: req.request_id,
            outcome,
        }
    }

    async fn do_auth_clear(&mut self, req: FeedAuthClearRequest) -> FeedAuthClearResult {
        let outcome = match self.resolve_feed(&req.feed_id).await {
            Ok(feed) => {
                let Some(support) = feed.supports_auth() else {
                    return FeedAuthClearResult {
                        request_id: req.request_id,
                        outcome: FeedAuthClearOutcome::Success,
                    };
                };

                let store = match self.auth_store_mut() {
                    Ok(store) => store,
                    Err(message) => {
                        return FeedAuthClearResult {
                            request_id: req.request_id,
                            outcome: FeedAuthClearOutcome::Error { message },
                        };
                    }
                };

                match store.clear_auth_info(&req.feed_id).await {
                    Ok(()) => match feed.set_auth_info(&support, None) {
                        Ok(()) => FeedAuthClearOutcome::Success,
                        Err(e) => FeedAuthClearOutcome::Error {
                            message: localize_error(&e),
                        },
                    },
                    Err(e) => FeedAuthClearOutcome::Error {
                        message: localize_error(&e),
                    },
                }
            }
            Err(message) => FeedAuthClearOutcome::Error { message },
        };

        FeedAuthClearResult {
            request_id: req.request_id,
            outcome,
        }
    }

    async fn listen_to_auth_capability(mut self_addr: Address<Self>) {
        let receiver = FeedAuthCapabilityRequest::get_dart_signal_receiver();
        while let Some(signal_pack) = receiver.recv().await {
            let _ = self_addr.notify(signal_pack.message).await;
        }
    }

    async fn listen_to_auth_entry(mut self_addr: Address<Self>) {
        let receiver = FeedAuthEntryRequest::get_dart_signal_receiver();
        while let Some(signal_pack) = receiver.recv().await {
            let _ = self_addr.notify(signal_pack.message).await;
        }
    }

    async fn listen_to_auth_submit_page(mut self_addr: Address<Self>) {
        let receiver = FeedAuthSubmitPageRequest::get_dart_signal_receiver();
        while let Some(signal_pack) = receiver.recv().await {
            let _ = self_addr.notify(signal_pack.message).await;
        }
    }

    async fn listen_to_auth_status(mut self_addr: Address<Self>) {
        let receiver = FeedAuthStatusRequest::get_dart_signal_receiver();
        while let Some(signal_pack) = receiver.recv().await {
            let _ = self_addr.notify(signal_pack.message).await;
        }
    }

    async fn listen_to_auth_clear(mut self_addr: Address<Self>) {
        let receiver = FeedAuthClearRequest::get_dart_signal_receiver();
        while let Some(signal_pack) = receiver.recv().await {
            let _ = self_addr.notify(signal_pack.message).await;
        }
    }
}

#[async_trait]
impl Handler<InitializeAppDataDirectory> for LoginActor {
    type Result = Result<(), String>;

    async fn handle(&mut self, msg: InitializeAppDataDirectory, _: &Context<Self>) -> Self::Result {
        self.initialize_app_data_directory(&msg.path).await
    }
}

#[async_trait]
impl Notifiable<FeedAuthCapabilityRequest> for LoginActor {
    async fn notify(&mut self, msg: FeedAuthCapabilityRequest, _: &Context<Self>) {
        self.do_auth_capability(msg).await.send_signal_to_dart();
    }
}

#[async_trait]
impl Notifiable<FeedAuthEntryRequest> for LoginActor {
    async fn notify(&mut self, msg: FeedAuthEntryRequest, _: &Context<Self>) {
        self.do_auth_entry(msg).await.send_signal_to_dart();
    }
}

#[async_trait]
impl Notifiable<FeedAuthSubmitPageRequest> for LoginActor {
    async fn notify(&mut self, msg: FeedAuthSubmitPageRequest, _: &Context<Self>) {
        self.do_auth_submit_page(msg).await.send_signal_to_dart();
    }
}

#[async_trait]
impl Notifiable<FeedAuthStatusRequest> for LoginActor {
    async fn notify(&mut self, msg: FeedAuthStatusRequest, _: &Context<Self>) {
        self.do_auth_status(msg).await.send_signal_to_dart();
    }
}

#[async_trait]
impl Notifiable<FeedAuthClearRequest> for LoginActor {
    async fn notify(&mut self, msg: FeedAuthClearRequest, _: &Context<Self>) {
        self.do_auth_clear(msg).await.send_signal_to_dart();
    }
}

#[cfg(test)]
mod tests {
    use std::error::Error;

    use langhuan::script::runtime::ScriptEngine;
    use messages::prelude::Context;

    use super::*;
    use crate::actors::registry_actor::RegistryActor;

    type TestResult = Result<(), Box<dyn Error>>;

    #[tokio::test]
    async fn initialize_app_data_directory_creates_auth_subdir() -> TestResult {
        let dir = tempfile::tempdir()?;

        let registry_context = Context::new();
        let registry_addr = registry_context.address();
        let login_context = Context::new();
        let login_addr = login_context.address();

        let registry_actor = RegistryActor::new(registry_addr.clone(), ScriptEngine::new());
        tokio::spawn(registry_context.run(registry_actor));

        let init_registry = registry_addr
            .clone()
            .send(InitializeAppDataDirectory {
                path: dir.path().to_string_lossy().to_string(),
            })
            .await;
        assert!(matches!(init_registry, Ok(Ok(_))));

        let mut login_actor = LoginActor::new(login_addr, registry_addr);
        let result = login_actor
            .initialize_app_data_directory(&dir.path().to_string_lossy())
            .await;

        assert!(result.is_ok());
        assert!(dir.path().join("auth").is_dir());
        Ok(())
    }
}