import SwiftUI

struct ResetPredictionView: View {
    @Environment(PulseStore.self) private var pulseStore
    @Environment(CodexResetPredictionStore.self) private var predictionStore

    var body: some View {
        DashboardPanel(title: "额外额度重置预测", systemImage: "waveform.path.ecg") {
            if !predictionStore.isEnabled {
                disabledState
            } else if predictionStore.isLoading && predictionStore.snapshot.updatedAt == .distantPast {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("正在读取官方与第三方 RSS 信号…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                predictionContent
            }
        }
        .onAppear { predictionStore.start() }
    }

    private var disabledState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(PulseTheme.blue)
            Text("额外额度重置预测尚未启用")
                .font(.headline)
            Text("仅预测补偿重置、临时扩容和官方活动；正常 5 小时及每周恢复仍使用原有倒计时。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            SettingsLink {
                Label("打开设置", systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private var predictionContent: some View {
        let snapshot = predictionStore.snapshot
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label("透明规则评分", systemImage: "list.bullet.clipboard")
                Text("·")
                Text("更新于 \(PulseFormatters.relativeDate(snapshot.updatedAt))")
                Spacer()
                Button {
                    Task { await predictionStore.refresh(force: true) }
                } label: {
                    if predictionStore.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(predictionStore.isLoading)
                .help("刷新额外重置预测")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("重置预测指数：")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(snapshot.predictionIndex)/100")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(levelColor)
                        Text(snapshot.level.displayName)
                            .font(.headline)
                            .foregroundStyle(levelColor)
                    }

                    ProgressView(value: Double(snapshot.predictionIndex), total: 100)
                        .tint(levelColor)
                        .accessibilityLabel("重置预测指数")
                        .accessibilityValue("\(snapshot.predictionIndex) / 100")

                    HStack(spacing: 24) {
                        predictionMetric("预计窗口", snapshot.estimatedWindow ?? "尚未明确")
                        predictionMetric("可信度", snapshot.confidence)
                        predictionMetric("有效来源", "\(Set(snapshot.activeSignals.map(\.source)).count)")
                    }

                    if snapshot.activeSignals.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("暂无额外额度重置信号")
                                .font(.headline)
                            Text(normalResetText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("主要依据")
                                .font(.subheadline.weight(.semibold))
                            ForEach(Array(snapshot.reasons.enumerated()), id: \.offset) { index, reason in
                                HStack(alignment: .top, spacing: 7) {
                                    Text("\(index + 1).")
                                        .monospacedDigit()
                                        .foregroundStyle(.tertiary)
                                    Text(reason)
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 9) {
                    Text("最新证据")
                        .font(.subheadline.weight(.semibold))
                    if snapshot.activeSignals.isEmpty {
                        Text("暂无有效证据")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(snapshot.activeSignals.prefix(4))) { signal in
                            signalRow(signal)
                        }
                    }
                    if !snapshot.history.isEmpty {
                        Divider()
                        Text("历史事件 \(snapshot.history.count) 条")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 330, alignment: .topLeading)
            }

            if let error = predictionStore.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(PulseTheme.red)
            } else if !snapshot.sourceWarnings.isEmpty {
                Text(snapshot.sourceWarnings.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            if snapshot.activeSignals.contains(where: { $0.source.isThirdPartyXSource }) {
                Label(
                    "X 动态来自第三方 RSS 代理，未经 X API 验证，不能单独触发“官方确认”。",
                    systemImage: "exclamationmark.shield"
                )
                .font(.caption2)
                .foregroundStyle(PulseTheme.orange)
            }

            Label(
                "这是规则驱动的预测指数，不是统计概率；正常周期额度恢复不计入本模块。",
                systemImage: "info.circle"
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private var normalResetText: String {
        guard let bucket = pulseStore.snapshot.rateLimits.primaryBucket else {
            return "当前仅显示正常额度恢复时间"
        }
        return "当前仅显示正常额度恢复时间：\(PulseFormatters.countdown(bucket.resetCountdown))"
    }

    private var levelColor: Color {
        switch predictionStore.snapshot.level {
        case .none: return Color.secondary
        case .low: return PulseTheme.blue
        case .possible: return PulseTheme.orange
        case .high, .veryHigh: return PulseTheme.red
        case .confirmed: return PulseTheme.green
        }
    }

    private func predictionMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
    }

    private func signalRow(_ signal: ResetPredictionSignal) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(signal.source.displayName)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(PulseFormatters.relativeDate(signal.publishedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let rawURL = signal.sourceURL, let url = URL(string: rawURL) {
                Link(signal.title, destination: url)
                    .font(.caption)
                    .lineLimit(1)
            } else {
                Text(signal.title)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }
}
