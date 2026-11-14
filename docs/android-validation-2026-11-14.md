# Android 快照验证：2026-11-14

> 本页记录的是当天早些时候在隔离快照上的构建验证；当时 ADB 没有设备。
> 当天晚些时候已在一加 PLK110（ColorOS 17）完成安装、默认短信角色、通知、
> 流体云与进程被杀唤醒的实机验证，以及发送失败/看门狗的行为验证。
> 最新结果与复测步骤以 [VERIFICATION.md](VERIFICATION.md) 为准。

本次构建来自 `build/verification/android-snapshot` 的隔离源码副本。共享工作目录有另一会话持续开发；本记录不覆盖快照之后的改动。每个源文件的 SHA-256 位于 `build/verification/verified-source-sha256.txt`。

## 产物

- APK：`build/verification/qingniao-android-verified-debug.apk`
- 应用 ID：`com.blue.qingniao`
- 版本：`0.4.0+40`
- Android：最低 API 31，目标 API 36
- ABI：`armeabi-v7a`、`arm64-v8a`、`x86_64`
- 文件大小：189,767,385 字节
- APK SHA-256：`47CFF0DE9CC0F3D837ACC2C1C825B31311ADE56986D6FF3DCF840EA7E0077B2D`
- 签名：Android Debug，APK v2 验证通过；不是正式发行签名
- 证书 SHA-256：`44ee3a577dfaa59d7b6d692168f4bfd17e56ea70dcd51557dff57fc425a63cc8`

## 验证结果

| 检查 | 结果 | 记录 |
| --- | --- | --- |
| Flutter 依赖锁文件校验 | 通过 | `snapshot-dependencies.log` |
| Flutter 静态分析 | 无问题 | `snapshot-analysis.log` |
| Flutter 测试 | 14 项通过 | `snapshot-flutter-tests.log` |
| 搜索提示精简后的收件箱布局复验 | 深、浅色均通过 | `snapshot-inbox-tests.log` |
| Rust 测试 | 83 项通过，包含 5 项 P2P 会话测试 | `snapshot-rust-tests.log` |
| Android 调试构建 | 通过 | `snapshot-apk-build.log` |
| Android Lint | 0 错误、39 条警告 | `snapshot-lint.log` |
| APK 签名校验 | 通过 | `snapshot-signature.log` |
| 缺失正式签名凭据 | 按预期拒绝 | `snapshot-signing-guard.log` |

日志均位于 `build/verification`。Lint 警告包括 SharedPreferences 同步提交、资源版本目录、KTX 建议和资源反射；没有通过新增 baseline 或关闭错误检查来隐藏问题。

浅色与深色收件箱截图为 `verified-inbox-light.png`、`verified-inbox-dark.png`。截图使用测试夹具和实际字体，只验证布局，不是真实短信收发证据。

ADB 未发现连接设备。OnePlus、OPPO、小米的默认短信接管、双卡、运营商彩信、锁屏接收、后台任务、功耗和帧耗时均未执行真机验收。GitHub 工作流尚未在线运行，正式密钥尚未配置，P2P 配对与传输及同步安全加固仍未完成。具体边界见 [Android 集成与验收记录](android-readiness.md)。
