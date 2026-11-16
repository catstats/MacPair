# MacPair：两台 Mac 近距离无线扩展屏

默认英文；右上角 Language 菜单可切换「简体中文」。[English guide](README.md) · [中文测试指南](TESTING.zh-CN.md)

最小原生 macOS 原型。支持 Mirror（镜像主屏幕）和 Extend（创建真正的第二块桌面），另一台 Mac 接收画面。用户已确认两台 Mac 分别连接不同 Wi-Fi 时可用。

**2026-11-16 用户实测反馈：虚拟屏和不同 Wi-Fi 下的双 Mac 副屏通过；用户所述“没有 Wi-Fi”的情况未通过。** 尚未明确该情况是关闭了 Wi-Fi 开关，还是开着无线但未连接任何网络，因此独立无接入点模式暂不记为通过。详见 [测试记录](TESTING.zh-CN.md)。

## 打开原型

已经构建的 App：`build/MacPair.app`。在 Finder 中双击，或双击项目根目录的「Start MacPair.command」。

把 `build/MacPair-0.1.2.zip` 复制到另一台 Mac，解压后打开其中的 MacPair.app。包内附完整源码。另一台 Mac 不需要安装 Xcode。

要求：两端 macOS 13 或以上，支持 Apple 点对点 Wi-Fi 的无线硬件。提供 arm64 和 x86_64 通用构建；开发环境是 Apple Silicon；用户验收设备的处理器与系统版本尚未单独记录。

App 使用本地临时签名，没有 Apple 公证。如果系统拦截自己构建的 App，可到「系统设置 → 隐私与安全性」按系统提示允许打开。无需关闭 SIP 或全局 Gatekeeper。

## 选择镜像或扩展

两台 Mac 都更新到 **0.1.2**。主机在连接前选择模式：

- **Mirror（镜像）**：显示主机现有主屏幕，保留屏幕比例缩放，不创建虚拟显示器；点击 **Mirror display（开始镜像）**。
- **Extend（扩展）**：创建独立的 1280 × 800 桌面，可以把窗口拖过去；点击 **Extend display（开始扩展）**。

切换模式时先断开，再选择另一模式并重新连接。副屏自动接收对应模式。镜像使用公开的屏幕捕获接口；非公开虚拟屏接口只用于扩展模式。

## 第一次连接

1. 两台 Mac 放在附近，**Wi-Fi 开关保持开启**；蓝牙建议开启。无需加入同一个无线网络。
2. 在副屏（例如 MacBook Air）打开 App，选择「这台是副屏」→「作为副屏等待连接」。
3. 两端如提示「本地网络」访问，请允许。macOS 防火墙如询问 App 入站连接，也需允许。
4. 主机（例如 MacBook Pro）选择「这台是主机」→「搜索附近副屏」。
5. 选择标有「AWDL 直连可用」的副屏，输入副屏显示的 12 位配对码。
6. 建议先点「测试直连」。成功后应显示「AWDL 直连测试通过」和往返时间。这一步不需要屏幕录制权限。
7. 点「断开连接」。主机点「授权屏幕录制」，在系统设置中允许 MacPair，然后 **退出并重新打开同一个 App**。副屏不需要屏幕录制权限。
8. 再次搜索、输入配对码，点「开始扩展」。
9. 主机右侧出现 1280 × 800 独立桌面。用主机鼠标把窗口拖出桌面右边缘，副屏会显示这个窗口。
10. 副屏双击画面切换全屏，Esc 退出全屏。主机的「调整显示器排列」可以更改屏幕相对位置。

停止会话会停止捕获；扩展模式还会释放虚拟显示器，macOS 会将其窗口移回现有屏幕。直接退出 App 也会释放虚拟显示器。副屏断开后可继续等待主机重新连接。

## 如何确认没有用到路由器

主机只允许连接 Bonjour 发现结果中的 `awdl*` 接口，并把 `NWParameters.requiredInterface` 设为这个接口。**没有 AWDL 接口时，连接按钮不能使用；不会自动回退到校园网或热点。**

验收时让两台 Mac 都断开路由器/手机热点的网络连接，但 **不要关闭 Wi-Fi 无线开关**，并拔掉以太网/Thunderbolt 网线。随后重新搜索，先做直连测试，再传输屏幕。这比在共同 Wi-Fi 下观察“能连上”更有说服力。

诊断栏的“网络路径”显示 Network.framework 报告的接口名；代码中的接口限定与断开公共网络的测试一起确认这条路径。需要现场测量实际时延、距离和吞吐，不预先承诺某个延迟数值。

## 首版范围

- 镜像主屏幕：按原比例缩放到 1280 × 800 内，兼容竖屏与超宽屏。
- 真正的扩展桌面；首版固定 1280 × 800、1×，目标上限 30 fps。
- Bonjour 自动发现 + Apple 点对点 Wi-Fi（AWDL）。
- 每次开始等待生成新的随机配对码，TLS-PSK 加密传输。
- ScreenCaptureKit 仅捕获新建的虚拟显示器，VideoToolbox H.264 编码。
- AVSampleBufferDisplayLayer 解码显示，接收端支持窗口/全屏。
- 心跳、往返时间、会话超时、断开清理、复制诊断信息。
- **用主机的键盘、鼠标/触控板操作。** 首版不转发副屏键鼠、不传声音、不做 Retina/自适应码率、多副屏或自动重连。

fps 统计的是实际发送/接收的新帧数；静止画面时 ScreenCaptureKit 可能不产生新帧，显示 0 fps 不代表断线。往返时间是网络心跳 RTT，**不是**“鼠标到画面”的端到端延迟。

## 构建与测试

只使用系统框架，不下载 Swift 包，不需要开发者付费账号。编译机需安装 Xcode 或包含 macOS SDK 的开发工具。

```bash
./scripts/build.sh            # arm64 + x86_64 通用 App
./scripts/build.sh --native   # 仅当前架构，开发时更快
./scripts/test.sh             # 实际本机 TLS、协议及视频编解码测试
./scripts/test.sh --display   # 额外短暂创建/移除真实虚拟显示器
./scripts/package.sh          # App + 说明 + 完整源码的 zip
```

测试不会自动授予系统权限，不会为了测试去录制已有桌面。不要在授予屏幕录制权限后反复重签同一测试会话中的 App；先完成构建，再授权并重启。Bundle ID 保持为 `local.macpair.prototype`。

## 架构与限制

```text
主机 Mac                               副屏 Mac
CGVirtualDisplay → 独立桌面
  ↓
ScreenCaptureKit → H.264 编码
  ↓
TLS-PSK / TCP ─── AWDL 点对点 Wi-Fi ───→ 解码与全屏显示
  ↑                                     ↓
  └────────────── 心跳 / RTT ────────────┘
```

**CGVirtualDisplay 是 macOS 非公开接口。** 不需要安装驱动，但系统升级可能使它失效；这里不是承诺可以上架 App Store 或保证所有 Mac 兼容。接口异常由 Objective-C 桥接层处理，失败会报告给用户。原型不依赖 OpenDisplay 的完整应用、自动更新器或云端服务。

无线发现受机型、系统权限、无线开关、无线环境及 AWDL 支持影响。首版保留严格接口选择，宁可报告无法发现，也不把局域网连接冒充成无需路由器的成功。

## 排障

| 现象 | 处理 |
| --- | --- |
| 找不到副屏 | 确认副屏已开始等待；两端 Wi-Fi 开启；允许本地网络；主机重新搜索 |
| 只显示“尚未发现点对点接口” | 保持 Wi-Fi 开启，靠近两台机器，确认权限后重试；此时不会回退到局域网 |
| 配对失败/超时 | 输入当前副屏显示的完整配对码；停止再重新等待会改变配对码 |
| 测试直连成功，扩展失败 | 检查主机屏幕录制权限；授权后退出并重开同一个 App；查看诊断错误 |
| 画面黑但帧数增加 | 在主机把一个普通窗口拖到扩展桌面；受保护内容可能不被捕获 |
| 窗口拖不进去 | 点“调整显示器排列”，查看 MacPair 所在方向 |
| 睡眠后断开 | 本版检测超时并清理；唤醒后手动重新连接 |
| 需要报告问题 | 两端点击“复制诊断信息”，保留系统版本、接口、错误、帧数；不包含配对码 |

## 后续修改和提交

在本项目中修改源码，按前面的命令构建和检查。可直接运行的 App 与 AirDrop 安装包放在 build/，已被 Git 忽略。

```bash
git status
./scripts/build.sh --native
./scripts/test.sh
git diff
git add -A
git commit -m "Describe the change"
```

## 参考与许可

- [Apple：选择网络 API（点对点 Wi-Fi）](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api)
- [Apple：includePeerToPeer](https://developer.apple.com/documentation/network/nwparameters/includepeertopeer)
- [Apple：ScreenCaptureKit 示例](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)
- [OpenDisplay](https://github.com/peetzweg/opendisplay)：虚拟屏接口定义的来源，GPL-3.0。
- [OpenAirDisplay](https://github.com/nmt3325/openairdisplay)：相关的 AWDL 方向工作；本原型没有克隆或依赖该分支。

本项目采用 GPL-3.0-only，完整条款见 LICENSE，第三方来源见 THIRD_PARTY_NOTICES.md。
