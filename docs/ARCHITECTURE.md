# 青鸟短信 · 架构

青鸟短信是一个 **Flutter UI + Kotlin 平台层 + Rust 核心引擎** 的本地优先短信客户端。
目标是在 Android 12+ 上替代系统短信应用与 CapsuleSMS：读写系统短信库、收发 SMS/MMS、
通知栏直回、双卡选择、可恢复回收站、验证码识别、全文搜索，以及可选的端到端加密同步。

```
┌──────────────────────────────────────────────────────────────┐
│ Flutter (Dart)                                               │
│  Aurora 设计系统 · 极光引擎 · 收件箱/会话/验证码/设置          │
│  MessageHub (ChangeNotifier) · MessageRepository             │
└───────────────┬──────────────────────────┬───────────────────┘
                │ MethodChannel            │ flutter_rust_bridge
                │ com.blue.qingniao/*      │ (FFI, 后台线程池)
┌───────────────▼──────────────┐  ┌────────▼───────────────────┐
│ Kotlin 平台层                │  │ Rust 核心 (rust/src/core)   │
│  · 默认短信角色 / 权限        │  │  · OTP / 分类 / 链接        │
│  · Telephony provider 读写    │  │  · GSM-7 / UCS-2 分段       │
│  · SmsManager 多段 + 双卡     │  │  · CJK 倒排索引与高亮       │
│  · MMS（android-smsmms）      │  │  · MMS PDU 编解码           │
│  · 接收器 / 通知 / 定时发送   │  │  · 回收站 / 设置持久化      │
│  · 联系人 / 附件 / 备份       │  │  · X25519 + AES-GCM 信封    │
└───────────────────────────────┘  └─────────────────────────────┘
                │
┌───────────────▼──────────────────────────────────────────────┐
│ 系统短信库 (content://sms, content://mms, threads)            │
└──────────────────────────────────────────────────────────────┘
```

## 1. 为什么是三层

| 层 | 负责 | 不负责 |
|---|---|---|
| Flutter | 视觉、交互、连续动效、状态编排 | 任何系统短信 API |
| Kotlin | Android 权限、provider、收发、通知、调度 | 文本分析与加密 |
| Rust | 纯计算：解析、索引、编解码、密码学、持久化 | UI 与系统 API |

Rust 通过 `flutter_rust_bridge` 运行在独立线程池，UI 线程只做数据绑定；
重活（验证码批量分析、全文索引、MMS PDU、信封加解密）不会掉帧。

## 2. 数据流

1. `MessageHub.start()` 订阅 `EventChannel com.blue.qingniao/changes`；系统短信库变化
   或新 Intent 到达时触发刷新。
2. `MessageRepository.conversations()` 通过 `MethodChannel` 请求 Kotlin；
   Kotlin 用单线程 executor 查询 provider，并附带联系人名称、置顶/归档/黑名单状态。
3. 返回的摘要批量送入 Rust `analyze_messages`，得到分类与验证码（UTF-16 下标）；
   Dart 侧合并后驱动列表。
4. 打开会话时按 `_id` 游标分页拉取，`reverse: true` 的列表保证输入法与键盘弹出时
   视口不跳动；新消息从底部弹簧式进入。
5. 发送走 `SmsTransport`：写入 Outbox → `SmsManager` 多段发送 → 回执 Receiver 聚合
   分片状态 → provider 更新 → 事件通道刷新 UI。

## 3. 极光引擎（Aurora Engine）

### 3.1 统一帧调度

- 全应用只有一个 `Ticker`（`AuroraEngine.attach`），所有按压/指示器弹簧
  （`AuroraSpring`）在同一个 tick 中推进，避免每个组件一个 `AnimationController`。
- 背景氛围动效使用共享 `ValueNotifier<double> clock`，页面切换不会重启时间线；
  不同页面的极光看起来是同一条持续的流。
- 背景按质量档位限频：完整 30fps、平衡 24fps、省电 15fps；滚动时最多 20fps。
- 列表逐项浮现使用隐式动画（`TweenAnimationBuilder`），动画结束即释放，
  不会在长列表里积累 ticker。

### 3.2 自适应画质

`SchedulerBinding.addTimingsCallback` 读取真实 build + raster 耗时：

- 平均帧耗时 > 26ms 持续约 90 帧 → 降一档（full → balanced → efficient）；
- < 13ms 持续约 600 帧 → 升一档；
- 画质影响光团数量（5/3/2）、星点、视差与背景帧率；`reduced` 动效档位直接停用漂移。

这套机制让低端机自动退到静态极光，而高端机保留完整氛围。

### 3.3 渲染优化

- 极光背景整体包在 `RepaintBoundary`，列表滚动不会重绘背景；
- 光团用径向渐变直接绘制，避免逐帧 `blur`；星点只在深色 + 完整画质时绘制；
- 头像、气泡、列表行各自 `RepaintBoundary`，选中/未读变化只重绘局部；
- 页面转场使用系统预测性返回 + Material 3 FadeForwards（Android），
  非 Android 使用自研共享轴；`MediaQuery.disableAnimations` 时全部退化为直切；
- 列表项圆角/阴影使用 `ShapeDecoration` 而非多层嵌套 `ClipRRect`。

### 3.4 Material 3 Expressive 形状

形状来自 `material_new_shapes`（AndroidX `graphics-shapes` 的 Flutter 实现）：

- 头像按号码稳定哈希到 cookie / clover / sunny / gem / flower / soft-burst 等形状；
- 未读状态在 `circle ↔ sunny` 之间用 `Morph` 连续形变；
- FAB 使用 `sunny`、发送键在空/非空之间 `circle ↔ cookie9` 形变；
- 气泡提供柔和（超椭圆、非对称收角）、胶囊、饼干三种风格；
- 页面内所有可交互表面使用 `RoundedSuperellipseBorder`，与 M3 Expressive 的
  超椭圆曲率一致。

## 4. 主题与动态取色

- 品牌色板：青碧、极光、湖水、晨曦、梅子、石墨；默认「青碧」。
- Android 12+ 读取系统 `system_accent1_500` 作为种子，Flutter 侧
  `ColorScheme.fromSeed` 生成完整明暗色板；也可在设置中关闭动态取色。
- 深色主题支持 AMOLED 纯黑（由协作分支扩展）。
- 字体：默认系统字体；可选内置 HarmonyOS Sans / Google Sans（见 `lib/design`）。

## 5. 安全与隐私

- 默认不联网、无广告/统计 SDK；验证码、分类、搜索、回收站状态均在本机完成。
- 云同步是可选项：客户端用 X25519 + HKDF-SHA256 + AES-256-GCM 生成不透明信封，
  服务端只保存密文、nonce、临时公钥和路由元数据。详见
  [SYNC-PROTOCOL.md](SYNC-PROTOCOL.md)。
- 设备私钥保存在应用私有目录（Unix 上 chmod 0600）。

## 6. 目录

```
lib/
  aurora/        设计系统、极光引擎、形状、背景、组件、转场
  messaging/     模型、仓库、MessageHub、收件箱/会话/撰写/验证码/回收站
  settings/      设置、外观、黑名单、同步
  onboarding/    默认短信角色与权限引导
  design/        内置字体与 Android 调色板桥
  src/rust/      FRB 生成代码
rust/src/
  api/           FRB 门面（engine.rs）
  core/          分析/分段/搜索/存储/MMS PDU/密码学
android/app/src/main/kotlin/com/blue/qingniao/
  MainActivity / SmsRepository / SmsTransport / MmsTransport
  MessageStore / 接收器 / 通知 / 定时发送
server-rs/       最小同步服务（axum + tokio）
docs/            架构、协议、功能
```

## 7. 构建与验证

```bash
flutter pub get --offline
flutter analyze
flutter test --no-pub
flutter build apk --debug --no-pub
```

本仓库在离线环境下使用以下验证：

- `flutter test`：收件箱/会话/回收站/窄屏大字体 5 项 Widget 测试；
- `cargo test --offline`：Rust 核心 76 个测试（分析、分段、搜索、存储、MMS PDU、密码学）；
- 渲染截图：`test/inbox_rendering_test.dart` 在 `QINGNIAO_RENDER_PREVIEW=1` 时输出
  `build/verification/inbox_{light,dark}.png`；
- `server-rs`：`cargo test --offline` 覆盖配对、信封校验、持久化损坏恢复与健康检查。

## 8. 已知限制

- MMS PDU 只实现 M-Retrieve.conf 子集；GB2312 文本缺少离线映射表；SMIL 只用于排版，
  不参与正文/附件提取。Android 侧发送/下载仍使用系统 `SmsManager` 与
  `android-smsmms`，Rust 编解码用于兼容性验证与未来替换。
- 搜索数字片段只索引 ≥4 位；单文档正文上限 4k 字符，超长 CJK 只索引前段。
- 多候选验证码同时邻近关键词时返回空，避免误复制（保守策略）。
- 定时发送、通知直回、MMS 下载依赖 Android 平台层；桌面调试使用演示仓库。
