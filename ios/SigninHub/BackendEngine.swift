import Foundation
import Combine

/// 内置 Python 后端的生命周期管理。
///
/// 设计取舍（为什么不是纯 Swift 重写签到逻辑）：
/// 签到接口签名、设备指纹派生、Cookie 刷新这些逻辑在 backend/signbot/ 里
/// 已经有 6 家平台的完整实现和大量线上修复记录。在 iOS 侧重写一遍等于维护
/// 两份会逐渐分叉的协议代码，而且第一版必然比 Python 那份多 bug。
/// 所以这里把**同一份后端**随 App 打包进 bundle，在本机 127.0.0.1 上跑，
/// WKWebView 加载它的控制台。签到逻辑只有一份，Android / iOS / 电脑端共用。
///
/// 代价：安装包大一截（要带 Python 运行时），首次启动慢一点。
/// 换来的是「协议改动只改一处」。
@MainActor
final class BackendEngine: ObservableObject {

    enum State {
        case starting(String)
        case ready(URL, String)
        case failed(String)
    }

    @Published private(set) var state: State = .starting("准备资源…")

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var logBuffer = ""
    private var token = ""
    private let port = 8787

    // MARK: - 对外

    func start() {
        guard process == nil else { return }
        state = .starting("准备资源…")

        guard let root = Bundle.main.resourceURL?.appendingPathComponent("backend") else {
            state = .failed("App 内缺少 backend 资源目录")
            return
        }
        let runner = root.appendingPathComponent("run.py")
        guard FileManager.default.fileExists(atPath: runner.path) else {
            state = .failed("找不到 backend/run.py\n打包时漏了 Resources/backend")
            return
        }
        guard let py = pythonPath(root: root) else {
            state = .failed("找不到 Python 运行时。\n\n这一版是给 GitHub Actions 出包的占位实现：\n脚本会在 CI 里用 python-build-standalone 把 CPython 塞进 \nResources/python/，本地直接 xcodebuild 会缺这一步。")
            return
        }

        token = loadOrCreateToken(root: root)
        seedConfig(root: root)

        state = .starting("启动本地服务…")
        launch(python: py, runner: runner, root: root)
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    // MARK: - 内部

    private func pythonPath(root: URL) -> String? {
        let candidates = [
            root.appendingPathComponent("python/bin/python3"),
            root.appendingPathComponent("python/bin/python3.12"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }?.path
    }

    private func dataDir(root: URL) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
            .appendingPathComponent("SigninHub", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.completeUnlessOpen])
        return base
    }

    /// 口令存 Keychain（与 SecretBox 对等），不在磁盘上留明文。
    private func loadOrCreateToken(root: URL) -> String {
        if let saved = KeychainBox.read(account: "api_token"), !saved.isEmpty {
            return saved
        }
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let t = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        KeychainBox.write(t, account: "api_token")
        return t
    }

    /// 首次启动往数据目录写 config.json：只监听回环，端口固定，口令从 Keychain 取。
    private func seedConfig(root: URL) {
        let dir = dataDir(root: root)
        let cfgURL = dir.appendingPathComponent("config.json")
        if FileManager.default.fileExists(atPath: cfgURL.path) { return }

        // 让后端把 data 目录指到沙盒可写位置（见 run.py 的 SIGNHUB_DATA 支持）
        setenv("SIGNHUB_DATA", dir.path, 1)
        setenv("SIGNHUB_TOKEN", token, 1)

        let cfg: [String: Any] = [
            "server": ["host": "127.0.0.1", "port": port, "api_token": token],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: cfg, options: [.prettyPrinted]) {
            try? data.write(to: cfgURL, options: [.atomic, .completeFileProtection])
        }
    }

    private func launch(python: String, runner: URL, root: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: python)
        p.arguments = [runner.path]
        p.currentDirectoryURL = root
        var env = ProcessInfo.processInfo.environment
        env["SIGNHUB_DATA"] = dataDir(root: root).path
        env["SIGNHUB_TOKEN"] = token
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        stdoutPipe = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
            Task { @MainActor in self?.ingest(text) }
        }

        do {
            try p.run()
            process = p
        } catch {
            state = .failed("Process.run 失败：\(error.localizedDescription)")
        }
    }

    /// 从后端 stdout 里认「SigninHub 已启动」，然后放行 WebView。
    /// 不用轮询 /api/ping —— 那条会先撞 401，且 200ms 一次太吵。
    private func ingest(_ text: String) {
        logBuffer += text
        if logBuffer.count > 8000 { logBuffer = String(logBuffer.suffix(4000)) }

        if case .starting = state, logBuffer.contains("SigninHub 已启动") {
            guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return }
            // 给 uvicorn/http.server 一点时间真正 listen
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self else { return }
                if case .starting = self.state {
                    self.state = .ready(url, self.token)
                }
            }
        }
        if logBuffer.contains("Traceback") || logBuffer.contains("端口 \(port) 无法绑定") {
            state = .failed(logBuffer.suffix(1200).description)
        }
    }
}

