import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct CodexPulseApp: App {
    @State private var store = PulseStore()
    @State private var modelRankings = ArtificialAnalysisLeaderboardStore()
    @State private var resetPrediction = CodexResetPredictionStore()
    @State private var appUpdates = AppUpdateService.shared
    private let isSecondaryInstance: Bool

    init() {
        #if os(macOS)
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let existing = NSRunningApplication
            .runningApplications(withBundleIdentifier: AppConstants.bundleID)
            .first { $0.processIdentifier != currentPID && !$0.isTerminated }
        isSecondaryInstance = existing != nil
        if let existing {
            existing.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        } else {
            // 显示 Dock 图标，避免“后台无界面、像没反应”
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        #else
        isSecondaryInstance = false
        #endif
    }

    var body: some Scene {
        // 主窗口：启动就会出现（Xcode 中间不再是白屏）
        WindowGroup("Codex-Pulse", id: "dashboard") {
            DashboardView()
                .environment(store)
                .environment(modelRankings)
                .environment(resetPrediction)
                .environment(appUpdates)
                .environment(\.pulseVisualTheme, store.settings.resolvedVisualTheme)
                .tint(store.settings.resolvedVisualTheme.accent)
                .preferredColorScheme(store.settings.resolvedAppearanceMode.colorScheme)
                .frame(minWidth: 860, minHeight: 620)
                .onAppear {
                    guard !isSecondaryInstance else { return }
                    store.start()
                    appUpdates.startAutomaticChecks()
                    #if os(macOS)
                    NSApp.activate(ignoringOtherApps: true)
                    FloatingCapsuleController.shared.restoreIfNeeded(store: store)
                    #endif
                }
        }
        .defaultSize(width: 1_080, height: 760)
        .handlesExternalEvents(matching: ["dashboard"])
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("退出 CodexPulse") {
                    CodexPulseLifecycle.quit(store: store)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }

        // 菜单栏：圆点 + 百分比 /「Pulse」
        MenuBarExtra {
            MenuBarPanelView()
                .environment(store)
                .environment(modelRankings)
                .environment(resetPrediction)
                .environment(appUpdates)
                .environment(\.pulseVisualTheme, store.settings.resolvedVisualTheme)
                .tint(store.settings.resolvedVisualTheme.accent)
                .preferredColorScheme(store.settings.resolvedAppearanceMode.colorScheme)
        } label: {
            MenuBarLabelView()
                .environment(store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(store)
                .environment(modelRankings)
                .environment(resetPrediction)
                .environment(appUpdates)
                .environment(\.pulseVisualTheme, store.settings.resolvedVisualTheme)
                .tint(store.settings.resolvedVisualTheme.accent)
                .preferredColorScheme(store.settings.resolvedAppearanceMode.colorScheme)
                .frame(width: 480, height: 680)
        }
    }
}

#if os(macOS)
@MainActor
enum CodexPulseLifecycle {
    static func quit(store: PulseStore) {
        store.stop()
        FloatingCapsuleController.shared.prepareForTermination()
        NSApplication.shared.terminate(nil)
    }
}
#endif
