//! 短信分段计算：GSM-7（含扩展表）与 UCS-2。
//!
//! 计费口径说明：
//! - `GSM-7` 下 `length` 是 **septet** 数，扩展表字符（`^ { } \ [ ] ~ | €`）
//!   占 2 个 septet，与运营商的计费单元一致。
//! - `UCS-2` 下 `length` 是 UTF-16 码元数，emoji 占 2 个码元。
//! - `remaining` 表示“当前最后一条还能再输入多少个计费单元”，
//!   `max_chars` 表示当前这一条的容量（单条 160/70，级联 153/67）。

/// GSM-7 单条容量（septet）。
pub const GSM7_SINGLE: u32 = 160;
/// GSM-7 级联时每条容量（septet）。
pub const GSM7_MULTI: u32 = 153;
/// UCS-2 单条容量（UTF-16 码元）。
pub const UCS2_SINGLE: u32 = 70;
/// UCS-2 级联时每条容量（UTF-16 码元）。
pub const UCS2_MULTI: u32 = 67;

/// 分段结果。
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Segmentation {
    /// 编码名：`GSM-7` 或 `UCS-2`。
    pub encoding: String,
    /// 需要发送的短信条数（空正文为 0）。
    pub segments: u32,
    /// 已使用的计费单元数（见模块注释）。
    pub length: u32,
    /// 最后一条剩余可输入单元数。
    pub remaining: u32,
    /// 当前条容量（单条或级联容量）。
    pub max_chars: u32,
}

/// 计算分段信息。
pub fn segmentation(body: &str) -> Segmentation {
    let mut gsm_units: u32 = 0;
    let mut gsm_ok = true;
    let mut ucs_units: u32 = 0;
    for ch in body.chars() {
        ucs_units = ucs_units.saturating_add(ch.len_utf16() as u32);
        if gsm_ok {
            match gsm7_cost(ch) {
                Some(cost) => gsm_units = gsm_units.saturating_add(cost),
                None => gsm_ok = false,
            }
        }
    }

    if gsm_ok {
        build("GSM-7", gsm_units, GSM7_SINGLE, GSM7_MULTI)
    } else {
        build("UCS-2", ucs_units, UCS2_SINGLE, UCS2_MULTI)
    }
}

fn build(encoding: &str, units: u32, single: u32, multi: u32) -> Segmentation {
    if units == 0 {
        return Segmentation {
            encoding: encoding.to_owned(),
            segments: 0,
            length: 0,
            remaining: single,
            max_chars: single,
        };
    }
    if units <= single {
        return Segmentation {
            encoding: encoding.to_owned(),
            segments: 1,
            length: units,
            remaining: single - units,
            max_chars: single,
        };
    }
    let segments = (units + multi - 1) / multi;
    let used = units % multi;
    Segmentation {
        encoding: encoding.to_owned(),
        segments,
        length: units,
        remaining: if used == 0 { multi } else { multi - used },
        max_chars: multi,
    }
}

/// 字符在 GSM-7 中的计费单元数，`None` 表示不可编码（需要 UCS-2）。
pub fn gsm7_cost(ch: char) -> Option<u32> {
    // 扩展表：ESC + 单字符，占 2 septet。
    if matches!(
        ch,
        '^' | '{' | '}' | '\\' | '[' | ']' | '~' | '|' | '€' | '\u{0C}'
    ) {
        return Some(2);
    }
    if ch.is_ascii() {
        // 默认表覆盖全部可打印 ASCII（反引号除外）以及 CR/LF。
        if ch == '\n' || ch == '\r' {
            return Some(1);
        }
        if ch == '`' {
            return None;
        }
        if ch.is_ascii_alphanumeric() || ch == ' ' || ch.is_ascii_punctuation() {
            return Some(1);
        }
        return None;
    }
    // GSM-7 默认表中的非 ASCII 字符。
    match ch {
        '¤' | '£' | '¥' | 'è' | 'é' | 'ù' | 'ì' | 'ò' | 'Ç' | 'Ø' | 'ø' | 'Å' | 'å' | 'Δ'
        | 'Φ' | 'Γ' | 'Λ' | 'Ω' | 'Π' | 'Ψ' | 'Σ' | 'Θ' | 'Ξ' | 'Æ' | 'æ' | 'ß' | 'É' | '¡'
        | 'Ä' | 'Ö' | 'Ñ' | 'Ü' | '§' | '¿' | 'ä' | 'ö' | 'ñ' | 'ü' | 'à' => Some(1),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_body_has_no_segment() {
        let result = segmentation("");
        assert_eq!(result.encoding, "GSM-7");
        assert_eq!(result.segments, 0);
        assert_eq!(result.length, 0);
        assert_eq!(result.remaining, 160);
        assert_eq!(result.max_chars, 160);
    }

    #[test]
    fn gsm7_boundaries() {
        let full = segmentation(&"a".repeat(160));
        assert_eq!(full.segments, 1);
        assert_eq!(full.remaining, 0);
        assert_eq!(full.max_chars, 160);

        let over = segmentation(&"a".repeat(161));
        assert_eq!(over.segments, 2);
        assert_eq!(over.max_chars, 153);
        assert_eq!(over.remaining, 145);

        let exact_multi = segmentation(&"a".repeat(306));
        assert_eq!(exact_multi.segments, 2);
        assert_eq!(exact_multi.remaining, 153);
    }

    #[test]
    fn gsm7_extension_chars_cost_two_septets() {
        assert_eq!(gsm7_cost('€'), Some(2));
        assert_eq!(gsm7_cost('['), Some(2));
        assert_eq!(gsm7_cost('a'), Some(1));
        assert_eq!(gsm7_cost('`'), None);

        let eighty = segmentation(&"€".repeat(80));
        assert_eq!(eighty.encoding, "GSM-7");
        assert_eq!(eighty.length, 160);
        assert_eq!(eighty.segments, 1);
        assert_eq!(eighty.remaining, 0);

        let eighty_one = segmentation(&"€".repeat(81));
        assert_eq!(eighty_one.length, 162);
        assert_eq!(eighty_one.segments, 2);
        assert_eq!(eighty_one.remaining, 144);
    }

    #[test]
    fn handles_newlines_and_cr() {
        assert_eq!(gsm7_cost('\n'), Some(1));
        assert_eq!(gsm7_cost('\r'), Some(1));
        // CRLF 是 2 septet，不改变编码表
        let result = segmentation("line1\r\nline2");
        assert_eq!(result.encoding, "GSM-7");
        assert_eq!(result.length, 12);
        assert_eq!(result.segments, 1);
    }

    #[test]
    fn chinese_uses_ucs2_with_utf16_lengths() {
        let single = segmentation(&"中".repeat(70));
        assert_eq!(single.encoding, "UCS-2");
        assert_eq!(single.segments, 1);
        assert_eq!(single.remaining, 0);
        assert_eq!(single.max_chars, 70);

        let multi = segmentation(&"中".repeat(71));
        assert_eq!(multi.segments, 2);
        assert_eq!(multi.max_chars, 67);
        assert_eq!(multi.remaining, 63);
    }

    #[test]
    fn emoji_counts_two_units() {
        // 35 个 emoji = 70 码元，恰好一条
        let single = segmentation(&"🌿".repeat(35));
        assert_eq!(single.encoding, "UCS-2");
        assert_eq!(single.length, 70);
        assert_eq!(single.segments, 1);
        assert_eq!(single.remaining, 0);

        let over = segmentation(&"🌿".repeat(36));
        assert_eq!(over.length, 72);
        assert_eq!(over.segments, 2);
        assert_eq!(over.remaining, 62);

        // 中英混排：只要含中文就整体切到 UCS-2
        let mixed = segmentation("你好, world");
        assert_eq!(mixed.encoding, "UCS-2");
        assert_eq!(mixed.length, 9);
    }

    #[test]
    fn latin1_accents_stay_in_gsm7() {
        let result = segmentation("café £5");
        assert_eq!(result.encoding, "GSM-7");
        assert_eq!(result.length, 7);
    }
}
