# GitHub Release 与应用在线更新

发布仓库为 [blueokanna/qingniao](https://github.com/blueokanna/qingniao)。[Android delivery 工作流](../.github/workflows/android-delivery.yml) 构建、验证并上传产物；维护者手动触发后可以创建正式签名的 **Release 草稿**，审核和真机验证完成后再发布。

## 触发方式与版本

| 操作 / 输入 | 结果 |
| --- | --- |
| PR、推送 `main` / `master`，或手动运行且 `production=false`、`release_tag` 留空 | Debug 验证产物；不生成 `update.json`，不创建 Release |
| 手动运行，`production=true`、`release_tag` 留空 | 生产签名 universal APK 与 `update.json`，仅上传 Actions artifact |
| 手动运行，`production=true`、`release_tag=v0.1.2` | 检出已有标签、核验版本并创建 Release 草稿 |
| `release_tag` 非空但 `production=false` | 立即失败，不能用 Debug APK 创建 Release |
| 推送 Git 标签 | 不触发发布；需要维护者手动运行工作流 |

当前源码版本为 **`0.1.2+4009`**，Android 清单使用 `versionName=0.1.2` 和 `versionCode=4009`，对应标签 **`v0.1.2`**。工作流只接受形如 `v<major>.<minor>.<patch>` 的稳定版标签，从该标签的 `pubspec.yaml` 读取版本名和 build number，构建后再与 APK 清单逐项核对。

旧版按 ABI 分包曾使用架构偏移，已核对的 arm64 设备上 0.1.1 的实际 `versionCode` 为 2008，历史 x86_64 APK 的版本代码进入了 4000 段。0.1.2 的统一包使用 4009。后续发布需要高于所有已分发 APK 的实际版本代码；若只发布统一包，下一版可用 **`0.1.3+4010` → `v0.1.3`**。发布器与更新器接受 **`1..2100000000`**，Android 侧以 `longVersionCode` 读取已安装版本。

已有标签固定其源码；工作区未提交改动及之后的提交不会被旧标签包含。工作流从运行该工作流的提交（`github.workflow_sha`）单独检出 `tool` 目录作发布验证，所以旧标签也能使用新校验，但应用仍严格由标签源码构建。若旧版 APK 不含在线更新器，用户需先手动安装同签名的 0.1.2。创建 `v0.1.2` 前应提交本次完整改动，不应移动已发布标签。

## GitHub Actions secrets

在仓库 **Settings → Secrets and variables → Actions → Repository secrets** 配置以下五项，使用同一套真实生产签名材料：

| Secret | 内容 / 用途 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 生产 JKS / PKCS12 密钥库完整文件的 Base64；构建时解码到 runner 临时目录 |
| `ANDROID_STORE_PASSWORD` | 密钥库密码，映射到 `QINGNIAO_STORE_PASSWORD` |
| `ANDROID_KEY_ALIAS` | 生产签名私钥别名，映射到 `QINGNIAO_KEY_ALIAS` |
| `ANDROID_KEY_PASSWORD` | 私钥密码，映射到 `QINGNIAO_KEY_PASSWORD` |
| `ANDROID_SIGNING_CERT_SHA256` | **生产签名证书**的 SHA-256 指纹，64 位十六进制，也接受冒号分隔和大写；不要填 APK 文件散列或公钥散列 |

密钥库路径由 CI 注入 `QINGNIAO_KEYSTORE_PATH`，无需另外配置 secret。证书指纹是公开标识，使用 secret 是为了集中配置，不能代替私钥保护。可以在可信本机通过 `keytool -list -v -keystore <生产密钥库路径> -alias <生产别名>` 交互输入密码，核对输出的证书 SHA256。不要在日志打印密钥库 Base64 或密码，不要生成临时“生产密钥”来通过校验，也不要把开发机 `debug.keystore` 配成生产密钥。

工作流使用自动提供的 `GITHUB_TOKEN`，仅 Release job 申请 `contents: write` 和 `actions: read`，无需个人访问令牌。仓库策略必须允许这些 job 权限。仅从已审核的分支运行生产构建、选择可信标签，因为构建过程会执行标签内的代码。缺少任意 secret、Gradle 缺少签名凭据、签名验证失败或证书指纹不匹配都会失败；临时密钥库在 `always()` 清理步骤删除。

## 发布产物与检查

正式更新的同一个 Release 必须包含下面两个名称固定的附件：

- **`qingniao-release.apk`**：生产证书签名的 universal APK，包含 `arm64-v8a`、`armeabi-v7a`、`x86_64` 三个 ABI 的 Flutter 与 Rust 原生库；不能用 split APK、AAB、Debug 或 Profile 代替。
- **`update.json`**：UTF-8 JSON，由 [`tool/generate_release_metadata.py`](../tool/generate_release_metadata.py) 从已经签名并验证的 APK 生成。

元数据的字段契约如下，不另行加入任意 APK 下载 URL：

| 字段 | 类型 / 值 |
| --- | --- |
| `schemaVersion` | 整数 `1` |
| `versionName` | `pubspec.yaml` 的 `+` 前部分，当前为 `"0.1.2"` |
| `versionCode` | JSON 正整数，当前支持 `1..2100000000`，与最终 APK 的 `longVersionCode` 一致，当前为 `4009` |
| `apkName` | 固定 `"qingniao-release.apk"` |
| `sha256` | 实际附件完整字节的 SHA-256，64 位小写十六进制 |
| `size` | 实际附件大小，正整数字节数，不超过更新器的 256 MiB 下载上限 |

生成器调用 SDK `apkanalyzer manifest print` 和 `apksigner verify --verbose --print-certs`，检查包名 `com.blue.qingniao`、非 split、非 debuggable、非 testOnly、版本、APK v2/v3 签名和唯一生产签名者。即使传入匹配的指纹，`Android Debug` 证书也会被拒绝。它检查三个 ABI 的原生库、ZIP 重复项，再读取整个 APK 计算大小和散列。`update.json` 仅在全部通过后写入，失败会删除上一次残留的元数据。

工作流同时保留 `SHA256SUMS`、`signature.txt`、`source-commit.txt`、`delivery-tools-commit.txt`、Flutter / Rust 版本和 `native-pages.json`。原生页大小及 ZIP 对齐检查继续执行；这不代替在 16 KB 页大小设备上的运行验证。重新运行创建 Release 时，若同名 Release 已存在，`gh release create` 会失败，不覆盖已发布附件。

## 应用内行为

「设置 → 关于 → 应用更新」显示实际安装版本、可用版本、下载进度和发布说明。自动检查默认开启，启动和恢复前台时按间隔检查，持续前台每 5 分钟复查，检查失败后自动重试间隔为 30 分钟。客户端通过 ETag 向 GitHub 发起条件请求，收到 304 时复用本进程已校验的发布元数据。用户可以关闭自动检查或手动检查。后台停止定时检查和界面进度轮询，下载过程中若系统结束进程，下次从更新页重新下载。

下载使用独立原生线程及 64 KiB 缓冲区，不占用短信处理队列，不把完整 APK 读入 Dart 内存。只接受指定 GitHub 仓库的 Release 附件及明确允许的 HTTPS 资产跳转，校验长度、SHA-256、包名、版本和当前安装包的签名者，并拒绝 debuggable / testOnly 包。安装前再次校验私有缓存文件；损坏或校验失败后可重新下载。下载不会自动安装：需要用户允许本应用安装来源，再点击安装，由 Android 系统安装器确认。

GitHub 不可达、限流或正式 Release 缺少有效附件时会显示检查失败。Latest 接口返回 404 时显示「暂无可用的正式发布版本」。

## 从草稿启用在线更新

1. 先将本工作流和发布工具提交到要运行的维护分支。确认目标标签已存在于远端且源码是预期版本；工作流不创建或推送标签。
2. 在 Actions 的 **Android delivery → Run workflow** 选择维护分支，填写已有 `release_tag`（当前为 `v0.1.2`），勾选 `production`。
3. 工作流通过后，在 Releases 打开生成的草稿。核对两个必需附件、版本、源提交、生产证书指纹和散列；补充变更说明，并在目标设备验证安装、升级和主要功能。
4. 维护者确认后，将草稿发布为**非 prerelease 的正式 Release**，并设为 **Latest**。只有完成这一步才对在线更新可见。
5. 检查 [GitHub latest API](https://api.github.com/repos/blueokanna/qingniao/releases/latest) 返回该 Release，`draft=false`、`prerelease=false` 且 `assets` 包含上述两个附件。

应用使用 `GET https://api.github.com/repos/blueokanna/qingniao/releases/latest`，只接受正式、非草稿、非预发布版本，从该 Release 的 `update.json` 获取元数据，再下载**同一个 Release**里的 `qingniao-release.apk`，核对大小和 SHA-256。草稿、预发布、只有 Actions artifact、缺少附件或尚无正式 Release（API 返回 404）都不能当作可用更新。元数据依赖官方仓库与 HTTPS 信任链，APK 最终仍须通过 Android 安装时的签名及版本检查。

同签名与更高版本代码是覆盖升级的前提。更新器要求下载 APK 与当前安装包的 signer 集合完全一致，当前不支持签名轮换或历史签名 lineage。已安装 Debug / Profile 开发签名的应用，不能把正式 APK 当作同签名更新；不要通过清除用户数据或伪装签名解决此问题。生产密钥丢失或更换属于单独的签名迁移任务。

## 本地轻量验证

元数据测试只用合成 ZIP、清单和签名工具输出夹具，覆盖版本、签名、架构、散列和失败路径；不需要正式密钥，不构建 Flutter / Gradle：

```powershell
python -m unittest discover -s tool/tests -p 'test_release_metadata.py' -v
python tool/generate_release_metadata.py version --pubspec pubspec.yaml --tag v0.1.2
```

对已有正式 universal APK，可先复制为 `build/delivery/qingniao-release.apk`，设置真实 `QINGNIAO_SIGNING_CERT_SHA256`，再检查并生成元数据（路径按本机 SDK 调整）：

```powershell
python tool/generate_release_metadata.py create `
  --pubspec pubspec.yaml --tag v0.1.2 `
  --apk build/delivery/qingniao-release.apk `
  --apkanalyzer "$env:ANDROID_HOME/cmdline-tools/latest/bin/apkanalyzer.bat" `
  --apksigner "$env:ANDROID_HOME/build-tools/36.0.0/apksigner.bat" `
  --output build/delivery/update.json
```

该命令检查现有 APK，不负责构建或签名。实际本地开发验证建议使用 `flutter build apk --debug` 或 `flutter build apk --profile`；正式构建继续使用 [`tool/build-release.ps1`](../tool/build-release.ps1) 与已有生产凭据，不带 `-SplitAbi` / `-Bundle` 才是在线更新所需的 universal APK。不要并行执行会重写插件注册文件的测试与正式构建。

CI 固定 Flutter `3.47.9`（提交 `c197ca5199e9ee5661e865596c9c07294dfab51c`）、Dart `3.13.7`、Rust `1.99.1`、JDK `17`、Android build-tools `36.0.0` 和 NDK `28.2.13676358`。这些是工作流配置值；CI 会核验 SDK 身份和实际版本，本地检查不代表完整远端工作流或生产发布已成功。Flutter SDK 固定 `material_color_utilities 0.13.0`，应用约束与锁文件保持兼容。
