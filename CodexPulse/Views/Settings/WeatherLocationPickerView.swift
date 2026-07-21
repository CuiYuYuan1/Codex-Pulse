import SwiftUI

/// Open-Meteo 地理编码搜索。结果同时显示城市、省/州和国家，减少同名城市误选。
struct WeatherLocationPickerView: View {
    let initialLocation: WeatherLocation?
    let onSelect: (WeatherLocation) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var results: [WeatherLocation] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var isSearchFieldFocused: Bool

    init(initialLocation: WeatherLocation?, onSelect: @escaping (WeatherLocation) -> Void) {
        self.initialLocation = initialLocation
        self.onSelect = onSelect
        _query = State(initialValue: initialLocation?.name ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("选择天气地区")
                        .font(.title3.weight(.semibold))
                    Text("输入城市名称，天气和本地时间会使用该地区的坐标与时区。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索城市，例如 杭州 / Tokyo", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFieldFocused)
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if !query.isEmpty {
                    Button {
                        query = ""
                        results = []
                        errorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("清除搜索")
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )

            Group {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(PulseTheme.orange)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if results.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "globe.asia.australia")
                            .font(.system(size: 26))
                            .foregroundStyle(.tertiary)
                        Text(query.isEmpty
                             ? "搜索并选择一个地区"
                             : (query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2
                                ? "请输入至少 2 个字符"
                                : "没有找到匹配的地区"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(results) { location in
                                Button {
                                    onSelect(location)
                                    dismiss()
                                } label: {
                                    locationRow(location)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 0) {
                Text("Weather data by ")
                Link("Open-Meteo.com", destination: URL(string: "https://open-meteo.com/")!)
                Text(" · Location data by ")
                Link("GeoNames", destination: URL(string: "https://www.geonames.org/")!)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 500, height: 470)
        .onAppear {
            // 首次开启时用户可以直接输入城市，不必再点击一次搜索框。
            isSearchFieldFocused = true
        }
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else {
                results = []
                errorMessage = nil
                isLoading = false
                return
            }
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            await search(trimmed)
        }
    }

    private func locationRow(_ location: WeatherLocation) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(PulseTheme.blue)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(location.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                let context = [location.admin1, location.country]
                    .compactMap { value -> String? in
                        guard let value, !value.isEmpty, value != location.name else { return nil }
                        return value
                    }
                    .joined(separator: " · ")
                if !context.isEmpty {
                    Text(context)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(String(format: "%.4f, %.4f · %@", location.latitude, location.longitude, location.timezone))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        }
    }

    @MainActor
    private func search(_ value: String) async {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            results = try await OpenMeteoClient.shared.searchLocations(query: trimmed)
        } catch is CancellationError {
            return
        } catch {
            results = []
            errorMessage = error.localizedDescription
        }
    }
}
