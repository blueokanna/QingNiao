# 本轮短信实现验证快照

> 历史快照，记录早期实现阶段的检查。当前代码已包含流体云、端到端同步、
> 发送看门狗等功能，最新验收请见 [VERIFICATION.md](VERIFICATION.md)。

日期：2026-11-14，Asia/Shanghai。

本轮业务源码使用 Kotlin、Dart 和 Rust。没有迁入 CapsuleSMS 的 Java 业务源码。Flutter 自动生成的插件注册及第三方 JVM 库仍属于构建依赖。

## 已通过的检查

- Rust message_analysis：2 项测试通过，包括 Unicode、前导零、歧义数字、过长输入。
- Flutter：5 项测试通过，包括发送失败保留草稿、永久删除确认、大字体窄屏、深浅色收件箱渲染。
- Android：非增量 assembleDebug 与 lintDebug 成功完成；Lint 仍有建议性质的警告，不是零告警。
- 深浅色页面已输出 PNG 并人工检查。渲染使用标注为“测试消息”的测试夹具，不是设备真实短信。

验证 APK 保存在 `build/verification/qingniao-sms-validated-debug.apk`，构建日志在 `build/verification/android-validation.log`，Android Lint 报告在 `build/app/reports/lint-results-debug.html`。

## 并行修改的影响

用户确认另一会话同时修改同一工程。本轮保留了其极光界面、类型化模型与加密依赖，并给 MessageRepository 增补了现有短信页面需要的兼容入口，没有回退其实现。

验证完成后，另一会话继续替换收件箱和会话接口。最近一次静态检查发现当时仍缺少 compose_screen.dart，以及新收件箱与原会话构造参数尚未一致。上述通过记录针对验证时的快照，不能外推为不断变化的最新工作区已通过全部检查。页面完成整合后，需要重新运行整个工程的分析、测试和构建；原收件箱渲染测试也需要与新页面依赖一起迁移。

没有连接 Android 设备，因此没有执行运营商真实收发、双卡、MMS APN、杀进程回执或 profile 帧耗时测试。不能把当前快照称为已全面替代 CapsuleSMS 的生产发行版。
