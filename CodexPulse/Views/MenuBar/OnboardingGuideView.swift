import SwiftUI
#if os(macOS)
import AppKit
#endif

/// 首启 / 异常引导：CLI 未安装、未登录、连接失败时给出分步指引，
/// 替代原本只有一行错误文本的空白面板。
struct OnboardingGuideView: View {
    @Environment(PulseStore.self) private var store

    enum GuideKind {
        case cliMissing
        case notLoggedIn
        case connectFailed

        var title: String {
            switch self {
            case .cliMissing: return "未检测到 Codex CLI"
            case .notLoggedIn: return "Codex 尚未登录"
            case .connectFailed: return "无法连接 Codex App Server"
            }
        }

        var icon: String {
            switch self {
            case .cliMissing: return "terminal"
            case .notLoggedIn: return "person.crop.circle.badge.exclamationmark"
            case .connectFailed: return "bolt.horizontal.circle"
            }
        }
    }

    /// 根据当前状态判断需要展示哪种引导；一切正常时返回 nil。
    static func kind(for store: PulseStore) -> GuideKind? {
        guard !store.isUsingMock else { return nil }
        if store.cliPath == nil { return .cliMissing }
        let snapshot = store.snapshot
        if snapshot.connectionState == .connected || snapshot.connectionState == .degraded {
            if !snapshot.account.isLoggedIn { return .notLoggedIn }
            return nil
        }
        // 尚未成功连接过（没有任何账号数据）才整屏引导；短暂断线时保留原面板。
        if snapshot.connectionState == .error || snapshot.connectionState == .disconnected,
           !snapshot.account.isLoggedIn,
           snapshot.rateLimits.buckets.isEmpty {
            return .connectFailed
        }
        return nil
    }

    let kind: GuideKind

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: kind.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(PulseTheme.blue)
                Text(kind.title)
                    .font(.system(size: 13, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 8) {
                switch kind {
                case .cliMissing:
                    step(1, "安装 Codex CLI：在终端执行", code: "npm install -g @openai/codex")
                    step(2, "或使用 Homebrew：", code: "brew install codex")
                    step(3, "安装完成后点击下方「重新检测」")
                case .notLoggedIn:
                    step(1, "在终端执行", code: "codex login")
                    step(2, "按提示在浏览器完成 ChatGPT 授权")
                    step(3, "回到这里点击「重新检测」")
                case .connectFailed:
                    step(1, "确认 Codex CLI 可用：", code: "codex --version")
                    step(2, "手动验证 App Server：", code: "codex app-server")
                    step(3, "如仍失败，点击「复制诊断」并反馈")
                }
            }

            HStack(spacing: 8) {
                Button("重新检测") {
                    Task { await store.reconnect() }
                }
                .buttonStyle(GlassButtonStyle())

                if kind == .connectFailed {
                    Button("复制诊断") {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(store.copyDiagnostics(), forType: .string)
                        #endif
                    }
                    .buttonStyle(GlassButtonStyle())
                }

                if kind == .cliMissing {
                    Button("安装指南") {
                        #if os(macOS)
                        if let url = URL(string: "https://developers.openai.com/codex/cli") {
                            NSWorkspace.shared.open(url)
                        }
                        #endif
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func step(_ index: Int, _ text: String, code: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(PulseTheme.blue.opacity(0.85)))
            VStack(alignment: .leading, spacing: 3) {
                Text(text)
                    .font(.system(size: 11.5))
                if let code {
                    Text(code)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)))
                        .textSelection(.enabled)
                }
            }
        }
    }
}
