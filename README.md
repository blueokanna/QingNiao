# 青鸟短信

面向 Android 的本地短信客户端。Flutter 绘制界面，Kotlin 对接系统短信服务，Rust 分析消息文本。业务源码没有迁入 CapsuleSMS 的 Java 实现。

当前版本可以构建测试 APK，但还不能作为 CapsuleSMS 已完成全部功能迁移的正式发行版。云同步、彩信音视频播放、彩信草稿恢复、统一 SMS/MMS 会话和完整设备兼容性验证仍未完成。

## 已接入的能力

- 默认短信角色申请，短信权限检查与撤销后的错误处理。
- 系统短信会话、未读筛选、全文搜索、分页历史、已读更新。
- 单卡和双卡发送、长短信拆分、持久化分段回执、失败后编辑重发。
- 系统联系人选择器、短信草稿、短信链接入口。
- 本地验证码识别与复制。多个不同候选数字时不提供自动复制。
- 回收站隐藏、恢复与确认后的永久删除。隐藏消息仍在系统消息库，其他短信应用可能看到它们；没有自动清空任务。
- 彩信通知接收、系统下载、失败重试、独立彩信列表、图片预览、多收件人发送和单个媒体附件发送。
- Material 3 深浅色主题、统一形状和转场、会话头像共享元素过渡、大字体适配与减少动画支持。

主界面不注入演示短信。测试夹具只存在于测试目录。消息分析不上传正文，通知默认不显示短信内容；应用禁用系统备份。SQLite 保存草稿、隐藏记录和回执状态，系统 Telephony Provider 仍是消息正文的数据源。

## 构建

开发环境使用 Flutter 3.47.9、Dart 3.13.7、JDK 17、Android SDK 36、Rust 和 flutter_rust_bridge 2.13.0。Android 最低版本为 12 / API 31。仓库中的其他平台目录来自 Flutter 模板，不代表这些平台支持短信功能。

```powershell
flutter pub get
flutter_rust_bridge_codegen generate
cargo test --manifest-path rust/Cargo.toml
flutter analyze
flutter test
flutter build apk --debug
```

测试包路径：`build/app/outputs/flutter-apk/app-debug.apk`。正式构建没有借用 debug 签名，发布前必须配置自己的签名及版本管理。

## 渲染与验证边界

应用复用 Flutter 的帧调度和渲染管线，没有另造所谓“极光引擎”。列表按需构建；搜索防抖；系统消息变更合并通知；查询和收发分别在 Kotlin 后台执行队列运行；文本分析通过异步 Rust bridge 执行。没有全屏持续动画、实时模糊或应用级定时重绘。

这些是可检查的实现措施，不等于已证明降低了 GPU 负载。需要在同一台真机、同一份消息库、同一刷新率下，对比 profile 构建的 UI / raster 帧耗时和内存，再讨论性能收益。debug 包不适合得出帧率结论。

自动测试覆盖 Rust 解析边界、发送失败保留草稿、删除确认和大字体布局。运营商收发、进程被杀后的回执、双卡切换、无信号、权限撤销及 MMS APN 仍需要真机验证。这里不承诺零漏洞、零 bug 或未经测试的机型兼容性。

具体分层和剩余迁移项见 [架构与验收说明](docs/messaging-architecture.md)。第三方依赖见 [依赖声明](THIRD_PARTY_NOTICES.md)。
