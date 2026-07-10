# Mac App Store 上架流程

本文记录 OneLaunch 打包并上传到 Mac App Store / TestFlight 的流程，以及本项目实际踩过的坑。

## 当前项目信息

- App 名称：`Onelaunch`
- Bundle ID / 套装 ID：`com.example.onelaunch`
- Team ID / Provider Short Name：`TEAMID`
- Team：`Your Company Name`
- 当前可上传包：`dist/OneLaunch-appstore.pkg`

## 第一次配置

### 1. 证书

在 Xcode 里登录加入公司 Team 的 Apple ID：

```text
Xcode → Settings → Accounts → Manage Certificates
```

需要有两个证书：

```text
Apple Distribution: Your Company Name (TEAMID)
3rd Party Mac Developer Installer: Your Company Name (TEAMID)
```

终端检查：

```bash
security find-identity -v -p codesigning
```

应能看到 `Apple Distribution`。

如果显示 `0 valid identities found`：

- 确认证书下面有“专用密钥”
- 安装 Apple WWDR G3 中间证书：https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
- 确保证书信任设置为“使用系统默认”

### 2. Provisioning Profile

打开：

```text
https://developer.apple.com/account/resources/profiles/list
```

创建 profile：

```text
Profile 类型：Mac App Store Connect
Profile Type：Mac
App ID：com.example.onelaunch
Certificate：Apple Distribution
Name：OneLaunch Mac App Store
```

下载到，例如：

```text
~/Downloads/OneLaunch_Mac_App_Store.provisionprofile
```

### 3. App 专用密码

打开：

```text
https://appleid.apple.com
```

创建：

```text
登录与安全性 → App 专用密码
```

该密码只用于上传，不是 Apple ID 登录密码。

## 每次发版

### 1. 递增 build 号

App Store Connect 不允许重复上传相同 build 号。比如已经上传过 `0.1.0 (5)`，下一次必须用：

```text
BUILD_VERSION=6
```

### 2. 打包

```bash
cd /path/to/one-launch

BUNDLE_ID="com.example.onelaunch" \
MARKETING_VERSION="0.1.0" \
BUILD_VERSION="6" \
APP_SIGN_IDENTITY="Apple Distribution: Your Company Name (TEAMID)" \
INSTALLER_SIGN_IDENTITY="3rd Party Mac Developer Installer: Your Company Name (TEAMID)" \
PROVISIONING_PROFILE="$HOME/Downloads/OneLaunch_Mac_App_Store.provisionprofile" \
./scripts/package-appstore.sh
```

生成：

```text
/path/to/one-launch/dist/OneLaunch-appstore.pkg
```

### 3. 本地检查

```bash
codesign --verify --deep --strict --verbose=2 dist/OneLaunch.app
```

查看 entitlements：

```bash
codesign -d --entitlements :- dist/OneLaunch.app | plutil -p -
```

应只包含类似：

```text
com.apple.application-identifier = TEAMID.com.example.onelaunch
com.apple.developer.team-identifier = TEAMID
com.apple.security.app-sandbox = true
com.apple.security.files.user-selected.read-only = true
```

检查 quarantine：

```bash
xattr -lr dist/OneLaunch.app | rg "com.apple.quarantine"
```

没有输出才正常。

### 4. 上传

图形 Transporter 可能因为内置 `iTMSTransporter 4.1.0` 报 1046。推荐用命令行上传，并强制 HTTP：

```bash
/Applications/Transporter.app/Contents/itms/bin/iTMSTransporter \
  -m upload \
  -assetFile /path/to/one-launch/dist/OneLaunch-appstore.pkg \
  -u "你的AppleID邮箱" \
  -p "你的App专用密码" \
  -asc_provider "TEAMID" \
  -t HTTP
```

成功时会看到：

```text
1 package was uploaded successfully
Returning 0
```

## 上传后

打开：

```text
https://appstoreconnect.apple.com
```

进入 App，等待 build 处理完成。通常几分钟到几十分钟。

然后可以：

- 在 `TestFlight` 里选择新 build 测试
- 在 `App Store` 版本页选择新 build，补截图、描述、隐私、年龄分级、价格、审核说明后提交审核

## 常见问题

### 0 valid identities found

证书没有被命令行识别为签名身份。

处理：

- 检查钥匙串里证书下面是否有“专用密钥”
- 安装 Apple WWDR G3 证书
- 信任设置改回“使用系统默认”

### missing provisioning profile

错误：

```text
missing a provisioning profile
```

处理：创建并下载 `Mac App Store Connect` profile，打包时传入：

```bash
PROVISIONING_PROFILE="/path/to/profile.provisionprofile"
```

### missing application identifier

错误：

```text
missing an application identifier
```

处理：签名 entitlements 必须包含 profile 里的：

```text
com.apple.application-identifier
com.apple.developer.team-identifier
```

当前 `scripts/package-appstore.sh` 已自动处理。

### invalid networkextension entitlement

错误：

```text
com.apple.developer.networking.networkextension isn't supported
```

原因：不能把 provisioning profile 里的所有 entitlements 原样签进 App。

处理：只白名单写入必要 entitlements。当前脚本已修复。

### com.apple.quarantine

错误：

```text
package contains one or more files with the com.apple.quarantine extended file attribute
```

原因：浏览器下载的 `.provisionprofile` 带 quarantine 属性。

处理：打包时清理 `.app` 扩展属性。当前脚本已执行：

```bash
xattr -cr "$APP_DIR"
```

### bundle version must be higher

错误：

```text
捆绑包版本必须高于之前上传的版本
```

处理：增加 `BUILD_VERSION`，例如从 `5` 改到 `6`。

### Transporter 1046

错误：

```text
Deprecated Transporter usage ... required to use Transporter 4.2 or later
```

处理：不要用 Transporter 图形界面验证/上传，改用命令行并加：

```bash
-t HTTP
```

### verify 模式提示 pkg is NOT a directory

`iTMSTransporter -m verify` 期望 `.itmsp` 目录，不适合直接验证当前 `.pkg`。

处理：直接使用：

```bash
-m upload -assetFile dist/OneLaunch-appstore.pkg
```
