# OneLaunch

一个原生 macOS 启动器，定位是 **Launchpad + Spotlight** 的组合。

- 顶部搜索，像 Spotlight
- 下方应用网格，像 Launchpad
- 全局快捷键呼出，默认 `⌥ Space`
- 多种排序方式（最近使用 / 字母 / 使用频率 / 手动拖拽）
- 可调节图标大小
- 自定义背景图片（支持毛玻璃效果叠加）
- 应用列表缓存，秒开
- 原生 SwiftUI + AppKit，无第三方依赖

## 功能

- 扫描 `/Applications`、`/System/Applications`、`~/Applications`
- 展示应用图标与名称
- 模糊搜索应用名和 bundle identifier
- 点击或回车启动应用
- 记录最近启动时间与使用频率
- 菜单栏常驻（左键打开 / 右键菜单）
- 设置面板（图标大小、排序方式、背景图片）

## 运行

```bash
swift run
```

首次启动后会自动弹出启动器窗口，也可以通过菜单栏图标或 `⌥ Space` 呼出。

## 打包成 `.app`

```bash
./scripts/package-app.sh
```

生成后的应用位于 `dist/OneLaunch.app`，可以直接双击运行。

打包 + 重启（开发时常用）：

```bash
./scripts/package-app.sh && pkill -x OneLaunch; sleep 1; open dist/OneLaunch.app
```

## 更换应用图标

1. 准备一张 **1024x1024** 的 PNG 图片
2. 放到项目根目录，命名为 `icon.png`
3. 重新打包：

```bash
./scripts/package-app.sh
```

打包脚本会自动生成所有尺寸（16x16 ~ 1024x1024）并转为 `.icns` 文件打入 `.app` 包中。如果根目录没有 `icon.png` 则跳过图标生成。

> macOS 会缓存应用图标，替换后如果没变化，可以重启 Finder（`killall Finder`）或注销重新登录。

## 技术栈

- **语言**：Swift 6.2
- **框架**：SwiftUI + AppKit + Carbon（全局快捷键）
- **构建**：Swift Package Manager
- **最低版本**：macOS 14.0

## 项目结构

```
Sources/OneLaunch/
├── main.swift                  # 应用入口
├── AppDelegate.swift           # 生命周期、菜单栏、快捷键
├── LauncherPanel.swift         # 自定义 NSPanel
├── LauncherPanelController.swift # 面板控制器（显示/隐藏/动画）
├── Models/
│   └── AppItem.swift           # 应用数据模型
├── ViewModels/
│   └── LauncherViewModel.swift # 核心业务逻辑
├── Views/
│   ├── LauncherView.swift      # 主界面
│   ├── AppCardView.swift       # 应用卡片
│   ├── SettingsView.swift      # 设置面板
│   ├── SearchField.swift       # 搜索输入框
│   ├── VisualEffectView.swift  # 毛玻璃效果
│   └── ScrollViewConfigurator.swift
└── Services/
    ├── AppScanner.swift        # 应用扫描与缓存
    ├── SearchScorer.swift      # 搜索评分算法
    ├── RecentAppsStore.swift   # 使用记录
    ├── HotKeyService.swift     # 全局快捷键
    ├── SettingsStore.swift     # 设置持久化
    └── AppIconProvider.swift   # 图标缓存
```
