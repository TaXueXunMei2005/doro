# Doro 桌面宠物

在 macOS 桌面常驻的 Doro：透明悬浮、可拖动，支持挥手、跳跃和抬爪思考。使用 Swift / AppKit 编写，关闭 ChatGPT 或 Codex 后仍可独立运行。日常运行不联网、不调用 AI 接口，也不消耗 AI 额度。

![抬爪思考预览](docs/preview.gif)

## 下载与启动

**[下载 Doro.app（Apple 芯片 Mac，macOS 15 或更新版本）](https://github.com/TaXueXunMei2005/doro/raw/refs/heads/main/downloads/Doro-macOS-arm64.zip)**

1. 下载并解压，得到 `Doro.app`。预编译包适用于 M 系列芯片的 Mac，无需安装开发工具。
2. 把应用放在固定位置，例如“应用程序”文件夹，或桌面的 `codex` 文件夹。
3. 双击 `Doro.app`，宠物会出现在屏幕角落，菜单栏同时出现 **Doro**。
4. 如旧版 Doro 正在运行，先通过旧版菜单栏选择“退出 Doro”，再打开新版本。

应用采用本地临时签名，未进行 Apple 公证。如果系统阻止打开，请核对下载来源，并按 macOS 的安全提示处理；也可以使用下方的源码构建方式。

> 目前仅提供 macOS 版本；不提供 Windows / Linux 版本。下载包为 arm64，Intel Mac 请尝试本机源码构建；尚未在 Intel Mac 上验证。

## 使用方式

| 操作 | 效果 |
| --- | --- |
| 按住宠物拖动 | 移动位置，播放左右步伐 |
| 单击或拖动后松开 | 挥手 |
| 双击 | 跳跃 |
| 右键宠物，或点击菜单栏 Doro | 选择挥手、跳跃、思考等动作 |
| 回到屏幕角落 | 重新定位并显示宠物 |
| 隐藏／显示 | 切换可见状态，进程继续运行 |
| 打开存储文件夹 | 查看窗口位置配置 |
| 退出 Doro | 保存位置并结束程序 |

当前有待机、左右跑动、挥手、跳跃、抬爪思考共 **6 组、37 帧**动画。修订素材收紧脸颊、突出下巴，思考时抬起一只原有前爪。资源目录 `running` 保留历史命名，对应思考动作。

“思考”只是本地动画演示，不与 ChatGPT / Codex 的任务状态同步。当前独立版没有鼠标视线跟随，也不会自动替换聊天软件内置宠物；如出现两只，可在对应软件中隐藏内置宠物。

## 登录后自动常驻

1. 将 `Doro.app` 放在准备长期保留的位置，并先手动打开一次。
2. 在 macOS“系统设置”中搜索“登录项”。
3. 在“登录时打开”列表中添加 `Doro.app`。之后登录 Mac 时即可启动。

设置完成后不要移动或删除应用；如果更换位置，请重新添加登录项。暂时隐藏宠物可以使用菜单栏的“隐藏／显示”，关闭聊天软件不会影响它。

取消自动启动时，从登录项列表中移除 Doro。若之前使用过本项目早期本地版的 `~/Library/LaunchAgents/local.doro.desktop.plist`，请先移除该旧启动入口，避免两套启动方式并存；本仓库不会自动安装 LaunchAgent。

## 从源码构建

需要 macOS 和 Xcode Command Line Tools（包含 Swift 编译器）。当前已在 **macOS 15.7.3 / Apple 芯片**环境完成构建验证；构建产物使用当前 Mac 的处理器架构。

尚未安装开发工具时，运行 `xcode-select --install`，按照系统提示完成安装，然后执行：

```bash
mkdir -p ~/Desktop/codex
cd ~/Desktop/codex
git clone https://github.com/TaXueXunMei2005/doro.git
cd doro
./scripts/build.sh
open build/Doro.app
```

脚本会编译、进行本地临时签名，并检查全部 37 张动画帧能否加载、是否为 192 × 208 像素。生成的应用位于 `build/Doro.app`，可复制到其他固定位置独立使用。项目不依赖第三方软件包。

也可以单独检查资源与签名：

```bash
build/Doro.app/Contents/MacOS/Doro --self-test
codesign --verify --deep --strict build/Doro.app
```

这些检查不启动桌面窗口；窗口交互和登录启动仍需在桌面会话中实际验证。

## 数据与卸载

窗口位置保存在 `~/Library/Application Support/Doro/position.json`，与应用或源码所在目录无关。退出 Doro、移除登录项后即可删除应用；需要清除位置记录时，再删除上述 Doro 数据文件夹。

## 项目结构

```text
source/main.swift          应用源码
resources/Info.plist        macOS 应用配置
resources/Frames/           37 张动画帧及相对路径清单
scripts/build.sh            构建、签名和资源自检
docs/preview.gif            动作预览
downloads/                  预编译应用压缩包与 SHA-256 校验值
```

编译缓存、本机登录启动配置、个人位置数据及日志不上传。压缩包的 SHA-256 校验值见 [downloads/SHA256SUMS](downloads/SHA256SUMS)。

## 素材说明

本项目是非官方 Doro 同人桌面宠物。动画素材使用 AI 生成并处理透明背景；脸型参考 [Good Smile 的 DORO 产品展示](https://www.goodsmile.com/ja/product/1140967/DORO)，仓库未收录该产品照片。角色及相关第三方素材的权利归原权利人所有；本仓库未授予这些素材的额外使用许可。
