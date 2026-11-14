//! 短信正文分析：分类、OTP（验证码）提取、链接提取。
//!
//! 提取策略是保守的：只有在出现验证码类关键词、且过滤掉日期/金额/电话/
//! 订单号等干扰后**唯一**存在的候选才会被当作验证码返回。
//! 返回的下标是 UTF-16 码元下标，Dart 侧可直接用于 `TextSpan` 高亮。

use crate::core::segment;
use crate::core::utf16;

/// 超过该字节数的正文只分析前缀，避免病态输入拖慢 UI。
const MAX_BODY_BYTES: usize = 64 * 1024;
const OTP_MIN: usize = 4;
const OTP_MAX: usize = 8;
/// 候选与关键词之间允许的最大字符间隔。
const KEYWORD_WINDOW: usize = 20;
/// 订单号关键词与数字之间允许的最大字符间隔（仅“关键词在前”这一侧）。
const ORDER_WINDOW: usize = 3;
const MAX_LINK_CHARS: usize = 512;

/// 单条正文的分析结果。
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Analysis {
    /// `verification` / `promotion` / `finance` / `personal`。
    pub category: String,
    /// 提取到的验证码（纯数字 4-8 位）。
    pub otp: Option<String>,
    /// `otp` 在正文中的起始 UTF-16 码元下标。
    pub otp_start: u32,
    /// `otp` 在正文中的结束 UTF-16 码元下标（不含）。
    pub otp_end: u32,
    /// 是否成功提取到验证码。
    pub is_otp: bool,
    /// 正文中第一个 http(s) 链接。
    pub link: Option<String>,
    /// 复用 `segment` 模块的分段结果。
    pub segments: u32,
    pub encoding: String,
    pub remaining: u32,
}

const VERIFICATION_KEYWORDS: &[&str] = &[
    "验证码",
    "校验码",
    "动态码",
    "口令",
    "激活码",
    "verification code",
    "security code",
    "one-time code",
    "one-time password",
    "otp",
    "passcode",
    "2fa",
];

const FINANCE_KEYWORDS: &[&str] = &[
    "贷款",
    "账单",
    "银行",
    "还款",
    "余额",
    "转账",
    "信用卡",
    "支付",
    "利息",
    "额度",
    "尾号",
];

const PROMOTION_KEYWORDS: &[&str] = &[
    "优惠",
    "促销",
    "退订",
    "折扣",
    "红包",
    "满减",
    "限时",
    "特价",
    "领取",
    "活动",
    "unsubscribe",
    "promo",
];

const ORDER_KEYWORDS: &[&str] = &[
    "订单编号",
    "订单号",
    "订单",
    "单号",
    "流水号",
    "交易号",
    "order no",
    "invoice",
];

/// 快递/取件类通知：四分类里没有独立物流类目，统一归入 `personal`。
const LOGISTICS_KEYWORDS: &[&str] = &["快递", "取件", "驿站", "派送", "物流"];

#[derive(Clone, Copy, Debug)]
struct Span {
    start: usize,
    end: usize,
}

impl Span {
    fn overlaps(self, start: usize, end: usize) -> bool {
        self.start < end && start < self.end
    }

    fn gap(self, other: Span) -> usize {
        if self.end <= other.start {
            other.start - self.end
        } else if other.end <= self.start {
            self.start - other.end
        } else {
            0
        }
    }
}

fn fold_ascii(ch: char) -> char {
    if ch.is_ascii_uppercase() {
        ch.to_ascii_lowercase()
    } else {
        ch
    }
}

/// 在字符序列中查找全部关键词出现位置（不重叠）。
fn keyword_spans(hay: &[char], keywords: &[&str]) -> Vec<Span> {
    let mut spans = Vec::new();
    for keyword in keywords {
        let needle: Vec<char> = keyword.chars().collect();
        if needle.is_empty() || needle.len() > hay.len() {
            continue;
        }
        let last = hay.len() - needle.len();
        let mut index = 0;
        while index <= last {
            if hay[index..index + needle.len()] == needle[..] {
                spans.push(Span {
                    start: index,
                    end: index + needle.len(),
                });
                index += needle.len();
            } else {
                index += 1;
            }
        }
    }
    spans
}

/// 分析一条正文。空串与超长输入都安全。
pub fn analyze(body: &str) -> Analysis {
    let text = if body.len() > MAX_BODY_BYTES {
        utf16::truncate_bytes(body, MAX_BODY_BYTES)
    } else {
        body
    };
    let chars: Vec<char> = text.chars().collect();
    let folded: Vec<char> = chars.iter().map(|&ch| fold_ascii(ch)).collect();
    let offsets = utf16::offsets(&chars);

    let verification = keyword_spans(&folded, VERIFICATION_KEYWORDS);
    let finance = keyword_spans(&folded, FINANCE_KEYWORDS);
    let promotion = keyword_spans(&folded, PROMOTION_KEYWORDS);
    let orders = keyword_spans(&folded, ORDER_KEYWORDS);
    let logistics = keyword_spans(&folded, LOGISTICS_KEYWORDS);

    let category = if !verification.is_empty() {
        "verification"
    } else if !logistics.is_empty() {
        // 快递/取件通知优先按个人消息归类，避免被“优惠”等词误判成推广
        "personal"
    } else if !finance.is_empty() {
        "finance"
    } else if !promotion.is_empty() {
        "promotion"
    } else {
        "personal"
    };

    let phones = phone_spans(&chars);
    let candidates = collect_candidates(&chars, &orders, &phones);
    let otp_candidate = if verification.is_empty() {
        None
    } else {
        select_candidate(&candidates, &verification)
    };

    let (otp, otp_start, otp_end) = match otp_candidate {
        Some(span) => (
            Some(chars[span.start..span.end].iter().collect::<String>()),
            offsets[span.start],
            offsets[span.end],
        ),
        None => (None, 0, 0),
    };
    let is_otp = otp.is_some();
    let link = extract_link(&chars);
    let segmentation = segment::segmentation(text);

    Analysis {
        category: category.to_owned(),
        otp,
        otp_start,
        otp_end,
        is_otp,
        link,
        segments: segmentation.segments,
        encoding: segmentation.encoding,
        remaining: segmentation.remaining,
    }
}

/// 收集 4-8 位纯数字候选，并按值去重。
fn collect_candidates(chars: &[char], orders: &[Span], phones: &[Span]) -> Vec<Span> {
    let mut out: Vec<Span> = Vec::new();
    let mut index = 0;
    while index < chars.len() {
        if !chars[index].is_ascii_digit() {
            index += 1;
            continue;
        }
        let start = index;
        while index < chars.len() && chars[index].is_ascii_digit() {
            index += 1;
        }
        let end = index;
        let length = end - start;
        if !(OTP_MIN..=OTP_MAX).contains(&length) {
            continue;
        }
        if !is_bounded(chars, start, end) {
            continue;
        }
        if is_date_like(chars, start, end) {
            continue;
        }
        if is_amount_like(chars, start, end) {
            continue;
        }
        if is_order_like(start, orders) {
            continue;
        }
        if is_repetitive(&chars[start..end]) {
            continue;
        }
        if phones.iter().any(|span| span.overlaps(start, end)) {
            continue;
        }
        let duplicated = out
            .iter()
            .any(|span| chars[span.start..span.end] == chars[start..end]);
        if !duplicated {
            out.push(Span { start, end });
        }
    }
    out
}

/// 数字两侧必须是 ASCII 词边界（`A123456B` / `_123456` 不算）。
fn is_bounded(chars: &[char], start: usize, end: usize) -> bool {
    let prev_ok = start == 0 || {
        let ch = chars[start - 1];
        !(ch.is_ascii_alphanumeric() || ch == '_')
    };
    let next_ok = end >= chars.len() || {
        let ch = chars[end];
        !(ch.is_ascii_alphanumeric() || ch == '_')
    };
    prev_ok && next_ok
}

fn is_date_marker(ch: char) -> bool {
    matches!(ch, '年' | '月' | '日')
}

fn is_date_like(chars: &[char], start: usize, end: usize) -> bool {
    let length = end - start;
    if (start > 0 && is_date_marker(chars[start - 1]))
        || (end < chars.len() && is_date_marker(chars[end]))
    {
        return true;
    }
    if length == 4 {
        let value = digits_value(&chars[start..end]);
        // 19xx / 20xx 年份
        if (1900..=2099).contains(&value) {
            return true;
        }
    }
    if length == 8 {
        let value = digits_value(&chars[start..end]);
        let year = value / 10000;
        let month = (value / 100) % 100;
        let day = value % 100;
        if (1900..=2100).contains(&year) && (1..=12).contains(&month) && (1..=31).contains(&day) {
            return true;
        }
    }
    false
}

fn digits_value(digits: &[char]) -> u32 {
    digits
        .iter()
        .fold(0u32, |acc, &ch| acc * 10 + (ch as u32 - '0' as u32))
}

fn is_amount_like(chars: &[char], start: usize, end: usize) -> bool {
    const CURRENCY: &[char] = &['¥', '￥', '$', '€', '£', '＄'];
    const UNIT: &[char] = &['元', '块', '圆', '折', '%', '％'];
    if start > 0 && CURRENCY.contains(&chars[start - 1]) {
        return true;
    }
    if end < chars.len() && UNIT.contains(&chars[end]) {
        return true;
    }
    // 千分位或小数分组：1,234 / 12.50
    if start >= 2
        && (chars[start - 1] == ',' || chars[start - 1] == '.')
        && chars[start - 2].is_ascii_digit()
    {
        return true;
    }
    if end + 1 < chars.len()
        && (chars[end] == ',' || chars[end] == '.')
        && chars[end + 1].is_ascii_digit()
    {
        return true;
    }
    false
}

fn is_order_like(start: usize, orders: &[Span]) -> bool {
    // 只把“订单号 123456”这种关键词紧邻在前的数字视为订单号；
    // 关键词在后的情况交给 OTP 关键词邻近判定处理，避免把验证码误吞掉。
    orders
        .iter()
        .any(|span| span.end <= start && start - span.end <= ORDER_WINDOW)
}

fn is_repetitive(digits: &[char]) -> bool {
    if digits.is_empty() {
        return false;
    }
    let first = digits[0];
    if digits.iter().all(|&ch| ch == first) {
        return true;
    }
    // 过长的连续递增/递减序列（1234567 / 7654321）视为占位数字
    if digits.len() >= 7 {
        let mut ascending = true;
        let mut descending = true;
        for pair in digits.windows(2) {
            let a = pair[0] as u32;
            let b = pair[1] as u32;
            if b != a + 1 {
                ascending = false;
            }
            if b + 1 != a {
                descending = false;
            }
        }
        if ascending || descending {
            return true;
        }
    }
    false
}

/// 识别由数字与分隔符组成、位数 >= 11 的电话号码片段。
fn phone_spans(chars: &[char]) -> Vec<Span> {
    let mut spans = Vec::new();
    let mut index = 0;
    while index < chars.len() {
        if !chars[index].is_ascii_digit() {
            index += 1;
            continue;
        }
        let start = index;
        let mut digits = 0usize;
        let mut cursor = index;
        while cursor < chars.len() {
            let ch = chars[cursor];
            if ch.is_ascii_digit() {
                digits += 1;
                cursor += 1;
                continue;
            }
            let separator = matches!(ch, '-' | ' ' | '(' | ')' | '\u{3000}');
            if separator && cursor + 1 < chars.len() && chars[cursor + 1].is_ascii_digit() {
                cursor += 1;
                continue;
            }
            break;
        }
        if digits >= 11 {
            spans.push(Span {
                start,
                end: cursor,
            });
        }
        index = if cursor > index { cursor } else { index + 1 };
    }
    spans
}

fn select_candidate(candidates: &[Span], verification: &[Span]) -> Option<Span> {
    if candidates.is_empty() {
        return None;
    }
    if candidates.len() == 1 {
        return Some(candidates[0]);
    }
    let near: Vec<Span> = candidates
        .iter()
        .copied()
        .filter(|candidate| {
            verification
                .iter()
                .any(|keyword| keyword.gap(*candidate) <= KEYWORD_WINDOW)
        })
        .collect();
    if near.len() == 1 {
        Some(near[0])
    } else {
        None
    }
}

fn extract_link(chars: &[char]) -> Option<String> {
    const PREFIXES: [&str; 2] = ["http://", "https://"];
    const STOP: &[char] = &[
        ' ', '\t', '\n', '\r', '\u{3000}', '，', '。', '；', '：', '！', '？', '、', '（', '）',
        '【', '】', '《', '》', '「', '」', '『', '』', '“', '”', '‘', '’', '"', '\'', '<', '>',
        '(', ')', '{', '}', '|', '`',
    ];
    const TRIM: &[char] = &[
        '.', ',', ';', '!', '?', '"', '\'', '。', '，', '；', '：', '！', '？', '…', '、',
    ];

    let mut index = 0;
    while index < chars.len() {
        let mut matched = 0usize;
        for prefix in PREFIXES.iter() {
            let needle: Vec<char> = prefix.chars().collect();
            if index + needle.len() <= chars.len()
                && chars[index..index + needle.len()]
                    .iter()
                    .zip(needle.iter())
                    .all(|(a, b)| fold_ascii(*a) == *b)
            {
                matched = needle.len();
                break;
            }
        }
        if matched == 0 {
            index += 1;
            continue;
        }
        let mut end = index + matched;
        let mut consumed = 0usize;
        while end < chars.len() && consumed < MAX_LINK_CHARS {
            if STOP.contains(&chars[end]) {
                break;
            }
            end += 1;
            consumed += 1;
        }
        while end > index + matched && TRIM.contains(&chars[end - 1]) {
            end -= 1;
        }
        if end > index + matched {
            return Some(chars[index..end].iter().collect::<String>());
        }
        index = end.max(index + 1);
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_body_is_safe() {
        let result = analyze("");
        assert_eq!(result.category, "personal");
        assert!(result.otp.is_none());
        assert!(!result.is_otp);
        assert!(result.link.is_none());
        assert_eq!(result.segments, 0);
        assert_eq!(result.encoding, "GSM-7");
        assert_eq!(result.remaining, 160);
    }

    #[test]
    fn extracts_chinese_verification_code() {
        let body = "【示例】您的验证码为 123456，5分钟内有效。";
        let result = analyze(body);
        assert_eq!(result.category, "verification");
        assert_eq!(result.otp.as_deref(), Some("123456"));
        assert!(result.is_otp);
        let expected_start = utf16::utf16_len("【示例】您的验证码为 ") as u32;
        assert_eq!(result.otp_start, expected_start);
        assert_eq!(result.otp_end, expected_start + 6);
    }

    #[test]
    fn otp_offsets_are_utf16_units() {
        // emoji 占 2 个码元，下标不能按字节或字符计算
        let result = analyze("🌿验证码：654321");
        assert_eq!(result.otp.as_deref(), Some("654321"));
        assert_eq!(result.otp_start, 6);
        assert_eq!(result.otp_end, 12);
    }

    #[test]
    fn english_keywords_are_case_insensitive() {
        let result = analyze("Your Security Code is 004321. Do not share.");
        assert_eq!(result.category, "verification");
        assert_eq!(result.otp.as_deref(), Some("004321"));
        assert_eq!(analyze("OTP: 778899").otp.as_deref(), Some("778899"));
        assert_eq!(analyze("Passcode 112233").otp.as_deref(), Some("112233"));
        assert_eq!(
            analyze("verification code: 909090").otp.as_deref(),
            Some("909090")
        );
    }

    #[test]
    fn ambiguous_candidates_are_rejected() {
        // 两个候选都紧邻验证码关键词 -> 不猜
        assert!(analyze("验证码 123456，备用验证码 654321").otp.is_none());
        // 一个候选邻关键词、另一个是订单号 -> 只保留唯一候选
        let result = analyze("验证码 123456，订单号 765432");
        assert_eq!(result.otp.as_deref(), Some("123456"));
        // 没有验证码关键词时不提取
        assert!(analyze("订单 123456").otp.is_none());
    }

    #[test]
    fn rejects_dates_amounts_phones_and_orders() {
        assert!(analyze("验证码 20240501").otp.is_none());
        assert!(analyze("验证码 2024").otp.is_none());
        assert_eq!(
            analyze("2024年5月1日 验证码 123456").otp.as_deref(),
            Some("123456")
        );
        assert!(analyze("验证码 1000元").otp.is_none());
        assert!(analyze("验证码 ¥1000").otp.is_none());
        assert!(analyze("验证码 13800138000").otp.is_none());
        assert_eq!(
            analyze("客服 138-0013-8000 验证码 654321")
                .otp
                .as_deref(),
            Some("654321")
        );
        assert_eq!(
            analyze("订单号 88888888 验证码 246810")
                .otp
                .as_deref(),
            Some("246810")
        );
    }

    #[test]
    fn rejects_repetitive_numbers() {
        assert!(analyze("验证码 111111").otp.is_none());
        assert!(analyze("验证码 0000").otp.is_none());
        assert_eq!(analyze("验证码 1234").otp.as_deref(), Some("1234"));
    }

    #[test]
    fn rejects_alphanumeric_neighbours() {
        assert!(analyze("验证码 A123456B").otp.is_none());
        assert!(analyze("验证码 #123456").otp.as_deref() == Some("123456"));
        assert!(analyze("验证码 123456789").otp.is_none());
    }

    #[test]
    fn extracts_first_link_with_bracket_truncation() {
        assert_eq!(
            analyze("点击 https://example.com/a?b=1 领取").link.as_deref(),
            Some("https://example.com/a?b=1")
        );
        assert_eq!(
            analyze("（https://x.cn/p)（更多）").link.as_deref(),
            Some("https://x.cn/p")
        );
        assert_eq!(
            analyze("see HTTP://Example.COM/x。").link.as_deref(),
            Some("HTTP://Example.COM/x")
        );
        assert!(analyze("没有链接").link.is_none());
    }

    #[test]
    fn categories_cover_finance_and_promotion() {
        assert_eq!(
            analyze("【招商银行】您尾号 1234 的账单已出").category,
            "finance"
        );
        assert_eq!(analyze("退订回T").category, "promotion");
        assert_eq!(analyze("今晚一起吃饭吗").category, "personal");
        assert_eq!(analyze("您的验证码已发送").category, "verification");
        // 快递/取件通知归入 personal，且“取件码”不会被当成验证码
        let delivery = analyze("您的快递已到菜鸟驿站，取件码 123456");
        assert_eq!(delivery.category, "personal");
        assert!(delivery.otp.is_none());
    }

    #[test]
    fn long_body_is_truncated_without_panic() {
        let body = format!("验证码 123456 {}", "x".repeat(70_000));
        let result = analyze(&body);
        assert_eq!(result.otp.as_deref(), Some("123456"));
        // 超长正文按 64KB 截断后再分段
        assert!(result.segments > 100);
        assert!(!analyze(&"😀".repeat(20_000)).is_otp);
    }

    #[test]
    fn segments_come_from_segment_module() {
        let gsm = analyze("hello world");
        assert_eq!(gsm.encoding, "GSM-7");
        assert_eq!(gsm.segments, 1);
        assert_eq!(gsm.remaining, 149);

        let ucs2 = analyze("你好世界");
        assert_eq!(ucs2.encoding, "UCS-2");
        assert_eq!(ucs2.remaining, 66);
    }
}
