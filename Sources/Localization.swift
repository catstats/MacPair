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
        "Pairing code from the display Mac": "输入副屏上的配对码，例如 ABCD-EFGH-JKLM",
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
