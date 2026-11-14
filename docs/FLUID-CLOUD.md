# 流体云与短信唤醒适配说明

本文说明青鸟如何在 OPPO ColorOS / 一加 OxygenOS 上尽可能接入「流体云」，
以及为什么短信唤醒**不需要 FCM**、也不会引入网络延迟。

## 1. 结论先行

| 系统 | 可用路径 | 青鸟的实现 |
|---|---|---|
| ColorOS 16 / OxygenOS 16（Android 16+） | 流体云兼容 Android **Live Updates** 标准 API | 已接入；系统可拒绝，自动回退普通高优先级通知 |
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
用户点通知进入青鸟后即可读取。

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

模拟器可用：

```bash
adb emu sms send 10086 "验证码 123456"
```

检查项：

- 应用被划掉后仍能收到通知；
- 通知可直回、可标为已读；
- ColorOS 16.1 上 `dumpsys notification` 可见 `promoted` 标志；
- 关闭「流体云实时胶囊」后仍出现普通横幅。

## 7. 已知限制

- 当前构建环境没有真机/可用模拟器，以上 UI 行为需要设备复核。
- ColorOS 16.0 若没有 API 36.1 的 promotion 接口，会自动退回普通通知。
- ColorOS 15 的流体云必须走 OPPO 合作申请；本项目不包含私有 SDK。
- ColorOS 可能折叠同一会话的多次通知；已使用 group + 每会话 ID。
- 通知正文预览可在设置关闭；验证码不会写入流体云短文本，避免锁屏泄露。
