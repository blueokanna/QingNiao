
use crate::core::analysis;
use crate::core::crypto;
use crate::core::mms_pdu;
use crate::core::search;
use crate::core::segment;
use crate::core::store;


pub struct MessageAnalysis {
    pub category: String,
    pub otp: Option<String>,
    pub otp_start: u32,
    pub otp_end: u32,
    pub is_otp: bool,
    pub link: Option<String>,
    pub segments: u32,
    pub encoding: String,
    pub remaining: u32,
}

pub fn analyze_messages(bodies: Vec<String>) -> Vec<MessageAnalysis> {
    bodies
        .iter()
        .map(|body| {
            let result = analysis::analyze(body);
            MessageAnalysis {
                category: result.category,
                otp: result.otp,
                otp_start: result.otp_start,
                otp_end: result.otp_end,
                is_otp: result.is_otp,
                link: result.link,
                segments: result.segments,
                encoding: result.encoding,
                remaining: result.remaining,
            }
        })
        .collect()
}


pub struct SearchDoc {
    pub id: i64,
    pub thread_id: i64,
    pub address: String,
    pub body: String,
    pub date: i64,
    pub read: bool,
}

pub struct TextRange {
    pub start: u32,
    pub end: u32,
}

pub struct SearchHit {
    pub id: i64,
    pub thread_id: i64,
    pub score: f64,
    pub snippet: String,
    pub highlights: Vec<TextRange>,
}

pub fn engine_init(data_dir: String) -> bool {
    let initialized = store::init(&data_dir);
    if initialized {
        search::set_root(&data_dir);
    }
    initialized
}

pub fn index_messages(docs: Vec<SearchDoc>) -> u32 {
    let documents: Vec<search::Document> = docs
        .into_iter()
        .map(|doc| search::Document {
            id: doc.id,
            thread_id: doc.thread_id,
            address: doc.address,
            body: doc.body,
            date: doc.date,
            read: doc.read,
        })
        .collect();
    search::index_messages(documents)
}

pub fn search_messages(query: String, limit: u32) -> Vec<SearchHit> {
    search::search_messages(&query, limit)
        .into_iter()
        .map(|hit| SearchHit {
            id: hit.id,
            thread_id: hit.thread_id,
            score: hit.score,
            snippet: hit.snippet,
            highlights: hit
                .highlights
                .into_iter()
                .map(|(start, end)| TextRange { start, end })
                .collect(),
        })
        .collect()
}

pub fn indexed_count() -> u32 {
    search::indexed_count()
}


pub struct Segmentation {
    pub encoding: String,
    pub segments: u32,
    pub length: u32,
    pub remaining: u32,
    pub max_chars: u32,
}

pub fn segment_message(body: String) -> Segmentation {
    let result = segment::segmentation(&body);
    Segmentation {
        encoding: result.encoding,
        segments: result.segments,
        length: result.length,
        remaining: result.remaining,
        max_chars: result.max_chars,
    }
}


pub struct TrashEntry {
    pub id: i64,
    pub thread_id: i64,
    pub address: String,
    pub body: String,
    pub date: i64,
    pub kind: i32,
    pub deleted_at: i64,
}

pub fn trash_add(
    id: i64,
    thread_id: i64,
    address: String,
    body: String,
    date: i64,
    kind: i32,
) -> bool {
    store::trash_add(store::TrashEntry {
        id,
        thread_id,
        address,
        body,
        date,
        kind,
        deleted_at: 0,
    })
}

pub fn trash_entries() -> Vec<TrashEntry> {
    store::trash_entries()
        .into_iter()
        .map(|entry| TrashEntry {
            id: entry.id,
            thread_id: entry.thread_id,
            address: entry.address,
            body: entry.body,
            date: entry.date,
            kind: entry.kind,
            deleted_at: entry.deleted_at,
        })
        .collect()
}

pub fn trash_restore(id: i64) -> bool {
    store::trash_restore(id)
}

pub fn trash_remove(id: i64) -> bool {
    store::trash_remove(id)
}

pub fn trash_purge(retention_days: i32) -> u32 {
    store::trash_purge(retention_days)
}

pub fn settings_get(key: String) -> Option<String> {
    store::settings_get(&key)
}

pub fn settings_set(key: String, value: String) -> bool {
    store::settings_set(&key, &value)
}


pub struct MmsAttachmentData {
    pub mime: String,
    pub name: String,
    pub data: Vec<u8>,
}

pub struct DecodedMms {
    pub sender: String,
    pub recipients: Vec<String>,
    pub subject: String,
    pub text: String,
    pub date_ms: i64,
    pub attachments: Vec<MmsAttachmentData>,
    pub message_type: i32,
}

pub fn decode_mms_pdu(pdu: Vec<u8>) -> Option<DecodedMms> {
    mms_pdu::decode(&pdu).map(|decoded| DecodedMms {
        sender: decoded.sender,
        recipients: decoded.recipients,
        subject: decoded.subject,
        text: decoded.text,
        date_ms: decoded.date_ms,
        attachments: decoded
            .attachments
            .into_iter()
            .map(|attachment| MmsAttachmentData {
                mime: attachment.mime,
                name: attachment.name,
                data: attachment.data,
            })
            .collect(),
        message_type: decoded.message_type,
    })
}

pub fn encode_mms_pdu(
    recipients: Vec<String>,
    text: String,
    subject: String,
    attachments: Vec<MmsAttachmentData>,
) -> Vec<u8> {
    let converted: Vec<mms_pdu::Attachment> = attachments
        .into_iter()
        .map(|attachment| mms_pdu::Attachment {
            mime: attachment.mime,
            name: attachment.name,
            data: attachment.data,
        })
        .collect();
    mms_pdu::encode(&recipients, &text, &subject, &converted)
}


pub struct DeviceIdentity {
    pub device_id: String,
    pub public_key: String,
    pub fingerprint: String,
}

pub struct EncryptedEnvelope {
    pub ephemeral_public_key: String,
    pub nonce: String,
    pub ciphertext: String,
}

pub fn sync_init() -> Option<DeviceIdentity> {
    crypto::sync_init().map(|identity| DeviceIdentity {
        device_id: identity.device_id,
        public_key: identity.public_key,
        fingerprint: identity.fingerprint,
    })
}

pub fn sync_fingerprint(public_key_base64: String) -> String {
    crypto::sync_fingerprint(&public_key_base64)
}

pub fn sync_encrypt(target_public_key_base64: String, plaintext: String) -> Option<EncryptedEnvelope> {
    crypto::sync_encrypt(&target_public_key_base64, &plaintext).map(|envelope| EncryptedEnvelope {
        ephemeral_public_key: envelope.ephemeral_public_key,
        nonce: envelope.nonce,
        ciphertext: envelope.ciphertext,
    })
}

pub fn sync_decrypt(
    ephemeral_public_key_base64: String,
    nonce_base64: String,
    ciphertext_base64: String,
) -> Option<String> {
    crypto::sync_decrypt(
        &ephemeral_public_key_base64,
        &nonce_base64,
        &ciphertext_base64,
    )
}

pub fn sync_reset() -> bool {
    crypto::sync_reset()
}

#[cfg(test)]
mod tests {
    use super::*;
    use once_cell::sync::Lazy;
    use parking_lot::{Mutex, MutexGuard};
    use std::fs;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    static TEST_LOCK: Lazy<Mutex<()>> = Lazy::new(|| Mutex::new(()));

    fn guard() -> MutexGuard<'static, ()> {
        TEST_LOCK.lock()
    }

    fn temp_dir(tag: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_nanos())
            .unwrap_or(0);
        let dir = std::env::temp_dir().join(format!(
            "qingniao-engine-{}-{}-{}",
            tag,
            std::process::id(),
            nanos
        ));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    #[test]
    fn analyzes_messages_with_utf16_ranges() {
        let results = analyze_messages(vec![
            "🌿您的验证码是 246810，请勿泄露".into(),
            "退订回T".into(),
            String::new(),
        ]);
        assert_eq!(results.len(), 3);
        assert_eq!(results[0].category, "verification");
        assert_eq!(results[0].otp.as_deref(), Some("246810"));
        assert!(results[0].is_otp);
        assert_eq!(results[0].otp_start, 9);
        assert_eq!(results[0].otp_end, 15);
        assert_eq!(results[0].encoding, "UCS-2");
        assert_eq!(results[1].category, "promotion");
        assert!(!results[1].is_otp);
        assert_eq!(results[2].segments, 0);
        assert_eq!(results[2].remaining, 160);
        assert!(results[2].otp.is_none());
    }

    #[test]
    fn segment_message_exposes_capacity() {
        let single = segment_message("hello".into());
        assert_eq!(single.encoding, "GSM-7");
        assert_eq!(single.segments, 1);
        assert_eq!(single.length, 5);
        assert_eq!(single.remaining, 155);
        assert_eq!(single.max_chars, 160);

        let long = segment_message("中".repeat(80));
        assert_eq!(long.encoding, "UCS-2");
        assert_eq!(long.segments, 2);
        assert_eq!(long.max_chars, 67);
        assert_eq!(long.remaining, 54);
    }

    #[test]
    fn engine_init_is_idempotent_and_creates_dir() {
        let _guard = guard();
        let dir = temp_dir("init");
        let path = dir.to_str().unwrap().to_string();
        assert!(engine_init(path.clone()));
        assert!(dir.is_dir());
        assert!(engine_init(path.clone()));
        assert!(!engine_init("  ".into()));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn index_and_search_round_trip() {
        let _guard = guard();
        let dir = temp_dir("search");
        engine_init(dir.to_str().unwrap().to_string());
        let indexed = index_messages(vec![
            SearchDoc {
                id: 1,
                thread_id: 1,
                address: "10086".into(),
                body: "您的验证码为 123456".into(),
                date: 1_700_000_000_000,
                read: false,
            },
            SearchDoc {
                id: 2,
                thread_id: 2,
                address: "95588".into(),
                body: "银行账单已出".into(),
                date: 1_600_000_000_000,
                read: true,
            },
        ]);
        assert_eq!(indexed, 2);
        assert_eq!(indexed_count(), 2);

        let hits = search_messages("验证码".into(), 10);
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].id, 1);
        assert!(hits[0].snippet.contains("验证码"));
        assert!(!hits[0].highlights.is_empty());
        let range = &hits[0].highlights[0];
        assert!(range.start < range.end);

        assert!(search_messages("".into(), 10).is_empty());
        assert!(search_messages("no-such-term".into(), 10).is_empty());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn trash_flow_through_facade() {
        let _guard = guard();
        let dir = temp_dir("trash");
        engine_init(dir.to_str().unwrap().to_string());

        assert!(trash_add(
            1,
            10,
            "10086".into(),
            "第一条".into(),
            1_700_000_000_000,
            0
        ));
        assert!(trash_add(
            2,
            20,
            "张三".into(),
            "第二条".into(),
            1_700_000_000_001,
            1
        ));
        let entries = trash_entries();
        assert_eq!(entries.len(), 2);
        assert!(entries.iter().any(|entry| entry.id == 2));
        assert!(entries.iter().all(|entry| entry.deleted_at > 0));

        assert!(trash_restore(1));
        assert!(!trash_restore(1));
        assert_eq!(trash_entries().len(), 1);
        assert!(trash_remove(2));
        assert!(trash_entries().is_empty());
        assert_eq!(trash_purge(0), 0);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn settings_flow_through_facade() {
        let _guard = guard();
        let dir = temp_dir("settings");
        engine_init(dir.to_str().unwrap().to_string());
        assert!(settings_set("retention_days".into(), "7".into()));
        assert_eq!(
            settings_get("retention_days".into()).as_deref(),
            Some("7")
        );
        assert!(settings_get("missing".into()).is_none());
        assert!(!settings_set("".into(), "x".into()));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn mms_round_trip_through_facade() {
        let pdu = encode_mms_pdu(
            vec!["+8613800138000".into()],
            "你好，彩信".into(),
            "主题".into(),
            vec![MmsAttachmentData {
                mime: "image/jpeg".into(),
                name: "photo.jpg".into(),
                data: vec![0xFF, 0xD8, 0xFF, 0xD9],
            }],
        );
        let decoded = decode_mms_pdu(pdu).expect("decode");
        assert_eq!(decoded.recipients, vec!["+8613800138000".to_string()]);
        assert_eq!(decoded.subject, "主题");
        assert_eq!(decoded.text, "你好，彩信");
        assert_eq!(decoded.message_type, 132);
        assert!(decoded.date_ms > 0);
        assert_eq!(decoded.attachments.len(), 1);
        assert_eq!(decoded.attachments[0].mime, "image/jpeg");
        assert_eq!(decoded.attachments[0].data, vec![0xFF, 0xD8, 0xFF, 0xD9]);

        assert!(decode_mms_pdu(vec![]).is_none());
        assert!(decode_mms_pdu(vec![1, 2, 3]).is_none());
    }

    #[test]
    fn sync_round_trip_through_facade() {
        let _guard = guard();
        let dir = temp_dir("sync");
        engine_init(dir.to_str().unwrap().to_string());
        let identity = sync_init().expect("identity");
        assert!(!identity.device_id.is_empty());
        assert_eq!(identity.fingerprint.len(), 39);
        assert_eq!(
            sync_fingerprint(identity.public_key.clone()),
            identity.fingerprint
        );

        let envelope = sync_encrypt(identity.public_key.clone(), "同步载荷 🌿".into()).expect("seal");
        let opened = sync_decrypt(
            envelope.ephemeral_public_key,
            envelope.nonce,
            envelope.ciphertext,
        )
        .expect("open");
        assert_eq!(opened, "同步载荷 🌿");

        assert!(sync_encrypt("bad-key".into(), "x".into()).is_none());
        assert!(sync_decrypt("bad".into(), "bad".into(), "bad".into()).is_none());

        assert!(sync_reset());
        let regenerated = sync_init().expect("identity after reset");
        assert!(!regenerated.device_id.is_empty());
        assert_ne!(regenerated.device_id, identity.device_id);
        let _ = fs::remove_dir_all(&dir);
    }
}
