# Doro 桌面宠物

使用 Swift 和 Cocoa 编写的 macOS 独立桌面宠物。透明悬浮窗口，可拖动、挥手、跳跃和演示思考动作；退出聊天软件后仍可独立运行。

![抬爪思考预览](docs/preview.gif)

## 系统要求

- macOS，安装 Xcode Command Line Tools（提供 Swift 编译器）。
- 不依赖第三方软件包，不联网，不调用 AI 接口。
- 只支持 macOS；构建产物使用当前 Mac 的处理器架构。

## 构建与启动

如未安装命令行工具，先运行 `xcode-select --install` 并完成系统安装提示。

```bash
git clone https://github.com/TaXueXunMei2005/doro.git
cd doro
./scripts/build.sh
open build/Doro.app
```

构建脚本会编译、进行本地临时签名，并检查全部 37 张动画帧能否加载及其尺寸。生成的应用位于 `build/Doro.app`，可复制到“应用程序”文件夹。这是本地构建版本，未进行 Apple 公证。

## 使用方式

| 操作 | 效果 |
| --- | --- |
| 拖动 | 移动宠物并播放左右步伐 |
| 双击 | 跳跃 |
| 右键宠物或点击菜单栏 Doro | 挥手、跳跃、思考、回到角落、隐藏／显示、退出 |
| 打开存储文件夹 | 查看窗口位置配置 |

思考是动画演示，不代表 AI 正在执行任务。支持待机、左右跑动、挥手、跳跃和抬爪思考，共 6 组、37 帧动画。`running` 资源目录保留历史名称，对应思考动作。

窗口位置保存在 `~/Library/Application Support/Doro/position.json`，不依赖源码或应用所在目录。首次运行本仓库构建的版本时，位置默认为屏幕角落。如旧版 Doro 正在运行，请先从菜单栏退出旧版，再打开新版本。

如需登录时启动，可在 macOS 系统设置中将构建后的应用添加到登录项。

## 项目结构

```text
source/main.swift          应用源码
resources/Info.plist        macOS 应用配置
resources/Frames/          动画帧及相对路径清单
scripts/build.sh           构建、签名和资源自检
docs/preview.gif           动作预览
```

编译缓存、生成的应用、本机登录启动配置和个人位置数据由 `.gitignore` 排除。

## 素材说明

本项目为非官方 Doro 桌面宠物。角色及相关第三方素材的权利归原权利人所有；本仓库未授予这些素材的额外使用许可。
