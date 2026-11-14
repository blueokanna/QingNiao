# 真机验证指引

这份文档是一份可以照着做的验收清单，覆盖默认短信角色、SMS/MMS、通知与流体云、
零延迟唤醒、双卡、验证码、搜索、回收站、备份和同步。

> 结论只写实测过的内容。当前实测设备：**一加 PLK110**（ColorOS `V17.0.0` /
> Android 17 / API 37，双卡：中国电信 + 中国联通）。其他机型请按同样步骤复核。

## 0. 环境与产物

```powershell
flutter pub get --offline
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

- 最低 Android 12（API 31）；本机 `compileSdk = 36`、`targetSdk = 36`。
- 包名 `com.blue.qingniao`。
- debug 包额外带一个 `DebugNotifyReceiver`，可用 adb 广播做无 UI 自检（release 不包含）。

## 1. 默认短信角色

**手动路径**：首次启动 → 「设为默认短信应用」→ 系统弹窗确认。

**验证**：

```bash
adb shell cmd role get-role-holders android.app.role.SMS
adb shell dumpsys package com.blue.qingniao | findstr /i "READ_SMS SEND_SMS RECEIVE_SMS"
```

期望：角色持有者是 `com.blue.qingniao`，三个危险权限 `granted=true`。

> **ColorOS 注意**：ColorOS 只写 `RoleManager`，可能不写
> `Settings.Secure.sms_default_application`。青鸟的判定以 `RoleManager.isRoleHeld`
> 为准，不依赖旧接口。如果系统短信服务仍报
> `SmsPermissions: Caller is not a default SMS application`，说明该 ROM 的电话服务
> 只认旧设置：请到「设置 → 应用 → 默认应用 → 短信」重新选择青鸟（开发者可用
> `adb shell settings put secure sms_default_application com.blue.qingniao` 兜底）。

## 2. 无 UI 自检（debug）

```bash
# 当前权限 / 流体云能力
adb shell am broadcast -n com.blue.qingniao/.DebugNotifyReceiver -a com.blue.qingniao.DEBUG_ACCESS
# 发一条带验证码的示例通知（走真实通知代码路径，含流体云提升）
adb shell am broadcast -n com.blue.qingniao/.DebugNotifyReceiver -a com.blue.qingniao.DEBUG_NOTIFY \
  --es address 95566 --es body "【中国银行】验证码445566，5分钟内有效" --ei sub 1
# 打印某号码在本机的所有短信行（id/type/status）
adb shell am broadcast -n com.blue.qingniao/.DebugNotifyReceiver -a com.blue.qingniao.DEBUG_DUMP --es address 95566
# 清理青鸟的全部通知
adb shell am broadcast -n com.blue.qingniao/.DebugNotifyReceiver -a com.blue.qingniao.DEBUG_CLEAR
```

`DEBUG_ACCESS` 期望输出（示例）：

```
access={defaultApp=true, readSms=true, sendSms=true, receiveSms=true, promoted=true, promotionActive=true, fluidCloud=true}
```

`type` 含义：1 收件箱、2 已发送、4 发件箱（发送中）、5 发送失败。
`status`：32 = `STATUS_PENDING`。

## 3. 通知与流体云

1. 执行上面的 `DEBUG_NOTIFY`，收起通知栏。
2. 状态栏应出现**胶囊**：闪电图标 + 「验证码」（无验证码时为「新短信」）。
3. 下拉通知栏，首条为放大的卡片：发件人、正文、「复制验证码」「标为已读」。
4. 点卡片应进入对应会话，且胶囊被撤下。

命令行确认：

```bash
adb shell dumpsys notification --noredact | findstr /i "PROMOTED_ONGOING qingniao"
```

期望：出现 `flags=ONGOING_EVENT|PROMOTED_ONGOING`。

- 流体云提醒最多保留 **15 分钟**（`NotificationExpiryReceiver`），避免胶囊常驻。
- 系统或 ROM 拒绝提升时，青鸟自动退回普通高优先级通知；设置页的
  「流体云实时胶囊」会显示当前设备是否真的可用。
- **已知取舍**：被提升的大卡片由系统渲染，不展示 RemoteInput「回复」动作；
  普通通知仍带回复。

## 4. 零延迟唤醒（最关键的一项）

1. 把青鸟从最近任务划掉（或 `adb shell am force-stop com.blue.qingniao`）。
2. 用另一台手机给本机号码发一条短信。
3. 期望：**1 秒级**出现通知；锁屏/桌面状态栏出现流体云胶囊；点通知直达会话。
4. 不需要 FCM、不需要打开应用、不需要后台常驻。

```bash
adb shell dumpsys notification --noredact | findstr /i qingniao
adb logcat -d | findstr /i "QingniaoSms IncomingSms"
```

原理：默认短信应用接收 `SMS_DELIVER`，非默认时接收 `SMS_RECEIVED`；两者都是
系统 Telephony 广播，进程被杀也会被拉起。青鸟在写数据库之前先发通知。

## 5. 发送短信

**手动**：会话页输入 → 发送。

> **ColorOS 注意**：部分版本会插入系统级确认弹窗
> 「青鸟短信 will send SMS to … Cancel(6) / Send」。这是 ROM 的防诈骗确认，
> 不是应用弹窗；不确认时发送会被系统丢弃。
> 因此青鸟在 90 秒后仍未收到 sent 回执时会把消息标为**失败**并显示「重新发送」
> （`SmsSendWatchdog`），不会无限转圈。设备重启后启动时也会补扫一次。

检查：

```bash
adb shell am broadcast -n com.blue.qingniao/.DebugNotifyReceiver -a com.blue.qingniao.DEBUG_DUMP --es address 130xxxxxxxx
```

- 发送中：`type=4 status=32`
- 已发送：`type=2`
- 失败：`type=5`，会话里出现红色感叹号与「重新发送」

发送失败请先确认：飞行模式是否关闭、SIM 是否注册（`dumpsys telephony.registry`
中 `mVoiceRegState=0(IN_SERVICE)` 且 `availableServices` 含 `SMS`）、短信中心号码
是否由运营商下发。

## 6. 双卡与彩信

- 双卡：会话/发送页的 SIM 选择器应列出两张卡；发送后 `sub_id` 与所选卡一致。
- 彩信：发送带附件的消息 → 通知栏出现「正在发送彩信」进度 → 完成后进入会话。
- 接收彩信：对方发送图片 → 通知先出现，下载完成后显示附件预览。

## 7. 其他功能抽查

| 功能 | 期望 |
|---|---|
| 验证码 | 「验证码」标签页列出 4–8 位码，点击复制；通知里可直接复制 |
| 搜索 | 输入中文/号码/正文片段能命中；Rust 索引不可用时回退 LIKE |
| 回收站 | 删除后进回收站，可恢复；保留天数可在设置调整 |
| 备份 | 导出 JSON 到 SAF；导入时合并短信、草稿、置顶/归档、黑名单 |
| 定时发送 | 选择未来时间，到点发送；权限不足时降级 |
| 同步 | 服务端 `cargo run --offline`，两台设备配对后互相推送/拉取 |
| 外观 | 深色/AMOLED/动态取色/字体大小；切换无硬切 |
| 极光引擎 | 收件箱右上角闪电图标可查看渲染质量、平均帧耗时 |

## 8. 故障排查

| 现象 | 排查 |
|---|---|
| 一直停在引导页 | 角色是否真的持有：`cmd role get-role-holders android.app.role.SMS` |
| 收短信但无通知 | 通知权限/渠道；历史版本曾因偏好类型冲突崩溃，现已修复（`AppPrefs.bool`） |
| 发送一直转圈 | ROM 确认弹窗；青鸟 90 秒后自动标失败；检查飞行模式与 SIM 注册 |
| 没有流体云 | 设置 → 设备与权限诊断查看「流体云 / 实时胶囊」；ColorOS 15 及更早需 OPPO `serviceId` |
| 后台收不到 | 关闭电池优化、允许自启动；ColorOS 的省电策略可能延迟非系统广播 |
| 通知里没有回复 | 流体云大卡片不承载 RemoteInput；关掉「流体云实时胶囊」即回到可回复的普通通知 |

## 9. 本次实测结果（2026-11-14）

| 项目 | 结果 | 证据 |
|---|---|---|
| 安装 / 冷启动 | 通过，0.7–1.4 s | `build/verification/device_inbox2.png` |
| 默认短信角色 | 通过（RoleManager 判定修复后） | 设置页「默认短信应用已就绪」 |
| 短信库读取 | 162 会话 / 8 未读 / 64 验证码 | `device_inbox.png` |
| 通知三动作 | 通过 | `device_notification_expanded.png` |
| 流体云胶囊 | 通过 | `device_fluid_cloud_final.png` |
| 流体云大卡片 | 通过（复制验证码 / 标为已读） | `device_fluid_cloud_card.png` |
| 进程被杀后发通知 | 通过（force-stop 后广播拉起） | `PROMOTED_ONGOING` 日志 |
| 通知点击进会话 | 通过，胶囊同步撤下 | `device_notification_open.png` |
| 验证码页布局 | 通过（修复状态栏遮挡与 2.2px 溢出） | `device_otp2.png` |
| 撰写页 | 通过（修复重复输入框） | `device_compose_final.png` |
| 短信发送 | **受运营商/ROM 限制**：本机两张卡均返回 generic failure，疑似 SMSC/IMS 未就绪；应用正确显示失败与重发 | `device_thread_status3.png` |
| 入站短信 | **待测**：需要另一台手机在关闭飞行模式时发送 | — |

> 发送失败与短信中心/运营商开通状态有关，与青鸟的发送代码无关：同一路径在
> `SmsPermissions` 日志里被系统判定为默认短信应用之外的调用时也会失败，修复
> 默认短信设置后可复测。
