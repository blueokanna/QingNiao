# 青鸟短信 · Qingniao

面向 Android 的本地优先短信与彩信客户端。Flutter 构建 Material 3 界面，Kotlin 对接系统通信能力，Rust 负责文本分析、搜索与密码学模块。

**简体中文** · [English](README_EN.md)

包名 `com.blue.qingniao`，最低 Android 12（API 31）。只维护 Android 应用；桌面构建脚本用于交叉编译，不代表提供桌面客户端。

## 功能

| 模块 | 当前实现 |
| --- | --- |
| 短信 | 默认短信角色、双卡、长短信分段、发送与送达状态、草稿、搜索、分页 |
| 会话 | 多选、复制、全部已读、置顶、归档、黑名单；左右滑可配置，默认左滑回收、右滑已读 |
| 验证码 | 本机识别、一键复制、敏感剪贴板、可关闭的阅后回收 |
| 回收站 | 恢复、永久删除、保留期限；无法确认系统删除时保留本地记录 |
| 定时发送 | 持久化任务、系统闹钟、启动及重启恢复；缺少精确闹钟权限时降级调度 |
| 彩信 | 混合 SMS/MMS 会话、群组收件人、附件预览与系统传输；需逐运营商验证 |
| 通知 | 回复、已读、复制验证码；系统支持时请求 promoted notification，展示由系统决定 |
| 外观 | Material 3 组件与 Expressive Shape、Monet、六套参考色、深色与 AMOLED、三种自适应图标 |
| 字体 | 系统字体、HarmonyOS Sans、Google Sans；中文使用 HarmonyOS Sans 回退 |
| 语言 | 中、英、印地、西班牙、阿拉伯、法、孟加拉、葡萄牙、俄、乌尔都语；支持 RTL |
| 可选联网 | 自建加密同步与 FCM 同步提示，默认关闭，需自行配置 |

阅后回收针对本次加载时未读、在前台会话完整显示约两秒的验证码。滚动、进入后台或多选会打断计时，批量已读不会触发回收。通知到期消失与短信正文回收是独立行为。错过发送时间的任务保留待确认，不会在重启后集中补发。

## Aurora 动效与渲染

Aurora 是应用层调度器，运行在 Flutter 帧调度与 GPU 渲染管线上，没有修改 Android 系统合成器或驱动。

- 自定义弹簧和背景共享一个 VSync Ticker，只推进活跃弹簧；集合变化时才重建遍历快照。Material 组件及路由保留 Flutter 自身的动画生命周期。
- 弹簧使用解析积分，快速反向保留位置与速度，长帧按真实经过时间推进。恢复前台时重置时间基准，不把后台停留时间计入过渡。
- 全局共享一个背景，通过 `CustomPainter.repaint` 更新绘制。标签页保留状态，直接过渡到目标页，隐藏页停止组件 Ticker 并屏蔽交互。
- 按屏幕刷新率计算帧预算，根据 build/raster 耗时降低背景复杂度，不将动画限为 30 FPS。最终显示模式仍由系统、电量、温度和用户设置决定。
- Shape 缓存最多 64 组；系统内存压力清理形状及可驱逐的图片缓存。附件按需读取，超限明确报错，不静默截断。
- 尊重系统减少动态效果。省电模式停止环境背景、保留交互；AMOLED 使用黑色表面并关闭极光背景。

以上机制不等于已证明降低功耗或稳定输出 120 FPS。性能结论需要 profile 模式真机数据。

## 颜色与资源

参考色来自提供的涂布纸色卡 PDF 中的 CMYK 模拟色块：[色板来源与转换结果](assets/palettes/coated_reference.json)。六色为 3295 C `#00907F`、2725 C `#4D5FAB`、3015 C `#007CB7`、1665 C `#F37121`、2587 C `#6352A2`、Cool Gray 11 C `#5A5B5E`。表面及状态色由参考色派生，Monet 使用系统色阶。RGB 显示不是经认证的实体潘通专色匹配。

字体来源与散列见 [字体清单](assets/fonts/manifest.json)，许可见 [assets/licenses](assets/licenses)。翻译位于 `assets/l10n`；应用代码使用英文注释。`rust/resources` 的 121 个 TXT 共 1,958 字节，全部有引用：37 个运行时关键词，其余为测试资源。文本通过 `include_str!` 在编译时嵌入，不在动画过程中逐文件读取，不能直接删除。

## 工程结构

| 目录 | 职责 |
| --- | --- |
| `lib/aurora` | 帧调度、弹簧、形状、主题、公共组件 |
| `lib/messaging` | 会话、验证码、撰写、彩信、回收站与状态 |
| `lib/settings`、`lib/sync` | 设置与同步客户端 |
| `android/app/src/main/kotlin` | 默认角色、Telephony、通知、双卡、权限及调度 |
| `rust/src` | 分段、分析、搜索、MMS 编解码、加密与桥接 |
| `server-rs` | 可选同步服务 |
| `test`、`integration_test`、`tool` | 回归测试、真机性能测试、构建与校验 |

业务代码使用 Dart、Kotlin、Rust；Flutter 生成的 Java 插件注册文件属于工具链产物。系统 Provider 保存真实 SMS/MMS，应用侧存储保存归档、回收站与调度状态。内部 SMS/MMS ID 分别为正、负值，访问 Provider 时恢复原始 ID。

## 构建与校验

当前固定环境：Flutter 3.47.9 / Dart 3.13.7、JDK 17、Android SDK 36、Rust 1.99.1、FRB 2.13.0。NDK 由 Flutter Gradle 配置选择，CI 版本见 [Android 工作流](.github/workflows/android-delivery.yml)。先安装 SDK/NDK 和 Rust Android targets；首次解析依赖需要网络。

```powershell
flutter pub get --enforce-lockfile
flutter analyze
flutter test
dart run tool/check_localization.dart
python tool/generate_android_strings.py --check
python tool/check_sms_contract.py
cargo test --locked --manifest-path rust/Cargo.toml
cargo test --locked --manifest-path server-rs/Cargo.toml
flutter build apk --profile
python tool/verify_android_pages.py build/app/outputs/flutter-apk/app-profile.apk
```

原生检查在 `android` 中运行 `./gradlew testDebugUnitTest lintDebug`，Windows 使用 `gradlew.bat`。若 Windows lint 报 `PropertyEscape`，检查生成的 `local.properties`：盘符冒号写作 `C\:`，反斜杠写作 `\\`，修正后重新执行受影响的 lint 任务。

GitHub Actions 使用 `tool/setup_android_sdk.sh` 从 `ANDROID_HOME`（或 `ANDROID_SDK_ROOT`）定位命令行工具，以绝对路径调用 `sdkmanager` 并安装固定 SDK/NDK，避免依赖 runner 的默认 PATH。SDK 根目录须包含 `cmdline-tools/latest/bin/sdkmanager`。失败时的测试与 lint 报告会作为独立 artifact 保留；工具链安装前失败则可能尚无报告。

Profile 产物位于 `build/app/outputs/flutter-apk/app-profile.apk`，使用开发签名。Debug 使用 `flutter build apk --debug`。只有修改 Rust 桥接接口后才需要重新运行 `flutter_rust_bridge_codegen generate`。

### 真机性能与兼容性

```powershell
$env:ORG_GRADLE_PROJECT_qingniaoBenchmark = 'true'
flutter drive --profile --driver=test_driver/interface_cadence_driver.dart --target=integration_test/interface_cadence_test.dart -d DEVICE_ID
Remove-Item Env:ORG_GRADLE_PROJECT_qingniaoBenchmark
```

测试使用独立包 `com.blue.qingniao.benchmark` 和固定数据，不申请短信权限。结果写入 `build/verification/device-interface-cadence.json`。测试会覆盖默认 profile 输出，交付普通应用前需重新构建。

16 KB 工具检查 ARM64/x86-64 ELF 段与 APK 库对齐，另可运行 Android SDK 的 `zipalign -c -P 16 4 APK_PATH`。对齐通过不代表完成 16 KB 系统运行验证。

真机验收覆盖默认角色、双卡、长短信回执、运营商 MMS、重启及后台限制、定时发送、删除恢复、RTL/大字体与减少动态效果。历史 OnePlus 结果不代表所有 OPPO、小米或 ROM 兼容。实际帧耗时、16 KB 运行与完整运营商矩阵仍需验证。

### 正式签名

密钥保存在仓库之外，通过安全环境注入 `QINGNIAO_KEYSTORE_PATH`、`QINGNIAO_STORE_PASSWORD`、`QINGNIAO_KEY_ALIAS`、`QINGNIAO_KEY_PASSWORD`。缺少凭据时正式构建失败，不使用 debug 签名替代。

```powershell
flutter build apk --release
flutter build appbundle --release
```

发布前递增 `pubspec.yaml` 版本代码，核验证书、SHA-256 和最终产物。签名不一致或降级会阻止覆盖安装；不要通过卸载绕过并丢失应用状态。CI 支持验证产物及手动 Release 草稿，具体配置见工作流。固定依赖不等于已证明逐字节可复现。

## 可选同步与 FCM

构建服务端：`cargo build --release --locked --manifest-path server-rs/Cargo.toml`。运行 `qingniao-sync --bind 127.0.0.1:8787 --data /path/to/data.json`，在前面部署 HTTPS 反向代理并限制注册入口。路由见 [服务端源码](server-rs/src/main.rs)，客户端见 [同步引擎](lib/sync/sync_engine.dart)。设备令牌是访问凭据，不得写入日志或公开配置。

同步在前台启动、恢复及周期检查时执行，当前不包含 MMS 附件。服务器可见设备、公钥、路由、密文大小与时间。v1 信封使用 X25519、HKDF-SHA256、AES-256-GCM，但没有独立发送者认证，私钥尚未由 Android Keystore 包装，公钥信任绑定仍需验收。不能宣称已完整抵御恶意服务器身份伪造或达到已审计通信产品的安全等级。

Rust P2P 模块提供基于 Noise 的认证会话层，需要可信渠道绑定对端公钥；尚未接入设备发现、Wi-Fi Direct 或用户可用的发送流程。普通 SMS/MMS 不会自动获得端到端加密。RCS、小布 AI/NPU 没有接入。

FCM 配置步骤：

1. 为 `com.blue.qingniao` 注册真实 Firebase 应用，取得 `google-services.json`。
2. 执行 `python tool/configure_firebase.py android/app/google-services.json` 后重建。配置与生成资源已被 Git 忽略，不得包含服务账号私钥。
3. 设备具备 Google Play services 且能访问 Firebase 后，在设置中开启网络推送、配对同步、复制 FID 推送标识。
4. 可信发送端安装 `google-auth`、`requests`，配置具有 FCM 发送权限的 Application Default Credentials，运行 `tool/send_sync_push.py --project PROJECT_ID --space-id SPACE_ID --installation-id-file PRIVATE_FILE`。

载荷只允许 `type=sync_available` 和匹配的 `spaceId`，不携带短信正文。前台触发同步；后台显示通用通知，打开应用后同步。服务端不自动登记 FID，标识变化需更新。实际注册与投递需真实 Firebase 项目验证，代理网络不会将运营商短信自动转成 FCM 消息。

## 维护与许可

本地测试和构建证据位于 `build/verification`，仅对应当时的源码与产物。功能实现、设备验证与安全审计是不同层次的证据，不承诺零缺陷或所有设备兼容。

项目采用 [PolyForm Small Business License 1.0.0](LICENSE)。字体与依赖保留各自许可证，重新分发前应核对相应条款。
