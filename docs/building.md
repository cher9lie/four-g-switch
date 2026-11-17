# 构建

## Windows

安装 .NET 10 SDK，在对应架构的 Windows 上执行：

```powershell
./scripts/package-windows.ps1 -Architecture x64
# Windows ARM64 原生机器：
./scripts/package-windows.ps1 -Architecture arm64
```

脚本发布自包含单文件应用，在本机架构运行 `--self-test`，核对 PE 架构并生成 ZIP。它不会对实体模块发送指令。自检输出中的 IP 仅为固定测试数据。

不要把“arm64 应用能构建”当成“x64 专有硬件驱动能在 ARM64 上使用”。程序不打包专有驱动，也不关闭驱动签名保护。

## Mac

需要完整 Xcode（当前 CI 使用 Xcode 16.4，包含 App Intents 元数据工具）、macOS 13+、Python 3 和系统自带的 make / curl。仅安装 Command Line Tools 不足以完成 App Intents 打包。

```bash
bash scripts/build-libusb.sh
# Apple Silicon：
bash scripts/package-macos.sh arm64
# Intel Mac：
bash scripts/package-macos.sh x86_64
```

`build-libusb.sh` 下载固定 1.0.29 版源代码，核对 GitHub 官方 release 提供的 SHA-256，然后本地编译。Mac 应用动态链接该库，打包时修改加载路径为应用内的 Frameworks 目录。

Swift 测试读取 `shared/protocol-cases.json`，检查命令白名单、未确认状态不能变绿、并发写入拒绝及过期查询不会覆盖新状态。打包脚本核对 Mach-O 架构，验证代码签名，并运行 `--version` 检查实际动态库加载。不会切换实体模块。

SwiftPM 不会自动完成 Xcode 应用工程的 App Intents 打包步骤。脚本显式启用 Swift 常量提取，再通过 Apple 的 `appintentsmetadataprocessor` 生成实际包内的 `Contents/Resources/Metadata.appintents`。校验器要求五个动作和状态实体确实出现在元数据中；缺失时构建失败。不要用 `--force-metadata-output` 隐藏提取错误。

CI artifacts 同时保留 `*-app-intents.json` 校验报告、`*-system-integration.txt` 状态接口检查，以及 Apple Silicon 上用实际 NSHostingView 渲染的原生控件预览。Intel 托管虚拟机缺少 Metal，跳过预览；协议、并发、编译、签名、元数据和接口检查仍执行。

### 签名和公证

默认使用 `codesign --sign -`，为测试构建提供临时签名，不代表 Apple 公证。

若已在本机钥匙串导入自己的 Developer ID Application 证书，可设置：

```bash
export MACOS_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export APPLE_NOTARY_PROFILE='your-existing-notarytool-keychain-profile'
bash scripts/package-macos.sh arm64
```

不设置这些变量时，脚本不尝试寻找或上传证书。不要将私钥、证书密码或公证凭据提交到仓库。CI 默认无发布证书，当前公开测试版因此没有公证。

## GitHub Release

```bash
git tag v3.0.0-beta.2
git push origin v3.0.0-beta.2
```

四个平台通过后自动发布预发行版。常规 push / PR 只构建，不发布。Actions 的 release job 才拥有 contents:write；测试 job 只有只读权限，不使用用户 API token。

## 替换 libusb

应用允许替换动态库。对应完整原始源码在 Mac 应用内 `Contents/Resources/ThirdParty/`。可按本仓库脚本重新编译，替换 `Contents/Frameworks/libusb-1.0.0.dylib`，保持安装名称兼容，然后重新为库和应用临时签名。修改应用会使原签名失效，重新签名即可；不需要关闭系统安全功能。
