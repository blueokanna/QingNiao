//! 端到端同步信封加密。
//!
//! 方案：X25519 静态密钥 + HKDF-SHA256（`info = "qingniao-envelope-v1"`）
//! + AES-256-GCM（12 字节随机 nonce）。每个信封携带临时公钥，
//! HKDF 的 salt 绑定“临时公钥 || 接收方静态公钥”，避免密钥复用混淆。
//! 所有 base64 均为 URL_SAFE_NO_PAD。
//!
//! 密钥持久化在 `<data_dir>/device_identity.json`（unix 上尽力设为 0600）。

use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use aes_gcm::aead::generic_array::GenericArray;
use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::Aes256Gcm;
use base64::engine::general_purpose::{STANDARD, STANDARD_NO_PAD, URL_SAFE_NO_PAD};
use base64::Engine as _;
use hkdf::Hkdf;
use once_cell::sync::Lazy;
use parking_lot::Mutex;
use rand::rngs::OsRng;
use rand::RngCore;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use x25519_dalek::{PublicKey, StaticSecret};
use zeroize::{Zeroize, Zeroizing};

use crate::core::store;

/// 密钥文件名。
pub const IDENTITY_FILE: &str = "device_identity.json";
const HKDF_INFO: &[u8] = b"qingniao-envelope-v1";
const KEY_LEN: usize = 32;
const NONCE_LEN: usize = 12;
const PUBLIC_KEY_LEN: usize = 32;

/// 设备身份（对外暴露的公开部分）。
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DeviceIdentity {
    pub device_id: String,
    pub public_key: String,
    pub fingerprint: String,
}

/// 加密信封。
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Envelope {
    pub ephemeral_public_key: String,
    pub nonce: String,
    pub ciphertext: String,
}

/// 本地静态密钥对。
pub struct Identity {
    device_id: String,
    secret: StaticSecret,
    public: PublicKey,
}

impl Identity {
    /// 生成新身份。
    pub fn generate() -> Self {
        let secret = StaticSecret::random_from_rng(OsRng);
        let public = PublicKey::from(&secret);
        Identity {
            device_id: uuid::Uuid::new_v4().to_string(),
            secret,
            public,
        }
    }

    /// 从已有私钥字节恢复身份。
    pub fn from_secret_bytes(device_id: &str, secret_bytes: [u8; PUBLIC_KEY_LEN]) -> Self {
        let secret = StaticSecret::from(secret_bytes);
        let public = PublicKey::from(&secret);
        Identity {
            device_id: device_id.to_owned(),
            secret,
            public,
        }
    }

    pub fn device_id(&self) -> &str {
        &self.device_id
    }

    pub fn public_key_bytes(&self) -> [u8; PUBLIC_KEY_LEN] {
        *self.public.as_bytes()
    }

    pub fn public_key_base64(&self) -> String {
        URL_SAFE_NO_PAD.encode(self.public.as_bytes())
    }

    pub fn fingerprint(&self) -> String {
        format_fingerprint(self.public.as_bytes())
    }

    /// 持久化所需的私钥字节（调用方负责清零）。
    fn secret_bytes(&self) -> [u8; KEY_LEN] {
        self.secret.to_bytes()
    }

    pub fn to_public(&self) -> DeviceIdentity {
        DeviceIdentity {
            device_id: self.device_id.clone(),
            public_key: self.public_key_base64(),
            fingerprint: self.fingerprint(),
        }
    }
}

/// 解密信封需要本地静态私钥。
pub fn open(
    identity: &Identity,
    ephemeral_public_key: &[u8; PUBLIC_KEY_LEN],
    nonce: &[u8],
    ciphertext: &[u8],
) -> Option<String> {
    if nonce.len() != NONCE_LEN || ciphertext.len() < 16 {
        return None;
    }
    let ephemeral = PublicKey::from(*ephemeral_public_key);
    let shared = identity.secret.diffie_hellman(&ephemeral);
    if shared.as_bytes().iter().all(|&byte| byte == 0) {
        return None;
    }
    let key = derive_key(shared.as_bytes(), ephemeral_public_key, identity.public.as_bytes())?;
    let cipher = Aes256Gcm::new_from_slice(&key[..]).ok()?;
    let nonce_array = GenericArray::from_slice(nonce);
    let plaintext = cipher.decrypt(nonce_array, ciphertext).ok()?;
    String::from_utf8(plaintext).ok()
}

/// 加密到目标公钥。
pub fn seal(
    recipient_public_key: &[u8; PUBLIC_KEY_LEN],
    plaintext: &str,
) -> Option<Envelope> {
    if plaintext.is_empty() {
        return None;
    }
    let recipient = PublicKey::from(*recipient_public_key);
    let ephemeral_secret = StaticSecret::random_from_rng(OsRng);
    let ephemeral_public = PublicKey::from(&ephemeral_secret);
    let shared = ephemeral_secret.diffie_hellman(&recipient);
    if shared.as_bytes().iter().all(|&byte| byte == 0) {
        return None;
    }
    let key = derive_key(
        shared.as_bytes(),
        ephemeral_public.as_bytes(),
        recipient_public_key,
    )?;
    let mut nonce_bytes = [0u8; NONCE_LEN];
    OsRng.fill_bytes(&mut nonce_bytes);
    let cipher = Aes256Gcm::new_from_slice(&key[..]).ok()?;
    let nonce_array = GenericArray::from_slice(&nonce_bytes);
    let ciphertext = cipher.encrypt(nonce_array, plaintext.as_bytes()).ok()?;
    Some(Envelope {
        ephemeral_public_key: URL_SAFE_NO_PAD.encode(ephemeral_public.as_bytes()),
        nonce: URL_SAFE_NO_PAD.encode(nonce_bytes),
        ciphertext: URL_SAFE_NO_PAD.encode(ciphertext),
    })
}

fn derive_key(
    shared: &[u8; PUBLIC_KEY_LEN],
    ephemeral_public: &[u8; PUBLIC_KEY_LEN],
    recipient_public: &[u8; PUBLIC_KEY_LEN],
) -> Option<Zeroizing<[u8; KEY_LEN]>> {
    let mut salt = [0u8; PUBLIC_KEY_LEN * 2];
    salt[..PUBLIC_KEY_LEN].copy_from_slice(ephemeral_public);
    salt[PUBLIC_KEY_LEN..].copy_from_slice(recipient_public);
    let hkdf = Hkdf::<Sha256>::new(Some(&salt), shared);
    let mut okm = Zeroizing::new([0u8; KEY_LEN]);
    hkdf.expand(HKDF_INFO, &mut okm[..]).ok()?;
    Some(okm)
}

/// 公钥指纹：SHA-256 取前 16 字节，8 组 4 位大写 hex，用 `-` 连接。
pub fn format_fingerprint(public_key: &[u8]) -> String {
    let digest = Sha256::digest(public_key);
    let mut output = String::with_capacity(39);
    for (index, chunk) in digest.iter().take(16).enumerate() {
        if index > 0 && index % 2 == 0 {
            output.push('-');
        }
        output.push_str(&format!("{:02X}", chunk));
    }
    output
}

/// 解码 base64（兼容带 `=` 填充与标准字母表的输入）。
pub fn decode_base64(text: &str) -> Option<Vec<u8>> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return None;
    }
    URL_SAFE_NO_PAD
        .decode(trimmed)
        .ok()
        .or_else(|| STANDARD_NO_PAD.decode(trimmed).ok())
        .or_else(|| STANDARD.decode(trimmed).ok())
}

/// 解析 32 字节公钥。
pub fn decode_public_key(text: &str) -> Option<[u8; PUBLIC_KEY_LEN]> {
    let bytes = decode_base64(text)?;
    if bytes.len() != PUBLIC_KEY_LEN {
        return None;
    }
    let mut out = [0u8; PUBLIC_KEY_LEN];
    out.copy_from_slice(&bytes);
    Some(out)
}

fn identity_path(dir: &Path) -> PathBuf {
    dir.join(IDENTITY_FILE)
}

/// 读取或创建身份文件。文件损坏时备份为 `.bak` 并重新生成。
pub fn load_or_create(dir: &Path) -> Option<Identity> {
    let path = identity_path(dir);
    if let Ok(data) = fs::read(&path) {
        match serde_json::from_slice::<IdentityFile>(&data) {
            Ok(file) => {
                if let Some(mut secret) = decode_base64(&file.secret_key) {
                    if secret.len() == KEY_LEN {
                        let mut bytes = [0u8; KEY_LEN];
                        bytes.copy_from_slice(&secret);
                        secret.zeroize();
                        let identity = Identity::from_secret_bytes(&file.device_id, bytes);
                        bytes.zeroize();
                        return Some(identity);
                    }
                    secret.zeroize();
                }
            }
            Err(_) => {}
        }
        let _ = fs::copy(&path, path.with_extension("json.bak"));
    }
    if fs::create_dir_all(dir).is_err() {
        return None;
    }
    let identity = Identity::generate();
    if !persist(dir, &identity) {
        return None;
    }
    Some(identity)
}

fn persist(dir: &Path, identity: &Identity) -> bool {
    let mut secret_bytes = identity.secret_bytes();
    let file = IdentityFile {
        version: 1,
        device_id: identity.device_id().to_owned(),
        secret_key: URL_SAFE_NO_PAD.encode(secret_bytes),
        public_key: identity.public_key_base64(),
        created_at: now_ms(),
    };
    secret_bytes.zeroize();
    let data = match serde_json::to_vec(&file) {
        Ok(data) => data,
        Err(_) => return false,
    };
    let path = identity_path(dir);
    let tmp = path.with_extension("json.tmp");
    if fs::write(&tmp, &data).is_err() {
        return false;
    }
    if fs::rename(&tmp, &path).is_err() {
        let _ = fs::remove_file(&tmp);
        if fs::write(&path, &data).is_err() {
            return false;
        }
    }
    set_private_permissions(&path);
    true
}

fn set_private_permissions(path: &Path) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(path, fs::Permissions::from_mode(0o600));
    }
    #[cfg(not(unix))]
    {
        let _ = path;
    }
}

#[derive(Serialize, Deserialize)]
struct IdentityFile {
    version: u32,
    device_id: String,
    secret_key: String,
    public_key: String,
    created_at: i64,
}

fn now_ms() -> i64 {
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(duration) => duration.as_millis() as i64,
        Err(_) => 0,
    }
}

struct SyncState {
    dir: Option<PathBuf>,
    identity: Option<Identity>,
}

static SYNC: Lazy<Mutex<SyncState>> = Lazy::new(|| {
    Mutex::new(SyncState {
        dir: None,
        identity: None,
    })
});

/// 初始化同步身份（需要先调用 `engine_init`）。返回公开信息。
pub fn sync_init() -> Option<DeviceIdentity> {
    let dir = store::data_dir()?;
    let mut state = SYNC.lock();
    if state.dir.as_ref() != Some(&dir) {
        state.identity = None;
        state.dir = Some(dir.clone());
    }
    if state.identity.is_none() {
        state.identity = load_or_create(&dir);
    }
    state.identity.as_ref().map(|identity| identity.to_public())
}

/// 计算任意公钥的指纹；输入非法时返回空串。
pub fn sync_fingerprint(public_key_base64: &str) -> String {
    match decode_public_key(public_key_base64) {
        Some(key) => format_fingerprint(&key),
        None => String::new(),
    }
}

/// 加密给目标公钥。
pub fn sync_encrypt(target_public_key_base64: &str, plaintext: &str) -> Option<Envelope> {
    let target = decode_public_key(target_public_key_base64)?;
    seal(&target, plaintext)
}

/// 用本地静态私钥解密。
pub fn sync_decrypt(
    ephemeral_public_key_base64: &str,
    nonce_base64: &str,
    ciphertext_base64: &str,
) -> Option<String> {
    let ephemeral = decode_public_key(ephemeral_public_key_base64)?;
    let nonce = decode_base64(nonce_base64)?;
    let ciphertext = decode_base64(ciphertext_base64)?;
    let state = SYNC.lock();
    let identity = state.identity.as_ref()?;
    open(identity, &ephemeral, &nonce, &ciphertext)
}

/// 删除密钥文件并清空缓存。返回文件是否已被清除（或本来就不存在）。
pub fn sync_reset() -> bool {
    let mut state = SYNC.lock();
    let dir = match state.dir.clone().or_else(store::data_dir) {
        Some(dir) => dir,
        None => return false,
    };
    let path = identity_path(&dir);
    state.identity = None;
    state.dir = Some(dir);
    match fs::remove_file(&path) {
        Ok(()) => true,
        Err(error) => error.kind() == std::io::ErrorKind::NotFound,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(tag: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_nanos())
            .unwrap_or(0);
        let dir = std::env::temp_dir().join(format!(
            "qingniao-crypto-{}-{}-{}",
            tag,
            std::process::id(),
            nanos
        ));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    #[test]
    fn envelope_round_trip() {
        let alice = Identity::generate();
        let bob = Identity::generate();
        let plaintext = "端到端同步 payload 🌿 with ASCII";
        let envelope = seal(&bob.public_key_bytes(), plaintext).expect("seal");
        assert!(!envelope.ciphertext.is_empty());
        assert!(!envelope.ciphertext.contains('='), "URL_SAFE_NO_PAD 无填充");
        assert!(!envelope.ciphertext.contains('+'));
        assert!(!envelope.ciphertext.contains('/'));

        let ephemeral = decode_public_key(&envelope.ephemeral_public_key).expect("ephemeral");
        let nonce = decode_base64(&envelope.nonce).expect("nonce");
        let ciphertext = decode_base64(&envelope.ciphertext).expect("ciphertext");
        let opened = open(&bob, &ephemeral, &nonce, &ciphertext).expect("open");
        assert_eq!(opened, plaintext);
        // 发送方（错误私钥）无法解出
        assert!(open(&alice, &ephemeral, &nonce, &ciphertext).is_none());
    }

    #[test]
    fn wrong_key_cannot_decrypt() {
        let bob = Identity::generate();
        let attacker = Identity::generate();
        let envelope = seal(&bob.public_key_bytes(), "secret").expect("seal");
        let ephemeral = decode_public_key(&envelope.ephemeral_public_key).unwrap();
        let nonce = decode_base64(&envelope.nonce).unwrap();
        let ciphertext = decode_base64(&envelope.ciphertext).unwrap();
        assert!(open(&attacker, &ephemeral, &nonce, &ciphertext).is_none());
    }

    #[test]
    fn tampered_ciphertext_is_rejected() {
        let bob = Identity::generate();
        let envelope = seal(&bob.public_key_bytes(), "tamper me").expect("seal");
        let ephemeral = decode_public_key(&envelope.ephemeral_public_key).unwrap();
        let nonce = decode_base64(&envelope.nonce).unwrap();
        let mut ciphertext = decode_base64(&envelope.ciphertext).unwrap();
        ciphertext[0] ^= 0x01;
        assert!(open(&bob, &ephemeral, &nonce, &ciphertext).is_none());

        // 篡改 nonce 同样失败
        let mut wrong_nonce = decode_base64(&envelope.nonce).unwrap();
        wrong_nonce[0] ^= 0x01;
        let ciphertext = decode_base64(&envelope.ciphertext).unwrap();
        assert!(open(&bob, &ephemeral, &wrong_nonce, &ciphertext).is_none());

        // 截断/空输入失败而不是 panic
        assert!(open(&bob, &ephemeral, &[], &ciphertext).is_none());
        assert!(open(&bob, &ephemeral, &nonce, &[]).is_none());
    }

    #[test]
    fn reject_invalid_public_keys_and_inputs() {
        assert!(seal(&[0u8; 32], "x").is_none(), "低阶公钥应被拒绝");
        assert!(seal(&[7u8; 32], "").is_none(), "空明文应被拒绝");
        assert!(decode_public_key("not-base64!!").is_none());
        assert!(decode_public_key(&URL_SAFE_NO_PAD.encode([0u8; 31])).is_none());

        let data = decode_base64("").is_none();
        assert!(data);
        // 带填充的标准 base64 也能解码
        let padded = STANDARD.encode([1u8, 2, 3]);
        assert_eq!(decode_base64(&padded).as_deref(), Some(&[1u8, 2, 3][..]));
    }

    #[test]
    fn fingerprint_has_eight_groups() {
        let identity = Identity::generate();
        let fingerprint = identity.fingerprint();
        assert_eq!(fingerprint.len(), 39, "8*4 hex + 7 个连字符");
        let groups: Vec<&str> = fingerprint.split('-').collect();
        assert_eq!(groups.len(), 8);
        for group in groups {
            assert_eq!(group.len(), 4);
            assert!(group.chars().all(|ch| ch.is_ascii_hexdigit() && !ch.is_ascii_lowercase()));
        }
        // 同一公钥稳定，不同公钥不同
        assert_eq!(fingerprint, format_fingerprint(&identity.public_key_bytes()));
        assert_ne!(fingerprint, Identity::generate().fingerprint());
        assert_eq!(
            sync_fingerprint(&identity.public_key_base64()),
            fingerprint
        );
        assert!(sync_fingerprint("bad key").is_empty());
    }

    #[test]
    fn identity_file_round_trip() {
        let dir = temp_dir("identity");
        fs::create_dir_all(&dir).unwrap();
        let first = load_or_create(&dir).expect("first");
        let device_id = first.device_id().to_owned();
        let public_key = first.public_key_base64();
        assert!(dir.join(IDENTITY_FILE).is_file());

        let second = load_or_create(&dir).expect("second");
        assert_eq!(second.device_id(), device_id);
        assert_eq!(second.public_key_base64(), public_key);

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = fs::metadata(dir.join(IDENTITY_FILE))
                .map(|meta| meta.permissions().mode() & 0o777)
                .unwrap_or(0);
            assert_eq!(mode, 0o600);
        }
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn corrupt_identity_file_is_replaced() {
        let dir = temp_dir("corrupt");
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join(IDENTITY_FILE), b"garbage").unwrap();
        let identity = load_or_create(&dir).expect("recreated");
        assert!(!identity.device_id().is_empty());
        assert!(dir.join("device_identity.json.bak").is_file());
        let reloaded = load_or_create(&dir).expect("stable");
        assert_eq!(reloaded.device_id(), identity.device_id());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn sync_apis_need_engine_init() {
        // 全局状态可能被其它测试影响，这里只验证未初始化/空输入不会 panic
        assert!(sync_encrypt("bad", "x").is_none());
        assert!(sync_decrypt("bad", "bad", "bad").is_none());
    }
}
