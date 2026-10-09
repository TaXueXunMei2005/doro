# Doro 桌面宠物

粉毛、紫眼、四条小短腿的 Doro，常驻 macOS 桌面。鼠标移到哪里，她就看向哪里；点一下，她会跳一跳、冒出爱心，再用小气泡和你打招呼，并显示 **Codex 本周剩余额度、可用重置卡和到期时间**。

![Doro 动作预览](docs/preview.gif)

## 下载与启动

**[下载 Doro.app（Apple 芯片 Mac，macOS 15 或更新版本）](https://github.com/TaXueXunMei2005/doro/raw/refs/heads/main/downloads/Doro-macOS-arm64.zip)**

1. 下载并解压，将 `Doro.app` 放在固定位置，例如“应用程序”或桌面的 `codex` 文件夹。
2. 如旧版正在运行，先从菜单栏 Doro 选择“退出 Doro”。
3. 双击新版 `Doro.app`。桌面角落出现宠物，菜单栏出现 **Doro**。
4. 查看额度时，需要已安装并登录 Codex / ChatGPT 桌面版，或本机 Codex CLI。

应用采用本地临时签名，未进行 Apple 公证。如果系统阻止打开，请核对下载来源后按 macOS 的安全提示处理，或使用下方源码构建方式。下载包仅适用于 Apple 芯片；Intel Mac 可尝试本机源码构建，尚未实测。不提供 Windows / Linux 版。

关闭聊天软件后，Doro 仍独立运行。播放动画和本地问候不消耗 AI 额度；查询额度需要联网，通过已登录的 Codex 读取账户信息，不发起模型任务。

## 怎么和她玩

| 操作 | 效果 |
| --- | --- |
| 移动鼠标 | 16 方向眼神跟随；靠近脸部中心时恢复待机 |
| 单击 Doro | 每次都跳一下并冒出三颗爱心；第一次显示问候与额度气泡，再点一次只收起气泡，Doro 继续常驻 |
| 双击 | 跳跃；不会被松开鼠标的动作打断 |
| 按住拖动 | 移动宠物并播放左右步伐；不会误触问候 |
| 点击气泡或“刷新 Codex 额度” | 重新查询额度，并从这次刷新起重新计时 10 秒 |
| 右键宠物 / 菜单栏 Doro | 眼神开关、动作演示、回到角落、隐藏／显示、退出 |

单击会短暂等待系统双击判定；气泡从显示时开始计时，约 10 秒后自动收起，Doro 本体继续留在桌面。再次单击 Doro 也只收起气泡；查询结果晚到不会重新打开气泡或延长显示时间。每次重新打开气泡会换一句招呼，不连续重复同一句。气泡不抢走正在输入的窗口焦点；爱心自动消失，并且不拦截鼠标。默认使用文字气泡。

当前素材包含待机、左右跑动、挥手、跳跃、委屈、等待、思考、检查共 **9 组、57 帧**标准动作，以及 **16 个视线方向**，总计 73 帧。思考和检查菜单用于动作演示，并不表示 AI 正在执行任务。

## 额度和重置卡

读取方式是官方 [Codex app-server 的账户额度接口](https://learn.chatgpt.com/docs/app-server)。Doro 使用本机已登录的 Codex，不要求填写 API Key，不复制登录凭据，也不会自动使用重置卡。

- 按真正的 7 天窗口计算 `100 − 已用百分比`，不会把短时限额当成本周额度。
- 卡片数量以接口返回的可用数量为准，显示可用卡中最近的到期时间；不把普通余额当重置卡。
- 连续点击可复用 60 秒内的结果，气泡会标明读取时间；点击刷新会强制重新读取。
- 到了额度重置或卡片到期时间，会清空旧数字并刷新。
- 未登录、离线、接口不支持或查询失败时显示“暂未获取”，不会将未知写成 0 或把过期值装成实时数据。

如果额度与当前桌面账户不符，请确认桌面版与本机 Codex CLI 登录的是同一账户，然后刷新。安装或更新 Codex 后仍无法读取时，可先确认 Codex 本身能显示额度。

## 登录后自动常驻

将 `Doro.app` 放在长期保留的位置，手动打开一次，然后在 macOS“系统设置”中搜索“登录项”，把它添加到“登录时打开”。以后登录 Mac 即可启动。移动应用后需要重新添加登录项。

若曾使用本项目早期本地版的 `~/Library/LaunchAgents/local.doro.desktop.plist`，该入口仍可指向原安装路径，不要同时重复添加两套启动方式。仓库不会自动安装 LaunchAgent。

## Codex 内与桌面外使用同一外观

[codex-pet/](codex-pet/) 提供同款 v2 宠物文件。桌面版所有 PNG 帧均从这一张最终图集拆出，外观、四肢、动作与 16 方向视线使用同一来源。两处显示大小由各自应用决定。

Codex / ChatGPT 内置宠物的自定义接口只接收素材与基本信息，点击行为由宿主应用控制。**跳跃爱心、中文问候、额度与重置卡气泡是本仓库独立桌面版功能**；同步素材不会向宿主注入这些交互代码。

本地 Codex 自定义宠物可将 `codex-pet` 中的两个文件放到 `~/.codex/pets/doro/` 后在宠物设置中选择 Doro。已经迁移到云端的宠物需要通过应用的宠物更新功能替换图集；只改本地文件不能替换云端版本。

## 从源码构建

需要 macOS 和 Xcode Command Line Tools（Swift 编译器）。如未安装，先运行 `xcode-select --install` 并完成系统提示。当前验证环境为 macOS 15.7.3 / Apple 芯片；构建产物使用本机架构。

```bash
mkdir -p ~/Desktop/codex
cd ~/Desktop/codex
git clone https://github.com/TaXueXunMei2005/doro.git
cd doro
./scripts/build.sh
open build/Doro.app
```

应用生成于 `build/Doro.app`，可复制到其他固定位置。构建脚本会签名、检查签名、验证 73 张 192 × 208 动画帧，以及方向、手势和多屏定位逻辑。无需第三方软件包。

```bash
build/Doro.app/Contents/MacOS/Doro --self-test
build/Doro.app/Contents/MacOS/Doro --interaction-self-test
build/Doro.app/Contents/MacOS/Doro --bubble-self-test
```

气泡自检需要图形桌面，会显示独立测试窗口约 11 秒，验证单击开关、10 秒自动收起与晚到回复；只使用合成额度，不查询账户，不关闭正在运行的 Doro。

额度接口与失败处理测试可运行 `./scripts/test.sh`，具体用例见 `tests/QuotaServiceTests.swift`。资源与逻辑自检不代替桌面交互和登录启动的实际验证。

## 存储与卸载

源码、素材和可下载应用保存在本仓库。运行时窗口位置与本机额度缓存位于 `~/Library/Application Support/Doro/`；额度缓存仅保存在当前电脑，不随应用分发。缓存不包含账户标识或登录凭据。

退出 Doro、移除登录启动入口后即可删除应用；需要清除位置和缓存时，再删除上述 Doro 数据文件夹。

```text
source/                    Swift 桌面程序与额度读取服务
resources/Frames/          73 张统一素材帧
resources/greetings.json   中文问候文案
resources/artwork.json     素材版本与图集校验信息
codex-pet/                 同款 Codex v2 图集及 pet.json
scripts/build.sh           构建、签名、自检
tests/                     额度读取与错误处理测试
docs/                      动作预览、参考来源与验证说明
downloads/                 应用压缩包与 SHA-256 校验值
```

本机额度、登录配置、缓存、日志及个人位置数据不上传。压缩包校验值见 [SHA256SUMS](downloads/SHA256SUMS)。

## 参考与素材

本项目为非官方 Doro 同人宠物。新版参考 [imdoro 粉丝站](https://imdoro.com/) 的经典 Doro 和 [Good Smile 官方 DORO](https://www.goodsmile.com/ja/product/1140967/DORO) 的角色比例，采用 AI 生成动画与确定性透明背景处理。问候参考社区的 Doro / Dororong 用语，中文句子为原创，不是官方配音或台词。原始参考图片不随仓库分发。

角色及相关第三方素材的权利归原权利人所有；本仓库未授予这些素材的额外使用许可。
