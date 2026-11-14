
/// Offsets crossing the Dart boundary count UTF-16 units, not Rust bytes.
pub fn utf16_len(text: &str) -> usize {
    text.encode_utf16().count()
}

pub fn offsets(chars: &[char]) -> Vec<u32> {
    let mut out = Vec::with_capacity(chars.len() + 1);
    let mut offset = 0u32;
    out.push(0);
    for ch in chars {
        offset += ch.len_utf16() as u32;
        out.push(offset);
    }
    out
}

pub fn char_index_at(offsets: &[u32], unit: u32) -> usize {
    offsets.partition_point(|&offset| offset < unit)
}

pub fn truncate_bytes(text: &str, max_bytes: usize) -> &str {
    if text.len() <= max_bytes {
        return text;
    }
    let mut end = max_bytes;
    while end > 0 && !text.is_char_boundary(end) {
        end -= 1;
    }
    &text[..end]
}

pub fn truncate_chars(text: &str, max_chars: usize) -> &str {
    match text.char_indices().nth(max_chars) {
        Some((index, _)) => &text[..index],
        None => text,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn counts_emoji_as_two_units() {
        assert_eq!(utf16_len(""), 0);
        assert_eq!(utf16_len("验证码"), 3);
        assert_eq!(utf16_len("🌿"), 2);
        assert_eq!(utf16_len("a🌿b"), 4);
        assert_eq!(utf16_len("𠮷"), 2);
    }

    #[test]
    fn offsets_align_to_char_boundaries() {
        let chars: Vec<char> = "a🌿b".chars().collect();
        let map = offsets(&chars);
        assert_eq!(map, vec![0, 1, 3, 4]);
        assert_eq!(char_index_at(&map, 0), 0);
        assert_eq!(char_index_at(&map, 1), 1);
        assert_eq!(char_index_at(&map, 2), 2);
        assert_eq!(char_index_at(&map, 3), 2);
        assert_eq!(char_index_at(&map, 4), 3);
    }

    #[test]
    fn truncation_keeps_char_boundaries() {
        let text = "ab🌿cd";
        assert_eq!(truncate_bytes(text, 4), "ab");
        assert_eq!(truncate_bytes(text, 100), text);
        assert_eq!(truncate_bytes("", 0), "");
        assert_eq!(truncate_chars(text, 2), "ab");
        assert_eq!(truncate_chars(text, 0), "");
        assert_eq!(truncate_chars(text, 99), text);
    }
}
