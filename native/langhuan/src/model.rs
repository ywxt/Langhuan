use std::collections::HashMap;
use std::fmt;
use std::str::FromStr;

use bytes::Bytes;
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
    /// Zero-based index indicating the chapter's position in the book.
    pub index: u32,
}

/// A single content unit in a chapter, emitted as part of a paragraphs stream.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Paragraph {
    /// The chapter title (typically emitted first).
    Title { text: String },
    /// A text paragraph.
    Text { content: String },
    /// An image.
    Image {
        url: String,
        #[serde(default)]
        alt: Option<String>,
    },
}

// ---------------------------------------------------------------------------
// HTTP request / response descriptors (Lua ↔ Rust boundary)
// ---------------------------------------------------------------------------

/// An HTTP request descriptor constructed by a Lua feed script.
///
/// The Lua `*_request` functions return a table that is deserialized into this
/// struct. Rust then executes the actual HTTP call.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HttpRequest {
    /// The target URL.
    pub url: String,
    /// HTTP method (GET, POST, …). Defaults to `"GET"`.
    #[serde(default = "default_method")]
    pub method: String,
    /// Query parameters appended to the URL.
    #[serde(default)]
    pub params: Option<HashMap<String, String>>,
    /// Additional HTTP headers.
    #[serde(default, deserialize_with = "deserialize_headers_opt")]
    pub headers: Option<Vec<(String, String)>>,
    /// An optional request body (for POST/PUT), as raw bytes.
    #[serde(default)]
    pub body: Option<HttpBody>,
}

/// A body carried by either an HTTP request or an HTTP response.
///
/// Raw bytes only — all encoding and decoding is the Lua script's responsibility.
/// On responses, Rust always delivers the raw bytes; Lua can call `json.decode`
/// or handle the string as needed.
#[derive(Debug, Clone)]
pub struct HttpBody(pub Bytes);

impl HttpBody {
    /// Construct an [`HttpBody`] from a UTF-8 [`String`].
    pub fn from_string(s: String) -> Self {
        Self(Bytes::from(s))
    }

    /// Decode this body as UTF-8 text.
    ///
    /// Returns an error if the body contains invalid UTF-8.
    pub fn as_str(&self) -> std::result::Result<&str, std::str::Utf8Error> {
        std::str::from_utf8(&self.0)
    }
}

impl From<String> for HttpBody {
    fn from(value: String) -> Self {
        Self::from_string(value)
    }
}

impl From<&str> for HttpBody {
    fn from(value: &str) -> Self {
        Self(Bytes::copy_from_slice(value.as_bytes()))
    }
}

impl Default for HttpBody {
    fn default() -> Self {
        Self(Bytes::new())
    }
}

impl fmt::Display for HttpBody {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self.as_str() {
            Ok(s) => f.write_str(s),
            Err(_) => Err(fmt::Error),
        }
    }
}

impl FromStr for HttpBody {
    type Err = std::convert::Infallible;

    fn from_str(s: &str) -> std::result::Result<Self, Self::Err> {
        Ok(Self::from(s))
    }
}

impl serde::Serialize for HttpBody {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        serializer.serialize_bytes(&self.0)
    }
}

impl<'de> serde::Deserialize<'de> for HttpBody {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        struct HttpBodyVisitor;

        impl<'de> serde::de::Visitor<'de> for HttpBodyVisitor {
            type Value = HttpBody;

            fn expecting(&self, formatter: &mut std::fmt::Formatter) -> std::fmt::Result {
                formatter.write_str("a byte array for HTTP body")
            }

            fn visit_bytes<E>(self, v: &[u8]) -> Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                Ok(HttpBody(Bytes::copy_from_slice(v)))
            }

            fn visit_byte_buf<E>(self, v: Vec<u8>) -> Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                Ok(HttpBody(Bytes::from(v)))
            }
        }

        deserializer.deserialize_bytes(HttpBodyVisitor)
    }
}

fn default_method() -> String {
    "GET".to_owned()
}

/// An HTTP response passed from Rust into a Lua `parse_*` function.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HttpResponse {
    /// HTTP status code.
    pub status: u16,
    /// Response headers.
    pub headers: Vec<(String, String)>,
    /// The response body as raw bytes.
    pub body: HttpBody,
    /// The final URL after any redirects.
    pub url: String,
}

fn deserialize_headers_opt<'de, D>(deserializer: D) -> Result<Option<Vec<(String, String)>>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum HeaderRepr {
        Pairs(Vec<(String, String)>),
        Map(std::collections::BTreeMap<String, String>),
    }

    let repr = Option::<HeaderRepr>::deserialize(deserializer)?;
    Ok(repr.map(|value| match value {
        HeaderRepr::Pairs(v) => v,
        HeaderRepr::Map(map) => map.into_iter().collect(),
    }))
}

#[cfg(test)]
mod tests {
    use super::HttpBody;

    #[test]
    fn http_body_to_string_roundtrip() {
        let src = "hello 世界";
        let body = HttpBody::from(src);
        assert_eq!(body.to_string(), src);
    }

    #[test]
    fn http_body_from_string_helper_works() {
        let body = HttpBody::from_string("payload".to_owned());
        assert_eq!(body.as_str().expect("valid utf-8"), "payload");
    }

    #[test]
    fn http_body_from_str_works() {
        let body: HttpBody = "abc".parse().expect("infallible parse should succeed");
        assert_eq!(body.as_str().expect("valid utf-8"), "abc");
    }
}
