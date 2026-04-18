//! OpenCC-based paragraph transform for Chinese simplified ↔ traditional conversion.
//!
//! Uses [`ferrous-opencc`] (pure Rust) so there is no C++ dependency and
//! cross-compilation for Android / iOS works out of the box.
//!
//! The heavy `OpenCC` instances are lazily initialised in `OnceLock` statics
//! and shared across all transform instances.

use std::sync::OnceLock;

use ferrous_opencc::config::BuiltinConfig;
use ferrous_opencc::OpenCC;

use crate::model::Paragraph;

use super::{ParagraphTransform, TransformOutput};

// ---------------------------------------------------------------------------
// Lazy-init converters (shared across all transform instances)
// ---------------------------------------------------------------------------

static S2T: OnceLock<OpenCC> = OnceLock::new();
static T2S: OnceLock<OpenCC> = OnceLock::new();

fn s2t_converter() -> &'static OpenCC {
    S2T.get_or_init(|| {
        OpenCC::from_config(BuiltinConfig::S2t).expect("failed to initialise OpenCC S2T")
    })
}

fn t2s_converter() -> &'static OpenCC {
    T2S.get_or_init(|| {
        OpenCC::from_config(BuiltinConfig::T2s).expect("failed to initialise OpenCC T2S")
    })
}

// ---------------------------------------------------------------------------
// Conversion mode
// ---------------------------------------------------------------------------

/// Which direction to convert, or no conversion.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConversionMode {
    /// No conversion — pass through unchanged.
    None,
    /// Simplified Chinese → Traditional Chinese.
    S2t,
    /// Traditional Chinese → Simplified Chinese.
    T2s,
}

// ---------------------------------------------------------------------------
// OpenCcTransform
// ---------------------------------------------------------------------------

/// A [`ParagraphTransform`] that converts Chinese text using OpenCC.
///
/// Converts the text fields of [`Paragraph::Title`] and [`Paragraph::Text`].
/// [`Paragraph::Image`] is passed through unchanged.
pub struct OpenCcTransform {
    mode: ConversionMode,
}

impl OpenCcTransform {
    /// Create a new transform with the given conversion mode.
    ///
    /// If `mode` is [`ConversionMode::None`], the transform acts as a
    /// pass-through and no OpenCC instance is initialised.
    pub fn new(mode: ConversionMode) -> Self {
        Self { mode }
    }

    /// Convert a single string according to the current mode.
    fn convert(&self, text: &str) -> String {
        match self.mode {
            ConversionMode::None => text.to_owned(),
            ConversionMode::S2t => s2t_converter().convert(text),
            ConversionMode::T2s => t2s_converter().convert(text),
        }
    }
}

impl ParagraphTransform for OpenCcTransform {
    fn init(&mut self, _chapter_id: &str) {
        // No per-chapter state needed — the converter is global.
    }

    fn apply(&mut self, paragraph: Paragraph, out: &mut TransformOutput<'_>) {
        if self.mode == ConversionMode::None {
            out.push(paragraph);
            return;
        }

        out.push(match paragraph {
            Paragraph::Title { text } => Paragraph::Title {
                text: self.convert(&text),
            },
            Paragraph::Text { content } => Paragraph::Text {
                content: self.convert(&content),
            },
            img @ Paragraph::Image { .. } => img,
        });
    }
}
