
use std::collections::HashMap;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use once_cell::sync::Lazy;
use parking_lot::RwLock;

use crate::core::utf16;

pub const MAX_DOCS: usize = 50_000;
pub const MAX_BODY_CHARS: usize = 4_000;
pub const MAX_ADDRESS_CHARS: usize = 256;
pub const MAX_RESULTS: usize = 100;

const MAX_TERMS_PER_DOC: usize = 1024;
const MAX_QUERY_TERMS: usize = 32;
const MAX_NUMERIC_FRAGMENT: usize = 12;
const SNIPPET_UNITS: usize = 120;
const SNIPPET_LEAD: usize = 24;
const MAX_HIGHLIGHTS: usize = 48;
const K1: f64 = 1.2;
const B: f64 = 0.75;
const BODY_WEIGHT: f64 = 1.0;
const ADDRESS_WEIGHT: f64 = 3.0;
const WEEK_MS: i64 = 7 * 24 * 60 * 60 * 1000;

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Document {
    pub id: i64,
    pub thread_id: i64,
    pub address: String,
    pub body: String,
    pub date: i64,
    pub read: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Hit {
    pub id: i64,
    pub thread_id: i64,
    pub score: f64,
    pub snippet: String,
    pub highlights: Vec<(u32, u32)>,
}

#[derive(Default)]
pub struct Index {
    docs: Vec<Document>,
    body_len: Vec<u32>,
    addr_len: Vec<u32>,
    body_postings: HashMap<String, Vec<(u32, u32)>>,
    addr_postings: HashMap<String, Vec<(u32, u32)>>,
    total_body: u64,
    total_addr: u64,
}

static INDEX: Lazy<RwLock<Index>> = Lazy::new(|| RwLock::new(Index::default()));
static ROOT: Lazy<RwLock<Option<PathBuf>>> = Lazy::new(|| RwLock::new(None));

pub fn set_root(dir: &str) {
    *ROOT.write() = Some(PathBuf::from(dir));
}

pub fn root() -> Option<PathBuf> {
    ROOT.read().clone()
}

pub fn index_messages(docs: Vec<Document>) -> u32 {
    INDEX.write().rebuild(docs)
}

pub fn search_messages(query: &str, limit: u32) -> Vec<Hit> {
    INDEX.read().search(query, limit)
}

pub fn indexed_count() -> u32 {
    INDEX.read().len()
}

pub fn clear() {
    INDEX.write().clear();
}

impl Index {
    pub fn len(&self) -> u32 {
        self.docs.len() as u32
    }

    pub fn is_empty(&self) -> bool {
        self.docs.is_empty()
    }

    pub fn clear(&mut self) {
        *self = Index::default();
    }

    pub fn rebuild(&mut self, docs: Vec<Document>) -> u32 {
        *self = Index::default();
        self.docs.reserve(docs.len().min(MAX_DOCS));
        for doc in docs.into_iter().take(MAX_DOCS) {
            let body = utf16::truncate_chars(&doc.body, MAX_BODY_CHARS).to_owned();
            let address = utf16::truncate_chars(&doc.address, MAX_ADDRESS_CHARS).to_owned();
            let (body_terms, body_total) = term_frequencies(&body);
            let (addr_terms, addr_total) = term_frequencies(&address);

            let doc_index = self.docs.len() as u32;
            self.body_len.push(body_total);
            self.addr_len.push(addr_total);
            self.total_body += body_total as u64;
            self.total_addr += addr_total as u64;
            for (term, tf) in body_terms {
                self.body_postings
                    .entry(term)
                    .or_default()
                    .push((doc_index, tf));
            }
            for (term, tf) in addr_terms {
                self.addr_postings
                    .entry(term)
                    .or_default()
                    .push((doc_index, tf));
            }
            let stored = Document {
                body,
                address,
                ..doc
            };
            self.docs.push(stored);
        }
        self.len()
    }

    pub fn search(&self, query: &str, limit: u32) -> Vec<Hit> {
        let limit = (limit as usize).min(MAX_RESULTS);
        if limit == 0 || self.docs.is_empty() {
            return Vec::new();
        }
        let terms = unique_terms(query, MAX_QUERY_TERMS);
        if terms.is_empty() {
            return Vec::new();
        }

        let count = self.docs.len() as f64;
        let avg_body = if self.total_body > 0 {
            self.total_body as f64 / count
        } else {
            0.0
        };
        let avg_addr = if self.total_addr > 0 {
            self.total_addr as f64 / count
        } else {
            0.0
        };

        let mut scores: HashMap<u32, f64> = HashMap::new();
        for term in &terms {
            if let Some(postings) = self.body_postings.get(term) {
                let idf = inverse_document_frequency(count, postings.len() as f64);
                for &(doc, tf) in postings {
                    let dl = self.body_len[doc as usize] as f64;
                    let value = idf * bm25_tf(tf as f64, dl, avg_body) * BODY_WEIGHT;
                    *scores.entry(doc).or_insert(0.0) += value;
                }
            }
            if let Some(postings) = self.addr_postings.get(term) {
                let idf = inverse_document_frequency(count, postings.len() as f64);
                for &(doc, tf) in postings {
                    let dl = self.addr_len[doc as usize] as f64;
                    let value = idf * bm25_tf(tf as f64, dl, avg_addr) * ADDRESS_WEIGHT;
                    *scores.entry(doc).or_insert(0.0) += value;
                }
            }
        }
        if scores.is_empty() {
            return Vec::new();
        }

        let now = now_ms();
        for (doc, score) in scores.iter_mut() {
            let document = &self.docs[*doc as usize];
            if document.date > 0 {
                let age = now.saturating_sub(document.date);
                if (0..WEEK_MS).contains(&age) {
                    *score += 0.3 * (1.0 - age as f64 / WEEK_MS as f64);
                }
            }
            if !document.read {
                *score += 0.05;
            }
        }

        let mut ranked: Vec<(u32, f64)> = scores.into_iter().collect();
        self.sort_ranked(&mut ranked);

        let phrase = normalize_phrase(query);
        if !phrase.is_empty() {
            let candidates = ranked.len().min((limit * 3).min(300));
            for entry in ranked.iter_mut().take(candidates) {
                let document = &self.docs[entry.0 as usize];
                if lower_1to1(&document.body).contains(&phrase) {
                    entry.1 += 3.0;
                } else if lower_1to1(&document.address).contains(&phrase) {
                    entry.1 += 2.0;
                }
            }
            self.sort_ranked(&mut ranked);
        }

        let mut hits = Vec::with_capacity(limit.min(ranked.len()));
        for (doc, score) in ranked.into_iter().take(limit) {
            let document = &self.docs[doc as usize];
            let (snippet, highlights) = build_snippet(document, &terms);
            hits.push(Hit {
                id: document.id,
                thread_id: document.thread_id,
                score,
                snippet,
                highlights,
            });
        }
        hits
    }

    fn sort_ranked(&self, ranked: &mut [(u32, f64)]) {
        ranked.sort_by(|left, right| {
            right
                .1
                .partial_cmp(&left.1)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| {
                    let a = &self.docs[right.0 as usize];
                    let b = &self.docs[left.0 as usize];
                    a.date.cmp(&b.date).then_with(|| a.id.cmp(&b.id))
                })
        });
    }
}

fn inverse_document_frequency(count: f64, df: f64) -> f64 {
    ((count - df + 0.5) / (df + 0.5) + 1.0).ln()
}

fn bm25_tf(tf: f64, doc_len: f64, avg_len: f64) -> f64 {
    if avg_len <= 0.0 {
        return tf * (K1 + 1.0) / (tf + K1);
    }
    let norm = 1.0 - B + B * doc_len / avg_len;
    tf * (K1 + 1.0) / (tf + K1 * norm)
}

fn now_ms() -> i64 {
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(duration) => duration.as_millis() as i64,
        Err(_) => 0,
    }
}

fn term_frequencies(text: &str) -> (HashMap<String, u32>, u32) {
    let mut map: HashMap<String, u32> = HashMap::new();
    let mut total = 0u32;
    for term in tokenize(text) {
        *map.entry(term).or_insert(0) += 1;
        total = total.saturating_add(1);
        if map.len() >= MAX_TERMS_PER_DOC {
            break;
        }
    }
    (map, total)
}

fn unique_terms(text: &str, limit: usize) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for term in tokenize(text) {
        if !out.iter().any(|existing| existing == &term) {
            out.push(term);
            if out.len() >= limit {
                break;
            }
        }
    }
    out
}

fn is_cjk(ch: char) -> bool {
    let cp = ch as u32;
    (0x3400..=0x4DBF).contains(&cp)
        || (0x4E00..=0x9FFF).contains(&cp)
        || (0xF900..=0xFAFF).contains(&cp)
        || (0x20000..=0x2FA1F).contains(&cp)
}

pub fn normalize_char(ch: char) -> char {
    let mapped = match ch {
        '\u{FF01}'..='\u{FF5E}' => char::from_u32(ch as u32 - 0xFEE0).unwrap_or(ch),
        '\u{3000}' => ' ',
        _ => ch,
    };
    let mut iter = mapped.to_lowercase();
    match (iter.next(), iter.next()) {
        (Some(first), None) => first,
        _ => mapped,
    }
}

fn lower_1to1(text: &str) -> String {
    text.chars().map(normalize_char).collect()
}

fn normalize_phrase(query: &str) -> String {
    let mut parts: Vec<String> = Vec::new();
    let mut current = String::new();
    for ch in query.chars() {
        let ch = normalize_char(ch);
        if ch.is_whitespace() {
            if !current.is_empty() {
                parts.push(std::mem::take(&mut current));
            }
        } else {
            current.push(ch);
        }
    }
    if !current.is_empty() {
        parts.push(current);
    }
    parts.join(" ")
}

pub fn tokenize(text: &str) -> Vec<String> {
    let mut terms: Vec<String> = Vec::new();
    let mut current: Vec<char> = Vec::new();
    for ch in text.chars() {
        let ch = normalize_char(ch);
        if ch.is_alphanumeric() {
            current.push(ch);
        } else if !current.is_empty() {
            emit_token(&current, &mut terms);
            current.clear();
        }
    }
    if !current.is_empty() {
        emit_token(&current, &mut terms);
    }
    terms
}

fn emit_token(chars: &[char], terms: &mut Vec<String>) {
    let all_digits = chars.iter().all(|ch| ch.is_ascii_digit());
    if all_digits {
        let token: String = chars.iter().collect();
        terms.push(token);
        if chars.len() > 4 && chars.len() <= MAX_NUMERIC_FRAGMENT {
            for length in 4..chars.len() {
                for start in 0..=chars.len() - length {
                    terms.push(chars[start..start + length].iter().collect());
                }
            }
        }
        return;
    }
    let cjk_count = chars.iter().filter(|ch| is_cjk(**ch)).count();
    if cjk_count == chars.len() {
        for ch in chars {
            terms.push(ch.to_string());
        }
        for pair in chars.windows(2) {
            terms.push(pair.iter().collect());
        }
        return;
    }
    terms.push(chars.iter().collect());
    for (index, ch) in chars.iter().enumerate() {
        if is_cjk(*ch) {
            terms.push(ch.to_string());
            if index + 1 < chars.len() && is_cjk(chars[index + 1]) {
                terms.push(chars[index..index + 2].iter().collect());
            }
        }
    }
}

fn find_from(hay: &[char], needle: &[char], from: usize) -> Option<usize> {
    if needle.is_empty() || needle.len() > hay.len() {
        return None;
    }
    let last = hay.len() - needle.len();
    let mut index = from;
    while index <= last {
        if hay[index..index + needle.len()] == needle[..] {
            return Some(index);
        }
        index += 1;
    }
    None
}

fn build_snippet(document: &Document, terms: &[String]) -> (String, Vec<(u32, u32)>) {
    let chars: Vec<char> = document.body.chars().collect();
    if chars.is_empty() {
        return (String::new(), Vec::new());
    }
    let folded: Vec<char> = chars.iter().map(|&ch| normalize_char(ch)).collect();
    let offsets = utf16::offsets(&chars);

    let mut hit: Option<usize> = None;
    for term in terms.iter().take(6) {
        let needle: Vec<char> = term.chars().collect();
        if needle.is_empty() || needle.len() > 48 {
            continue;
        }
        if let Some(pos) = find_from(&folded, &needle, 0) {
            hit = Some(match hit {
                Some(existing) => existing.min(pos),
                None => pos,
            });
        }
    }

    let start_char = match hit {
        Some(pos) => utf16::char_index_at(&offsets, offsets[pos].saturating_sub(SNIPPET_LEAD as u32)),
        None => 0,
    };
    let limit_unit = offsets[start_char] + SNIPPET_UNITS as u32;
    let end_char = utf16::char_index_at(&offsets, limit_unit).min(chars.len());
    let end_char = end_char.max(start_char);

    let prefix_units = if start_char > 0 { 1u32 } else { 0 };
    let prefix = if start_char > 0 { "…" } else { "" };
    let suffix = if end_char < chars.len() { "…" } else { "" };
    let snippet: String = format!(
        "{}{}{}",
        prefix,
        chars[start_char..end_char].iter().collect::<String>(),
        suffix
    );

    let mut ranges: Vec<(u32, u32)> = Vec::new();
    for term in terms {
        let needle: Vec<char> = term.chars().collect();
        if needle.is_empty() || needle.len() > end_char.saturating_sub(start_char) {
            continue;
        }
        let mut pos = start_char;
        while pos + needle.len() <= end_char {
            if folded[pos..pos + needle.len()] == needle[..] {
                let start = offsets[pos] - offsets[start_char] + prefix_units;
                let end = offsets[pos + needle.len()] - offsets[start_char] + prefix_units;
                ranges.push((start, end));
                pos += needle.len();
            } else {
                pos += 1;
            }
        }
        if ranges.len() >= MAX_HIGHLIGHTS {
            break;
        }
    }
    ranges.sort_unstable();
    let mut merged: Vec<(u32, u32)> = Vec::new();
    for (start, end) in ranges {
        let mut absorbed = false;
        if let Some(last) = merged.last_mut() {
            if start <= last.1 {
                if end > last.1 {
                    last.1 = end;
                }
                absorbed = true;
            }
        }
        if !absorbed {
            merged.push((start, end));
        }
    }
    (snippet, merged)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Vec<Document> {
        vec![
            Document {
                id: 1,
                thread_id: 11,
                address: "10086".into(),
                body: "您的验证码为 123456，5分钟内有效".into(),
                date: now_ms(),
                read: false,
            },
            Document {
                id: 2,
                thread_id: 12,
                address: "95588".into(),
                body: "招商银行账单已出，点击查看".into(),
                date: now_ms() - 10 * 24 * 60 * 60 * 1000,
                read: true,
            },
            Document {
                id: 3,
                thread_id: 13,
                address: "张三".into(),
                body: "今晚一起吃饭吗？验证码稍后发你".into(),
                date: now_ms() - 30 * 24 * 60 * 60 * 1000,
                read: true,
            },
        ]
    }

    #[test]
    fn indexes_and_searches_chinese() {
        let mut index = Index::default();
        assert_eq!(index.rebuild(sample()), 3);
        let hits = index.search("验证码", 10);
        assert_eq!(hits.len(), 2);
        assert_eq!(hits[0].id, 1);
        assert!(hits[0].snippet.contains("验证码"));
        assert!(!hits[0].highlights.is_empty());
    }

    #[test]
    fn empty_query_and_zero_limit_return_nothing() {
        let mut index = Index::default();
        index.rebuild(sample());
        assert!(index.search("", 10).is_empty());
        assert!(index.search("   ", 10).is_empty());
        assert!(index.search("！！！", 10).is_empty());
        assert!(index.search("验证码", 0).is_empty());
        assert!(index.search("zzzz", 10).is_empty());
        assert!(index.search("🦄", 10).is_empty());
    }

    #[test]
    fn address_weight_beats_body_weight() {
        let mut index = Index::default();
        index.rebuild(vec![
            Document {
                id: 1,
                thread_id: 1,
                address: "alice".into(),
                body: "你好".into(),
                date: 0,
                read: true,
            },
            Document {
                id: 2,
                thread_id: 2,
                address: "bob".into(),
                body: "alice 你好".into(),
                date: 0,
                read: true,
            },
        ]);
        let hits = index.search("alice", 10);
        assert_eq!(hits.len(), 2);
        assert_eq!(hits[0].id, 1, "号码匹配权重更高");
    }

    #[test]
    fn numeric_fragments_are_searchable() {
        let mut index = Index::default();
        index.rebuild(vec![Document {
            id: 7,
            thread_id: 7,
            address: "客服".into(),
            body: "您的订单 13800138000 已发货".into(),
            date: 0,
            read: true,
        }]);
        assert_eq!(index.search("13800138000", 10).len(), 1);
        assert_eq!(index.search("8000", 10).len(), 1);
        assert_eq!(index.search("0013", 10).len(), 1);
        assert!(index.search("9999", 10).is_empty());
    }

    #[test]
    fn fullwidth_and_case_are_normalized() {
        let mut index = Index::default();
        index.rebuild(vec![Document {
            id: 9,
            thread_id: 9,
            address: "Bank".into(),
            body: "Your ABC code".into(),
            date: 0,
            read: true,
        }]);
        assert_eq!(index.search("abc", 10).len(), 1);
        assert_eq!(index.search("ＡＢＣ", 10).len(), 1);
        assert_eq!(index.search("bank", 10).len(), 1);
    }

    #[test]
    fn highlights_use_utf16_units_after_emoji() {
        let mut index = Index::default();
        index.rebuild(vec![Document {
            id: 5,
            thread_id: 5,
            address: "10086".into(),
            body: "🌿验证码 123456".into(),
            date: 0,
            read: true,
        }]);
        let hits = index.search("验证码", 10);
        assert_eq!(hits.len(), 1);
        let (start, end) = hits[0].highlights[0];
        assert_eq!(start, 2, "emoji 占 2 个 UTF-16 码元");
        assert_eq!(end, 5);
        let snippet: Vec<u16> = hits[0].snippet.encode_utf16().collect();
        assert_eq!(&snippet[start as usize..end as usize], &[0x9A8C, 0x8BC1, 0x7801]);
    }

    #[test]
    fn snippet_is_bounded_and_ellipsized() {
        let long_body = format!("{} 关键词 {}", "前".repeat(3000), "后".repeat(3000));
        let mut index = Index::default();
        index.rebuild(vec![Document {
            id: 6,
            thread_id: 6,
            address: "x".into(),
            body: long_body,
            date: 0,
            read: true,
        }]);
        let hits = index.search("关键词", 10);
        assert_eq!(hits.len(), 1);
        let units = utf16::utf16_len(&hits[0].snippet);
        assert!(units <= SNIPPET_UNITS + 2, "snippet units = {units}");
        assert!(hits[0].snippet.starts_with('…'));
        assert!(hits[0].snippet.ends_with('…'));
        for (start, end) in &hits[0].highlights {
            assert!(start < end);
            assert!(*end as usize <= units);
        }
    }

    #[test]
    fn highlights_are_sorted_and_merged() {
        let mut index = Index::default();
        index.rebuild(vec![Document {
            id: 8,
            thread_id: 8,
            address: "x".into(),
            body: "验证码 验证码".into(),
            date: 0,
            read: true,
        }]);
        let hits = index.search("验证码 验证", 10);
        assert_eq!(hits.len(), 1);
        let highlights = &hits[0].highlights;
        assert!(!highlights.is_empty());
        for pair in highlights.windows(2) {
            assert!(pair[0].1 <= pair[1].0, "范围必须升序且不重叠");
        }
    }

    #[test]
    fn limit_is_capped_and_docs_are_capped() {
        let docs: Vec<Document> = (0..150)
            .map(|i| Document {
                id: i,
                thread_id: i,
                address: "10086".into(),
                body: "验证码 123456".into(),
                date: 0,
                read: true,
            })
            .collect();
        let mut index = Index::default();
        assert_eq!(index.rebuild(docs), 150);
        assert_eq!(index.search("验证码", 1000).len(), MAX_RESULTS);
    }

    #[test]
    fn body_is_truncated_to_four_thousand_chars() {
        let mut index = Index::default();
        index.rebuild(vec![Document {
            id: 1,
            thread_id: 1,
            address: "x".into(),
            body: format!("{}TAILMARK", "字".repeat(10_000)),
            date: 0,
            read: true,
        }]);
        assert!(index.search("tailmark", 10).is_empty());
        assert_eq!(index.search("字", 10).len(), 1);
    }

    #[test]
    fn concurrent_reads_are_safe() {
        let mut index = Index::default();
        index.rebuild(sample());
        let handles: Vec<_> = (0..4)
            .map(|_| std::thread::spawn(|| search_messages("验证码", 5).len()))
            .collect();
        for handle in handles {
            assert!(handle.join().is_ok());
        }
    }

    #[test]
    fn root_path_is_recorded() {
        set_root("/tmp/qingniao-search-root");
        assert_eq!(root(), Some(PathBuf::from("/tmp/qingniao-search-root")));
    }
}
