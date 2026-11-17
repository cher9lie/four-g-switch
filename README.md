# 4G 网卡开关 / FourGSwitch

[![Build native apps](https://github.com/cher9lie/four-g-switch/actions/workflows/build.yml/badge.svg)](https://github.com/cher9lie/four-g-switch/actions/workflows/build.yml)
[![MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

把第一代 DJI 4G 模块在 Windows、Mac 和 iPad 之间切换，收成一个小按钮。

Windows 使用原生 WPF 托盘面板，Mac 使用原生 SwiftUI 菜单栏面板。没有网页服务、账号或遥测。

**[下载安装包](https://github.com/cher9lie/four-g-switch/releases)**

## 选择版本

| 电脑 | 下载文件 | 界面 |
|---|---|---|
| Windows Intel / AMD 64 位 | `win-x64.zip` | Windows 原生小面板 |
| Windows ARM64，例如 Snapdragon | `win-arm64.zip` | Windows 原生小面板 |
| Mac Apple Silicon，M 系列 | `macos-arm64.dmg` 或 `.zip` | Apple 原生菜单栏面板 |
| Mac Intel | `macos-x86_64.dmg` 或 `.zip` | Apple 原生菜单栏面板 |

文件名带版本号，例如 `FourGSwitch-3.0.0-beta.2-win-x64.zip`。Windows 版本自带 .NET，不用额外安装运行库。Mac 版本自带 USB 库，不用安装 Homebrew。

系统要求：Windows 11；macOS 13 或更高版本。仅支持第一代 DJI 4G 模块，USB 标识 **`2CA3:4006`**。

**驱动要求与验证范围：** Windows 需要与处理器架构匹配、且支持该硬件 ID 的网卡和 AT 串口驱动。Windows ARM64 的安装包是原生 ARM64 应用，但并不包含或保证提供适用的 Quectel ARM64 驱动。x64 驱动不能替代 ARM64 驱动。Mac 直接使用打包的 libusb 访问 AT 接口。

首次跨平台发行是测试版：CI 会在四种架构上分别编译、执行协议及状态检查，并核对二进制架构；这不等于四个平台都已连接实体网卡验证。Windows x64 设备逻辑来自已实测的 2.1 版；Mac 和 Windows ARM64 的实物兼容性仍需验证。

## Windows

升级前先从托盘退出旧版，避免两个工具同时占用设备。解压后双击 `FourGSwitch.exe`。右下角托盘左键单击可以直接切换，右键选择“打开小面板”。

- **绿色**：Windows 模式和自动联网设置已确认，模块网卡已取得有效 IPv4 和网关。
- **切换为 iPad / Mac 模式**：等待“可以拔下网卡”，再拔出。
- **黄色**：正在切换或等待地址，不会提前显示成功。

关闭面板只是收起到托盘；完全退出使用菜单中的“退出”。支持面板置顶。

## Mac

打开 DMG，把 `FourGSwitch.app` 拖入“应用程序”，然后启动。点击菜单栏天线图标打开面板。

- **开启**：选择 Mac / iPad 的 ECM 模式；只有取得网卡地址后才显示绿色和“Mac 已连接”，等待地址时显示等待状态。
- **关闭**：准备给 Windows 使用。显示“可以拔下网卡”后再拔出。
- 将模块从 Mac 交给 iPad，保持开启的 Mac / iPad 模式即可，不需要先关闭。

使用前退出 DJOneHub 或其他可能同时占用模块 AT 接口的工具。程序不会抢占或卸载内核驱动。

面板采用 SwiftUI 系统开关、菜单、字体与材质，使用系统语义颜色。状态同时用文字和图标表达；适配减少透明度、增强对比度、减少动态效果。VoiceOver 可读取操作标签和状态，重要状态变化会播报。更多菜单可打开可调整大小的独立面板，面板较小时支持滚动。

键盘：`⌘⇧M` 切换模式、`⌘R` 刷新、`⌘O` 打开独立面板、`⌘⇧C` 复制诊断。键盘遍历系统控件时，可在 macOS 系统设置中启用“键盘导航”。完整无障碍检查清单见 [验证范围](docs/validation.md)。

### 快捷指令和系统接口

首次启动应用后，可在“快捷指令”中搜索 **FourGSwitch**。应用通过 Apple App Intents 暴露以下动作，并注册四个预设 App Shortcuts：

| 动作 | 返回 / 行为 |
|---|---|
| 查询 4G 网卡状态 | 返回状态实体，可读取模式、是否连接、是否正在切换、USB 配置是否确认、是否已准备给 Windows 使用 |
| 在 Mac 使用 4G 网卡 | 明确设置 Mac / iPad 模式，返回检查后的状态 |
| 准备给 Windows 使用 4G 网卡 | 明确设置 Windows 模式，返回检查后的状态 |
| 设置 4G 网卡模式 | 接收目标模式参数，便于自行组合自动化 |
| 打开 4G 网卡面板 | 打开独立原生控制面板 |

例如：添加“在 Mac 使用 4G 网卡”，读取结果中的“Mac 网络已连接”，再用“如果”决定是否显示通知。动作完成不一定代表已取得网络地址，应以返回字段为准。未连接设备、切换中或读取失败时，不会返回已确认成功的旧状态。

状态查询和模式动作无需弹出面板，修改模式需要本机解锁。模式动作采用明确目标，重复运行不会反向切换。系统动作和界面共用串行设备入口，切换时的第二个写操作会被拒绝。没有暴露通用 AT 命令、HTTP 服务或远程端口。

系统可用这些动作构建快捷指令，并在系统支持的入口发现 App Shortcuts；Siri 的可用性取决于系统版本、语言与配置。本项目没有自定义控制中心控件或 WidgetKit 桌面小组件。实际注册、语音调用与 VoiceOver 操作仍需真实 Mac 验证，CI 元数据检查不能替代这些测试。

公开测试版采用临时签名，尚未通过 Apple Developer ID 公证。若系统拦截，请按 [Apple 的说明](https://support.apple.com/102445) 对这个已确认来源的应用使用“仍要打开”；不要关闭 Gatekeeper。可选的 Developer ID 签名及公证方法见 [构建说明](docs/building.md)。

## 为什么切换需要等待

模块把 USB 网络协议保存在自身配置中，主机换了不会自动选择另一套协议。

| 配置 | 用途 |
|---|---|
| `usbnet=0` | 当前模块已实测的 Windows NDIS 模式 |
| `usbnet=1` | Mac / iPad 的 CDC ECM 模式 |
| `qcautoconnect=1` | 自动联网 |

程序先确认实际 USB 接口已经改变，再重开控制接口，避免在接口消失过程中反复读取。Windows x64 的旧版设备实测中，切回 Mac/iPad 约 2 秒；切回 Windows 并获取地址约 37.5 秒，其中仍需要一次模块重启。这些是单机参考值，不保证所有环境相同。

取得本地地址不代表套餐、DNS 或所有网站都可用。切换过程中保持连接即可。程序不改 APN、SIM、固件、USB VID/PID 或系统安全设置。

## 自动构建与发布

每次 push / PR 自动在以下原生 runner 构建和自检：

- `windows-2022` → Windows x64
- `windows-11-arm` → Windows ARM64
- `macos-15` → Mac Apple Silicon
- `macos-15-intel` → Mac Intel

构建成功后可以在 Actions 下载 artifacts。推送 `v*` 标签后，四个平台全部通过才会自动建立 GitHub Release，上传 ZIP、DMG 和 `SHA256SUMS.txt`。带预发行后缀的标签自动发布为预发行版。

## 源码

```text
windows/       WPF 窗口、Windows 设备控制和自检
macos/         SwiftUI 应用、USB 控制层和 Swift 测试
shared/        两端共用的 AT 协议测试样本
scripts/       本地与 CI 使用的构建、打包脚本
third_party/   依赖版本、摘要与许可证说明
```

详见 [构建说明](docs/building.md) 和 [验证范围](docs/validation.md)。

## 隐私与许可证

所有设备操作在本机完成。不包含云服务、屏幕捕获、自动开机任务、固件升级或远程命令。诊断只能由用户主动复制；Windows 诊断可能包含模块的局域网地址，分享前请自行检查。

原创代码使用 MIT 许可证。Mac 动态链接的 libusb 为 LGPL-2.1-or-later，每个 Mac 包内附对应库的完整源代码、许可证和可重建脚本。[第三方说明](third_party/NOTICES.md)

本项目是社区工具，与 DJI、Quectel 或 Apple 无隶属关系。协议和设计资料参考：
[DJIModeSwitcher](https://github.com/hiwangchuan/DJIModeSwitcher)、
[DJOneHub](https://github.com/rogerbush007-a11y/DJOneHub-mac-enhanced)、
[Quectel AT 手册](https://forums.quectel.com/uploads/short-url/w8Y0o7voqL5apyCaZtpszM0up1D.pdf)。
这些项目的代码没有复制进本仓库。
