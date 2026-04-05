/// Encode an arbitrary string into a filesystem-safe path component.
///
/// The output is prefixed with `h` and then lower-case hex bytes, providing
/// a collision-free mapping for UTF-8 input.
pub fn encode_path_component(raw: &str) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let bytes = raw.as_bytes();
    let mut out = String::with_capacity(1 + bytes.len() * 2);
    out.push('h');
    for byte in bytes {
        out.push(HEX[(byte >> 4) as usize] as char);
        out.push(HEX[(byte & 0x0f) as usize] as char);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::encode_path_component;

    #[test]
    fn encode_component_is_stable_and_non_empty() {
        assert_eq!(encode_path_component(""), "h");
        assert_eq!(encode_path_component("abc"), "h616263");
    }

    #[test]
    fn encode_component_distinguishes_different_inputs() {
        assert_ne!(encode_path_component("a/b"), encode_path_component("a_b"));
    }
}
