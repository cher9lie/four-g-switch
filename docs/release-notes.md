原生跨平台测试版：Windows WPF 托盘小面板、Mac SwiftUI 菜单栏小面板。

提供 Windows x64 / ARM64，以及 Mac Apple Silicon / Intel 四种原生构建；Windows 自带运行库，Mac 自带 USB 库。

下载：Windows 解压 ZIP 后运行 FourGSwitch.exe；Mac 打开对应架构的 DMG，把应用拖到“应用程序”。

Mac 包目前使用临时签名，未通过 Apple Developer ID 公证。Windows ARM64 仍需要匹配该网卡硬件 ID 的 ARM64 驱动，安装包不提供专有驱动。

CI 编译、自检和架构检查不等于实体 USB 硬件验证。Mac 与 Windows ARM64 为待实物验证的初版，请见 README 和 docs/validation.md。切换过程中保持模块连接，不要提前拔出。
