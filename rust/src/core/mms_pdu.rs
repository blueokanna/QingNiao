
use crate::core::wsp::{
    charset_from_name, decode_text, is_multipart, read_text_bytes, read_text_string,
    well_known_content_type, well_known_index, write_long_integer, write_text_string, write_uintvar,
    write_value_length, Cursor, CHARSET_UTF8,
};

pub const MAX_PDU_BYTES: usize = 2 * 1024 * 1024;
const MAX_PARTS: u32 = 64;
const TEXT_PLAIN_INDEX: u8 = 3;
const MULTIPART_MIXED_INDEX: u8 = 35;
const MESSAGE_TYPE_RETRIEVE_CONF: u8 = 132;

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Attachment {
    pub mime: String,
    pub name: String,
    pub data: Vec<u8>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct DecodedMms {
    pub sender: String,
    pub recipients: Vec<String>,
    pub subject: String,
    pub text: String,
    pub date_ms: i64,
    pub attachments: Vec<Attachment>,
    pub message_type: i32,
}

fn read_encoded_string(cursor: &mut Cursor) -> Option<String> {
    let first = cursor.peek()?;
    let bounded = if first < 0x20 {
        let length = cursor.value_length()?;
        Some(cursor.pos.saturating_add(length).min(cursor.data.len()))
    } else {
        None
    };
    let region_end = bounded.unwrap_or(cursor.data.len());
    let mut scan = cursor.pos;
    // address-present-token
    if scan < region_end && cursor.data[scan] == 0x80 {
        scan += 1;
    }
    if scan < region_end && cursor.data[scan] < 0x20 {
        let byte = cursor.data[scan];
        if byte <= 30 {
            scan += 1;
        } else if byte == 0x1F {
            scan += 1;
            while scan < region_end && cursor.data[scan] & 0x80 != 0 {
                scan += 1;
            }
            scan = (scan + 1).min(region_end);
        }
    }
    let mut charset = None;
    if scan < region_end && cursor.data[scan] >= 0x80 {
        charset = Some((cursor.data[scan] & 0x7F) as u32);
        scan += 1;
    }
    cursor.pos = scan;
    if bounded.is_some() && scan >= region_end {
        cursor.pos = region_end;
        return Some(String::new());
    }
    let bytes = read_text_bytes(cursor).unwrap_or_default();
    let value = decode_text(&bytes, charset);
    if let Some(end) = bounded {
        cursor.pos = end;
    }
    Some(value)
}

fn read_address_value(cursor: &mut Cursor) -> Option<String> {
    read_encoded_string(cursor).map(|value| clean_address(&value))
}

fn clean_address(value: &str) -> String {
    let trimmed = value.trim();
    let without_type = match trimmed.find('/') {
        Some(index) if index > 0 => &trimmed[..index],
        _ => trimmed,
    };
    without_type.trim().trim_matches('"').to_string()
}

fn skip_value(cursor: &mut Cursor) {
    let first = match cursor.peek() {
        Some(byte) => byte,
        None => return,
    };
    match first {
        0 => {
            cursor.pos += 1;
        }
        0x01..=0x1F => match cursor.value_length() {
            Some(length) => cursor.skip(length),
            None => cursor.pos = cursor.data.len(),
        },
        0x20..=0x7F => {
            let _ = read_text_bytes(cursor);
        }
        _ => {
            cursor.pos += 1;
        }
    }
}

fn read_media_type(cursor: &mut Cursor) -> Option<String> {
    let first = cursor.peek()?;
    if first >= 0x80 {
        let index = cursor.short_integer()? as usize;
        return Some(well_known_content_type(index).unwrap_or("*/*").to_string());
    }
    if first == 0 {
        cursor.pos += 1;
        return Some("*/*".to_string());
    }
    let bytes = read_text_bytes(cursor)?;
    Some(decode_text(&bytes, None))
}

fn read_charset_parameter(cursor: &mut Cursor) -> Option<u32> {
    match cursor.peek() {
        Some(byte) if byte >= 0x80 => cursor.short_integer().map(|value| value as u32),
        Some(0) => {
            cursor.pos += 1;
            None
        }
        Some(_) => {
            read_text_bytes(cursor).map(|bytes| charset_from_name(&decode_text(&bytes, None)))
        }
        None => None,
    }
}

type ContentTypeInfo = (String, Option<u32>, Option<String>);

fn read_content_type(cursor: &mut Cursor) -> Option<ContentTypeInfo> {
    let first = cursor.peek()?;
    if first >= 0x80 {
        let index = cursor.short_integer()? as usize;
        return Some((
            well_known_content_type(index).unwrap_or("*/*").to_string(),
            None,
            None,
        ));
    }
    if first == 0 {
        cursor.pos += 1;
        return Some(("*/*".to_string(), None, None));
    }
    if first < 0x20 {
        let length = cursor.value_length()?;
        let end = cursor.pos.saturating_add(length).min(cursor.data.len());
        let mime = read_media_type(cursor)?;
        let mut charset = None;
        let mut name = None;
        let mut guard = 0;
        while cursor.pos < end {
            guard += 1;
            if guard > 64 {
                break;
            }
            let parameter = match cursor.take() {
                Some(parameter) => parameter,
                None => break,
            };
            if parameter < 0x80 {
                break;
            }
            match parameter {
                0x81 => charset = read_charset_parameter(cursor),
                0x85 | 0x97 => {
                    name = read_text_bytes(cursor).map(|bytes| decode_text(&bytes, None))
                }
                0x83 | 0x89 | 0x8A | 0x99 => {
                    let _ = read_text_bytes(cursor);
                }
                _ => skip_value(cursor),
            }
        }
        cursor.pos = end;
        return Some((mime, charset, name));
    }
    let bytes = read_text_bytes(cursor)?;
    Some((decode_text(&bytes, None), None, None))
}

fn looks_like_parameter_block(cursor: &Cursor, length: u8) -> bool {
    if length == 0 || length > 30 {
        return false;
    }
    let end = match cursor.pos.checked_add(length as usize) {
        Some(end) if end <= cursor.data.len() => end,
        _ => return false,
    };
    let mut scan = cursor.pos;
    while scan < end {
        let parameter = cursor.data[scan];
        if !matches!(parameter, 0x81 | 0x83 | 0x85 | 0x89 | 0x8A | 0x97 | 0x99) {
            return false;
        }
        scan += 1;
        if scan >= end {
            return false;
        }
        if cursor.data[scan] == 0x7F {
            scan += 1;
        }
        if scan >= end {
            return false;
        }
        if cursor.data[scan] >= 0x80 {
            scan += 1;
        } else {
            while scan < end && cursor.data[scan] != 0 {
                scan += 1;
            }
            if scan >= end {
                return false;
            }
            scan += 1;
        }
    }
    scan == end
}

pub fn decode(bytes: &[u8]) -> Option<DecodedMms> {
    if bytes.is_empty() || bytes.len() > MAX_PDU_BYTES {
        return None;
    }
    let mut cursor = Cursor::new(bytes);
    let mut message = DecodedMms::default();
    let mut content_type = String::new();

    let mut guard = 0usize;
    while !cursor.eof() {
        guard += 1;
        if guard > 256 {
            return None;
        }
        let header_pos = cursor.pos;
        let header = match cursor.take() {
            Some(header) => header,
            None => break,
        };
        if header < 0x80 {
            if !content_type.is_empty() && looks_like_parameter_block(&cursor, header) {
                cursor.skip(header as usize);
                continue;
            }
            cursor.pos = header_pos;
            break;
        }
        let start = cursor.pos;
        match header {
            0x8C => message.message_type = cursor.take()? as i32,
            // Content-Type
            0x84 => {
                let (mime, charset, _) = match read_content_type(&mut cursor) {
                    Some(info) => info,
                    None => return None,
                };
                content_type = mime;
                if !is_multipart(&content_type) {
                    let rest = &cursor.data[cursor.pos..];
                    let text = decode_text(rest, charset);
                    if !text.is_empty() {
                        message.text = text;
                    }
                    cursor.pos = cursor.data.len();
                    break;
                }
            }
            0x85 => {
                let seconds = cursor.long_integer()?;
                message.date_ms = (seconds as i64).saturating_mul(1000);
            }
            // From
            0x89 => message.sender = read_address_value(&mut cursor).unwrap_or_default(),
            // To / Cc / Bcc
            0x97 => {
                if let Some(value) = read_address_value(&mut cursor) {
                    if !value.is_empty() {
                        message.recipients.push(value);
                    }
                }
            }
            0x82 | 0x81 => {
                let _ = read_address_value(&mut cursor);
            }
            // Subject
            0x96 => message.subject = read_encoded_string(&mut cursor).unwrap_or_default(),
            0x8A => {
                let _ = cursor.take();
            }
            // X-Mms-MMS-Version：Short-integer
            0x8D => {
                let _ = cursor.short_integer();
            }
            0x98 | 0x8B | 0x93 | 0x9A | 0x83 => {
                let _ = read_text_bytes(&mut cursor);
            }
            // X-Mms-Expiry / Delivery-Time：Value-length (token Long-integer)
            0x88 | 0x87 => {
                let length = cursor.value_length()?;
                let end = cursor.pos.saturating_add(length).min(cursor.data.len());
                let _ = cursor.take();
                let _ = cursor.long_integer();
                cursor.pos = end;
            }
            _ => skip_value(&mut cursor),
        }
        if cursor.pos <= start {
            cursor.pos = start + 1;
        }
    }

    if content_type.is_empty() {
        return None;
    }
    if is_multipart(&content_type) && !parse_multipart(&mut cursor, &mut message) {
        return None;
    }
    Some(message)
}

fn parse_multipart(cursor: &mut Cursor, message: &mut DecodedMms) -> bool {
    let count = match cursor.uintvar() {
        Some(count) => count.min(MAX_PARTS),
        None => return false,
    };
    for _ in 0..count {
        let headers_len = match cursor.uintvar() {
            Some(value) => value as usize,
            None => return false,
        };
        let data_len = match cursor.uintvar() {
            Some(value) => value as usize,
            None => return false,
        };
        let headers_start = cursor.pos;
        let headers_end = match headers_start.checked_add(headers_len) {
            Some(end) if end <= cursor.data.len() => end,
            _ => return false,
        };
        let (mime, charset, mut name) = match read_content_type(cursor) {
            Some(info) => info,
            None => return false,
        };
        if cursor.pos > headers_end {
            return false;
        }
        while cursor.pos < headers_end {
            let parameter = match cursor.take() {
                Some(parameter) => parameter,
                None => return false,
            };
            if parameter < 0x80 {
                break;
            }
            match parameter {
                0x8E | 0xC1 | 0xC5 | 0xAE => {
                    if let Some(value) = read_text_string(cursor) {
                        if !value.trim().is_empty() && name.is_none() {
                            name = Some(value);
                        }
                    }
                }
                0xC0 => {
                    let _ = read_text_bytes(cursor);
                }
                _ => skip_value(cursor),
            }
        }
        cursor.pos = headers_end;

        let data_end = match headers_end.checked_add(data_len) {
            Some(end) if end <= cursor.data.len() => end,
            _ => return false,
        };
        let data = &cursor.data[headers_end..data_end];
        cursor.pos = data_end;
        classify_part(&mime, charset, name, data, message);
    }
    true
}

fn classify_part(
    mime: &str,
    charset: Option<u32>,
    name: Option<String>,
    data: &[u8],
    message: &mut DecodedMms,
) {
    let lower = mime.to_ascii_lowercase();
    if lower == "application/smil" || lower == "application/smil+xml" {
        return;
    }
    if lower.starts_with("text/") && lower != "text/x-vcard" && lower != "text/x-vcalendar" {
        let text = decode_text(data, charset);
        if !text.trim().is_empty() {
            if message.text.is_empty() {
                message.text = text;
            } else {
                message.text.push('\n');
                message.text.push_str(&text);
            }
        }
        return;
    }
    if data.is_empty() {
        return;
    }
    let file_name = match name {
        Some(name) if !name.trim().is_empty() => name.trim().to_string(),
        _ => default_name(&lower),
    };
    message.attachments.push(Attachment {
        mime: mime.to_owned(),
        name: file_name,
        data: data.to_vec(),
    });
}

fn default_name(mime: &str) -> String {
    let extension = match mime {
        "image/jpeg" => "jpg",
        "image/png" => "png",
        "image/gif" => "gif",
        "image/tiff" => "tiff",
        "image/vnd.wap.wbmp" => "wbmp",
        "audio/amr" => "amr",
        "video/mp4" | "audio/mp4" => "mp4",
        "text/x-vcard" => "vcf",
        _ => "bin",
    };
    format!("attachment.{}", extension)
}

fn write_encoded_string(out: &mut Vec<u8>, value: &str) {
    let mut inner: Vec<u8> = Vec::with_capacity(value.len() + 4);
    inner.push(0x80 | CHARSET_UTF8 as u8);
    write_text_string(&mut inner, value.as_bytes());
    write_value_length(out, inner.len() as u32);
    out.extend_from_slice(&inner);
}

fn write_parameter_text(out: &mut Vec<u8>, parameter: u8, value: &str) {
    out.push(parameter);
    write_text_string(out, value.as_bytes());
}

fn address_with_type(address: &str) -> String {
    let trimmed = address.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    if trimmed.contains('/') || trimmed.contains('@') {
        return trimmed.to_string();
    }
    let digits = trimmed.chars().filter(|ch| ch.is_ascii_digit()).count();
    let phone_like = trimmed
        .chars()
        .all(|ch| ch.is_ascii_digit() || matches!(ch, '+' | '-' | ' ' | '(' | ')'));
    if phone_like && digits >= 3 {
        format!("{}/TYPE=PLMN", trimmed)
    } else {
        trimmed.to_string()
    }
}

fn transaction_id() -> String {
    uuid::Uuid::new_v4().simple().to_string()
}

fn now_seconds() -> u64 {
    match std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH) {
        Ok(duration) => duration.as_secs(),
        Err(_) => 0,
    }
}

fn write_part(out: &mut Vec<u8>, content_type: &[u8], location: Option<&str>, data: &[u8]) {
    let mut headers: Vec<u8> = Vec::new();
    write_value_length(&mut headers, content_type.len() as u32);
    headers.extend_from_slice(content_type);
    if let Some(location) = location {
        headers.push(0x8E);
        write_text_string(&mut headers, location.as_bytes());
    }
    write_uintvar(out, headers.len() as u32);
    write_uintvar(out, data.len() as u32);
    out.extend_from_slice(&headers);
    out.extend_from_slice(data);
}

pub fn encode(
    recipients: &[String],
    text: &str,
    subject: &str,
    attachments: &[Attachment],
) -> Vec<u8> {
    let mut out: Vec<u8> = Vec::with_capacity(256 + text.len());
    out.push(0x8C);
    out.push(MESSAGE_TYPE_RETRIEVE_CONF);
    out.push(0x98);
    write_text_string(&mut out, transaction_id().as_bytes());
    out.push(0x8D);
    out.push(0x80 | 0x12); // MMS 1.2
    out.push(0x85);
    write_long_integer(&mut out, now_seconds());

    out.push(0x89);
    out.push(0x01);
    out.push(0x81);

    for recipient in recipients.iter().take(16) {
        out.push(0x97);
        write_encoded_string(&mut out, &address_with_type(recipient));
    }
    out.push(0x96);
    write_encoded_string(&mut out, subject);
    out.push(0x8A);
    out.push(0x80); // personal
    out.push(0x84);
    out.push(0x80 | MULTIPART_MIXED_INDEX);

    struct Part {
        content_type: Vec<u8>,
        location: String,
        data: Vec<u8>,
    }
    let mut parts: Vec<Part> = Vec::new();
    if !text.is_empty() {
        let mut content_type: Vec<u8> = Vec::new();
        content_type.push(0x80 | TEXT_PLAIN_INDEX);
        write_parameter_text(&mut content_type, 0x85, "message.txt");
        write_parameter_text(&mut content_type, 0x81, "utf-8");
        parts.push(Part {
            content_type,
            location: "message.txt".to_string(),
            data: text.as_bytes().to_vec(),
        });
    }
    for attachment in attachments {
        let mime = attachment.mime.trim().to_ascii_lowercase();
        let mime = if mime.is_empty() {
            "application/octet-stream".to_string()
        } else {
            mime
        };
        let mut content_type: Vec<u8> = Vec::new();
        match well_known_index(&mime) {
            Some(index) => content_type.push(0x80 | index),
            None => write_text_string(&mut content_type, mime.as_bytes()),
        }
        let name = if attachment.name.trim().is_empty() {
            default_name(&mime)
        } else {
            attachment.name.trim().to_string()
        };
        write_parameter_text(&mut content_type, 0x85, &name);
        if mime.starts_with("text/") {
            write_parameter_text(&mut content_type, 0x81, "utf-8");
        }
        parts.push(Part {
            content_type,
            location: name,
            data: attachment.data.clone(),
        });
    }

    write_uintvar(&mut out, parts.len() as u32);
    for part in &parts {
        write_part(
            &mut out,
            &part.content_type,
            Some(part.location.as_str()),
            &part.data,
        );
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn attachment(mime: &str, name: &str, data: &[u8]) -> Attachment {
        Attachment {
            mime: mime.into(),
            name: name.into(),
            data: data.to_vec(),
        }
    }

    #[test]
    fn round_trip_text_and_attachments() {
        let recipients = vec!["+8613800138000".to_string(), "\u{5f20}\u{4e09}".to_string()];
        let text = "\u{4f60}\u{597d}🌿，\u{8fd9}\u{662f}\u{4e00}\u{6761}\u{5f69}\u{4fe1}。\n\u{7b2c}\u{4e8c}\u{884c}";
        let attachments = vec![
            attachment("image/jpeg", "photo.jpg", &[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0xD9]),
            attachment("audio/amr", "voice.amr", b"#!AMR\n...."),
        ];
        let pdu = encode(&recipients, text, "\u{6807}\u{9898} subject", &attachments);
        let decoded = decode(&pdu).expect("decode");
        assert_eq!(decoded.message_type, 132);
        assert_eq!(decoded.recipients, recipients);
        assert_eq!(decoded.subject, "\u{6807}\u{9898} subject");
        assert_eq!(decoded.text, text);
        assert!(decoded.date_ms > 1_600_000_000_000);
        assert_eq!(decoded.attachments, attachments);
        assert_eq!(decoded.sender, "", "insert-address-token \u{8868}\u{793a}\u{672c}\u{673a}");
    }

    #[test]
    fn round_trip_without_attachments() {
        let pdu = encode(&["10086".into()], "\u{53ea}\u{6709}\u{6587}\u{672c}", "", &[]);
        let decoded = decode(&pdu).expect("decode");
        assert_eq!(decoded.text, "\u{53ea}\u{6709}\u{6587}\u{672c}");
        assert!(decoded.attachments.is_empty());
        assert_eq!(decoded.recipients, vec!["10086".to_string()]);
    }

    #[test]
    fn round_trip_empty_content() {
        let pdu = encode(&[], "", "", &[]);
        let decoded = decode(&pdu).expect("decode");
        assert_eq!(decoded.message_type, 132);
        assert!(decoded.text.is_empty());
        assert!(decoded.attachments.is_empty());
        assert!(decoded.recipients.is_empty());
    }

    #[test]
    fn decodes_address_present_token_from() {
        let mut pdu: Vec<u8> = vec![0x8C, 0x84];
        let mut inner: Vec<u8> = vec![0x80 | CHARSET_UTF8 as u8];
        write_text_string(&mut inner, b"10086/TYPE=PLMN");
        let mut value: Vec<u8> = vec![0x80];
        value.push(inner.len() as u8);
        value.extend_from_slice(&inner);
        pdu.push(0x89);
        pdu.push(value.len() as u8);
        pdu.extend_from_slice(&value);
        pdu.push(0x84);
        pdu.push(0x80 | MULTIPART_MIXED_INDEX);
        let mut content_type: Vec<u8> = vec![0x80 | TEXT_PLAIN_INDEX];
        write_parameter_text(&mut content_type, 0x81, "utf-8");
        write_uintvar(&mut pdu, 1);
        write_part(&mut pdu, &content_type, None, "\u{6765}\u{81ea} 10086".as_bytes());

        let decoded = decode(&pdu).expect("decode");
        assert_eq!(decoded.sender, "10086");
        assert_eq!(decoded.text, "\u{6765}\u{81ea} 10086");
    }

    #[test]
    fn skips_unknown_headers() {
        let pdu = encode(&["10086".into()], "\u{672a}\u{77e5}\u{5934}\u{6d4b}\u{8bd5}", "", &[]);
        let mut injected: Vec<u8> = vec![0xA5, 0x03, b'x', b'y', b'z'];
        injected.extend_from_slice(&pdu);
        let decoded = decode(&injected).expect("decode");
        assert_eq!(decoded.text, "\u{672a}\u{77e5}\u{5934}\u{6d4b}\u{8bd5}");
        assert_eq!(decoded.message_type, 132);
    }

    #[test]
    fn rejects_truncated_and_invalid_lengths() {
        let pdu = encode(&["10086".into()], "\u{622a}\u{65ad}\u{6d4b}\u{8bd5}", "\u{4e3b}\u{9898}", &[]);
        assert!(decode(&pdu[..2]).is_none(), "\u{7f3a}\u{5c11} Content-Type");
        assert!(decode(&pdu[..6]).is_none());
        assert!(decode(&pdu[..pdu.len() / 2]).is_none(), "\u{6b63}\u{6587}\u{88ab}\u{622a}\u{65ad}");
        assert!(decode(&[]).is_none());

        let mut broken: Vec<u8> = vec![0x8C, 0x84, 0x84, 0x80 | MULTIPART_MIXED_INDEX];
        broken.extend_from_slice(&[0x01, 0x7F, 0x00]);
        assert!(decode(&broken).is_none());

        let mut broken: Vec<u8> = vec![0x8C, 0x84, 0x84, 0x80 | MULTIPART_MIXED_INDEX];
        broken.extend_from_slice(&[0x01, 0x04, 0x7F, 0x83, 0x00, 0x00]);
        assert!(decode(&broken).is_none());
    }

    #[test]
    fn rejects_oversized_and_garbage_input() {
        let oversized = vec![0u8; MAX_PDU_BYTES + 1];
        assert!(decode(&oversized).is_none());
        assert!(decode(&[0x00, 0x01, 0x02, 0x03]).is_none());
        assert!(decode(&[0xFF; 64]).is_none());
        let _ = decode(&[0xA5; 200]);
    }

    #[test]
    fn smil_parts_are_ignored() {
        let smil = b"<smil><body/></smil>";
        let pdu = encode(
            &["10086".into()],
            "\u{5e26} SMIL",
            "",
            &[attachment("application/smil", "smil.xml", smil)],
        );
        let decoded = decode(&pdu).expect("decode");
        assert_eq!(decoded.text, "\u{5e26} SMIL");
        assert!(decoded.attachments.is_empty(), "SMIL \u{53ea}\u{7528}\u{4e8e}\u{6392}\u{7248}，\u{88ab}\u{5ffd}\u{7565}");
    }

    #[test]
    fn recipient_with_type_suffix_is_cleaned() {
        let pdu = encode(&["13800138000".into()], "x", "", &[]);
        let decoded = decode(&pdu).expect("decode");
        assert_eq!(decoded.recipients, vec!["13800138000".to_string()]);
        assert_eq!(address_with_type("13800138000"), "13800138000/TYPE=PLMN");
        assert_eq!(address_with_type("alice@example.com"), "alice@example.com");
        assert_eq!(address_with_type(""), "");
        assert_eq!(address_with_type("+86 138 0013 8000"), "+86 138 0013 8000/TYPE=PLMN");
    }

    #[test]
    fn tolerates_content_type_parameter_block() {
        let mut pdu: Vec<u8> = vec![0x8C, 0x84, 0x84, 0x80 | MULTIPART_MIXED_INDEX];
        let mut parameters: Vec<u8> = Vec::new();
        parameters.push(0x8A);
        write_text_string(&mut parameters, b"<smil.xml>");
        parameters.push(0x89);
        write_text_string(&mut parameters, b"application/smil");
        assert!(parameters.len() <= 30);
        pdu.push(parameters.len() as u8);
        pdu.extend_from_slice(&parameters);

        let mut content_type: Vec<u8> = vec![0x80 | TEXT_PLAIN_INDEX];
        write_parameter_text(&mut content_type, 0x81, "utf-8");
        write_uintvar(&mut pdu, 1);
        write_part(&mut pdu, &content_type, None, "\u{53c2}\u{6570}\u{5757}\u{4e4b}\u{540e}\u{7684}\u{6b63}\u{6587}".as_bytes());

        let decoded = decode(&pdu).expect("decode");
        assert_eq!(decoded.text, "\u{53c2}\u{6570}\u{5757}\u{4e4b}\u{540e}\u{7684}\u{6b63}\u{6587}");
    }

    #[test]
    fn large_attachment_is_bounded() {
        let big = vec![0x5A; 300_000];
        let pdu = encode(
            &["10086".into()],
            "\u{5927}\u{9644}\u{4ef6}",
            "",
            &[attachment("image/png", "big.png", &big)],
        );
        let decoded = decode(&pdu).expect("decode");
        assert_eq!(decoded.attachments.len(), 1);
        assert_eq!(decoded.attachments[0].data.len(), big.len());
    }
}
