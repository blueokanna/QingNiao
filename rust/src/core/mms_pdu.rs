//! WAP-230/WSP 鐨?M-Retrieve.conf 瀛愰泦缂栬В鐮併€?//!
//! 鏀寔瑙ｇ爜锛?//! - 澶村瓧娈?`X-Mms-Message-Type(0x8C)`銆乣X-Mms-Transaction-Id(0x98)`銆乣Date(0x85)`銆?//!   `From(0x89)`銆乣To(0x97)`銆乣Cc(0x82)`銆乣Bcc(0x81)`銆乣Subject(0x96)`銆?//!   `Content-Type(0x84)`銆乣Message-Class(0x8A)`銆乣X-Mms-Expiry(0x88)` 绛夛紱
//! - 澶氶儴鍒嗘鏂囷紙`multipart.mixed` / `multipart.related` / `multipart.alternative`锛夛紝
//!   姣忛儴鍒?`HeadersLen DataLen Headers Data`锛?//! - 鏂囨湰閮ㄥ垎 `text/plain`锛圲TF-8 / UTF-16锛孏B2312 灏藉姏鑰屼负锛夛紱
//! - 闄勪欢锛歚image/jpeg|png|gif`銆乣audio/amr` 浠ュ強鍏跺畠鏈煡濯掍綋绫诲瀷銆?//!
//! 鏀寔缂栫爜锛氱敓鎴?`multipart.mixed`锛堟枃鏈儴鍒?+ 闄勪欢閮ㄥ垎锛夛紝甯︿笂杩板ご閮紝
//! `Date` 浣跨敤褰撳墠鏃堕棿锛宍From` 浣跨敤 insert-address-token銆?//!
//! 瀵规埅鏂€侀暱搴﹂潪娉曘€佽秴澶э紙> 2MB锛夎緭鍏ヨ繑鍥?`None`锛屼笉 panic銆?
/// 鍏佽瑙ｇ爜鐨勬渶澶?PDU 瀛楄妭鏁般€?pub const MAX_PDU_BYTES: usize = 2 * 1024 * 1024;
const MAX_PARTS: u32 = 64;
const CHARSET_UTF8: u32 = 106;
const CHARSET_UTF16: u32 = 1015;
const CHARSET_UCS2: u32 = 1000;
const CHARSET_GB2312: u32 = 2025;
const TEXT_PLAIN_INDEX: u8 = 3;
const MULTIPART_MIXED_INDEX: u8 = 35;
const MESSAGE_TYPE_RETRIEVE_CONF: u8 = 132;

/// 闄勪欢銆?#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Attachment {
    pub mime: String,
    pub name: String,
    pub data: Vec<u8>,
}

/// 瑙ｇ爜鍚庣殑褰╀俊銆?#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct DecodedMms {
    pub sender: String,
    pub recipients: Vec<String>,
    pub subject: String,
    pub text: String,
    pub date_ms: i64,
    pub attachments: Vec<Attachment>,
    pub message_type: i32,
}

/// WSP 宸茬煡濯掍綋绫诲瀷琛紙涓嬫爣鍗?well-known media 缂栧彿锛夈€?const CONTENT_TYPES: &[&str] = &[
    "*/*",
    "text/*",
    "text/html",
    "text/plain",
    "text/x-hdml",
    "text/x-ttml",
    "text/x-vCalendar",
    "text/x-vCard",
    "text/vnd.wap.wml",
    "text/vnd.wap.wmlscript",
    "text/vnd.wap.wta-event",
    "multipart/*",
    "multipart/mixed",
    "multipart/form-data",
    "multipart/byterantes",
    "multipart/alternative",
    "application/*",
    "application/java-vm",
    "application/x-www-form-urlencoded",
    "application/x-hdmlc",
    "application/vnd.wap.wmlc",
    "application/vnd.wap.wmlscriptc",
    "application/vnd.wap.wta-eventc",
    "application/vnd.wap.uaprof",
    "application/vnd.wap.wtls-ca-certificate",
    "application/vnd.wap.wtls-user-certificate",
    "application/x-x509-ca-cert",
    "application/x-x509-user-cert",
    "image/*",
    "image/gif",
    "image/jpeg",
    "image/tiff",
    "image/png",
    "image/vnd.wap.wbmp",
    "application/vnd.wap.multipart.*",
    "application/vnd.wap.multipart.mixed",
    "application/vnd.wap.multipart.form-data",
    "application/vnd.wap.multipart.byteranges",
    "application/vnd.wap.multipart.alternative",
    "application/xml",
    "text/xml",
    "application/vnd.wap.wbxml",
    "application/x-x968-cross-cert",
    "application/x-x968-ca-cert",
    "application/x-x968-user-cert",
    "text/vnd.wap.si",
    "application/vnd.wap.sic",
    "text/vnd.wap.sl",
    "application/vnd.wap.slc",
    "text/vnd.wap.co",
    "application/vnd.wap.coc",
    "application/vnd.wap.multipart.related",
    "application/vnd.wap.sia",
    "text/vnd.wap.connectivity-xml",
    "application/vnd.wap.connectivity-wbxml",
    "application/pkcs7-mime",
    "application/vnd.wap.hashed-certificate",
    "application/vnd.wap.signed-certificate",
    "application/vnd.wap.cert-response",
    "application/xhtml+xml",
    "application/wml+xml",
    "text/css",
    "application/vnd.wap.mms-message",
    "application/vnd.wap.rollover-certificate",
    "application/vnd.wap.locc+wbxml",
    "application/vnd.wap.loc+xml",
    "application/vnd.syncml.dm+wbxml",
    "application/vnd.syncml.dm+xml",
    "application/vnd.syncml.notification",
    "application/vnd.wap.xhtml+xml",
    "application/vnd.wv.csp.cir",
    "application/vnd.oma.dd+xml",
    "application/vnd.oma.drm.message",
    "application/vnd.oma.drm.content",
    "application/vnd.oma.drm.rights+xml",
    "application/vnd.oma.drm.rights+wbxml",
    "application/vnd.wv.csp+xml",
    "application/vnd.wv.csp+wbxml",
    "application/vnd.syncml.ds.notification",
    "audio/*",
    "video/*",
    "application/vnd.oma.dd2+xml",
    "application/mikey",
];

fn well_known_content_type(index: usize) -> Option<&'static str> {
    CONTENT_TYPES.get(index).copied()
}

fn well_known_index(mime: &str) -> Option<u8> {
    let lower = mime.trim().to_ascii_lowercase();
    CONTENT_TYPES
        .iter()
        .position(|candidate| *candidate == lower)
        .map(|index| index as u8)
}

fn is_multipart(mime: &str) -> bool {
    let lower = mime.to_ascii_lowercase();
    lower.starts_with("multipart/") || lower.contains("vnd.wap.multipart")
}

struct Cursor<'a> {
    data: &'a [u8],
    pos: usize,
}

impl<'a> Cursor<'a> {
    fn new(data: &'a [u8]) -> Self {
        Cursor { data, pos: 0 }
    }

    fn eof(&self) -> bool {
        self.pos >= self.data.len()
    }

    fn peek(&self) -> Option<u8> {
        self.data.get(self.pos).copied()
    }

    fn take(&mut self) -> Option<u8> {
        let byte = self.peek()?;
        self.pos += 1;
        Some(byte)
    }

    fn skip(&mut self, count: usize) {
        self.pos = self.pos.saturating_add(count).min(self.data.len());
    }

    /// WSP uintvar锛堟瘡瀛楄妭 7 浣嶏紝鏈€楂樹綅涓虹画浣嶏級銆?    fn uintvar(&mut self) -> Option<u32> {
        let mut value: u32 = 0;
        for count in 0..5 {
            let byte = self.take()?;
            value = (value << 7) | (byte & 0x7F) as u32;
            if byte & 0x80 == 0 {
                return Some(value);
            }
            if count == 4 {
                return None;
            }
        }
        None
    }

    /// 鍊奸暱搴︼細0-30 鍗曞瓧鑺傦紝31 鍚庤窡 uintvar銆?    fn value_length(&mut self) -> Option<usize> {
        let byte = self.take()?;
        if byte <= 30 {
            return Some(byte as usize);
        }
        if byte == 0x1F {
            return self.uintvar().map(|value| value as usize);
        }
        None
    }

    fn short_integer(&mut self) -> Option<u8> {
        self.take().map(|byte| byte & 0x7F)
    }

    fn long_integer(&mut self) -> Option<u64> {
        let count = self.take()?;
        if count > 8 {
            return None;
        }
        let mut value = 0u64;
        for _ in 0..count {
            let byte = self.take()?;
            value = (value << 8) | byte as u64;
        }
        Some(value)
    }
}

/// 璇诲彇 Text-string锛堝彲閫?0x7F quote 鍓嶇紑 + 浠?0x00 缁撳熬锛夈€?fn read_text_bytes(cursor: &mut Cursor) -> Option<Vec<u8>> {
    if cursor.peek() == Some(0x7F) {
        cursor.pos += 1;
    }
    let start = cursor.pos;
    while let Some(byte) = cursor.peek() {
        if byte == 0 {
            let bytes = cursor.data[start..cursor.pos].to_vec();
            cursor.pos += 1;
            return Some(bytes);
        }
        cursor.pos += 1;
    }
    // 缂虹粓姝㈢锛氬蹇嶅埌褰撳墠浣嶇疆
    if cursor.pos > start {
        Some(cursor.data[start..cursor.pos].to_vec())
    } else {
        None
    }
}

fn read_text_string(cursor: &mut Cursor) -> Option<String> {
    read_text_bytes(cursor).map(|bytes| decode_text(&bytes, None))
}

/// 璇诲彇 Encoded-string-value銆傚吋瀹逛笁绉嶅疄闄呭嚭鐜拌繃鐨勭紪鐮侊細
/// 1. `Text-string`锛?/// 2. `Value-length ( Short-integer charset Text-string )`锛圓ndroid 缂栫爜鍣級锛?/// 3. `Value-length ( Address-present-token Encoded-string-value )`锛堣鑼冨舰寮忥紝
///    鍐呴儴杩樺彲鑳藉啀濂椾竴灞?value-length锛夈€?///
/// 鍋氭硶鏄湪 value-length 鍒掑畾鐨勫尯闂村唴渚濇璺宠繃鍙€変护鐗?瀛楃闆嗭紝鐒跺悗璇绘枃鏈覆銆?fn read_encoded_string(cursor: &mut Cursor) -> Option<String> {
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
    // 鍐呭眰 value-length
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
    // 瀛楃闆嗭紙short-integer锛?    let mut charset = None;
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

/// 鍦板潃瀛楁锛欶rom / To / Cc / Bcc銆?fn read_address_value(cursor: &mut Cursor) -> Option<String> {
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

/// 璺宠繃鏃犳硶璇嗗埆鐨勫ご閮?鍙傛暟鍊硷紙淇濊瘉鑷冲皯鎺ㄨ繘涓€涓瓧鑺傦級銆?fn skip_value(cursor: &mut Cursor) {
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
            // 0x80..=0xFF锛氱煭鏁存暟/浠ょ墝
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
        Some(_) => read_text_bytes(cursor).map(|bytes| charset_from_name(&decode_text(&bytes, None))),
        None => None,
    }
}

fn charset_from_name(name: &str) -> u32 {
    match name.trim().to_ascii_lowercase().as_str() {
        "utf-8" | "utf8" => CHARSET_UTF8,
        "utf-16" | "utf16" => CHARSET_UTF16,
        "iso-10646-ucs-2" | "ucs-2" | "ucs2" => CHARSET_UCS2,
        "us-ascii" | "ascii" => 3,
        "iso-8859-1" | "latin1" => 4,
        "gb2312" | "gbk" | "gb18030" => CHARSET_GB2312,
        _ => 0,
    }
}

type ContentTypeInfo = (String, Option<u32>, Option<String>);

/// 瑙ｆ瀽 Content-Type 鍊硷細瑁?short-integer銆乣Value-length Media-type *(Parameter)`銆?/// 鎴栬８鏂囨湰涓诧紙閮ㄥ垎鑰佺紪鐮佸櫒锛夈€?fn read_content_type(cursor: &mut Cursor) -> Option<ContentTypeInfo> {
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

/// 鍒ゆ柇 `length` 瀛楄妭鐨勫潡鏄惁涓虹揣璺?Content-Type 鐨勫弬鏁板潡銆?///
/// 鍙湁鏁村潡閮借兘鎸夆€滃凡鐭ュ弬鏁?id + 鍊尖€濊В鏋愭椂鎵嶈涓哄畠鏄弬鏁板潡锛岄伩鍏嶆妸
/// 姝ｆ枃閲岀殑 `part count / headers_len` 璇垽鎴愬弬鏁般€?fn looks_like_parameter_block(cursor: &Cursor, length: u8) -> bool {
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

/// 瑙ｇ爜 M-Retrieve.conf锛堝瓙闆嗭級銆?pub fn decode(bytes: &[u8]) -> Option<DecodedMms> {
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
            // 閮ㄥ垎缂栫爜鍣ㄦ妸 multipart.related 鐨?start/type 鍙傛暟鍐欐垚绱ц窡鍦ㄨ８鐭暣鏁?            // Content-Type 涔嬪悗鐨勪竴涓嫭绔?value-length 鍧楋紝杩欓噷璇嗗埆骞惰烦杩囥€?            if !content_type.is_empty() && looks_like_parameter_block(&cursor, header) {
                cursor.skip(header as usize);
                continue;
            }
            // 杩欎釜瀛楄妭鏄鏂囩殑绗竴涓瓧鑺傦紝鍥為€€鍚庝氦缁欏閮ㄥ垎瑙ｆ瀽
            cursor.pos = header_pos;
            break;
        }
        let start = cursor.pos;
        match header {
            // X-Mms-Message-Type锛氳８ octet
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
                // multipart锛氱户缁惊鐜紝鍓╀綑鐨勫ご瀛楁涓?Content-Type 鍙傛暟鍧椾細鍦?                // 涓嬮潰鐨?`header < 0x80` 鍒嗘敮閲岃璺宠繃锛屾鏂囪捣鐐瑰垯璺冲嚭寰幆銆?            }
            // Date锛歀ong-integer锛堢锛?            0x85 => {
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
            // Message-Class锛氱煭浠ょ墝
            0x8A => {
                let _ = cursor.take();
            }
            // X-Mms-MMS-Version锛歋hort-integer
            0x8D => {
                let _ = cursor.short_integer();
            }
            // 鏂囨湰鍨嬪ご锛歍ransaction-Id / Message-Id / Response-Text / Retrieve-Text
            0x98 | 0x8B | 0x93 | 0x9A | 0x83 => {
                let _ = read_text_bytes(&mut cursor);
            }
            // X-Mms-Expiry / Delivery-Time锛歏alue-length (token Long-integer)
            0x88 | 0x87 => {
                let length = cursor.value_length()?;
                let end = cursor.pos.saturating_add(length).min(cursor.data.len());
                let _ = cursor.take();
                let _ = cursor.long_integer();
                cursor.pos = end;
            }
            // 鍏朵綑鏈煡澶达細灏介噺璺宠繃
            _ => skip_value(&mut cursor),
        }
        if cursor.pos <= start {
            // 娌℃湁鎺ㄨ繘锛岄伩鍏嶆寰幆
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
        // 鍓╀綑 part 澶撮儴
        while cursor.pos < headers_end {
            let parameter = match cursor.take() {
                Some(parameter) => parameter,
                None => return false,
            };
            if parameter < 0x80 {
                break;
            }
            match parameter {
                // Content-Location / Content-Disposition(filename) / Content-ID
                0x8E | 0xC1 | 0xC5 | 0xAE => {
                    let value = read_text_string(cursor);
                    if let Some(value) = value {
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
    // SMIL 鍙槸鎺掔増鎻忚堪锛屼笉鍙備笌姝ｆ枃/闄勪欢
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

/// 鏂囨湰瑙ｇ爜锛欱OM/UTF-8 浼樺厛锛屽叾娆?UTF-16锛屾渶鍚?GB2312 灏藉姏鑰屼负锛堜笉 panic锛夈€?pub fn decode_text(data: &[u8], charset: Option<u32>) -> String {
    if data.len() >= 2 {
        if data[0] == 0xFF && data[1] == 0xFE {
            return decode_utf16(&data[2..], true);
        }
        if data[0] == 0xFE && data[1] == 0xFF {
            return decode_utf16(&data[2..], false);
        }
    }
    let wide = matches!(charset, Some(CHARSET_UTF16) | Some(CHARSET_UCS2));
    if !wide {
        if let Ok(text) = std::str::from_utf8(data) {
            return text.to_string();
        }
    }
    if wide {
        // 鏃?BOM 鐨?UTF-16锛氭寜闆跺瓧鑺備綅缃寽瀛楄妭搴?        let big_endian = data.len() >= 2 && data[0] == 0 && data[1] != 0;
        return decode_utf16(data, !big_endian);
    }
    // GB2312 绛夋棤鍐呯疆鏄犲皠琛細淇濈暀 ASCII锛屽叾浣欑敤鏇挎崲绗︼紙灏藉姏鑰屼负锛?    String::from_utf8_lossy(data).into_owned()
}

fn decode_utf16(data: &[u8], little_endian: bool) -> String {
    let mut units: Vec<u16> = Vec::with_capacity(data.len() / 2);
    for chunk in data.chunks_exact(2) {
        units.push(if little_endian {
            u16::from_le_bytes([chunk[0], chunk[1]])
        } else {
            u16::from_be_bytes([chunk[0], chunk[1]])
        });
    }
    String::from_utf16_lossy(&units)
}

fn write_uintvar(out: &mut Vec<u8>, value: u32) {
    let mut groups = [0u8; 5];
    let mut count = 0usize;
    let mut remaining = value;
    loop {
        groups[count] = (remaining & 0x7F) as u8;
        count += 1;
        remaining >>= 7;
        if remaining == 0 || count == groups.len() {
            break;
        }
    }
    for index in (0..count).rev() {
        let mut byte = groups[index];
        if index > 0 {
            byte |= 0x80;
        }
        out.push(byte);
    }
}

fn write_value_length(out: &mut Vec<u8>, length: u32) {
    if length < 31 {
        out.push(length as u8);
    } else {
        out.push(0x1F);
        write_uintvar(out, length);
    }
}

fn write_text_string(out: &mut Vec<u8>, bytes: &[u8]) {
    if bytes.first().map(|byte| byte & 0x80 != 0).unwrap_or(false) {
        out.push(0x7F);
    }
    out.extend_from_slice(bytes);
    out.push(0x00);
}

fn write_encoded_string(out: &mut Vec<u8>, value: &str) {
    let mut inner: Vec<u8> = Vec::with_capacity(value.len() + 4);
    inner.push(0x80 | CHARSET_UTF8 as u8);
    write_text_string(&mut inner, value.as_bytes());
    write_value_length(out, inner.len() as u32);
    out.extend_from_slice(&inner);
}

fn write_long_integer(out: &mut Vec<u8>, value: u64) {
    let mut bytes = [0u8; 8];
    let mut count = 0usize;
    let mut remaining = value;
    while remaining > 0 {
        bytes[count] = (remaining & 0xFF) as u8;
        count += 1;
        remaining >>= 8;
    }
    out.push(count as u8);
    for index in (0..count).rev() {
        out.push(bytes[index]);
    }
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

/// 缂栫爜 M-Retrieve.conf锛坄multipart.mixed`锛氭枃鏈?+ 闄勪欢锛夈€?pub fn encode(
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

    // From锛歩nsert-address-token锛堟湰鏈哄彂閫侊紝涓嶅洖濉彿鐮侊級
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

    // 缁勮 parts
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
        let recipients = vec!["+8613800138000".to_string(), "寮犱笁".to_string()];
        let text = "浣犲ソ馃尶锛岃繖鏄竴鏉″僵淇°€俓n绗簩琛?;
        let attachments = vec![
            attachment("image/jpeg", "photo.jpg", &[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0xD9]),
            attachment("audio/amr", "voice.amr", b"#!AMR\n...."),
        ];
        let pdu = encode(&recipients, text, "鏍囬 subject", &attachments);
        let decoded = decode(&pdu).expect("decode");
        assert_eq!(decoded.message_type, 132);
        assert_eq!(decoded.recipients, recipients);
        assert_eq!(decoded.subject, "鏍囬 subject");
        assert_eq!(decoded.text, text);
        assert!(decoded.date_ms > 1_600_000_000_000);
        assert_eq!(decoded.attachments, attachments);
        assert_eq!(decoded.sender, "", "insert-address-token 琛ㄧず鏈満");
    }

    #[test]
    fn round_trip_without_attachments() {
        let pdu = encode(&["10086".into()], "鍙湁鏂囨湰", "", &[]);
        let decoded = decode(&pdu).expect("decode");
        assert_eq!(decoded.text, "鍙湁鏂囨湰");
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
        // 鎵嬪伐鏋勯€狅細From = Value-length(0x80 + Encoded-string(short-int charset + text))
        let mut pdu: Vec<u8> = Vec::new();
        pdu.extend_from_slice(&[0x8C, 0x84]);
        let mut inner: Vec<u8> = vec![0x80 | 106];
        write_text_string(&mut inner, b"10086/TYPE=PLMN");
        pdu.push(0x89);
        let mut value: Vec<u8> = vec![0x80];
        value.push(inner.len() as u8);
        value.extend_from_slice(&inner);
        pdu.push(value.len() as u8);
        pdu.extend_from_slice(&value);
        // Content-Type 涓鸿８ short-integer锛堜笌甯歌缂栫爜鍣ㄤ竴鑷达級
        pdu.push(0x84);
        pdu.push(0x80 | MULTIPART_MIXED_INDEX);
        // 1 涓儴鍒嗭細text/plain + utf-8
        let mut content_type: Vec<u8> = vec![0x80 | TEXT_PLAIN_INDEX];
        write_parameter_text(&mut content_type, 0x81, "utf-8");
        write_uintvar(&mut pdu, 1);
        write_part(&mut pdu, &content_type, None, "鏉ヨ嚜 10086".as_bytes());

        let decoded = decode(&pdu).expect("decode");
        assert_eq!(decoded.sender, "10086");
        assert_eq!(decoded.text, "鏉ヨ嚜 10086");
    }

    #[test]
    fn skips_unknown_headers() {
        let mut pdu = encode(&["10086".into()], "鏈煡澶存祴璇?, "", &[]);
        // 鍦ㄧ涓€涓ご涔嬪墠鎻掑叆涓€涓湭鐭ュご锛?xA5 + value-length 3 + 鏂囨湰锛?        let mut injected: Vec<u8> = vec![0xA5, 0x03, b'x', b'y', b'z'];
        injected.extend_from_slice(&pdu);
        pdu = injected;
        let decoded = decode(&pdu).expect("decode");
        assert_eq!(decoded.text, "鏈煡澶存祴璇?);
        assert_eq!(decoded.message_type, 132);
    }

    #[test]
    fn rejects_truncated_and_invalid_lengths() {
        let pdu = encode(&["10086".into()], "鎴柇娴嬭瘯", "涓婚", &[]);
        assert!(decode(&pdu[..2]).is_none(), "缂哄皯 Content-Type");
        assert!(decode(&pdu[..6]).is_none());
        assert!(decode(&pdu[..pdu.len() / 2]).is_none(), "姝ｆ枃琚埅鏂?);
        assert!(decode(&[]).is_none());

        // 澶氶儴鍒嗗ご閮ㄩ暱搴﹂潪娉曪紙瓒呭嚭鍓╀綑瀛楄妭锛?        let mut broken: Vec<u8> = Vec::new();
        broken.extend_from_slice(&[0x8C, 0x84, 0x84, 0x80 | MULTIPART_MIXED_INDEX]);
        broken.extend_from_slice(&[0x01, 0x7F, 0x00]);
        assert!(decode(&broken).is_none());

        // 閮ㄥ垎鏁版嵁闀垮害闈炴硶
        let mut broken: Vec<u8> = Vec::new();
        broken.extend_from_slice(&[0x8C, 0x84, 0x84, 0x80 | MULTIPART_MIXED_INDEX]);
        broken.extend_from_slice(&[0x01, 0x04, 0x7F, 0x83, 0x00, 0x00]);
        assert!(decode(&broken).is_none());
    }

    #[test]
    fn rejects_oversized_and_garbage_input() {
        let oversized = vec![0u8; MAX_PDU_BYTES + 1];
        assert!(decode(&oversized).is_none());
        assert!(decode(&[0x00, 0x01, 0x02, 0x03]).is_none());
        assert!(decode(&[0xFF; 64]).is_none());
        // 鍏ㄦ槸鏈煡澶翠篃涓嶄細 panic
        let _ = decode(&[0xA5; 200]);
    }

    #[test]
    fn decodes_text_encodings() {
        // UTF-8
        assert_eq!(decode_text("浣犲ソ".as_bytes(), Some(CHARSET_UTF8)), "浣犲ソ");
        // UTF-16LE 甯?BOM
        let mut le = vec![0xFF, 0xFE];
        for unit in "浣犲ソ".encode_utf16() {
            le.extend_from_slice(&unit.to_le_bytes());
        }
        assert_eq!(decode_text(&le, Some(CHARSET_UTF16)), "浣犲ソ");
        // UTF-16BE 甯?BOM
        let mut be = vec![0xFE, 0xFF];
        for unit in "褰╀俊".encode_utf16() {
            be.extend_from_slice(&unit.to_be_bytes());
        }
        assert_eq!(decode_text(&be, Some(CHARSET_UTF16)), "褰╀俊");
        // 鏃?BOM 鐨?UTF-16LE锛堟寜闆跺瓧鑺傜寽锛?        let mut plain = Vec::new();
        for unit in "娴嬭瘯".encode_utf16() {
            plain.extend_from_slice(&unit.to_le_bytes());
        }
        assert_eq!(decode_text(&plain, Some(CHARSET_UTF16)), "娴嬭瘯");
        // GB2312 瀛楄妭锛氬敖鍔涜€屼负锛屽彧淇濊瘉 ASCII 姝ｇ‘涓斾笉 panic
        let gb = decode_text(&[0xC4, 0xE3, b'A', b'B'], Some(CHARSET_GB2312));
        assert!(gb.ends_with("AB"));
    }

    #[test]
    fn smil_parts_are_ignored() {
        let smil = b"<smil><body/></smil>";
        let pdu = encode(
            &["10086".into()],
            "甯?SMIL",
            "",
            &[attachment("application/smil", "smil.xml", smil)],
        );
        let decoded = decode(&pdu).expect("decode");
        assert_eq!(decoded.text, "甯?SMIL");
        assert!(decoded.attachments.is_empty(), "SMIL 鍙敤浜庢帓鐗堬紝琚拷鐣?);
    }

    #[test]
    fn recipient_with_type_suffix_is_cleaned() {
        let pdu = encode(&["13800138000".into()], "x", "", &[]);
        let decoded = decode(&pdu).expect("decode");
        assert_eq!(decoded.recipients, vec!["13800138000".to_string()]);
        assert_eq!(address_with_type("13800138000"), "13800138000/TYPE=PLMN");
        assert_eq!(address_with_type("alice@example.com"), "alice@example.com");
        assert_eq!(address_with_type(""), "");
    }

    #[test]
    fn uintvar_round_trip() {
        for value in [0u32, 1, 127, 128, 300, 16_383, 16_384, 1_000_000] {
            let mut buffer = Vec::new();
            write_uintvar(&mut buffer, value);
            let mut cursor = Cursor::new(&buffer);
            assert_eq!(cursor.uintvar(), Some(value));
        }
        // 瓒呰繃 5 瀛楄妭鐨勯潪娉?varint 杩斿洖 None
        let mut cursor = Cursor::new(&[0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);
        assert!(cursor.uintvar().is_none());
    }

    #[test]
    fn long_and_short_integers() {
        let mut buffer = Vec::new();
        write_long_integer(&mut buffer, 1_600_000_000);
        let mut cursor = Cursor::new(&buffer);
        assert_eq!(cursor.long_integer(), Some(1_600_000_000));
        cursor.pos = 0;
        assert_eq!(cursor.value_length(), Some(4));

        let mut cursor = Cursor::new(&[0x84]);
        assert_eq!(cursor.short_integer(), Some(4));
        let mut cursor = Cursor::new(&[0x01, 0x02]);
        assert_eq!(cursor.long_integer(), Some(2));
    }

    #[test]
    fn tolerates_content_type_parameter_block() {
        // 閮ㄥ垎缂栫爜鍣ㄦ妸 multipart.related 鐨?start/type 鍙傛暟鍐欐垚绱ц窡 Content-Type
        // 涔嬪悗鐨勭嫭绔?value-length 鍧?        let mut pdu: Vec<u8> = vec![0x8C, 0x84, 0x84, 0x80 | MULTIPART_MIXED_INDEX];
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
        write_part(&mut pdu, &content_type, None, "鍙傛暟鍧椾箣鍚庣殑姝ｆ枃".as_bytes());

        let decoded = decode(&pdu).expect("decode");
        assert_eq!(decoded.text, "鍙傛暟鍧椾箣鍚庣殑姝ｆ枃");
    }

    #[test]
    fn large_attachment_is_bounded() {
        let big = vec![0x5A; 300_000];
        let pdu = encode(
            &["10086".into()],
            "澶ч檮浠?,
            "",
            &[attachment("image/png", "big.png", &big)],
        );
        let decoded = decode(&pdu).expect("decode");
        assert_eq!(decoded.attachments.len(), 1);
        assert_eq!(decoded.attachments[0].data.len(), big.len());
    }
}