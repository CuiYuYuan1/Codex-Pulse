import Foundation

/// Codex App Server JSON-RPC 客户端协议
protocol CodexAppServerClient: AnyObject, Sendable {
    var isConnected: Bool { get }
    func connect() async throws
    func disconnect() async
    func readAccount() async throws -> AccountInfo
    func readRateLimits(forceRefresh: Bool) async throws -> RateLimitSnapshot
    func readUsage(forceRefresh: Bool) async throws -> UsageStats
    func readLocalUsage(merging cached: UsageStats) async -> UsageStats
    /// 登录账号/工作区变化后清除额度、用量缓存与失败退避。
    func invalidateAccountScopedState()
    func listRecentThreads(limit: Int) async throws -> [TaskRecord]
    /// 仅刷新任务运行状态；不得触发额度、Token 或其他远端 profile 请求。
    func listLiveThreads(limit: Int) async throws -> [TaskRecord]
    /// 订阅推送事件（额度更新、turn 等）
    func eventStream() -> AsyncStream<CodexServerEvent>
}

enum CodexServerEvent: Sendable {
    case accountUpdated
    /// 本地认证文件被 Codex 登录流程改写；现有 app-server 可能仍持有旧认证，
    /// Store 收到后必须重建连接，而不是只重读 account/read。
    case authenticationChanged
    case rateLimitsUpdated(RateLimitSnapshot)
    /// 线程活跃状态发生变化；具体任务以随后的 thread/list 为准。
    case threadsChanged
    /// 本机 session 文件写入后直接解析出的单线程状态，不经过全局 thread/list。
    case localTaskStateChanged(TaskRecord)
    case turnStarted(CurrentTaskInfo)
    case turnCompleted(CurrentTaskInfo)
    /// 新版 App Server 的可见回复文本增量；不包含隐藏推理内容。
    case agentMessageDelta(threadID: String, itemID: String, delta: String)
    /// App Server 推送的线程累计 Token。值是该线程截至当前的累计量，不是增量。
    case tokenUsageUpdated(threadID: String, turnID: String?, totalTokens: Int64)
    case itemStarted(String)
    case itemCompleted(String)
    case connectionLost(String)
    case connectionRestored
}

enum CodexServerError: Error, LocalizedError {
    case notConnected
    case cliNotFound
    case processFailed(String)
    case invalidResponse(String)
    case timeout
    case unauthorized
    case requestDeferred
    case rpcError(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "未连接到 Codex App Server"
        case .cliNotFound: return "未检测到 Codex CLI，请先安装并登录"
        case .processFailed(let msg): return "App Server 进程错误: \(msg)"
        case .invalidResponse(let msg): return "无效响应: \(msg)"
        case .timeout: return "请求超时"
        case .unauthorized: return "未登录或登录已失效"
        case .requestDeferred: return "请求已暂缓"
        case .rpcError(let code, let msg): return "RPC \(code): \(msg)"
        }
    }
}
