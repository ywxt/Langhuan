//! Per-chapter title deduplication transform.
//!
//! Keeps only the first [`Paragraph::Title`] in each chapter and drops
//! all subsequent ones.  State is reset on every [`init`](DedupTitle::init)
//! call, so each chapter starts fresh.

use crate::model::Paragraph;

use super::{ParagraphTransform, TransformOutput};

/// Drops duplicate [`Paragraph::Title`]s — only the first title per chapter
/// is kept.
pub struct DedupTitleTransform {
    seen: bool,
}

impl DedupTitleTransform {
    pub fn new() -> Self {
        Self { seen: false }
    }
}

impl Default for DedupTitleTransform {
    fn default() -> Self {
        Self::new()
    }
}

impl ParagraphTransform for DedupTitleTransform {
    fn init(&mut self, _chapter_id: &str) {
        self.seen = false;
    }

    fn apply(&mut self, paragraph: Paragraph, out: &mut TransformOutput<'_>) {
        if matches!(paragraph, Paragraph::Title { .. }) {
            if !self.seen {
                self.seen = true;
                out.push(paragraph);
            }
            // duplicate title — dropped
        } else {
            out.push(paragraph);
        }
    }
}
