# OneLaunch

一个原生 macOS 启动器，定位是 **Launchpad + Spotlight** 的组合。

- 顶部搜索，像 Spotlight
- 下方应用网格，像 Launchpad
- 全局快捷键呼出，默认 `⌥ Space`
- 多种排序方式（最近使用 / 字母 / 使用频率 / 手动拖拽）
- 支持拖拽把应用归类到文件夹
- 支持自定义左侧分类（可新增/删除）
- 自定义分类支持排序
- 系统分类也支持排序（左侧可快捷上移/下移）
- 分类栏支持位置切换（左侧 / 右侧 / 下方）
- 支持在设置中隐藏分类（系统分类 + 自定义分类）
- 系统分类支持手动调整（可恢复自动分类）
- 支持自由拖拽调整应用/文件夹位置
- 文件夹支持自定义名称
- 可调节图标大小
- 可调节主列表宽度
- 自定义背景图片（支持毛玻璃效果叠加）
- 应用列表缓存，秒开
- 原生 SwiftUI + AppKit，无第三方依赖

## 功能

- 扫描 `/Applications`、`/System/Applications`、`~/Applications`
- 展示应用图标与名称
- 模糊搜索应用名
- 点击或回车启动应用
- 拖拽应用到应用/文件夹上，快速创建或合并文件夹
- 拖拽应用或文件夹到任意位置，手动调整顺序
- 点击文件夹查看其中应用，右键可解散文件夹
- 文件夹内支持自定义名称与更精致的分组视图
- 记录最近启动时间与使用频率
- 菜单栏常驻（左键打开 / 右键菜单）
- 设置面板（图标大小、列表宽度、排序方式、背景图片）
- 设置面板支持管理自定义分类

## 运行

```bash
swift run
```

启动后应用常驻菜单栏，可通过菜单栏图标或 `⌥ Space` 呼出。

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
├── OneLaunchMain.swift         # 应用入口
├── AppDelegate.swift           # 生命周期、菜单栏、快捷键
├── LauncherPanel.swift         # 自定义 NSPanel
├── LauncherPanelController.swift # 面板控制器（显示/隐藏/动画）
├── Models/
│   └── AppItem.swift           # 应用数据模型
│   └── AppFolder.swift         # 文件夹数据模型
├── ViewModels/
│   └── LauncherViewModel.swift # 核心业务逻辑
├── Views/
│   ├── LauncherView.swift      # 主界面
│   ├── AppCardView.swift       # 应用卡片
│   ├── FolderCardView.swift    # 文件夹卡片
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
