import SwiftUI

/// 根视图：启动时拉起内置 Python 后端，起好之后把 WebView 铺满。
struct RootView: View {
    @EnvironmentObject private var engine: BackendEngine

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.06).ignoresSafeArea()

            switch engine.state {
            case .starting(let msg):
                LoadingScreen(title: "正在启动签到引擎", detail: msg)
            case .ready(let url, let token):
                WebShell(url: url, token: token)
                    .ignoresSafeArea(edges: .bottom)
            case .failed(let msg):
                ErrorScreen(message: msg) { engine.start() }
            }
        }
        .task { engine.start() }
    }
}

private struct LoadingScreen: View {
    let title: String
    let detail: String
    @State private var spin = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52, weight: .regular))
                .foregroundStyle(.linearGradient(colors: [.cyan, .blue],
                                                 startPoint: .topLeading,
                                                 endPoint: .bottomTrailing))
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 2.4).repeatForever(autoreverses: false),
                           value: spin)
            Text(title).font(.headline)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .onAppear { spin = true }
    }
}

private struct ErrorScreen: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("引擎启动失败").font(.headline)
            ScrollView {
                Text(message)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 260)
            .padding(12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

            Button("重试", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
}

