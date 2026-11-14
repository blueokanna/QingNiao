# 青鸟同步协议 v1

目标：在**服务器不可信**的前提下，让多台设备同步短信正文。

- 传输层：HTTPS（自建服务请置于 TLS 反向代理之后）。
- 内容层：客户端生成的端到端加密信封；服务器只保存密文。
- 服务器不持有私钥、不解析正文、不做验证码识别。

## 1. 密码学

每台设备首次启动时生成一份长期 X25519 密钥对：

```
device_identity.json
  deviceId      UUID
  privateKey    base64url(32B)
  publicKey     base64url(32B)
```

发送一条消息：

1. 生成一次性 X25519 密钥对 `(eph_sk, eph_pk)`；
2. `shared = X25519(eph_sk, recipient_pk)`；
3. `key = HKDF-SHA256(shared, salt = sender_pk || recipient_pk, info = "qingniao-envelope-v1", 32B)`；
4. `nonce = 12 random bytes`；
5. `ciphertext = AES-256-GCM(key, nonce, plaintext)`。

信封（base64url，无 padding）：

```json
{
  "ephemeralPublicKey": "...",
  "nonce": "...",
  "ciphertext": "..."
}
```

接收方用**自己的长期私钥**与 `ephemeralPublicKey` 做 ECDH，重新派生同一把内容密钥。
指纹 = `SHA-256(publicKey)` 前 16 字节，格式化为 8 组 4 位大写 hex，用于人工核对。

> 群发/广播信封（`to = null`）对空间内每台设备各生成一个信封，不复用内容密钥。

## 2. 空间与配对

服务器把设备组织为 **space**。一台设备先创建空间，其余设备凭一次性配对码加入。

- 配对码：8 位，去除 `0/O/1/I` 等易混字符；10 分钟有效；使用一次后失效。
- 设备令牌：32 字节随机数（uuid v4 simple），`Authorization: Bearer <token>`。
- 每空间最多 8 台设备；每空间最多保存 8192 个信封（超出丢弃最旧）。

服务器可见：空间 ID、设备 ID/名称/公钥、设备在线时间、信封大小与时间、路由目标。
服务器不可见：短信正文、验证码、联系人、附件内容。

## 3. HTTP API

所有请求/响应均为 JSON；时间单位为 Unix 秒。

### `GET /v1/health`

```json
{ "ok": true, "spaces": 1, "devices": 2, "envelopes": 12, "protocol": 1 }
```

### `POST /v1/spaces`（创建空间，第一台设备）

请求：

```json
{ "name": "Pale Blue", "publicKey": "base64url" }
```

响应：

```json
{
  "spaceId": "...",
  "deviceId": "...",
  "token": "...",
  "pairingCode": "K7Q2M9XA",
  "devices": [{ "id": "...", "name": "Pale Blue", "publicKey": "...", "createdAt": 0, "lastSeen": 0 }],
  "serverTime": 0
}
```

### `POST /v1/spaces/join`（凭配对码加入）

请求：

```json
{ "pairingCode": "K7Q2M9XA", "name": "小岛", "publicKey": "base64url" }
```

响应同创建；`pairingCode` 为空（已失效）。

### `GET /v1/space`（需令牌）

返回空间、设备列表与服务器时间；同时更新本设备 `lastSeen`。

### `POST /v1/pairing-code`（需令牌）

生成/轮换当前空间的配对码；旧的未使用配对码立即失效。

```json
{ "pairingCode": "M4X8Q2TW", "expiresAt": 1730000000, "serverTime": 1730000000 }
```

### `POST /v1/envelopes`（需令牌）

```json
{
  "to": "device-id 或 null（广播）",
  "ephemeralPublicKey": "base64url",
  "nonce": "base64url",
  "ciphertext": "base64url",
  "messageId": "客户端去重 ID（可选）"
}
```

响应 `{ "id": 42, "cursor": 42, "serverTime": ... }`。

约束：单个字段 ≤ 4KB，请求体 ≤ 64KB；`to` 必须是同空间设备。

### `GET /v1/envelopes?after=<cursor>&wait=<0..30>`（需令牌）

- `after`：上次游标，默认 0；
- `wait`：长轮询秒数，0 表示立即返回；
- 返回 `id > after`、`from != self`、且 `to == self || to == null` 的最多 200 条；
- 按 id 升序，`cursor` 为本次最大 id。

```json
{
  "envelopes": [
    {
      "id": 42,
      "from": "device-id",
      "to": null,
      "ephemeralPublicKey": "...",
      "nonce": "...",
      "ciphertext": "...",
      "messageId": "...",
      "createdAt": 1730000000
    }
  ],
  "cursor": 42,
  "serverTime": 1730000000
}
```

客户端只需持久化 `cursor`；同一条信封可重复拉取，由客户端按 `messageId` 去重。

### `POST /v1/devices/{id}/revoke`（需令牌）

移除设备并吊销其令牌；不能撤销当前设备。

## 4. 客户端同步循环

```
pull(cursor, wait=25) → 逐条 sync_decrypt → 按 messageId 去重 → 写入本地
本地新短信 → 为每台已配对设备 sync_encrypt → POST /v1/envelopes → 记录已发送
断网/失败 → 写入本地 outbox → 指数退避重试
```

建议：

- 前台 25s 长轮询；后台用 WorkManager/JobScheduler 兜底（最短 15 分钟）；
- 只同步 SMS 文本与必要元数据（时间、对端号码、SIM）；MMS 附件暂不同步；
- 服务器地址、令牌与游标保存在应用私有存储，不写入日志。

## 5. 威胁模型

| 攻击者 | 能做什么 | 不能做什么 |
|---|---|---|
| 服务器运营者 | 看到账号、设备、时间、密文大小；拒绝服务 | 解密正文；伪造可解密信封 |
| 网络中间人 | 无 TLS 时可阻断/重放 | 解密（AES-GCM 认证失败） |
| 拿到数据库的人 | 看到密文与公钥 | 解密（无私钥） |
| 拿到手机的人 | 读取应用私有目录 | 在设备锁定时无 Keystore 保护（当前实现为文件 ACL） |

未实现：前向保密（长期私钥泄露可解历史）、密钥轮换 UI、设备撤销后的密钥重加密。
这些是 v2 的方向。

## 6. 运行

```bash
cd server-rs
cargo build --release --offline
./target/release/qingniao-sync --bind 0.0.0.0:8787 --data /var/lib/qingniao/data.json
```

反向代理示例（Caddy）：

```
sync.example.com {
  reverse_proxy 127.0.0.1:8787
}
```

健康检查：`curl https://sync.example.com/v1/health`。

> 服务器不提供账号密码登录；设备令牌即凭证。请自行限制注册入口或部署在私有网络。
