# 正式包构建与签名

青鸟默认只产出 debug 包。release 包必须显式提供签名凭据，否则
`android/app/build.gradle.kts` 里的 `verifyReleaseSigning` 会直接拒绝构建——
这样不会出现「用 debug 密钥冒充发行版」的产物。

## 1. 生成 keystore（只需一次）

```powershell
keytool -genkeypair -v `
  -keystore D:\keys\qingniao.jks `
  -storetype PKCS12 `
  -alias qingniao `
  -keyalg RSA -keysize 4096 -validity 10000 `
  -dname "CN=Qingniao, OU=Mobile, O=Qingniao, L=Guangzhou, ST=Guangdong, C=CN"
```

把 `.jks` 放到仓库之外，并做好离线备份；丢失后无法覆盖升级已发布的应用。

## 2. 设置环境变量

```powershell
$env:QINGNIAO_KEYSTORE_PATH  = "D:\keys\qingniao.jks"
$env:QINGNIAO_STORE_PASSWORD = "你的store密码"
$env:QINGNIAO_KEY_ALIAS      = "qingniao"
$env:QINGNIAO_KEY_PASSWORD   = "你的key密码"
```

四个变量缺一不可，名字与 `build.gradle.kts` 中的读取逻辑一致。

## 3. 构建

```powershell
# 单个通用 APK（含全部 ABI）
powershell -NoProfile -ExecutionPolicy Bypass -File tool\build-release.ps1

# 按 ABI 拆分，体积更小，适合分发
powershell -NoProfile -ExecutionPolicy Bypass -File tool\build-release.ps1 -SplitAbi

# 上架 Google Play 用 AAB
powershell -NoProfile -ExecutionPolicy Bypass -File tool\build-release.ps1 -Bundle
```

> 若终端里有 PowerShell 7（`pwsh`），把上面的 `powershell` 换成 `pwsh` 即可。

产物：

- `build/app/outputs/flutter-apk/app-release.apk`
- `build/app/outputs/flutter-apk/app-*-release.apk`（`-SplitAbi`）
- `build/app/outputs/bundle/release/app-release.aab`（`-Bundle`）

脚本结尾会打印文件大小与 SHA-256；也可手工校验：

```powershell
Get-FileHash build\app\outputs\flutter-apk\app-release.apk -Algorithm SHA256
& "$env:ANDROID_HOME\build-tools\<版本>\apksigner.bat" verify --print-certs `
  build\app\outputs\flutter-apk\app-release.apk
```

## 4. 版本号

`pubspec.yaml` 的 `version:` 同时决定 `versionName+versionCode`：

```yaml
version: 0.5.0+41
```

每次发布都要递增 `+N`，否则商店与覆盖安装会拒绝。

## 5. 安装与真机验证

```powershell
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

release 包不包含 debug 调试接收器（`DebugNotifyReceiver`），所以
[VERIFICATION.md](VERIFICATION.md) 里的 `DEBUG_*` 广播只在 debug 包可用；
release 验收请走真实短信与通知。

## 6. 常见失败

| 报错 | 原因 |
|---|---|
| `Release signing requires QINGNIAO_KEYSTORE_PATH...` | 有环境变量没设置，或当前终端是新开的 |
| `keystore does not exist` | 路径写错，或用了相对路径但工作目录不同 |
| `compileReleaseJavaWithJavac` 报 `dev.flutter.plugins.integration_test` 不存在 | debug 构建把 `integration_test` 开发插件写进了 `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`，而 release 不含该依赖。`tool/build-release.ps1` 会在构建前删掉这个生成文件；手工构建时同样先删除即可 |
| R8 `Missing class` | 新增依赖未配置规则；先在 `android/app/proguard-rules.pro` 补 keep |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | 设备上装的是 debug 签名，先 `adb uninstall com.blue.qingniao`（会清数据） |
