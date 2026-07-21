import SwiftUI

struct ModelLeaderboardsView: View {
    @Environment(ArtificialAnalysisLeaderboardStore.self) private var rankings

    var body: some View {
        DashboardPanel(title: "模型排行榜", systemImage: "trophy") {
            header

            if let error = rankings.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(PulseTheme.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PulseTheme.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            }

            if let snapshot = rankings.snapshot {
                let qualityLeaders = snapshot.qualityLeaders.filter { $0.isOpenAI }
                let costLeaders = snapshot.costLeaders.filter { $0.isOpenAI }
                let speedLeaders = snapshot.speedLeaders.filter { $0.isOpenAI }

                HStack(alignment: .top, spacing: 12) {
                    LeaderboardColumn(
                        title: "模型质量",
                        subtitle: "Intelligence Index · 越高越好",
                        systemImage: "brain.head.profile",
                        tint: PulseTheme.blue,
                        metric: .quality,
                        models: Array(qualityLeaders.prefix(6))
                    )
                    LeaderboardColumn(
                        title: "任务成本",
                        subtitle: "每个 Intelligence 任务 · 越低越好",
                        systemImage: "dollarsign.circle",
                        tint: PulseTheme.green,
                        metric: .cost,
                        models: Array(costLeaders.prefix(6))
                    )
                    LeaderboardColumn(
                        title: "输出速度",
                        subtitle: "输出 Token/秒 · 越高越好",
                        systemImage: "speedometer",
                        tint: PulseTheme.orange,
                        metric: .speed,
                        models: Array(speedLeaders.prefix(6))
                    )
                }

                HStack(spacing: 5) {
                    Image(systemName: "info.circle")
                    Text("排名来自独立基准测试；速度为各模型服务商的中位数，实际体验会随地区与负载变化。")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            } else if rankings.isLoading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("正在获取模型基准数据…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "key.horizontal")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(PulseTheme.blue)
                    Text("填写 Artificial Analysis API Key 后显示排行榜")
                        .font(.headline)
                    Text("密钥只保存在本机 macOS Keychain，不会写入源码、日志或共享快照。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SettingsLink {
                        Label("打开设置", systemImage: "gearshape")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            }
        }
        .onAppear { rankings.start() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let snapshot = rankings.snapshot {
                Text("AA Intelligence Index v\(formatVersion(snapshot.intelligenceIndexVersion))")
                Text("·")
                Text("仅 OpenAI · \(snapshot.models.filter { $0.isOpenAI }.count) 个模型")
                Text("·")
                Text("更新于 \(PulseFormatters.relativeDate(snapshot.fetchedAt))")
            } else {
                Text(rankings.hasAPIKey ? "等待首次同步" : "尚未配置 API Key")
            }

            Spacer()

            if let sourceURL = URL(string: "https://artificialanalysis.ai/") {
                Link(destination: sourceURL) {
                    Label("数据来源 Artificial Analysis", systemImage: "arrow.up.right.square")
                }
                .help("打开 Artificial Analysis")
            }

            Button {
                Task { await rankings.refresh(force: true) }
            } label: {
                if rankings.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .frame(width: 28, height: 28)
            .disabled(!rankings.hasAPIKey || rankings.isLoading)
            .help("刷新排行榜")
            .accessibilityLabel("刷新 Artificial Analysis 排行榜")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func formatVersion(_ value: Double) -> String {
        value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

}

private enum LeaderboardMetric {
    case quality
    case cost
    case speed

    func value(for model: ArtificialAnalysisModel) -> String {
        switch self {
        case .quality:
            return model.intelligenceIndex.map { String(format: "%.1f", $0) } ?? "—"
        case .cost:
            guard let cost = model.costPerTaskUSD else { return "—" }
            return cost < 0.01
                ? String(format: "$%.4f", cost)
                : String(format: "$%.3f", cost)
        case .speed:
            return model.outputTokensPerSecond.map { String(format: "%.0f t/s", $0) } ?? "—"
        }
    }

    func detail(for model: ArtificialAnalysisModel) -> String {
        switch self {
        case .quality:
            return model.codingIndex.map { "编程指数 \(String(format: "%.1f", $0))" }
                ?? "暂无编程指数"
        case .cost:
            return model.intelligenceIndex.map { "质量指数 \(String(format: "%.1f", $0))" }
                ?? "暂无质量指数"
        case .speed:
            return model.timeToFirstTokenSeconds.map { "首 Token \(String(format: "%.2fs", $0))" }
                ?? "暂无首 Token 数据"
        }
    }
}

private struct LeaderboardColumn: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let metric: LeaderboardMetric
    let models: [ArtificialAnalysisModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            VStack(spacing: 4) {
                ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                    LeaderboardRow(
                        rank: index + 1,
                        model: model,
                        value: metric.value(for: model),
                        detail: metric.detail(for: model),
                        tint: tint
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct LeaderboardRow: View {
    let rank: Int
    let model: ArtificialAnalysisModel
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(rank <= 3 ? tint : Color.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text("\(model.creator.name) · \(detail)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(value)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 44)
        .background(
            rank == 1 ? tint.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(rank) 名，\(model.name)，\(value)，\(detail)")
    }
}
