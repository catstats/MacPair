// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh-Hans"
    var id: String { rawValue }
    var title: String { self == .english ? "English" : "简体中文" }
}
enum L10n {
    static let preferenceKey = "MacPairLanguage"
    static var language: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "en") ?? .english
    }
    static func setLanguage(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: preferenceKey)
    }
    static func text(_ english: String) -> String {
        language == .english ? english : chinese[english] ?? english
    }
    private static let chinese: [String: String] = [
        "This pairing could not be kept for this app session. Disconnect and pair again.": "未能在本次打开期间记住配对，请断开后重新配对。",
        "Pairings stay in memory while both apps remain open. Reopening either app requires a new code.": "配对仅保存在内存中。保持两端 App 打开可免输码；重开任一端后需重新配对。",
        "Session paired · No code needed": "本次已配对 · 无需输码",
        "Session-paired Macs only": "仅限本次已配对的 Mac",
        "Session-paired Macs can connect without a code. Choose New code to pair a new Mac.": "本次已配对的 Mac 无需输码；添加新 Mac 请点击「换一个码」。",
        "Select this Mac on the host. Session-paired Macs need no code.": "在主机上选择这台 Mac，本次已配对的 Mac 无需输码。",
        "Paired for this app session. Keep both apps open to reconnect without a code.": "已记住本次配对；保持两端 App 打开，重连时无需输码。",
        "This connection is encrypted, but its pairing was not kept. Pair again to reconnect.": "本次连接已加密，但未记住配对；下次连接请重新配对。",
        "Session pairings": "本次配对",
        "No pairings in this app session.": "本次打开期间尚未配对。",
        "Keep Wi-Fi on. Reopen either app to pair again.": "保持 Wi-Fi 开启；重开任一端 App 后需重新配对。",
        "Generated performance fixture": "生成的性能界面示例",
        "Capture": "捕获",
        "Encode": "编码",
        "Send": "发送",
        "Raw wait": "原始帧等待",
        "Encode avg/p95": "编码平均/p95",
        "Local send": "本机发送",
        "Callback → receiver submit → ACK": "捕获回调 → 副屏提交 → 确认",
        "includes return trip": "包含返回链路",
        "Receiver queue / sample / renderer wait": "副屏队列/样本构建/显示等待",
        "Raw frames replaced": "已替换原始帧",
        "Outstanding": "在途帧",
        "Peak": "峰值",
        "Hardware required": "要求硬件加速",
        "Low latency": "低延迟",
        "Frame feedback": "帧反馈",
        "System renderer submissions": "系统显示层提交",
        "not presentation rate": "非实际呈现帧率",
        "Video updates per second. A still desktop can report fewer frames.": "每秒视频更新数；静止桌面可能产生较少的新帧。",
        "Legacy video path: 30 fps target. Update both Macs for frame feedback.": "兼容视频路径：目标 30 fps。两端更新后可启用帧反馈。",
        "Video feedback enabled: at most two frames in flight; 60 fps target.": "已启用帧反馈：最多两帧在途，目标 60 fps。",
        "Encoded video frame exceeds the packet limit. Choose Larger Text and reconnect.": "编码视频帧超出上限，请选择「更大文字」并重新连接。",
        "Video send failed": "视频发送失败",
        "Unsupported video feedback settings": "视频反馈设置不受支持",
        "Invalid video frame identifier": "视频帧序号无效",
        "Invalid video acknowledgement": "视频确认消息无效",
        "Video feedback was not negotiated": "尚未协商视频反馈",
        "Video receiver exceeded the negotiated frame window": "接收的视频帧超出已协商的缓冲上限",
        "Unexpected encoded frame": "收到非预期的编码帧",
        "The video receiver stopped accepting frames. Reconnect to resume.": "副屏已停止接收视频帧，请断开重连。",
        "The video renderer stopped accepting frames. Reconnect to resume.": "视频显示层已停止接收帧，请断开重连。",
        "Prototype 0.1.8": "原型 0.1.8",
        "Nearby Mac detected": "发现附近的 Mac",
        "Available as a second display": "可作为第二块屏幕",
        "Not now": "暂不连接",
        "MacPair · Nearby display": "MacPair · 附近的副屏",
        "Automatically find displays": "自动寻找副屏",
        "Show a connection card when an available display is found.": "发现可用的副屏时显示连接卡片。",
        "Automatic discovery is off. Choose Find nearby displays to search.": "自动发现已关闭，可点击「搜索附近副屏」手动查找。",
        "On the other Mac, choose Display Mac to start waiting.": "在另一台 Mac 选择「这台是副屏」，即可开始等待连接。",
        "Select this Mac on the host. Paired Macs need no code.": "在主机上选择这台 Mac，已配对的 Mac 无需输码。",
        "Settings": "设置",
        "Prototype 0.1.7": "原型 0.1.7",
        "Resolution": "分辨率",
        "Pairing code": "配对码",
        "Six digits from the display Mac": "输入副屏上的六位数字",
        "Connect": "连接",
        "Connecting…": "正在连接…",
        "Disconnecting…": "正在断开…",
        "Disconnected": "已断开",
        "Ready": "准备就绪",
        "Connected": "已连接",
        "Connection test passed": "连接测试通过",
        "Last session": "上次连接",
        "Connection test": "连接测试",
        "{0} frames": "{0} 帧",
        "{0} fps": "{0} fps",
        "No saved pairings yet.": "还没有已保存的配对。",
        "Pair once with six digits. Remembered Macs need no code.": "首次用六位数字配对，已记住的 Mac 无需输码。",
        "Keep Wi-Fi on on both Macs.": "两台 Mac 的 Wi-Fi 均需保持开启。",
        "Checks the link without sharing a screen.": "仅检查连接，不传输屏幕。",
        "On the other Mac, choose Display Mac → Wait for connection.": "在另一台 Mac 选择「这台是副屏」，然后等待连接。",
        "Ready to connect": "可以连接",
        "Waiting for direct Wi-Fi…": "正在等待无线直连…",
        "Screen Recording is required on the host.": "主机需要屏幕录制权限。",
        "Valid for 5 minutes. Enter it on the host for first pairing only.": "五分钟内有效，仅首次配对时需在主机输入。",
        "Connect on the host to open this display in full screen. Press Esc to exit.": "在主机点击连接，副屏会自动全屏显示；按 Esc 可退出。",
        "Connection test passed. Disconnect, then click Connect on the host to share its display.": "连接测试通过。断开后，在主机点击「连接」即可传输屏幕。",
        "Receiving the mirrored screen. Press Esc to exit full screen.": "正在接收镜像画面，按 Esc 可退出全屏。",
        "Receiving the extended desktop. Press Esc to exit full screen.": "正在接收扩展桌面，按 Esc 可退出全屏。",
        "macOS Keychain {0} failed ({1})": "macOS 钥匙串{0}失败（{1}）",
        "list pairings": "列出配对",
        "read pairing": "读取配对",
        "save pairing": "保存配对",
        "update pairing": "更新配对",
        "forget pairing": "移除配对",
        "Code expired. Paired Macs can still connect. Choose New code to pair another Mac.": "配对码已过期，已配对的 Mac 仍可连接。添加新 Mac 时请点击「换一个码」。",
        "Paired Macs can connect without a code. Choose New code to pair a new Mac.": "已配对的 Mac 无需输码。添加新 Mac 时请点击「换一个码」。",
        "For a new Mac, enter these six digits on the host. Valid for 5 minutes and one successful connection.": "新 Mac 首次在主机输入这六位数字。五分钟内有效，成功连接后即失效。",
        "Paired Macs only": "仅限已配对的 Mac",
        "Invalid device identity": "设备身份无效",
        "Invalid saved pairing": "已保存的配对凭据无效",
        "macOS Keychain could not save or read this pairing ({0})": "macOS 钥匙串无法保存或读取配对凭据（{0}）",
        "Saved pairing is no longer available. Pair again with a new code.": "原配对已被移除，请使用新配对码重新配对。",
        "Forgot {0}. Use a new six-digit code to pair again.": "已忘记 {0}。下次请用新的六位数字码重新配对。",
        "Waiting for the display's identity. Search again and use the latest MacPair on both Macs.": "正在等待副屏的设备身份，请重新搜索，并确认两端均使用最新版 MacPair。",
        "Could not verify the saved pairing. Check Wi-Fi and the other Mac; if needed, forget this Mac and pair again.": "无法验证已保存的配对。请检查 Wi-Fi 和另一台 Mac；必要时忘记此设备并重新配对。",
        "This Mac is remembered. Future connections need no code.": "已记住这台 Mac，以后连接无需再输入配对码。",
        "Connected for this session only. Pair again after allowing Keychain access to remember this Mac.": "本次连接不会被记住。允许钥匙串访问后重新配对，即可记住这台 Mac。",
        "Paired Macs": "已配对的 Mac",
        "Forget": "忘记",
        "Forget this Mac": "忘记这台 Mac",
        "This session could not be remembered. Allow Keychain access and pair again to skip codes next time.": "未能记住此次配对。允许钥匙串访问并重新配对后，下次即可免输码。",
        "Saved pairing · No code needed": "已保存配对 · 无需输入配对码",
        "Paired · No code needed": "已配对 · 无需输入配对码",
        "Pair once with six digits. Remembered Macs reconnect without a code. Use MacPair 0.1.6 on both Macs.": "首次用六位数字配对，以后连接已记住的 Mac 无需输码。两端均需使用 MacPair 0.1.6。",
        "Prototype 0.1.6": "原型 0.1.6",
        "Cannot prepare secure pairing": "无法准备安全配对",
        "Invalid secure pairing message": "安全配对消息无效",
        "Invalid encrypted packet": "加密数据包无效",
        "Encrypted packet was altered or replayed": "加密数据包被篡改或重放",
        "Update MacPair on both Macs to use six-digit pairing": "请在两台 Mac 上更新 MacPair，以使用六位数字配对",
        "Pairing failed. Check the six-digit code currently shown on the display Mac.": "配对失败，请核对副屏当前显示的六位数字配对码。",
        "Unencrypted packet rejected": "已拒绝未加密的数据包",
        "Pairing is temporarily paused. Please wait before trying again.": "配对暂时暂停，请稍后重试。",
        "Pairing code expired. Start waiting again for a new code.": "配对码已过期，请重新开始等待以生成新码。",
        "Ready for a new code. Click Wait for connection.": "可以生成新配对码了，请点击「作为副屏等待连接」。",
        "Enter the six-digit code shown on the display Mac.": "请输入副屏显示的六位数字配对码。",
        "Pairing paused after 5 failed attempts. Wait 30 seconds, then start waiting again.": "配对失败已达五次，暂停三十秒后请重新开始等待。",
        "Secure pairing verified · SPAKE2 + AES-256-GCM": "安全配对已验证 · SPAKE2 + AES-256-GCM",
        "Six-digit code from the display Mac": "输入副屏上的六位数字配对码",
        "Paired. A new code will appear after disconnecting.": "已配对，断开后会生成新的配对码。",
        "Enter these six digits on the host. Valid for 5 minutes and one successful connection.": "在主机输入这六位数字。五分钟内有效，成功连接后即失效。",
        "New code": "换一个码",
        "Use MacPair 0.1.6 on both Macs for six-digit pairing.": "两端均使用 MacPair 0.1.6，即可用六位数字配对。",
        "Prototype 0.1.5": "原型 0.1.5",
        "macOS rejected the extended display configuration ({0})": "macOS 拒绝了扩展屏配置（{0}）",
        "Display resolution": "显示分辨率",
        "Larger Text": "更大文字",
        "Default (Recommended)": "默认（推荐）",
        "More Space": "更多空间",
        "Default matches the display Mac. Larger Text increases text size; More Space fits more windows. Reconnect to change.": "默认匹配副屏 Mac；更大文字使文字更大；更多空间可放下更多窗口。更改后需重新连接。",
        "Up to 30 fps. Extend matches the display Mac with Retina scaling. Aspect ratio is preserved.": "目标 30 fps。扩展屏匹配副屏 Mac 的 Retina 缩放，并保持画面比例。",
        "The display Mac needs no Screen Recording permission. Video opens in full screen automatically. Double-click or press Esc to exit full screen.": "副屏无需屏幕录制权限。连接后自动全屏显示；双击或按 Esc 可退出全屏。",
        "The display Mac reported invalid screen dimensions": "副屏 Mac 上报的屏幕尺寸无效",
        "This resolution is too large for this prototype. Choose Larger Text and reconnect.": "此分辨率超出当前原型的处理范围，请选择「更大文字」后重新连接。",
        "MacPair versions differ. Update MacPair on both Macs and reconnect.": "两端 MacPair 版本不同，请在两台 Mac 上更新后重新连接。",
        "macOS did not offer the requested Retina display mode": "macOS 未提供所需的 Retina 显示模式",
        "macOS rejected the requested Retina display mode": "macOS 拒绝了所需的 Retina 显示模式",
        "Matching the display Mac's resolution…": "正在匹配副屏 Mac 的分辨率…",
        "Cannot enter full screen on the display Mac. Close other full-screen windows and reconnect.": "副屏 Mac 无法进入全屏，请关闭其他全屏窗口后重新连接。",
        "Receiver {0}: {1} × {2} pt, {3} × {4} px, {5}×": "副屏 {0}：{1} × {2} 逻辑点，{3} × {4} 像素，{5}×",
        "Full-screen viewport: {0} × {1} pt, {2} × {3} px": "全屏画面区域：{0} × {1} 逻辑点，{2} × {3} 像素",
        "Desktop: {0} × {1} pt at {2}×; stream: {3} × {4} px": "桌面：{0} × {1} 逻辑点，{2}×；传输：{3} × {4} 像素",
        "Stream {0} × {1} px · {2} fps": "传输 {0} × {1} 像素 · {2} fps",
        "Waiting for video…": "等待画面…",
        "Desktop {0} × {1} pt · {2}×": "桌面 {0} × {1} 逻辑点 · {2}×",
        "Creating a Retina-aware extended desktop…": "正在创建适配 Retina 的扩展桌面…",
        "Virtual display {0}: {1} × {2} pixels, H.264 up to {3} fps": "虚拟显示器 {0}：{1} × {2} 像素，H.264 目标 {3} fps",
        "Cannot read the display Mac's screen settings": "无法读取副屏 Mac 的显示设置",
        "The video dimensions do not match the negotiated display": "视频尺寸与协商的显示尺寸不匹配",
        "Capture source: {0} × {1}; encoder: {2} × {3} px; bitrate {4} Mbps": "捕获来源：{0} × {1}；编码：{2} × {3} 像素；码率 {4} Mbps",
        "Screen capture returned unexpected pixel dimensions": "屏幕捕获返回的像素尺寸与预期不同",
        "Actual captured frame: {0} × {1} px": "实际捕获帧：{0} × {1} 像素",
        "Display mode": "显示模式",
        "Extend": "扩展",
        "Mirror": "镜像",
        "Prototype 0.1.2": "原型 0.1.2",
        "Prototype 0.1.3": "原型 0.1.3",
        "Prototype 0.1.4": "原型 0.1.4",
        "Extend adds a separate desktop; drag windows onto it.": "扩展会创建独立桌面，可以把窗口拖进去。",
        "Mirror shows the host's main screen on the display Mac.": "镜像会在副屏 Mac 上显示主机的主屏幕。",
        "Mirror display": "开始镜像",
        "Start with Test connection. Disconnect after it passes, choose a display mode, then start streaming.": "先点击「测试直连」。通过后断开，选择显示模式，再开始传输。",
        "Up to 30 fps. Mirror uses your main screen; Extend adds a 1280 × 800 desktop.": "目标 30 fps。镜像显示主屏幕；扩展增加 1280 × 800 独立桌面。",
        "Use the host's keyboard and trackpad. Display-side input and audio are not included yet.": "请使用主机的键盘和触控板操作。首版不转发副屏输入或声音。",
        "Connection test passed. Disconnect on the host, choose Mirror or Extend, then start streaming.": "直连测试通过。在主机上断开，选择镜像或扩展，再开始传输。",
        "Connected. Waiting for the mirrored screen…": "已连接，等待镜像画面…",
        "Receiving the mirrored screen. Double-click the video to toggle full screen.": "正在接收镜像画面。双击画面可切换全屏。",
        "Preparing the host's main screen for mirroring…": "正在准备镜像主机的主屏幕…",
        "Mirroring the host's main screen. Open or move a window to check the other Mac.": "正在镜像主机的主屏幕。打开或移动窗口，即可在另一台 Mac 上查看。",
        "Mirror source {0}: {1} × {2}, H.264 up to {3} fps": "镜像来源 {0}：{1} × {2}，H.264 目标 {3} fps",
        "The main display is no longer available for mirroring": "用于镜像的主屏幕已不可用",
        "Screen capture could not find the selected display": "屏幕捕获未找到选定的显示器",
        "Cannot scale this screen for mirroring": "无法为此屏幕生成镜像分辨率",
        "Host Mac": "这台是主机",
        "Display Mac": "这台是副屏",
        "Your nearby Mac. Your second display.": "两台 Mac，近距离无线扩展屏",
        "Prototype 0.1": "原型 0.1",
        "Prototype 0.1.1": "原型 0.1.1",
        "Looking for displays…": "正在搜索副屏…",
        "On the other Mac, open MacPair, select Display Mac, and click Wait for connection.": "在另一台 Mac 打开 MacPair，选择「这台是副屏」，然后开始等待连接。",
        "No router, internet, or Apple ID needed. Keep Wi-Fi on; Bluetooth is recommended.": "无需路由器、互联网或 Apple ID。两端 Wi-Fi 保持开启，蓝牙建议开启。",
        "This Mac's role": "这台 Mac 的角色",
        "Round trip {0}": "往返 {0}",
        "{0} fps · {1} frames": "{0} fps · {1} 帧",
        "Disconnect": "断开连接",
        "Open display": "打开副屏画面",
        "Full screen": "副屏全屏",
        "Arrange displays": "调整显示器排列",
        "Diagnostics": "诊断信息",
        "Copy diagnostics": "复制诊断信息",
        "1280 × 800, up to 30 fps. Use the host's keyboard and trackpad. Experimental virtual display API.": "首版：1280 × 800，目标 30 fps；使用主机键盘和触控板操作。虚拟屏依赖 macOS 非公开接口。",
        "Nearby displays": "附近的副屏",
        "Search again": "重新搜索",
        "Find nearby displays": "搜索附近副屏",
        "Looking for displays… On the other Mac, open MacPair, select Display Mac, and click Wait for connection.": "等待发现… 请在另一台 Mac 打开 MacPair，选择「这台是副屏」并开始等待连接。",
        "Start waiting on the other Mac, then search here.": "先让另一台 Mac 等待连接，再点击搜索。",
        "Direct AWDL available · {0}": "AWDL 直连可用 · {0}",
        "Waiting for a direct interface · {0}": "尚未发现点对点接口 · {0}",
        "Pairing code from the display Mac": "输入副屏上的配对码，例如 024681",
        "Test connection": "测试直连",
        "Extend display": "开始扩展",
        "Screen Recording permission is required on the host.": "镜像和扩展均需主机的屏幕录制权限。",
        "Grant Screen Recording": "授权屏幕录制",
        "Start with Test connection. Disconnect after it passes, then choose Extend display. The new desktop appears to the right.": "首次可先点「测试直连」。测试通过后断开，再点「开始扩展」。副屏默认出现在主屏右侧。",
        "Use this Mac as a second display": "让这台 Mac 成为另一台的第二块屏幕",
        "Enter this code on the host. A new code is generated each time you start waiting.": "把配对码输入主机（每次重新等待时更新）",
        "Stop waiting": "停止等待",
        "Wait for connection": "作为副屏等待连接",
        "The display Mac needs no Screen Recording permission. Its video window opens automatically. Double-click for full screen; press Esc to exit.": "副屏无需屏幕录制权限。连接后会自动打开画面窗口；双击画面切换全屏，Esc 退出全屏。",
        "Control the extended desktop with the host's keyboard and trackpad. Display-side input and audio are not included yet.": "用主机的鼠标和键盘操作扩展桌面。首版不转发副屏的鼠标、键盘或声音。",
        "Place both Macs nearby. Select Display Mac on the other Mac.": "把两台 Mac 放在附近，在另一台上选择「这台是副屏」。",
        "Not connected": "尚未连接",
        "Looking for nearby displays… Keep Wi-Fi on on both Macs.": "正在寻找附近的副屏… 两端 Wi-Fi 必须开启。",
        "Discovery failed: {0}. Check Local Network permission.": "发现失败：{0}。检查本地网络权限。",
        "Waiting for network: {0}": "等待网络：{0}",
        "Waiting for the host. Select this Mac on the host and enter the pairing code below.": "等待主机连接。在主机上选择这台 Mac，并输入下方配对码。",
        "Display advertising via Bonjour with peer-to-peer Wi-Fi enabled": "副屏正在广播 Bonjour，已启用点对点 Wi-Fi",
        "Listener failed: {0}": "监听失败：{0}",
        "Verifying pairing…": "正在验证配对…",
        "Select a display with a direct AWDL interface.": "请选择已发现 AWDL 点对点接口的副屏。",
        "Enter the complete 12-character code shown on the display Mac.": "请输入副屏显示的完整 12 位配对码。",
        "The host needs Screen Recording permission. Click Grant Screen Recording, allow access, then quit and reopen the app.": "主机需要屏幕录制权限。点击「授权屏幕录制」，授权后退出并重新打开 App。",
        "Establishing an encrypted connection over {0}…": "正在通过 {0} 与副屏建立加密连接…",
        "Connection restricted to {0}; router-network fallback is disabled": "连接接口限定为 {0}，禁止自动回退到路由器网络",
        "TLS pairing verified": "TLS 配对验证成功",
        "Session handshake timed out": "会话握手超时",
        "Invalid session sequence": "会话顺序无效",
        "Connection test passed. Disconnect on the host, then choose Extend display.": "直连测试通过。主机可以结束测试，再开始扩展。",
        "Connected. Waiting for the extended desktop…": "已连接，等待扩展屏画面…",
        "The display returned incompatible parameters": "副屏返回了不匹配的参数",
        "AWDL connection test passed. Round-trip time is shown below.": "AWDL 直连测试通过。下方显示连接往返时间。",
        "Peer-to-peer session handshake completed": "已完成点对点应用握手",
        "Video session has not been negotiated": "尚未协商视频会话",
        "Video display failed: {0}": "视频显示失败：{0}",
        "unknown error": "未知错误",
        "Receiving the extended desktop. Double-click the video to toggle full screen.": "正在接收扩展屏。双击画面可切换全屏。",
        "First H.264 frame received": "已收到第一帧 H.264 画面",
        "Peer reported: {0}": "对方报告：{0}",
        "Creating a 1280 × 800 extended desktop…": "正在创建 1280 × 800 扩展屏…",
        "Screen streaming failed: {0}": "屏幕传输失败：{0}",
        "Extended desktop is ready. Drag a window past the host desktop's right edge.": "扩展屏已启动。用主机鼠标把窗口拖出桌面右边缘。",
        "Virtual display {0}: 1280 × 800, extended desktop, H.264 up to 30 fps": "虚拟显示器 {0}：1280 × 800，独立桌面，H.264 目标 30 fps",
        "Connection ended": "连接已结束",
        "Ending session…": "正在结束会话…",
        "{0} Waiting for the host to reconnect.": "{0}。正在等待主机重新连接。",
        "Stopped": "已停止",
        "Allow MacPair in System Settings, then quit and reopen this app.": "请在系统设置中允许 MacPair 录制屏幕，然后退出并重新打开此 App。",
        "MacPair Display · Double-click to toggle full screen": "MacPair 副屏 · 双击切换全屏",
        "Pairing failed. Check the code currently shown on the display Mac.": "配对验证失败，请核对副屏当前显示的配对码",
        "Connection failed (check the code, Wi-Fi, and Local Network permission): {0}": "连接失败（检查配对码、Wi-Fi 和本地网络权限）：{0}",
        "Connection closed": "连接已关闭",
        "Connection timed out. Check the pairing code, Wi-Fi, and Local Network permission.": "连接超时：检查两端配对码、Wi-Fi 和本地网络权限",
        "Network path: {0}": "网络路径：{0}",
        "waiting for interface": "等待接口",
        "Send failed: {0}": "发送失败：{0}",
        "Invalid heartbeat packet": "无效的心跳包",
        "Invalid heartbeat reply": "无效的心跳回包",
        "Receive failed: {0}": "接收失败：{0}",
        "The other Mac disconnected": "对方已断开连接",
        "The other Mac stopped responding. Connection closed.": "对方已失去响应，连接已关闭",
        "Invalid or oversized packet": "收到无效或过大的数据包",
        "Unsupported packet type": "不支持的数据包类型",
        "Incompatible protocol version or display settings": "两端版本或画面参数不兼容",
        "{0} failed ({1})": "{0}失败（{1}）",
        "Video encoding failed ({0})": "视频编码失败（{0}）",
        "Create H.264 encoder": "创建 H.264 编码器",
        "No H.264 encoder is available": "没有可用的 H.264 编码器",
        "Set H.264 property {0}": "设置 H.264 参数 {0}",
        "Prepare encoder": "准备编码",
        "The encoder has stopped": "编码器已停止",
        "Encode frame": "编码画面",
        "Encoded output is not readable": "编码结果不可读取",
        "Cannot read H.264 configuration": "无法读取 H.264 参数",
        "Cannot read video frame": "无法读取视频帧",
        "Incomplete H.264 configuration": "H.264 参数不完整",
        "Invalid H.264 SPS length": "H.264 SPS 长度无效",
        "Invalid H.264 PPS length": "H.264 PPS 长度无效",
        "Parse video configuration": "解析视频参数",
        "Video format is not ready": "视频格式尚未就绪",
        "Incomplete video frame header": "视频帧头不完整",
        "Invalid video frame length": "视频帧长度无效",
        "Allocate video buffer": "分配视频缓冲",
        "Cannot allocate video buffer": "无法分配视频缓冲",
        "Copy video data": "复制视频数据",
        "Create video sample": "创建视频样本",
        "Cannot create video sample": "无法创建视频样本",
        "Screen capture could not find the virtual display": "屏幕捕获没有找到虚拟显示器",
        "This system could not create a virtual display (experimental macOS API)": "此系统无法创建虚拟显示器（使用 macOS 非公开接口）",
        "The virtual display did not come online": "虚拟显示器没有上线",
        "Cannot read display arrangement": "无法读取显示器排列",
        "Cannot configure display arrangement": "无法设置显示器排列",
        "Cannot enable the extended desktop": "无法将虚拟显示器设为扩展屏",
        "macOS rejected the extended display configuration": "macOS 拒绝了扩展屏配置",
        "The virtual display is still mirrored": "虚拟显示器仍处于镜像模式",
        "Language": "语言"
    ]
}

/// Keep the message template and its arguments, so changing language also
/// updates existing status messages and diagnostic events.
struct LocalizedMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, CustomStringConvertible {
    indirect enum Argument {
        case value(String)
        case message(LocalizedMessage)
        var localized: String {
            switch self { case .value(let value): return value; case .message(let message): return message.localized }
        }
    }
    let key: String
    let arguments: [Argument]
    let verbatim: Bool
    init(stringLiteral value: String) { key = value; arguments = []; verbatim = false }
    init(verbatim value: String) { key = value; arguments = []; verbatim = true }
    init(stringInterpolation value: StringInterpolation) {
        key = value.key; arguments = value.arguments; verbatim = false
    }
    struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [Argument] = []
        init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity) }
        mutating func appendLiteral(_ literal: String) { key += literal }
        mutating func appendInterpolation(_ value: LocalizedMessage) {
            key += "{\(arguments.count)}"; arguments.append(.message(value))
        }
        mutating func appendInterpolation<T>(_ value: T) {
            key += "{\(arguments.count)}"; arguments.append(.value(String(describing: value)))
        }
    }
    var localized: String {
        let pattern = verbatim ? key : L10n.text(key)
        // Scan the template once, so an argument containing "{0}" cannot
        // accidentally become a second formatting instruction.
        var result = ""
        var cursor = pattern.startIndex
        while cursor < pattern.endIndex {
            if pattern[cursor] == "{", let end = pattern[cursor...].firstIndex(of: "}"),
               let index = Int(pattern[pattern.index(after: cursor)..<end]), arguments.indices.contains(index) {
                result += arguments[index].localized
                cursor = pattern.index(after: end)
            } else { result.append(pattern[cursor]); cursor = pattern.index(after: cursor) }
        }
        return result
    }
    var description: String { localized }
}
func L(_ message: LocalizedMessage) -> String { message.localized }
extension Error {
    var appMessage: LocalizedMessage {
        if let pairError = self as? PairError, case .message(let message) = pairError { return message }
        return LocalizedMessage(verbatim: localizedDescription)
    }
}
