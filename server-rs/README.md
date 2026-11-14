# qingniao-sync

青鸟短信的最小同步服务。它只保存**不透明密文信封**，不持有任何私钥，也不解析正文。

- Rust / axum 0.8 / tokio
- 单文件 JSON 持久化（原子写、损坏自动备份）
- 设备空间、一次性配对码、Bearer 令牌、长轮询
- 无数据库、无外部依赖、无账号密码

## 运行

```bash
cargo build --release --offline
./target/release/qingniao-sync --bind 0.0.0.0:8787 --data ./data.json
```

参数：

| 参数 | 默认 | 说明 |
|---|---|---|
| `--bind` | `127.0.0.1:8787` | 监听地址；对外服务请置于 TLS 反向代理之后 |
| `--data` | `qingniao-sync-data.json` | 数据文件路径 |

## 健康检查

```bash
curl http://127.0.0.1:8787/v1/health
# {"ok":true,"spaces":0,"devices":0,"envelopes":0,"serverTime":...,"protocol":1}
```

## 自动冒烟测试

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File server-rs\scripts\smoke.ps1
```

脚本会构建服务端、在本地随机端口启动、然后依次验证：健康检查 → 创建空间 →
用配对码加入第二台设备 → 轮换配对码 → 投递密文信封 → 以第二台设备拉取 →
确认发送方拉不到自己的信封。数据文件写在 `build/verification/`，退出时清理，
成功输出 `ALL PASS`。

可选参数：`-Port 8899`、`-SkipBuild`。

## API

| 方法 | 路径 | 说明 |
|---|---|---|
| `GET` | `/v1/health` | 健康检查 |
| `POST` | `/v1/spaces` | 创建空间（第一台设备） |
| `POST` | `/v1/spaces/join` | 凭配对码加入 |
| `GET` | `/v1/space` | 空间与设备列表 |
| `POST` | `/v1/pairing-code` | 轮换配对码 |
| `POST` | `/v1/envelopes` | 投递密文信封 |
| `GET` | `/v1/envelopes?after=&wait=` | 按游标拉取 / 长轮询 |
| `POST` | `/v1/devices/{id}/revoke` | 撤销设备 |

完整字段、密码学与威胁模型见 [../docs/SYNC-PROTOCOL.md](../docs/SYNC-PROTOCOL.md)。

## 部署建议

- 使用 Caddy/Nginx 终止 TLS；
- 数据文件放在持久卷，定期备份；
- 通过防火墙/私有网络限制注册入口；
- 监控 `/v1/health` 的 `envelopes` 增长，必要时调低 `MAX_ENVELOPES`。

## 安全边界

服务器可以看到：空间、设备名称/公钥、在线时间、密文大小与时间、路由目标。
服务器看不到：短信正文、验证码、联系人、附件内容。
客户端负责端到端加密；没有客户端私钥时，拿到数据文件也无法解密。
