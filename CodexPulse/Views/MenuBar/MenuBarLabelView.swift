import SwiftUI

/// 菜单栏图标：状态色 + 百分比/「Pulse」，更容易找到
struct MenuBarLabelView: View {
    @Environment(PulseStore.self) private var store

    var body: some View {
        HStack(spacing: 4) {
            statusIcon
                .foregroundStyle(statusColor)
            Text(labelText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 28, alignment: .leading)
                .layoutPriority(1)
        }
        .fixedSize(horizontal: true, vertical: true)
        .help(statusHelp)
        .onAppear {
            store.start()
            #if os(macOS)
            FloatingCapsuleController.shared.restoreIfNeeded(store: store)
            #endif
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if showsChatGPTIcon {
            Image("ChatGPTMenuIcon")
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: iconName)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var showsChatGPTIcon: Bool {
        guard !store.snapshot.currentTask.state.needsAttention else { return false }
        switch store.snapshot.statusColor {
        case .green, .blue, .yellow:
            return true
        case .red, .gray:
            return false
        }
    }

    private var labelText: String {
        if let p = store.snapshot.rateLimits.primaryBucket {
            return PulseFormatters.percent(p.remainingPercent)
        }
        if store.snapshot.account.authMode == .apiKey {
            return "API"
        }
        return "--%"
    }

    private var iconName: String {
        switch store.snapshot.statusColor {
        case .blue: return "waveform.path.ecg"
        case .yellow:
            if store.snapshot.currentTask.state.needsAttention {
                return "exclamationmark.triangle.fill"
            }
            return "circle"
        case .red: return "xmark.octagon.fill"
        case .gray: return "circle.dashed"
        case .green: return "circle.fill"
        }
    }

    private var statusHelp: String {
        if store.snapshot.currentTask.state.needsAttention {
            return "Codex-Pulse · \(store.snapshot.currentTask.state.rawValue)"
        }
        if store.snapshot.connectionState == .degraded {
            return "Codex-Pulse · 部分数据同步异常"
        }
        if store.snapshot.account.authMode == .apiKey,
           store.snapshot.rateLimits.primaryBucket == nil {
            return "Codex-Pulse · API Key 按 Token 计费"
        }
        if let primary = store.snapshot.rateLimits.primaryBucket,
           primary.remainingPercent < 80 {
            return "Codex-Pulse · 主额度剩余 \(PulseFormatters.percent(primary.remainingPercent))"
        }
        return "Codex-Pulse · \(store.snapshot.taskStatusLabel)"
    }

    private var statusColor: Color {
        // 不依赖 PulseTheme，避免主题文件未编译时找不到符号
        switch store.snapshot.statusColor {
        case .green: return Color(red: 0.20, green: 0.78, blue: 0.35)
        case .blue: return Color(red: 0.04, green: 0.52, blue: 1.0)
        case .yellow: return Color(red: 1.0, green: 0.84, blue: 0.04)
        case .red: return Color(red: 1.0, green: 0.27, blue: 0.23)
        case .gray: return Color(red: 0.56, green: 0.56, blue: 0.58)
        }
    }
}
