//! Paragraph transforms — stateful per-chapter transformations.
//!
//! A [`ParagraphTransform`] is initialised once per chapter and then called for
//! each [`Paragraph`] in sequence.  Results are pushed into an output `Vec`
//! to avoid per-call allocations:
//!
//! - push nothing → drop
//! - push one → keep / modify
//! - push many → insert additional paragraphs
//!
//! Implementations are expected to be cheap to construct — expensive resources
//! (e.g. OpenCC dictionaries) should be shared via `Arc` or lazy statics.

pub mod dedup_title;
pub mod opencc;

use crate::model::Paragraph;

// ---------------------------------------------------------------------------
// TransformOutput — append-only output sink
// ---------------------------------------------------------------------------

/// An append-only output sink for [`ParagraphTransform::apply`].
///
/// Wraps a `&mut Vec<Paragraph>` but only exposes `push`, preventing
/// transforms from inspecting or mutating previously emitted paragraphs.
pub struct TransformOutput<'a>(&'a mut Vec<Paragraph>);

impl TransformOutput<'_> {
    /// Emit a paragraph to the output.
    #[inline]
    pub fn push(&mut self, paragraph: Paragraph) {
        self.0.push(paragraph);
    }
}

// ---------------------------------------------------------------------------
// ParagraphTransform trait
// ---------------------------------------------------------------------------

/// A stateful, per-chapter paragraph transform.
///
/// # Lifecycle
///
/// 1. [`init`](Self::init) is called once when a chapter stream is opened.
/// 2. [`apply`](Self::apply) is called for every paragraph in order.
/// 3. The transform is dropped when the stream ends or is cancelled.
pub trait ParagraphTransform: Send + Sync {
    /// Initialise the transform for a chapter.
    ///
    /// `chapter_id` is provided so transforms can use chapter-specific state
    /// if needed.
    fn init(&mut self, chapter_id: &str);

    /// Transform a paragraph, pushing results into `out`.
    ///
    /// - push nothing → drop the paragraph
    /// - push one → keep or modify
    /// - push many → expand into multiple paragraphs
    ///
    /// `out` is append-only — previously emitted paragraphs cannot be accessed.
    fn apply(&mut self, paragraph: Paragraph, out: &mut TransformOutput<'_>);
}

// ---------------------------------------------------------------------------
// TransformChain — compose multiple transforms
// ---------------------------------------------------------------------------

/// Applies a chain of [`ParagraphTransform`]s in order.
///
/// Each transform sees the output of the previous one.  When a transform
/// drops a paragraph, subsequent transforms never see it.
///
/// Internally uses two pre-allocated buffers that are swapped each stage,
/// so steady-state operation involves zero heap allocations.
pub struct TransformChain {
    transforms: Vec<Box<dyn ParagraphTransform>>,
}

impl TransformChain {
    /// Create an empty chain (pass-through).
    pub fn new() -> Self {
        Self {
            transforms: Vec::new(),
        }
    }

    /// Append a transform to the end of the chain.
    pub fn push(&mut self, transform: Box<dyn ParagraphTransform>) {
        self.transforms.push(transform);
    }

    /// Returns `true` if the chain contains no transforms (pure pass-through).
    pub fn is_empty(&self) -> bool {
        self.transforms.is_empty()
    }

    /// Initialize every transform in the chain for the given chapter.
    pub fn init(&mut self, chapter_id: &str) {
        for t in &mut self.transforms {
            t.init(chapter_id);
        }
    }

    /// Run a single paragraph through the full chain.
    pub fn apply(&mut self, paragraph: Paragraph) -> Vec<Paragraph> {
        // Seed buf_a with the input paragraph.
        let mut buf_a = Vec::new();
        let mut buf_b = vec![paragraph];

        for transform in &mut self.transforms {
            buf_a.clear();
            for p in buf_b.drain(..) {
                transform.apply(p, &mut TransformOutput(&mut buf_a));
            }
            std::mem::swap(&mut buf_a, &mut buf_b);
        }

        buf_b
    }
}

impl Default for TransformChain {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::ParagraphTransform;
    use super::TransformChain;
    use super::TransformOutput;
    use crate::model::Paragraph;

    /// A test transform that duplicates every paragraph.
    struct Duplicator;

    impl ParagraphTransform for Duplicator {
        fn init(&mut self, _chapter_id: &str) {}

        fn apply(&mut self, paragraph: Paragraph, out: &mut TransformOutput<'_>) {
            out.push(paragraph.clone());
            out.push(paragraph);
        }
    }

    #[test]
    fn test_transform_chain() {
        let mut chain = TransformChain::new();
        chain.push(Box::new(Duplicator));
        chain.push(Box::new(Duplicator));

        let input = Paragraph::Text {
            content: "Hello".to_string(),
        };
        let output = chain.apply(input);

        assert_eq!(output.len(), 4);
        assert_eq!(
            output[0],
            Paragraph::Text {
                content: "Hello".to_string()
            }
        );
        assert_eq!(
            output[1],
            Paragraph::Text {
                content: "Hello".to_string()
            }
        );
        assert_eq!(
            output[2],
            Paragraph::Text {
                content: "Hello".to_string()
            }
        );
        assert_eq!(
            output[3],
            Paragraph::Text {
                content: "Hello".to_string()
            }
        );
    }
}
