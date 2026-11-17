Mac 原生界面与系统集成更新：系统开关、可调整大小的独立面板、键盘快捷键、VoiceOver 状态标签及重要变化播报，适配减少透明度、增强对比度和减少动态效果。

通过 Apple App Intents 提供五个动作：查询状态、在 Mac 使用、准备给 Windows 使用、设置目标模式、打开面板。状态以结构化字段返回，方便快捷指令条件判断；注册四个 App Shortcuts。界面与系统动作共用设备入口，拒绝并发写入，失败或切换中不会返回旧的成功状态。

四种原生构建：Windows x64 / ARM64、Mac Apple Silicon / Intel。Mac 两架构均生成并校验实际 App Intents 元数据。Windows 设备逻辑未改变。

下载：Windows 解压 ZIP 后运行 FourGSwitch.exe；Mac 打开对应架构 DMG，把应用拖入“应用程序”并首次启动，再到快捷指令中搜索 FourGSwitch。

这是公开测试版。Mac 包采用临时签名，未通过 Developer ID 公证。Mac 实体 USB、VoiceOver 和 Siri 操作仍需真实设备验证；Windows ARM64 需要适配该硬件的 ARM64 驱动，安装包不提供专有驱动。CI 构建与自检不能替代实机验证。请参阅 README 和 docs/validation.md。
