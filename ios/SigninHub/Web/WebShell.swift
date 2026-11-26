import SwiftUI
import WebKit

/// WKWebView 壳 + 安全区适配。
///
/// 只加载本机 127.0.0.1，不挂 WKScriptMessageHandler：
/// 后端就在本机，网页直接 fetch 即可，不需要 Android 那套 JS 桥
/// （也就没有 trusted() 那个来源判定需要维护）。
struct WebShell: UIViewRepresentable {
    let url: URL
    let token: String

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        // 本机 HTTP：App Transport Security 需要例外，Info.plist 里已声明
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true

        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        web.scrollView.contentInsetAdjustmentBehavior = .always
        web.allowsBackForwardNavigationGestures = false
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)
        web.scrollView.backgroundColor = web.backgroundColor

        // 先把口令塞进 localStorage 再加载页面：
        // app.js 读的是 sessionStorage.signhub_token，页面同源，这里注入的能活到脚本执行。
        let js = """
        try {
          sessionStorage.setItem('signhub_token', \(jsString(token)));
          localStorage.setItem('signhub_base', '');
        } catch (e) {}
        """
        let script = WKUserScript(source: js,
                                  injectionTime: .atDocumentStart,
                                  forMainFrameOnly: true)
        web.configuration.userContentController.addUserScript(script)

        web.load(URLRequest(url: url))
        context.coordinator.web = web
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func jsString(_ s: String) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: [s], options: []),
              let arr = String(data: d, encoding: .utf8) else { return "\"\"" }
        return String(arr.dropFirst().dropLast())
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var web: WKWebView?

        /// 外部链接一律丢给系统浏览器，WebView 只承载本机控制台。
        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let u = action.request.url else { return decisionHandler(.cancel) }
            if u.host == "127.0.0.1" || u.host == "localhost" {
                return decisionHandler(.allow)
            }
            if u.scheme == "http" || u.scheme == "https" {
                UIApplication.shared.open(u)
            }
            decisionHandler(.cancel)
        }
    }
}

