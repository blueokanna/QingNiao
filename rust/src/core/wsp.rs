
/// MIBenum：UTF-8。
pub const CHARSET_UTF8: u32 = 106;
/// MIBenum：UTF-16。
pub const CHARSET_UTF16: u32 = 1015;
/// MIBenum：UCS-2。
pub const CHARSET_UCS2: u32 = 1000;
/// MIBenum：GB2312。
pub const CHARSET_GB2312: u32 = 2025;

const CONTENT_TYPES: &[&str] = &[
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

pub fn well_known_content_type(index: usize) -> Option<&'static str> {
    CONTENT_TYPES.get(index).copied()
}

pub fn well_known_index(mime: &str) -> Option<u8> {
    let lower = mime.trim().to_ascii_lowercase();
    CONTENT_TYPES
        .iter()
        .position(|candidate| *candidate == lower)
        .map(|index| index as u8)
}

pub fn is_multipart(mime: &str) -> bool {
    let lower = mime.to_ascii_lowercase();
    lower.starts_with("multipart/") || lower.contains("vnd.wap.multipart")
}

pub struct Cursor<'a> {
    pub(crate) data: &'a [u8],
    pub(crate) pos: usize,
}

impl<'a> Cursor<'a> {
    pub fn new(data: &'a [u8]) -> Self {
        Cursor { data, pos: 0 }
    }

    pub fn eof(&self) -> bool {
        self.pos >= self.data.len()
    }

    pub fn peek(&self) -> Option<u8> {
        self.data.get(self.pos).copied()
    }

    pub fn take(&mut self) -> Option<u8> {
        let byte = self.peek()?;
        self.pos += 1;
        Some(byte)
    }

    pub fn skip(&mut self, count: usize) {
        self.pos = self.pos.saturating_add(count).min(self.data.len());
    }

    pub fn uintvar(&mut self) -> Option<u32> {
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

    pub fn value_length(&mut self) -> Option<usize> {
        let byte = self.take()?;
        if byte <= 30 {
            return Some(byte as usize);
        }
        if byte == 0x1F {
            return self.uintvar().map(|value| value as usize);
        }
        None
    }

    pub fn short_integer(&mut self) -> Option<u8> {
        self.take().map(|byte| byte & 0x7F)
    }

    pub fn long_integer(&mut self) -> Option<u64> {
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

pub fn read_text_bytes(cursor: &mut Cursor) -> Option<Vec<u8>> {
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
    if cursor.pos > start {
        Some(cursor.data[start..cursor.pos].to_vec())
    } else {
        None
    }
}

pub fn read_text_string(cursor: &mut Cursor) -> Option<String> {
    read_text_bytes(cursor).map(|bytes| decode_text(&bytes, None))
}

pub fn charset_from_name(name: &str) -> u32 {
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

pub fn decode_text(data: &[u8], charset: Option<u32>) -> String {
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
        let big_endian = data.len() >= 2 && data[0] == 0 && data[1] != 0;
        return decode_utf16(data, !big_endian);
    }
    String::from_utf8_lossy(data).into_owned()
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

pub fn write_uintvar(out: &mut Vec<u8>, value: u32) {
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

pub fn write_value_length(out: &mut Vec<u8>, length: u32) {
    if length < 31 {
        out.push(length as u8);
    } else {
        out.push(0x1F);
        write_uintvar(out, length);
    }
}

pub fn write_text_string(out: &mut Vec<u8>, bytes: &[u8]) {
    if bytes.first().map(|byte| byte & 0x80 != 0).unwrap_or(false) {
        out.push(0x7F);
    }
    out.extend_from_slice(bytes);
    out.push(0x00);
}

pub fn write_long_integer(out: &mut Vec<u8>, value: u64) {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uintvar_round_trip() {
        for value in [0u32, 1, 127, 128, 300, 16_383, 16_384, 1_000_000] {
            let mut buffer = Vec::new();
            write_uintvar(&mut buffer, value);
            let mut cursor = Cursor::new(&buffer);
            assert_eq!(cursor.uintvar(), Some(value), "value = {value}");
        }
        let mut cursor = Cursor::new(&[0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);
        assert!(cursor.uintvar().is_none());
        let mut cursor = Cursor::new(&[0x81]);
        assert!(cursor.uintvar().is_none());
    }

    #[test]
    fn value_length_boundaries() {
        for length in [0u32, 1, 30] {
            let mut buffer = Vec::new();
            write_value_length(&mut buffer, length);
            assert_eq!(buffer.len(), 1, "短长度单字节");
            let mut cursor = Cursor::new(&buffer);
            assert_eq!(cursor.value_length(), Some(length as usize));
        }
        let mut buffer = Vec::new();
        write_value_length(&mut buffer, 31);
        assert_eq!(buffer[0], 0x1F);
        let mut cursor = Cursor::new(&buffer);
        assert_eq!(cursor.value_length(), Some(31));

        let mut buffer = Vec::new();
        write_value_length(&mut buffer, 1000);
        let mut cursor = Cursor::new(&buffer);
        assert_eq!(cursor.value_length(), Some(1000));

        let mut cursor = Cursor::new(&[0x85]);
        assert!(cursor.value_length().is_none());
    }

    #[test]
    fn long_and_short_integers() {
        let mut buffer = Vec::new();
        write_long_integer(&mut buffer, 1_600_000_000);
        let mut cursor = Cursor::new(&buffer);
        assert_eq!(cursor.long_integer(), Some(1_600_000_000));

        let mut cursor = Cursor::new(&[0x84]);
        assert_eq!(cursor.short_integer(), Some(4));
        let mut cursor = Cursor::new(&[0x01, 0x02]);
        assert_eq!(cursor.long_integer(), Some(2));
        let mut cursor = Cursor::new(&[0x09, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
        assert!(cursor.long_integer().is_none());
    }

    #[test]
    fn text_string_handles_quote_and_terminator() {
        let mut buffer = Vec::new();
        write_text_string(&mut buffer, "abc".as_bytes());
        assert_eq!(buffer, b"abc\0");
        let mut cursor = Cursor::new(&buffer);
        assert_eq!(read_text_string(&mut cursor).as_deref(), Some("abc"));

        let mut buffer = Vec::new();
        write_text_string(&mut buffer, "标题".as_bytes());
        assert_eq!(buffer[0], 0x7F);
        let mut cursor = Cursor::new(&buffer);
        assert_eq!(read_text_string(&mut cursor).as_deref(), Some("标题"));

        let mut buffer = Vec::new();
        write_text_string(&mut buffer, b"");
        assert_eq!(buffer, vec![0x00]);
        let mut cursor = Cursor::new(&buffer);
        assert_eq!(read_text_string(&mut cursor).as_deref(), Some(""));
    }

    #[test]
    fn decodes_text_encodings() {
        assert_eq!(decode_text("你好".as_bytes(), Some(CHARSET_UTF8)), "你好");
        assert_eq!(decode_text("hello".as_bytes(), None), "hello");
        assert_eq!(decode_text(&[], None), "");

        let mut le = vec![0xFF, 0xFE];
        for unit in "你好".encode_utf16() {
            le.extend_from_slice(&unit.to_le_bytes());
        }
        assert_eq!(decode_text(&le, Some(CHARSET_UTF16)), "你好");

        let mut be = vec![0xFE, 0xFF];
        for unit in "彩信".encode_utf16() {
            be.extend_from_slice(&unit.to_be_bytes());
        }
        assert_eq!(decode_text(&be, Some(CHARSET_UTF16)), "彩信");

        let mut plain = Vec::new();
        for unit in "测试".encode_utf16() {
            plain.extend_from_slice(&unit.to_le_bytes());
        }
        assert_eq!(decode_text(&plain, Some(CHARSET_UTF16)), "测试");

        let gb = decode_text(&[0xC4, 0xE3, b'A', b'B'], Some(CHARSET_GB2312));
        assert!(gb.ends_with("AB"));
        assert!(!decode_text(&[0xFF, 0xFF, 0xFF], None).is_empty());
    }

    #[test]
    fn charset_names_map_to_mibenum() {
        assert_eq!(charset_from_name("UTF-8"), CHARSET_UTF8);
        assert_eq!(charset_from_name(" utf-16 "), CHARSET_UTF16);
        assert_eq!(charset_from_name("gbk"), CHARSET_GB2312);
        assert_eq!(charset_from_name("gb2312"), CHARSET_GB2312);
        assert_eq!(charset_from_name("cn"), 0);
    }

    #[test]
    fn content_type_table_lookups() {
        assert_eq!(well_known_content_type(3), Some("text/plain"));
        assert_eq!(
            well_known_content_type(35),
            Some("application/vnd.wap.multipart.mixed")
        );
        assert_eq!(
            well_known_content_type(51),
            Some("application/vnd.wap.multipart.related")
        );
        assert_eq!(well_known_content_type(9999), None);
        assert_eq!(well_known_index("TEXT/PLAIN"), Some(3));
        assert_eq!(well_known_index("audio/amr"), None);
        assert!(is_multipart("multipart/mixed"));
        assert!(is_multipart("application/vnd.wap.multipart.mixed"));
        assert!(!is_multipart("text/plain"));
    }
}
