//! 青鸟短信同步服务（最小实现）。
//!
//! 服务器只做三件事：
//! 1. 维护一个由配对码连接的设备空间（space）；
//! 2. 保存设备提交的**不透明密文信封**；
//! 3. 为每台设备提供按游标拉取与长轮询。
//!
//! 它不持有任何私钥，也无法解密正文。默认监听 `127.0.0.1:8787`，
//! 通过 `--bind 0.0.0.0:8787` 对外提供服务；生产环境请放在 TLS 反向代理之后。

use std::{
    collections::HashMap,
    net::SocketAddr,
    path::{Path as FsPath, PathBuf},
    sync::{Arc, Mutex},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use axum::{
    extract::{DefaultBodyLimit, Path, RawQuery, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use rand::Rng;
use serde::{Deserialize, Serialize};
use serde_json::json;
use uuid::Uuid;

const MAX_DEVICES: usize = 8;
const MAX_ENVELOPES: usize = 8192;
const MAX_ENVELOPE_BYTES: usize = 4096;
const PAIRING_TTL_SECS: i64 = 600;

// ---------------------------------------------------------------------------
// 数据模型
// ---------------------------------------------------------------------------

#[derive(Serialize, Deserialize, Default)]
struct Store {
    spaces: HashMap<String, Space>,
    tokens: HashMap<String, TokenRef>,
    pairings: HashMap<String, Pairing>,
}

#[derive(Serialize, Deserialize)]
struct Space {
    id: String,
    created_at: i64,
    devices: Vec<Device>,
    envelopes: Vec<Envelope>,
    next_envelope: u64,
}

#[derive(Serialize, Deserialize, Clone)]
struct Device {
    id: String,
    name: String,
    public_key: String,
    created_at: i64,
    last_seen: i64,
}

#[derive(Serialize, Deserialize, Clone)]
struct Envelope {
    id: u64,
    from: String,
    to: Option<String>,
    ephemeral_public_key: String,
    nonce: String,
    ciphertext: String,
    message_id: String,
    created_at: i64,
}

#[derive(Serialize, Deserialize, Clone)]
struct TokenRef {
    space_id: String,
    device_id: String,
}

#[derive(Serialize, Deserialize, Clone)]
struct Pairing {
    space_id: String,
    expires_at: i64,
}

#[derive(Clone)]
struct AppState {
    store: Arc<Mutex<Store>>,
    data: Arc<PathBuf>,
}

struct ApiError(StatusCode, String);

impl ApiError {
    fn bad(message: impl Into<String>) -> Self {
        Self(StatusCode::BAD_REQUEST, message.into())
    }
    fn unauthorized() -> Self {
        Self(StatusCode::UNAUTHORIZED, "设备令牌无效".into())
    }
    fn not_found(message: impl Into<String>) -> Self {
        Self(StatusCode::NOT_FOUND, message.into())
    }
    fn conflict(message: impl Into<String>) -> Self {
        Self(StatusCode::CONFLICT, message.into())
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        (self.0, Json(json!({ "error": self.1 }))).into_response()
    }
}

impl Store {
    fn load(path: &FsPath) -> Self {
        match std::fs::read(path) {
            Ok(bytes) => serde_json::from_slice(&bytes).unwrap_or_else(|error| {
                eprintln!("数据文件损坏（{error}），已备份并重新开始");
                let _ = std::fs::rename(path, path.with_extension("bak"));
                Store::default()
            }),
            Err(_) => Store::default(),
        }
    }

    fn save(&self, path: &FsPath) {
        let temp = path.with_extension("tmp");
        match serde_json::to_vec(self) {
            Ok(bytes) => {
                if std::fs::write(&temp, bytes).is_ok() {
                    let _ = std::fs::rename(&temp, path);
                }
            }
            Err(error) => eprintln!("无法序列化数据：{error}"),
        }
    }

    fn prune_pairings(&mut self, now: i64) {
        self.pairings.retain(|_, pairing| pairing.expires_at > now);
    }
}

// ---------------------------------------------------------------------------
// 请求 / 响应
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct CreateSpaceRequest {
    name: String,
    public_key: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct JoinRequest {
    pairing_code: String,
    name: String,
    public_key: String,
}

#[derive(Deserialize)]
struct PairingRequest {
    #[serde(default)]
    rotate: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct EnvelopeRequest {
    to: Option<String>,
    ephemeral_public_key: String,
    nonce: String,
    ciphertext: String,
    #[serde(default)]
    message_id: String,
}

fn parse_pull_query(raw: Option<String>) -> (u64, u64) {
    let mut after = 0;
    let mut wait = 0;
    if let Some(raw) = raw {
        for pair in raw.split('&') {
            let Some((key, value)) = pair.split_once('=') else {
                continue;
            };
            match key {
                "after" => after = value.parse().unwrap_or(0),
                "wait" => wait = value.parse().unwrap_or(0),
                _ => {}
            }
        }
    }
    (after, wait)
}

#[derive(Serialize)]
struct DeviceView {
    id: String,
    name: String,
    #[serde(rename = "publicKey")]
    public_key: String,
    created_at: i64,
    last_seen: i64,
}

#[derive(Serialize)]
struct SpaceView {
    #[serde(rename = "spaceId")]
    space_id: String,
    #[serde(rename = "deviceId")]
    device_id: String,
    devices: Vec<DeviceView>,
    #[serde(rename = "serverTime")]
    server_time: i64,
}

#[derive(Serialize)]
struct AuthView {
    #[serde(rename = "spaceId")]
    space_id: String,
    #[serde(rename = "deviceId")]
    device_id: String,
    token: String,
    #[serde(rename = "pairingCode")]
    pairing_code: String,
    devices: Vec<DeviceView>,
    #[serde(rename = "serverTime")]
    server_time: i64,
}

#[derive(Serialize)]
struct EnvelopeView {
    id: u64,
    from: String,
    to: Option<String>,
    #[serde(rename = "ephemeralPublicKey")]
    ephemeral_public_key: String,
    nonce: String,
    ciphertext: String,
    #[serde(rename = "messageId")]
    message_id: String,
    #[serde(rename = "createdAt")]
    created_at: i64,
}

#[derive(Serialize)]
struct PullView {
    envelopes: Vec<EnvelopeView>,
    cursor: u64,
    #[serde(rename = "serverTime")]
    server_time: i64,
}

fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_secs() as i64)
        .unwrap_or(0)
}

fn new_token() -> String {
    Uuid::new_v4().simple().to_string()
}

fn new_pairing_code() -> String {
    // 去掉 0/O/1/I 等易混字符。
    const ALPHABET: &[u8] = b"ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    let mut rng = rand::thread_rng();
    (0..8)
        .map(|_| ALPHABET[rng.gen_range(0..ALPHABET.len())] as char)
        .collect()
}

fn clean_name(value: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        "未命名设备".into()
    } else {
        trimmed.chars().take(40).collect()
    }
}

fn validate_public_key(value: &str) -> Result<(), ApiError> {
    if value.len() < 32 || value.len() > 256 {
        return Err(ApiError::bad("公钥格式无效"));
    }
    Ok(())
}

fn validate_envelope(body: &EnvelopeRequest) -> Result<(), ApiError> {
    for (label, value) in [
        ("ephemeral_public_key", body.ephemeral_public_key.as_str()),
        ("nonce", body.nonce.as_str()),
        ("ciphertext", body.ciphertext.as_str()),
    ] {
        if value.is_empty() || value.len() > MAX_ENVELOPE_BYTES {
            return Err(ApiError::bad(format!("{label} 为空或过长")));
        }
        if !value
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_' || b == b'=')
        {
            return Err(ApiError::bad(format!("{label} 不是合法的 base64url")));
        }
    }
    if body.ciphertext.len() < 24 {
        return Err(ApiError::bad("密文过短"));
    }
    Ok(())
}

fn bearer(headers: &HeaderMap) -> Option<&str> {
    headers
        .get(axum::http::header::AUTHORIZATION)?
        .to_str()
        .ok()?
        .strip_prefix("Bearer ")
        .map(str::trim)
}

fn authenticate(state: &AppState, headers: &HeaderMap) -> Result<TokenRef, ApiError> {
    let token = bearer(headers).ok_or_else(ApiError::unauthorized)?;
    let store = state.store.lock().unwrap();
    store
        .tokens
        .get(token)
        .cloned()
        .ok_or_else(ApiError::unauthorized)
}

fn devices_view(space: &Space) -> Vec<DeviceView> {
    space
        .devices
        .iter()
        .map(|device| DeviceView {
            id: device.id.clone(),
            name: device.name.clone(),
            public_key: device.public_key.clone(),
            created_at: device.created_at,
            last_seen: device.last_seen,
        })
        .collect()
}

// ---------------------------------------------------------------------------
// 路由
// ---------------------------------------------------------------------------

fn router(state: AppState) -> Router {
    Router::new()
        .route("/v1/health", get(health))
        .route("/v1/spaces", post(create_space))
        .route("/v1/spaces/join", post(join_space))
        .route("/v1/space", get(space_info))
        .route("/v1/pairing-code", post(pairing_code))
        .route("/v1/envelopes", post(push_envelope).get(pull_envelopes))
        .route("/v1/devices/{id}/revoke", post(revoke_device))
        .layer(DefaultBodyLimit::max(64 * 1024))
        .with_state(state)
}

async fn health(State(state): State<AppState>) -> Json<serde_json::Value> {
    let store = state.store.lock().unwrap();
    let devices: usize = store.spaces.values().map(|space| space.devices.len()).sum();
    let envelopes: usize = store
        .spaces
        .values()
        .map(|space| space.envelopes.len())
        .sum();
    Json(json!({
        "ok": true,
        "spaces": store.spaces.len(),
        "devices": devices,
        "envelopes": envelopes,
        "serverTime": now(),
        "protocol": 1
    }))
}

async fn create_space(
    State(state): State<AppState>,
    Json(body): Json<CreateSpaceRequest>,
) -> Result<Json<AuthView>, ApiError> {
    validate_public_key(&body.public_key)?;
    let timestamp = now();
    let space_id = Uuid::new_v4().simple().to_string();
    let device = Device {
        id: Uuid::new_v4().simple().to_string(),
        name: clean_name(&body.name),
        public_key: body.public_key,
        created_at: timestamp,
        last_seen: timestamp,
    };
    let token = new_token();
    let pairing = new_pairing_code();
    let space = Space {
        id: space_id.clone(),
        created_at: timestamp,
        devices: vec![device.clone()],
        envelopes: Vec::new(),
        next_envelope: 1,
    };
    {
        let mut store = state.store.lock().unwrap();
        store.prune_pairings(timestamp);
        store.spaces.insert(space_id.clone(), space);
        store.tokens.insert(
            token.clone(),
            TokenRef {
                space_id: space_id.clone(),
                device_id: device.id.clone(),
            },
        );
        store.pairings.insert(
            pairing.clone(),
            Pairing {
                space_id: space_id.clone(),
                expires_at: timestamp + PAIRING_TTL_SECS,
            },
        );
        store.save(&state.data);
    }
    Ok(Json(AuthView {
        space_id,
        device_id: device.id.clone(),
        token,
        pairing_code: pairing,
        devices: devices_view(&Space {
            id: String::new(),
            created_at: 0,
            devices: vec![device],
            envelopes: Vec::new(),
            next_envelope: 0,
        }),
        server_time: timestamp,
    }))
}

async fn join_space(
    State(state): State<AppState>,
    Json(body): Json<JoinRequest>,
) -> Result<Json<AuthView>, ApiError> {
    validate_public_key(&body.public_key)?;
    let timestamp = now();
    let code = body
        .pairing_code
        .trim()
        .to_uppercase()
        .replace([' ', '-'], "");
    let token = new_token();
    let mut store = state.store.lock().unwrap();
    store.prune_pairings(timestamp);
    let pairing = store
        .pairings
        .get(&code)
        .cloned()
        .ok_or_else(|| ApiError::not_found("配对码不存在或已过期"))?;
    let space = store
        .spaces
        .get_mut(&pairing.space_id)
        .ok_or_else(|| ApiError::not_found("设备空间不存在"))?;
    if space.devices.len() >= MAX_DEVICES {
        return Err(ApiError::conflict("设备数量已达上限"));
    }
    let device = Device {
        id: Uuid::new_v4().simple().to_string(),
        name: clean_name(&body.name),
        public_key: body.public_key,
        created_at: timestamp,
        last_seen: timestamp,
    };
    space.devices.push(device.clone());
    let space_id = space.id.clone();
    let devices = devices_view(space);
    store.tokens.insert(
        token.clone(),
        TokenRef {
            space_id: space_id.clone(),
            device_id: device.id.clone(),
        },
    );
    // 配对码使用一次后即失效，避免被重放。
    store.pairings.remove(&code);
    store.save(&state.data);
    Ok(Json(AuthView {
        space_id,
        device_id: device.id,
        token,
        pairing_code: String::new(),
        devices,
        server_time: timestamp,
    }))
}

async fn space_info(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<SpaceView>, ApiError> {
    let auth = authenticate(&state, &headers)?;
    let mut store = state.store.lock().unwrap();
    let timestamp = now();
    let space = store
        .spaces
        .get_mut(&auth.space_id)
        .ok_or_else(|| ApiError::not_found("设备空间不存在"))?;
    if let Some(device) = space.devices.iter_mut().find(|item| item.id == auth.device_id) {
        device.last_seen = timestamp;
    }
    let devices = devices_view(space);
    let space_id = space.id.clone();
    store.save(&state.data);
    Ok(Json(SpaceView {
        space_id,
        device_id: auth.device_id,
        devices,
        server_time: timestamp,
    }))
}

async fn pairing_code(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<PairingRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let auth = authenticate(&state, &headers)?;
    let timestamp = now();
    let mut store = state.store.lock().unwrap();
    store.prune_pairings(timestamp);
    // 同一空间只保留最新一个配对码，避免旧码长期可用。
    store
        .pairings
        .retain(|_, pairing| pairing.space_id != auth.space_id);
    let code = new_pairing_code();
    store.pairings.insert(
        code.clone(),
        Pairing {
            space_id: auth.space_id.clone(),
            expires_at: timestamp + PAIRING_TTL_SECS,
        },
    );
    store.save(&state.data);
    let _ = body.rotate;
    Ok(Json(json!({
        "pairingCode": code,
        "expiresAt": timestamp + PAIRING_TTL_SECS,
        "serverTime": timestamp
    })))
}

async fn push_envelope(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<EnvelopeRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let auth = authenticate(&state, &headers)?;
    validate_envelope(&body)?;
    let timestamp = now();
    let mut store = state.store.lock().unwrap();
    let space = store
        .spaces
        .get_mut(&auth.space_id)
        .ok_or_else(|| ApiError::not_found("设备空间不存在"))?;
    if let Some(target) = body.to.as_deref() {
        if !space.devices.iter().any(|device| device.id == target) {
            return Err(ApiError::bad("目标设备不在当前空间"));
        }
    }
    let id = space.next_envelope;
    space.next_envelope += 1;
    space.envelopes.push(Envelope {
        id,
        from: auth.device_id.clone(),
        to: body.to,
        ephemeral_public_key: body.ephemeral_public_key,
        nonce: body.nonce,
        ciphertext: body.ciphertext,
        message_id: body.message_id.chars().take(80).collect(),
        created_at: timestamp,
    });
    while space.envelopes.len() > MAX_ENVELOPES {
        space.envelopes.remove(0);
    }
    store.save(&state.data);
    Ok(Json(json!({ "id": id, "cursor": id, "serverTime": timestamp })))
}

fn poll_envelopes(
    state: &AppState,
    auth: &TokenRef,
    after: u64,
) -> Result<(Vec<EnvelopeView>, u64, i64), ApiError> {
    let timestamp = now();
    let mut store = state.store.lock().unwrap();
    let space = store
        .spaces
        .get_mut(&auth.space_id)
        .ok_or_else(|| ApiError::not_found("设备空间不存在"))?;
    if let Some(device) = space.devices.iter_mut().find(|item| item.id == auth.device_id) {
        device.last_seen = timestamp;
    }
    let mut envelopes: Vec<EnvelopeView> = space
        .envelopes
        .iter()
        .filter(|envelope| {
            envelope.id > after
                && envelope.from != auth.device_id
                && envelope
                    .to
                    .as_deref()
                    .map(|target| target == auth.device_id)
                    .unwrap_or(true)
        })
        .take(200)
        .map(|envelope| EnvelopeView {
            id: envelope.id,
            from: envelope.from.clone(),
            to: envelope.to.clone(),
            ephemeral_public_key: envelope.ephemeral_public_key.clone(),
            nonce: envelope.nonce.clone(),
            ciphertext: envelope.ciphertext.clone(),
            message_id: envelope.message_id.clone(),
            created_at: envelope.created_at,
        })
        .collect();
    envelopes.sort_by_key(|envelope| envelope.id);
    let cursor = envelopes.last().map(|envelope| envelope.id).unwrap_or(after);
    if !envelopes.is_empty() {
        store.save(&state.data);
    }
    Ok((envelopes, cursor, timestamp))
}

async fn pull_envelopes(
    State(state): State<AppState>,
    headers: HeaderMap,
    RawQuery(raw): RawQuery,
) -> Result<Json<PullView>, ApiError> {
    let auth = authenticate(&state, &headers)?;
    let (after, wait) = parse_pull_query(raw);
    let wait = wait.min(30);
    let deadline = now() + wait as i64;
    loop {
        let (envelopes, cursor, timestamp) = poll_envelopes(&state, &auth, after)?;
        if !envelopes.is_empty() || timestamp >= deadline || wait == 0 {
            return Ok(Json(PullView {
                envelopes,
                cursor,
                server_time: timestamp,
            }));
        }
        tokio::time::sleep(Duration::from_millis(400)).await;
    }
}

async fn revoke_device(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let auth = authenticate(&state, &headers)?;
    if id == auth.device_id {
        return Err(ApiError::bad("不能撤销当前设备"));
    }
    let mut store = state.store.lock().unwrap();
    let space = store
        .spaces
        .get_mut(&auth.space_id)
        .ok_or_else(|| ApiError::not_found("设备空间不存在"))?;
    space.devices.retain(|device| device.id != id);
    store
        .tokens
        .retain(|_, token| !(token.space_id == auth.space_id && token.device_id == id));
    store.save(&state.data);
    Ok(Json(json!({ "revoked": id, "serverTime": now() })))
}

// ---------------------------------------------------------------------------
// 启动
// ---------------------------------------------------------------------------

fn parse_args() -> (SocketAddr, PathBuf) {
    let mut bind = "127.0.0.1:8787".to_string();
    let mut data = PathBuf::from("qingniao-sync-data.json");
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--bind" => {
                if let Some(value) = args.next() {
                    bind = value;
                }
            }
            "--data" => {
                if let Some(value) = args.next() {
                    data = PathBuf::from(value);
                }
            }
            "--help" | "-h" => {
                println!(
                    "青鸟同步服务\n\n用法:\n  qingniao-sync [--bind 127.0.0.1:8787] [--data ./data.json]\n\n\
                     服务器只保存端到端加密信封；请置于 TLS 反向代理之后。"
                );
                std::process::exit(0);
            }
            _ => {}
        }
    }
    let address = bind.parse().unwrap_or_else(|_| {
        eprintln!("监听地址无效：{bind}");
        std::process::exit(2);
    });
    (address, data)
}

#[tokio::main]
async fn main() {
    let (address, data_path) = parse_args();
    if let Some(parent) = data_path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let store = Store::load(&data_path);
    let state = AppState {
        store: Arc::new(Mutex::new(store)),
        data: Arc::new(data_path.clone()),
    };
    let app = router(state);
    let listener = match tokio::net::TcpListener::bind(address).await {
        Ok(listener) => listener,
        Err(error) => {
            eprintln!("无法监听 {address}：{error}");
            std::process::exit(1);
        }
    };
    println!("青鸟同步服务已启动：http://{address}");
    println!("数据文件：{}", data_path.display());
    println!("只保存密文信封；请使用 TLS 反向代理。");
    if let Err(error) = axum::serve(listener, app)
        .with_graceful_shutdown(async {
            let _ = tokio::signal::ctrl_c().await;
        })
        .await
    {
        eprintln!("服务异常退出：{error}");
    }
}

// ---------------------------------------------------------------------------
// 测试
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_state() -> AppState {
        let path = std::env::temp_dir().join(format!("qingniao-sync-{}.json", Uuid::new_v4()));
        AppState {
            store: Arc::new(Mutex::new(Store::default())),
            data: Arc::new(path),
        }
    }

    #[test]
    fn pairing_codes_are_unambiguous_and_unique_enough() {
        let codes: Vec<String> = (0..64).map(|_| new_pairing_code()).collect();
        assert!(codes.iter().all(|code| code.len() == 8));
        assert!(codes
            .iter()
            .all(|code| !code.contains('0') && !code.contains('O') && !code.contains('I')));
        let unique: std::collections::HashSet<_> = codes.iter().collect();
        assert!(unique.len() > 60);
    }

    #[test]
    fn store_round_trip_survives_corruption() {
        let path = std::env::temp_dir().join(format!("qingniao-store-{}.json", Uuid::new_v4()));
        let mut store = Store::default();
        store.spaces.insert(
            "space".into(),
            Space {
                id: "space".into(),
                created_at: now(),
                devices: vec![Device {
                    id: "dev".into(),
                    name: "测试".into(),
                    public_key: "pk".into(),
                    created_at: now(),
                    last_seen: now(),
                }],
                envelopes: Vec::new(),
                next_envelope: 1,
            },
        );
        store.save(&path);
        let loaded = Store::load(&path);
        assert_eq!(loaded.spaces["space"].devices.len(), 1);
        std::fs::write(&path, b"not-json").unwrap();
        let recovered = Store::load(&path);
        assert!(recovered.spaces.is_empty());
        assert!(path.with_extension("bak").exists());
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn envelope_validation_rejects_plaintext_and_oversize() {
        let ok = EnvelopeRequest {
            to: None,
            ephemeral_public_key: "AAAA".into(),
            nonce: "BBBB".into(),
            ciphertext: "C".repeat(64),
            message_id: "m1".into(),
        };
        assert!(validate_envelope(&ok).is_ok());
        let mut bad = EnvelopeRequest {
            to: None,
            ephemeral_public_key: String::new(),
            nonce: "BBBB".into(),
            ciphertext: "C".repeat(64),
            message_id: "m1".into(),
        };
        assert!(validate_envelope(&bad).is_err());
        bad.ephemeral_public_key = "AAAA".into();
        bad.ciphertext = "密文".into();
        assert!(validate_envelope(&bad).is_err());
        bad.ciphertext = "C".repeat(MAX_ENVELOPE_BYTES + 1);
        assert!(validate_envelope(&bad).is_err());
    }

    #[tokio::test]
    async fn health_endpoint_responds() {
        use http_body_util::BodyExt;
        use tower::ServiceExt;

        let state = temp_state();
        let response = router(state)
            .oneshot(
                axum::http::Request::builder()
                    .uri("/v1/health")
                    .body(axum::body::Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let bytes = response.into_body().collect().await.unwrap().to_bytes();
        let json: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(json["ok"], true);
        assert_eq!(json["protocol"], 1);
    }
}
