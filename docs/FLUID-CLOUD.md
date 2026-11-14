# 流体云与短信唤醒适配说明

本文说明青鸟如何在 OPPO ColorOS / 一加 OxygenOS 上尽可能接入「流体云」，
以及为什么短信唤醒**不需要 FCM**、也不会引入网络延迟。

## 1. 结论先行

| 系统 | 可用路径 | 青鸟的实现 |
|---|---|---|
| ColorOS 16 / OxygenOS 16（Android 16+） | 流体云兼容 Android **Live Updates** 标准 API | 已接入；系统可拒绝，自动回退普通高优先级通知 |
| ColorOS 17 / OxygenOS 17（Android 17，V17.0.0 实测） | 流体云兼容 Android **Live Updates** 标准 API | **已实测上岛**：状态栏出现「新短信」胶囊，下拉为大卡片（含「复制验证码 / 标为已读」） |
| ColorOS 15 及更早 | OPPO `SeedlingSupportSDK` / `IntelligentIntent` 卡片体系 | 第三方无法自助接入：需要 OPPO 审核、服务 ID 与场景白名单；当前回退普通通知 |
| 所有 Android 12+ | 短信 Telephony 广播唤醒 + 高优先级通知 | 已接入，默认短信应用与非默认应用都有入口 |

**重要边界**：流体云卡片不是普通通知的“换皮”。ColorOS 15 的卡片是 OPPO 的
合作方能力，`entityName` 只开放打车、外卖、到店、赛事、导航、任务等场景；
短信不在开放场景内，普通开发者无法仅靠代码把任意通知塞进流体云。
ColorOS 16 改为兼容 Google 标准后，才有了一条**应用侧可自助**的路径。

参考：

- [OPPO ColorOS 16 流体云兼容 Android Live Updates（IT之家）](https://www.ithome.com/0/890/345.htm)
- [OPPO SeedlingSupportSDK 接入指南](https://open.oppomobile.com/documentation/page/info?id=12719)
- [OPPO 流体云本地 Intent Sharing](https://open.oppomobile.com/documentation/page/info?id=13558)
- [OPPO 流体云 Intent 数据结构](https://open.oppomobile.com/documentation/page/info?id=13565)
- [阿里云 EMAS：OPPO 流体云推送指南](https://help.aliyun.com/en/document_detail/2997310.html)
- [Android：Create live update notifications](https://developer.android.com/develop/ui/views/notifications/live-update)

## 2. ColorOS 16：通过 Android 16 Live Updates 上岛

Android 16 的 Live Updates 要求：

- 清单声明 `android.permission.POST_PROMOTED_NOTIFICATIONS`；
- 通知为 `BigTextStyle` / `ProgressStyle` 等标准样式，不能是 `RemoteViews`；
- `setOngoing(true)`，并通过 `setRequestPromotedOngoing(true)` 请求提升；
- 不能是 group summary；渠道重要性不能是 `IMPORTANCE_MIN`；
- 系统还会检查应用是否被用户允许使用 Live Updates。

青鸟在 `Notifications.showSms` 中做了以下处理：

```kotlin
if (canPromote(context) && prefs.getBoolean("fluidCloud", true)) {
    builder.setOngoing(true)
        .setAutoCancel(false)
        .setShortCriticalText("新短信")
    requestPromotedOngoing(builder) // API 36.1，反射调用
}
```

- `canPostPromotedNotifications()` 与 `setRequestPromotedOngoing()` 实际位于
  **Android 16.1（API 36.1）**；当前工程 `compileSdk = 36`，因此用反射调用，
  避免锁死 Preview SDK。设备是 36.0 时自动判定不支持。
- 通知仍是标准高优先级渠道；系统拒绝提升时，用户看到的是普通横幅通知。
- 设置中提供「流体云实时胶囊」开关；关闭后完全退回普通通知。
- 只对**未读短信**保持 ongoing，标记已读/回复后取消，不伪造“进行中任务”。
- ongoing 通知最多保留 15 分钟（`NotificationExpiryReceiver` 自动撤下），
  避免状态栏胶囊长期占位；点开通知或会话即提前取消。

> Google 的 Live Updates 指南把聊天消息列为不推荐场景，OEM 可追加更严格条件。
> 因此青鸟不承诺“必定上岛”；这是一条**尽力而为**的标准路径，而不是私有后门。

## 3. ColorOS 15：为什么不能直接接

OPPO 的流体云卡片通过 `IntelligentIntent`（本地 ContentProvider 或 OPPO Push）
创建，关键字段包括：

- `serviceId.launcher` / `serviceId.fluidCloud`：OPPO 分配给合作方的卡片 ID；
- `intentEntity.entityName`：`TAXI` / `DELIVERY` / `PICKUP` / `MATCH` /
  `NAVIGATION` / `TASK` 等已开放场景；
- `milestone`、`capsule`、`primary`、`secondaryData`：卡片内容与进度；
- `actionStatus`：0 创建、1 更新、2 结束。

没有 OPPO 分配的 `serviceId` 与审核通过的应用，调用会被系统拒绝。短信也不在
开放场景列表中。远程方式（OPPO Push）同样需要 `client_id` / `client_secret`
与服务端，且会产生网络往返，不适合“本地短信零延迟提醒”。

因此本项目：

- 不伪造 `serviceId`，不依赖 Xposed 修改系统；
- 在 ColorOS 15 上使用普通高优先级通知（横幅、锁屏、通知栏、直回、已读）；
- 保留 `Notification.fluidCloud` 适配层，未来若有 OPPO 合作资质，可在
  `Notifications.kt` 内替换为 Seedling SDK 调用，而不影响其他逻辑。

如果希望正式上岛，需要走 OPPO 开放平台申请：提交应用资质、场景说明、
`serviceId` 申请与真机联调，通常面向打车/外卖/赛事/导航等持续任务。

## 4. 短信如何“自己唤醒”青鸟

### 4.1 默认短信应用

清单接收 `android.provider.Telephony.SMS_DELIVER`：

```xml
<receiver android:name=".IncomingSmsReceiver"
    android:exported="true"
    android:permission="android.permission.BROADCAST_SMS">
    <intent-filter>
        <action android:name="android.provider.Telephony.SMS_DELIVER" />
    </intent-filter>
</receiver>
```

短信到达时由系统直接启动应用进程，不需要应用在前台，也不需要用户先打开。

### 4.2 非默认短信应用

清单接收 `android.provider.Telephony.SMS_RECEIVED`：

```xml
<receiver android:name=".SmsReceivedReceiver" android:exported="true">
    <intent-filter android:priority="999">
        <action android:name="android.provider.Telephony.SMS_RECEIVED" />
    </intent-filter>
</receiver>
```

非默认应用没有系统短信库写权限，但可以立即发通知；正文由系统默认短信应用写入，
用户点通知进入青鸟后即可读取。即使默认短信角色被拒绝、或设备不支持 `ROLE_SMS`，
青鸟仍会继续申请 `READ_SMS` / `RECEIVE_SMS` 等权限，保证 `SMS_RECEIVED` 唤醒链路可用。
彩信下载期间会显示“正在接收彩信”进度通知，完成后替换为带发件人/会话/直回的富通知。

### 4.3 通知先行

两个接收器都在 `onReceive` 的最前面直接调用 `Notifications.showSms(...)`，
之后才在后台线程写数据库。通知路径不等待 SQLite、线程查询或网络。

### 4.4 为什么不用 FCM

| 方案 | 问题 |
|---|---|
| FCM | 需要服务器先知道短信内容；设备必须能连 Google 服务；中国大陆通常不可用；多一次网络往返，延迟更高 |
| OPPO Push | 同样需要服务端转发与 OPPO 审核；本地短信不需要 |
| 前台服务长轮询 | 只为收短信而常驻会耗电；且仍要服务器 |
| **Telephony 广播** | 运营商短信到达即由系统分发，**本地零网络延迟**，青鸟采用 |

FCM 适合“另一端设备/服务器产生事件”的同步；青鸟已有自建端到端加密同步用于多设备，
但**本机短信提醒绝不经过服务器**。

## 5. ColorOS / OxygenOS 设置清单

应用内「设置 → 消息与通知 → 后台唤醒与自启动」提供入口：

1. **设为默认短信应用**：否则无法写入系统短信库，MMS 也不完整。
2. **允许通知与横幅**：ColorOS 的“横幅通知”默认可能关闭；渠道重要性为 High。
3. **电池优化白名单**：`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`。
4. **允许自启动**：尝试打开 ColorOS/OxygenOS 的自启动管理页；机型不同入口不同，
   找不到时退回应用详情页。
5. **最近任务锁定**（可选）：在最近任务中下拉/长按锁定青鸟。

> 即使不做 3–5，`SMS_DELIVER` / `SMS_RECEIVED` 是系统级广播，通常仍能唤醒；
> 但 ColorOS 的省电策略可能延迟或折叠通知，白名单能显著提高稳定性。

## 6. 验证方法

真机（默认短信应用）：

```bash
# 从另一台手机发送短信，观察 1 秒内是否出现通知/流体云
adb shell dumpsys notification --noredact | findstr qingniao
```

应用内「设置 → 设备与权限诊断」新增两个自检入口：

- **流体云 / 实时胶囊**：直接显示 `canPostPromotedNotifications()` 的结果；
- **发送一条测试通知**：发出一条带验证码的示例短信通知，可在通知栏确认
  标题、正文、「回复 / 复制验证码 / 标为已读」三个动作，以及是否被系统提升。

模拟器可用：

```bash
adb emu sms send 10086 "验证码 123456"
```

检查项：

- 应用被划掉后仍能收到通知；
- 通知可直回、可标为已读；
- 支持的系统上 `dumpsys notification` 可见 `promoted` 标志；
- 关闭「流体云实时胶囊」后仍出现普通横幅。

## 7. 真机实测记录（OnePlus PLK110）

2026-11 在一加 PLK110（ColorOS V17.0.0 / Android 17 / API 37，双卡：电信 + 联通）上实测：

| 项目 | 结果 |
|---|---|
| 安装与冷启动 | 通过，冷启动约 0.7–1.0 s |
| 默认短信角色 | 通过。ColorOS 只写 `RoleManager`，不写 `Settings.Secure.sms_default_application`，旧接口 `Telephony.Sms.getDefaultSmsPackage()` 返回 null |
| 短信库读取 | 通过，162 个会话、8 条未读、64 条验证码正常聚合 |
| 通知与动作 | 通过。`dumpsys notification` 显示 `actions=3`（回复 / 复制验证码 / 标为已读），BigText 正文正确 |
| 流体云 / Live Updates | **通过**。`POST_PROMOTED_NOTIFICATIONS` 已授予，通知带 `ONGOING_EVENT\|PROMOTED_ONGOING`；锁屏外的状态栏出现「验证码 · 95566」胶囊，下拉为大卡片与两个快捷动作。进程被 `force-stop` 后由广播拉起再发通知同样生效 |
| 后台广播唤醒 | 自定义广播在后台可能被 ColorOS 延迟投递；系统 Telephony 广播属于豁免通道，仍需真实入站短信复核 |

由此修正了三处真机才暴露的问题：

1. 默认短信角色改以 `RoleManager.isRoleHeld(ROLE_SMS)` 为准，旧接口只作回退
   （`SmsAccess.kt`）。否则 ColorOS 上会永远显示“还没有获得默认短信角色”。
2. 清单补声明 `READ_CELL_BROADCASTS`（dangerous）。默认短信应用会被系统自动授予，
   不声明时 ColorOS 的 `SmsApplication` 会重复打印
   `lost android:read_cell_broadcasts: (no permission to fix)`。
3. **通知设置读写类型冲突**：Dart 把 `notifications/preview/fluidCloud` 以字符串写入
   `appearance` 偏好，Kotlin 用 `getBoolean` 读取会抛 `ClassCastException`，
   接收器随之崩溃——真机现象是“短信到了却完全没有通知”。现在 Kotlin 统一走
   `AppPrefs.bool()` 宽容解析，写入端也改为真正的 Boolean。
4. `canPostPromotedNotifications()` 会在进程刚被广播拉起等时机短暂返回 false，
   因此不再用它作为是否尝试提升的唯一开关：只要 API 存在且权限已授予就尝试，
   由系统决定是否接受；设置页另用 `promotionActive()` 展示真实状态。

## 8. 已知限制

- 以上结论来自单台一加真机（ColorOS 17），其他 ColorOS/OxygenOS 版本仍需复核；
  构建环境没有可用的 Android 模拟器。
- ColorOS 16.0 若没有 API 36.1 的 promotion 接口，会自动退回普通通知。
- 被提升为流体云的通知由系统渲染，**不支持 RemoteInput 直接回复**：胶囊大卡片只保留
  「复制验证码 / 标为已读」两个动作；未提升的普通通知仍带「回复」。
- ColorOS 15 的流体云必须走 OPPO 合作申请（`serviceId`）；本项目不包含私有 SDK，
  仅使用 Android 标准 Live Updates。
- ColorOS 可能折叠同一会话的多次通知；已使用 group + 每会话 ID。
- ColorOS 可能在后台发送短信时插入系统二次确认弹窗，导致无人工确认的
  自动化发送被丢弃；正常前台使用不受影响，真实收发仍需人工走一遍。
