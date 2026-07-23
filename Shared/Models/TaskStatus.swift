import Foundation

/// Codex 运行状态
enum CodexRunState: String, Codable, CaseIterable, Sendable {
    case notStarted = "未启动"
    case connecting = "正在连接"
    case idle = "空闲"
    case thinking = "正在思考"
    case generatingCode = "正在生成代码"
    case executingCommand = "正在执行命令"
    case modifyingFiles = "正在修改文件"
    case callingTool = "正在调用工具"
    case awaitingAuthorization = "等待用户授权"
    case awaitingInput = "等待用户输入"
    case completed = "已完成"
    case stopped = "已停止"
    case failed = "执行失败"
    case networkError = "网络异常"

    var isActive: Bool {
        switch self {
        case .thinking, .generatingCode, .executingCommand, .modifyingFiles, .callingTool:
            return true
        default:
            return false
        }
    }

    var needsAttention: Bool {
        switch self {
        case .awaitingAuthorization, .awaitingInput, .failed, .networkError:
            return true
        default:
            return false
        }
    }

    var indicatorColor: PulseStatusColor {
        switch self {
        case .thinking, .generatingCode, .executingCommand, .modifyingFiles, .callingTool:
            return .blue
        case .awaitingAuthorization, .awaitingInput:
            return .yellow
        case .failed, .networkError:
            return .red
        case .idle, .completed:
            return .green
        case .notStarted, .connecting, .stopped:
            return .gray
        }
    }

    /// 状态简短说明（用于 UI 副标题）
    var detailDescription: String {
        switch self {
        case .notStarted:
            return "尚未检测到 Codex 任务"
        case .connecting:
            return "正在连接本地 App Server"
        case .idle:
            return "已连接，当前没有正在执行的任务"
        case .thinking:
            return "模型正在推理"
        case .generatingCode:
            return "正在生成或改写代码"
        case .executingCommand:
            return "正在执行终端命令"
        case .modifyingFiles:
            return "正在修改项目文件"
        case .callingTool:
            return "正在调用工具"
        case .awaitingAuthorization:
            return "需要你在 Codex 中确认操作"
        case .awaitingInput:
            return "等待你补充输入"
        case .completed:
            return "最近一次任务已完成"
        case .stopped:
            return "任务已停止"
        case .failed:
            return "最近一次任务执行失败"
        case .networkError:
            return "网络异常，请检查连接"
        }
    }
}

/// 菜单栏 / 小组件状态色
enum PulseStatusColor: String, Sendable {
    case green  // 空闲且额度充足
    case blue   // 正在运行
    case yellow // 等待确认或额度较低
    case red    // 额度耗尽、失败、登录失效
    case gray   // 未启动或未登录
}

/// 当前 Codex turn 中可展示的对话内容。只保留用户可见消息，不包含推理原文、
/// 工具参数、权限数据或隐藏上下文。
struct TaskConversationMessage: Codable, Equatable, Identifiable, Sendable {
    enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    var id: String
    var role: Role
    var text: String
    var timestamp: Date?
    var isStreaming: Bool
}

/// 当前任务快照
struct CurrentTaskInfo: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var projectName: String?
    var projectPath: String?
    var gitBranch: String?
    var model: String?
    var reasoningEffort: String?
    var startedAt: Date?
    var state: CodexRunState
    var currentStep: String?
    var filesChanged: Int
    var linesAdded: Int
    var linesRemoved: Int
    var lastStatusMessage: String?
    /// 当前 turn 的可见对话；可选字段保证旧版共享快照能够继续解码。
    var conversation: [TaskConversationMessage]? = nil

    var elapsedSeconds: TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, Date().timeIntervalSince(startedAt))
    }

    static let empty = CurrentTaskInfo(
        id: "none",
        projectName: nil,
        projectPath: nil,
        gitBranch: nil,
        model: nil,
        reasoningEffort: nil,
        startedAt: nil,
        state: .notStarted,
        currentStep: nil,
        filesChanged: 0,
        linesAdded: 0,
        linesRemoved: 0,
        lastStatusMessage: nil
    )
}

/// 历史任务记录（本地）
struct TaskRecord: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var projectName: String
    var projectPath: String?
    var gitBranch: String?
    var model: String?
    var tokenUsage: Int64?
    var durationSeconds: TimeInterval
    var succeeded: Bool
    var filesChanged: Int
    var summary: String?
    var finishedAt: Date
    /// thread/list 返回的实时状态；旧缓存没有该字段时保持 nil。
    var runState: CodexRunState? = nil
    /// active 状态的细分标记，例如 waitingOnApproval。
    var activeFlags: [String]? = nil
    /// 当前活动 turn 的开始时间；历史缓存或接口未提供时为 nil。
    var startedAt: Date? = nil
    /// 本机会话监听提取出的当前 turn 可见对话，不写入历史导出时可保持 nil。
    var conversation: [TaskConversationMessage]? = nil

    var indicatorColor: PulseStatusColor {
        if let runState { return runState.indicatorColor }
        return succeeded ? .green : .red
    }
}
