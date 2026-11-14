# 青鸟短信 · Qingniao

**面向 Android 12+ 的本地优先短信与彩信客户端。**  
Flutter 负责界面与流体动效，Kotlin 对接系统短信服务，Rust 承担分析、搜索、MMS PDU 与端到端加密。

> 青鸟不是 CapsuleSMS 的 Java 代码移植；它用 Flutter + Rust 重新实现了短信工作流，
> 并补上 Material 3 Expressive 形状、统一帧调度与自建端到端加密同步。

---

## 亮点

| | 能力 | 实现 |
|:--:|---|---|
| 💬 | **完整 SMS 工作流** | 会话、未读、搜索、分页、草稿、双卡、长短信分段与分片回执 |
| 🔐 | **验证码中心** | Rust 保守解析（UTF-16 高亮），独立标签页一键复制；正文不上传 |
| 🖼️ | **彩信** | 系统 `SmsManager` + `android-smsmms` 收发、附件预览；Rust MMS PDU 编解码 |
| 🔔 | **通知直回** | 通知栏直接回复、标记已读、按 SIM 分渠道、会话分组 |
| 🗑️ | **可恢复回收站** | 7 / 30 / 90 天或永久；恢复与永久删除均二次确认 |
| 🕒 | **定时发送** | `AlarmManager` 精确闹钟，权限不足时自动降级 |
| 🎨 | **Material 3 Expressive** | 头像 / FAB / 发送键 / 气泡在 `circle ↔ cookie / sunny` 间连续形变 |
| 🌊 | **极光引擎** | 单 Ticker 驱动全部弹簧；背景限频、滚动退避、按真实帧耗时自适应降级 |
| 🌈 | **Material You** | 读取系统强调色 + 6 套品牌色板；深色 / AMOLED |
| ☁️ | **端到端加密同步** | X25519 + HKDF-SHA256 + AES-256-GCM；自带最小 Rust 服务端 |
| 🪶 | **本地优先** | 默认不联网、无广告 / 统计 SDK；解析、索引、密钥都在设备上 |

## 界面与动效

- **极光背景**：5 组径向渐变光团 + 星点，全部包在 `RepaintBoundary` 中；
  滚动时降低帧率与漂移幅度，避免与列表争抢 GPU。
- **统一时钟**：背景、弹簧按压、加载指示器共享一个 `Ticker`；页面切换不重启时间线。
- **自适应画质**：`SchedulerBinding.addTimingsCallback` 监控 build/raster 耗时，
  超过阈值自动从 full → balanced → efficient；恢复后逐级回升。
- **形状系统**：基于 `material_new_shapes`（AndroidX graphics-shapes 的 Flutter 实现），
  超椭圆表面、非对称气泡、形变头像与发送键。
- **连续转场**：Android 使用系统预测性返回 + Material 3 FadeForwards；
  其他平台使用自研共享轴；`disableAnimations` 时全部退化为直切。

## 架构

```
Flutter (Dart)
  lib/aurora     设计系统 / 极光引擎 / 形状 / 组件 / 转场
  lib/messaging  收件箱 / 会话 / 撰写 / 验证码 / 回收站 / 状态
  lib/settings   外观 / 黑名单 / 同步 / 诊断
  lib/sync       E2E 同步客户端（HTTP + 游标 + 去重）
        │ MethodChannel com.blue.qingniao/*      │ flutter_rust_bridge
Kotlin 平台层                                    Rust 核心
  默认短信角色 / 权限                             OTP / 分类 / 链接
  Telephony provider 读写                         GSM-7 / UCS-2 分段
  SmsManager 多段 + 双卡                          CJK 倒排索引 + BM25-lite
  MMS / 通知直回 / 定时 / 回收站                  MMS PDU 编解码
  联系人 / 附件 / 备份                            X25519 + AES-GCM / 存储
        │
系统短信库 (content://sms, content://mms, threads)
```

更详细的设计与数据流见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，
同步协议见 [docs/SYNC-PROTOCOL.md](docs/SYNC-PROTOCOL.md)，
与 CapsuleSMS 的能力对照见 [docs/FEATURES.md](docs/FEATURES.md)。

## 同步（可选）

```bash
cd server-rs
cargo build --release --offline
./target/release/qingniao-sync --bind 0.0.0.0:8787 --data /var/lib/qingniao/data.json
```

服务器只保存不透明密文信封；设备通过一次性配对码加入空间。客户端用 Rust 生成
X25519 信封，Dart 负责 HTTP、游标与去重，Kotlin 把解出的消息写回系统短信库。
部署在 TLS 反向代理之后；完整威胁模型见协议文档。

## 构建

环境：Flutter 3.47.9 / Dart 3.13.7、JDK 17、Android SDK 36、NDK、Rust、FRB 2.13.0。
最低 Android 12（API 31）。

```powershell
flutter pub get --offline
flutter_rust_bridge_codegen generate
cargo test --manifest-path rust/Cargo.toml --offline
flutter analyze
flutter test
flutter build apk --debug
```

产物：`build/app/outputs/flutter-apk/app-debug.apk`。发布前请配置自己的签名。

## 已验证

| 项目 | 结果 |
|---|---|
| `flutter analyze` | **No issues found** |
| Flutter Widget / 渲染测试 | 14 项通过（收件箱/会话/回收站/窄屏大字体/截图） |
| Rust 核心 | `core::` 68 项、`api::engine` 8 项通过 |
| 同步服务端 | 健康检查、创建空间、配对、投递/拉取信封端到端实测通过 |
| APK | debug 构建成功（armv7 / arm64 / x86 / x86_64） |

渲染截图可通过 `QINGNIAO_RENDER_PREVIEW=1 flutter test` 输出到
`build/verification/`（浅色/深色收件箱与会话）。

## 已知边界

- 本环境没有可用的 Android 模拟器硬件加速与真机，**尚未完成真机收发验证**；
  运营商 MMS APN、进程被杀后的回执、双卡切换需要在设备上复核。
- 通知回复、定时发送、MMS 下载已实现但需要设备验证。
- MMS PDU 仅实现 M-Retrieve.conf 子集；GB2312 文本离线解码为尽力而为。
- 同步目前为手动触发；后台长轮询 / JobScheduler 兜底与备份导入仍在路线图中。
- 搜索索引在内存中重建；超大短信库只索引前 4k 字符/条。

## 目录

```
lib/             Flutter 应用
rust/            Rust 核心与 FRB 门面
android/         Kotlin 平台层与清单
server-rs/       最小同步服务（axum）
docs/            架构、同步协议、功能对照
test/            Widget / 渲染测试
```

## 许可

业务源码用于本项目的替换与验证。`CapsuleSMS`、`OPPO`、`ColorOS` 与 Android
相关标识归各自权利人所有。
