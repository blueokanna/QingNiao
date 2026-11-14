# Android 集成与验收记录

应用标识为 `com.blue.qingniao`，最低 Android 12（API 31）。应用业务代码使用 Kotlin、Dart 和 Rust。Flutter 生成的 `GeneratedPluginRegistrant.java` 属于工具链产物，不是手写业务实现。

## 平台与外观

已移除应用和 Rust 插件的 iOS、macOS、Windows、Linux、Web 宿主目录。`rust_builder/cargokit` 保留构建主机支持；在 Windows 上构建 Android 仍需要这些脚本。桥接生成入口为 `dart run tool/generate_android_bridge.dart`，它处理 FRB 2.13 在关闭 Web 输出后仍保留条件导入的问题。

外观包含六套内置色板、Android 系统五组 Monet 色阶、浅色、深色和 AMOLED；AMOLED 关闭极光背景绘制。字体内置 HarmonyOS Sans SC 的 Regular / Medium / Bold，以及 Google Sans 可变字体。Google Sans 的中文回退到 HarmonyOS Sans。原始字体与许可证随应用分发，字体散列记录在 `assets/fonts/manifest.json`，外观页可打开许可说明。

形状使用 Material 3 控件、超椭圆及形变组件。应用弹簧由共享 Ticker 调度，采用解析积分，切换目标保留速度；关闭背景且弹簧全部静止时停止 Ticker。Flutter 自身仍管理路由、滚动和框架动画，不能把应用调度器描述为 Android 系统渲染引擎。系统减少动画、应用省电设置和系统字号已接入。尚无真机帧耗时、GPU 或功耗对照数据，不声称已经取得某个百分比的性能改善，也不声称通过官方“100% Expressive”认证。

## 设备验证矩阵

诊断页读取设备厂商、型号、API、短信角色、短信权限、通知、后台限制和省电状态；设置入口使用公开 Android API。厂商说明是故障排查指引，不等于机型测试结果。

| 系统 | SMS / 双卡 / 回执 | MMS / 群组 / 媒体 | 锁屏 / 重启 / 后台 | 状态 |
| --- | --- | --- | --- | --- |
| OnePlus OxygenOS / ColorOS | 待设备测试 | 待设备及运营商测试 | 待设备测试 | 未认证 |
| OPPO ColorOS | 待设备测试 | 待设备及运营商测试 | 待设备测试 | 未认证 |
| Xiaomi / Redmi HyperOS、MIUI | 待设备测试 | 待设备及运营商测试 | 待设备测试 | 未认证 |
| AOSP / Pixel Android 12–16 | 待设备测试 | 待设备及运营商测试 | 待设备测试 | 未认证 |

验收至少覆盖：默认角色授予与撤销、拒绝可选权限、单卡与双卡无默认发送卡、长短信与 emoji 分段、飞行模式失败、延迟回执、锁屏接收、彩信移动数据与 APN、图片/音视频附件、群组收件人、重启后的任务、字体放大和减少动画。构建成功无法替代这些检查。

## 加密边界

`rust/src/peer_transport.rs` 实现已固定对端公钥的 Noise XX 会话，协议为 `Noise_XX_25519_ChaChaPoly_SHA256`，要求可靠有序的帧传输。握手限制 30 秒；会话限制 1 小时或单方向 2²⁰ 条消息；单帧明文最多 32 KiB。认证、重放或接收帧长度错误会关闭会话。握手需要由调用者通过可信配对渠道取得对端公钥。

这一模块是加密会话层，尚未接入 Wi-Fi Direct、设备发现、二维码配对或用户可用的 P2P 发送流程。它不使用自创密码算法。测试覆盖双向通信、错误公钥、未完成握手、篡改、重放、跨会话密文及帧长度边界；这些测试不是独立密码审计。

并行开发的同步信封目前使用临时 X25519、HKDF 和 AES-GCM。该信封格式本身没有发送者签名或静态发送者认证；服务器返回公钥的信任绑定也需要单独验收。现有身份私钥位于应用私有文件，尚未由 Android Keystore 包装。完成密钥保护、可信配对、公钥变化处理、重放状态和接收者身份校验之前，不应将该同步实现宣传为已满足高安全生产标准。

普通运营商 SMS/MMS 本身不会因应用加入加密模块而自动获得端到端加密。

## 构建与发行

`.github/workflows/android-delivery.yml` 提供 Android 校验、APK artifact 和手动创建 GitHub Release 草稿。默认只生成调试包；正式包使用真实签名配置，缺失配置时构建失败。工作流已固定 Flutter 提交、Rust 版本、NDK、Gradle 下载校验值和 Action 提交。Cargo 与 Dart 使用锁文件。

本机正式构建需要环境变量 `QINGNIAO_KEYSTORE_PATH`、`QINGNIAO_STORE_PASSWORD`、`QINGNIAO_KEY_ALIAS`、`QINGNIAO_KEY_PASSWORD`。CI 使用对应的 `ANDROID_KEYSTORE_BASE64`、`ANDROID_STORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD` secrets。私钥和密码不得提交到仓库；工作流结束会清理临时密钥文件。

手动发行需要仓库中已存在的 `v` 前缀版本标签；测试包创建预发行草稿，正式包创建普通草稿。附件包含 APK、SHA-256、证书指纹、源码提交和工具链版本。当前没有替用户上传 Release，也未获得正式签名密钥。调试证书不能作为正式版更新身份。

固定工具链和依赖是可复建的基础；本轮尚未在两个干净环境完成逐字节产物比对，不能宣称已证明位级可复现。

## 规范依据

- [Android 构建与正式签名](https://docs.flutter.dev/deployment/android)
- [Noise 协议框架](https://noiseprotocol.org/noise.html)
- [GitHub Actions secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)

具体自动化结果与 APK 散列见本次 `build/verification` 中的验证记录。共享工作目录仍有另一会话写入，后续修改不自动继承本次验证结论。
