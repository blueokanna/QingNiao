//! UTF-16 码元工具。
//!
//! Dart 的 `String` 以 UTF-16 码元计数，跨语言传递的下标（如高亮范围）
//! 必须使用 UTF-16 码元而不是字节或 Unicode 标量值。此模块集中处理这些换算，
//! 保证 emoji（代理对）被正确计为 2 个码元。

/// 字符串的 UTF-16 码元长度。
pub fn utf16_len(text: &str) -> usize {
    text.encode_utf16().count()
}

/// 给定字符序列，返回 `len + 1` 个 UTF-16 码元偏移。
///
/// `offsets[i]` 是第 `i` 个字符之前的码元数，`offsets[len]` 等于总长度。
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

/// 按 UTF-16 码元偏移定位字符下标（总是对齐到字符边界）。
///
/// 返回值是第一个 `offsets[i] >= unit` 的 `i`，因此可用于安全切片。
pub fn char_index_at(offsets: &[u32], unit: u32) -> usize {
    offsets.partition_point(|&offset| offset < unit)
}

/// 按字节上限截断，且保证落在字符边界上。
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

/// 按字符数截断。
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
        // unit 2 落在代理对内部：返回下一个字符的起点（offsets[2] == 3 >= 2）
        assert_eq!(char_index_at(&map, 2), 2);
        assert_eq!(char_index_at(&map, 3), 2);
        assert_eq!(char_index_at(&map, 4), 3);
    }

    #[test]
    fn truncation_keeps_char_boundaries() {
        let text = "ab🌿cd";
        // 4 字节落在 emoji 中间，必须回退到 2 字节
        assert_eq!(truncate_bytes(text, 4), "ab");
        assert_eq!(truncate_bytes(text, 100), text);
        assert_eq!(truncate_bytes("", 0), "");
        assert_eq!(truncate_chars(text, 2), "ab");
        assert_eq!(truncate_chars(text, 0), "");
        assert_eq!(truncate_chars(text, 99), text);
    }
}
