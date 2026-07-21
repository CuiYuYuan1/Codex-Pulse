import Foundation
import SQLite3

/// App Group 共享快照，供主 App 与 Widget 读写
final class SnapshotStore: Sendable {
    static let shared = SnapshotStore()

    private let fileName = AppConstants.snapshotFileName
    /// 编码 + 写盘在后台串行队列执行，避免阻塞主线程。
    private let ioQueue = DispatchQueue(label: "com.codexpulse.snapshot-io", qos: .utility)

    private var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupID
        )
    }

    private var snapshotURL: URL? {
        // 开发时若无 App Group，回退到 Application Support
        if let containerURL {
            return containerURL.appendingPathComponent(fileName)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CodexPulse", isDirectory: true)
        if let support {
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            return support.appendingPathComponent(fileName)
        }
        return nil
    }

    func save(_ snapshot: PulseSnapshot, synchronous: Bool = false) {
        guard let url = snapshotURL else { return }
        let work = {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
        if synchronous {
            ioQueue.sync(execute: work)
        } else {
            ioQueue.async(execute: work)
        }
    }

    func load() -> PulseSnapshot? {
        guard let url = snapshotURL,
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PulseSnapshot.self, from: data)
    }
}

/// 本地 SQLite 数据：任务历史与额度采样。实时任务状态始终由 App Server / session 提供。
final class TaskHistoryStore: @unchecked Sendable {
    static let shared = TaskHistoryStore()

    private let queue = DispatchQueue(label: "com.codexpulse.task-history")
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private var lastPrunedAt: Date = .distantPast
    private var lastRetentionDays: Int?
    private var lastRateSamplePrunedAt: Date = .distantPast

    private var databaseURL: URL? {
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupID
        ) {
            return container.appendingPathComponent(AppConstants.historyDBName)
        }
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("CodexPulse", isDirectory: true) else {
            return nil
        }
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent(AppConstants.historyDBName)
    }

    func persistAndMerge(
        liveTasks: [TaskRecord],
        retentionDays: Int,
        limit: Int = 100
    ) -> [TaskRecord] {
        guard retentionDays > 0 else { return liveTasks }
        return queue.sync {
            guard let db = openDatabase() else { return liveTasks }
            defer { sqlite3_close(db) }
            upsert(liveTasks, in: db)
            pruneIfNeeded(retentionDays: retentionDays, in: db)
            let history = load(limit: limit, preserveRuntimeState: false, from: db)
            var ids = Set(liveTasks.map(\.id))
            return liveTasks + history.filter { ids.insert($0.id).inserted }
        }
    }

    func persist(_ tasks: [TaskRecord], retentionDays: Int) {
        guard retentionDays > 0 else { return }
        queue.sync {
            guard let db = openDatabase() else { return }
            defer { sqlite3_close(db) }
            upsert(tasks, in: db)
            pruneIfNeeded(retentionDays: retentionDays, in: db)
        }
    }

    func prune(retentionDays: Int) {
        guard retentionDays > 0 else { return }
        queue.sync {
            guard let db = openDatabase() else { return }
            defer { sqlite3_close(db) }
            prune(retentionDays: retentionDays, in: db)
            lastPrunedAt = Date()
            lastRetentionDays = retentionDays
        }
    }

    func recordCount() -> Int {
        return queue.sync {
            guard let db = openDatabase() else { return 0 }
            defer { sqlite3_close(db) }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM task_history", -1, &statement, nil) == SQLITE_OK else {
                return 0
            }
            defer { sqlite3_finalize(statement) }
            return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
        }
    }

    func tasks(since cutoff: Date, limit: Int = 50_000) -> [TaskRecord] {
        return queue.sync {
            guard let db = openDatabase() else { return [] }
            defer { sqlite3_close(db) }
            return load(
                limit: min(50_000, max(1, limit)),
                preserveRuntimeState: true,
                from: db
            ).filter { $0.finishedAt >= cutoff }
        }
    }

    /// 最多每 5 分钟记录同一额度桶一次，避免随 5 秒轮询高频写盘。
    func recordRateLimitSample(_ bucket: RateLimitBucket, sampledAt: Date = Date()) {
        queue.sync {
            guard let db = openDatabase() else { return }
            defer { sqlite3_close(db) }

            var latestStatement: OpaquePointer?
            guard sqlite3_prepare_v2(
                db,
                "SELECT MAX(sampled_at) FROM rate_limit_samples WHERE bucket_id = ?",
                -1,
                &latestStatement,
                nil
            ) == SQLITE_OK, let latestStatement else { return }
            bind(bucket.id, at: 1, to: latestStatement)
            let latest: TimeInterval? = sqlite3_step(latestStatement) == SQLITE_ROW
                && sqlite3_column_type(latestStatement, 0) != SQLITE_NULL
                ? sqlite3_column_double(latestStatement, 0)
                : nil
            sqlite3_finalize(latestStatement)
            if let latest, sampledAt.timeIntervalSince1970 - latest < 5 * 60 { return }

            var insert: OpaquePointer?
            let sql = """
            INSERT INTO rate_limit_samples (bucket_id, sampled_at, used_percent, resets_at)
            VALUES (?, ?, ?, ?)
            """
            guard sqlite3_prepare_v2(db, sql, -1, &insert, nil) == SQLITE_OK, let insert else { return }
            defer { sqlite3_finalize(insert) }
            bind(bucket.id, at: 1, to: insert)
            sqlite3_bind_double(insert, 2, sampledAt.timeIntervalSince1970)
            sqlite3_bind_double(insert, 3, min(100, max(0, bucket.usedPercent)))
            if let resetsAt = bucket.resetsAt {
                sqlite3_bind_double(insert, 4, resetsAt.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(insert, 4)
            }
            if sqlite3_step(insert) != SQLITE_DONE {
                PulseLog.write("rate sample insert failed: \(sqliteMessage(db))")
            }

            if sampledAt.timeIntervalSince(lastRateSamplePrunedAt) >= 3_600 {
                let cutoff = sampledAt.addingTimeInterval(-14 * 86_400).timeIntervalSince1970
                var prune: OpaquePointer?
                if sqlite3_prepare_v2(
                    db,
                    "DELETE FROM rate_limit_samples WHERE sampled_at < ?",
                    -1,
                    &prune,
                    nil
                ) == SQLITE_OK, let prune {
                    sqlite3_bind_double(prune, 1, cutoff)
                    sqlite3_step(prune)
                    sqlite3_finalize(prune)
                    lastRateSamplePrunedAt = sampledAt
                }
            }
        }
    }

    func rateLimitForecast(
        for bucket: RateLimitBucket,
        reference: Date = Date()
    ) -> RateLimitForecast? {
        let bucketWindow = bucket.windowDurationSeconds ?? 8 * 3_600
        let minimumObservationWindow = 2 * 3_600.0
        let maximumObservationWindow = 24 * 3_600.0
        let observationWindow = min(
            maximumObservationWindow,
            max(minimumObservationWindow, bucketWindow * 0.25)
        )
        var cutoff = reference.addingTimeInterval(-observationWindow)
        if let resetsAt = bucket.resetsAt,
           let duration = bucket.windowDurationSeconds {
            cutoff = max(cutoff, resetsAt.addingTimeInterval(-duration))
        }

        let samples: [StoredRateLimitSample] = queue.sync {
            guard let db = openDatabase() else { return [] }
            defer { sqlite3_close(db) }
            return loadRateLimitSamples(
                bucketID: bucket.id,
                since: cutoff,
                matchingResetAt: bucket.resetsAt,
                from: db
            )
        }

        return makeRateLimitForecast(
            bucket: bucket,
            reference: reference,
            samples: samples
        )
    }

    func rateLimitSampleCount() -> Int {
        return queue.sync {
            guard let db = openDatabase() else { return 0 }
            defer { sqlite3_close(db) }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                db,
                "SELECT COUNT(*) FROM rate_limit_samples",
                -1,
                &statement,
                nil
            ) == SQLITE_OK, let statement else { return 0 }
            defer { sqlite3_finalize(statement) }
            return sqlite3_step(statement) == SQLITE_ROW
                ? Int(sqlite3_column_int64(statement, 0))
                : 0
        }
    }

    func clearRateLimitSamples() {
        queue.sync {
            guard let db = openDatabase() else { return }
            defer { sqlite3_close(db) }
            if sqlite3_exec(db, "DELETE FROM rate_limit_samples", nil, nil, nil) != SQLITE_OK {
                PulseLog.write("rate samples clear failed: \(sqliteMessage(db))")
            }
            lastRateSamplePrunedAt = .distantPast
        }
    }

    func clear() {
        queue.sync {
            guard let db = openDatabase() else { return }
            defer { sqlite3_close(db) }
            if sqlite3_exec(db, "DELETE FROM task_history", nil, nil, nil) != SQLITE_OK {
                PulseLog.write("history clear failed: \(sqliteMessage(db))")
            }
            lastPrunedAt = .distantPast
            lastRetentionDays = nil
        }
    }

    func csvData() -> Data {
        return queue.sync {
            guard let db = openDatabase() else { return Data() }
            defer { sqlite3_close(db) }
            let tasks = load(limit: 50_000, preserveRuntimeState: true, from: db)
            var rows = ["任务ID,项目,路径,分支,模型,状态,Token,运行秒数,修改文件数,摘要,开始时间,结束时间"]
            let iso = ISO8601DateFormatter()
            rows.append(contentsOf: tasks.map { csvRow(for: $0, formatter: iso) })
            var data = Data([0xEF, 0xBB, 0xBF]) // UTF-8 BOM，兼容 Excel 中文识别。
            data.append(Data((rows.joined(separator: "\n") + "\n").utf8))
            return data
        }
    }

    private func openDatabase() -> OpaquePointer? {
        guard let url = databaseURL else { return nil }
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            PulseLog.write("history database open failed: \(url.path)")
            return nil
        }
        sqlite3_busy_timeout(db, 1_000)
        let schema = """
        CREATE TABLE IF NOT EXISTS task_history (
            id TEXT PRIMARY KEY NOT NULL,
            project_name TEXT NOT NULL,
            project_path TEXT,
            git_branch TEXT,
            model TEXT,
            token_usage INTEGER,
            duration_seconds REAL NOT NULL DEFAULT 0,
            succeeded INTEGER NOT NULL DEFAULT 1,
            files_changed INTEGER NOT NULL DEFAULT 0,
            summary TEXT,
            finished_at REAL NOT NULL,
            run_state TEXT,
            active_flags TEXT,
            started_at REAL
        );
        CREATE INDEX IF NOT EXISTS idx_task_history_finished_at
            ON task_history(finished_at DESC);
        CREATE TABLE IF NOT EXISTS rate_limit_samples (
            bucket_id TEXT NOT NULL,
            sampled_at REAL NOT NULL,
            used_percent REAL NOT NULL,
            resets_at REAL,
            PRIMARY KEY (bucket_id, sampled_at)
        );
        CREATE INDEX IF NOT EXISTS idx_rate_limit_samples_lookup
            ON rate_limit_samples(bucket_id, sampled_at DESC);
        """
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else {
            PulseLog.write("history database schema failed: \(sqliteMessage(db))")
            sqlite3_close(db)
            return nil
        }
        return db
    }

    private func upsert(_ tasks: [TaskRecord], in db: OpaquePointer) {
        guard !tasks.isEmpty else { return }
        let sql = """
        INSERT INTO task_history (
            id, project_name, project_path, git_branch, model, token_usage,
            duration_seconds, succeeded, files_changed, summary, finished_at,
            run_state, active_flags, started_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            project_name=excluded.project_name,
            project_path=COALESCE(excluded.project_path, task_history.project_path),
            git_branch=COALESCE(excluded.git_branch, task_history.git_branch),
            model=COALESCE(excluded.model, task_history.model),
            token_usage=COALESCE(excluded.token_usage, task_history.token_usage),
            duration_seconds=MAX(excluded.duration_seconds, task_history.duration_seconds),
            succeeded=excluded.succeeded,
            files_changed=MAX(excluded.files_changed, task_history.files_changed),
            summary=COALESCE(excluded.summary, task_history.summary),
            finished_at=MAX(excluded.finished_at, task_history.finished_at),
            run_state=excluded.run_state,
            active_flags=excluded.active_flags,
            started_at=COALESCE(excluded.started_at, task_history.started_at)
        WHERE
            excluded.finished_at > task_history.finished_at OR
            excluded.duration_seconds > task_history.duration_seconds OR
            excluded.succeeded <> task_history.succeeded OR
            excluded.files_changed > task_history.files_changed OR
            COALESCE(excluded.run_state, '') <> COALESCE(task_history.run_state, '') OR
            (task_history.project_path IS NULL AND excluded.project_path IS NOT NULL) OR
            (task_history.git_branch IS NULL AND excluded.git_branch IS NOT NULL) OR
            (task_history.model IS NULL AND excluded.model IS NOT NULL) OR
            (task_history.summary IS NULL AND excluded.summary IS NOT NULL)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            PulseLog.write("history prepare failed: \(sqliteMessage(db))")
            return
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil)
        for task in tasks {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bind(task.id, at: 1, to: statement)
            bind(task.projectName, at: 2, to: statement)
            bind(task.projectPath, at: 3, to: statement)
            bind(task.gitBranch, at: 4, to: statement)
            bind(task.model, at: 5, to: statement)
            bind(task.tokenUsage, at: 6, to: statement)
            sqlite3_bind_double(statement, 7, task.durationSeconds)
            sqlite3_bind_int(statement, 8, task.succeeded ? 1 : 0)
            sqlite3_bind_int(statement, 9, Int32(task.filesChanged))
            bind(task.summary, at: 10, to: statement)
            sqlite3_bind_double(statement, 11, task.finishedAt.timeIntervalSince1970)
            bind(task.runState?.rawValue, at: 12, to: statement)
            let flags = task.activeFlags.flatMap { try? JSONEncoder().encode($0) }
                .flatMap { String(data: $0, encoding: .utf8) }
            bind(flags, at: 13, to: statement)
            if let startedAt = task.startedAt {
                sqlite3_bind_double(statement, 14, startedAt.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 14)
            }
            if sqlite3_step(statement) != SQLITE_DONE {
                PulseLog.write("history upsert failed: \(sqliteMessage(db))")
            }
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    private func prune(retentionDays: Int, in db: OpaquePointer) {
        let days = min(3_650, max(1, retentionDays))
        let cutoff = Date().addingTimeInterval(-TimeInterval(days * 86_400)).timeIntervalSince1970
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM task_history WHERE finished_at < ?", -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, cutoff)
        sqlite3_step(statement)
    }

    private func pruneIfNeeded(retentionDays: Int, in db: OpaquePointer) {
        let retentionChanged = lastRetentionDays != retentionDays
        guard retentionChanged || Date().timeIntervalSince(lastPrunedAt) >= 3_600 else { return }
        prune(retentionDays: retentionDays, in: db)
        lastPrunedAt = Date()
        lastRetentionDays = retentionDays
    }

    private func load(limit: Int, preserveRuntimeState: Bool, from db: OpaquePointer) -> [TaskRecord] {
        let sql = """
        SELECT id, project_name, project_path, git_branch, model, token_usage,
               duration_seconds, succeeded, files_changed, summary, finished_at,
               run_state, active_flags, started_at
        FROM task_history ORDER BY finished_at DESC LIMIT ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(max(1, limit)))

        var result: [TaskRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(taskRecord(
                from: statement,
                preserveRuntimeState: preserveRuntimeState
            ))
        }
        return result
    }

    private func taskRecord(
        from statement: OpaquePointer,
        preserveRuntimeState: Bool
    ) -> TaskRecord {
        let rawFlags = string(at: 12, from: statement)
        let flagsData = rawFlags.map { Data($0.utf8) }
        let decodedFlags = flagsData.flatMap {
            try? JSONDecoder().decode([String].self, from: $0)
        }
        let rawState = string(at: 11, from: statement)
        let storedState = rawState.flatMap { CodexRunState(rawValue: $0) }
        let storedStartDate = double(at: 13, from: statement).map {
            Date(timeIntervalSince1970: $0)
        }

        let runState: CodexRunState? = preserveRuntimeState ? storedState : nil
        let activeFlags: [String]? = preserveRuntimeState ? decodedFlags : nil
        let startedAt: Date? = preserveRuntimeState ? storedStartDate : nil

        return TaskRecord(
            id: string(at: 0, from: statement) ?? UUID().uuidString,
            projectName: string(at: 1, from: statement) ?? "Untitled",
            projectPath: string(at: 2, from: statement),
            gitBranch: string(at: 3, from: statement),
            model: string(at: 4, from: statement),
            tokenUsage: int64(at: 5, from: statement),
            durationSeconds: sqlite3_column_double(statement, 6),
            succeeded: sqlite3_column_int(statement, 7) != 0,
            filesChanged: Int(sqlite3_column_int(statement, 8)),
            summary: string(at: 9, from: statement),
            finishedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 10)),
            runState: runState,
            activeFlags: activeFlags,
            startedAt: startedAt
        )
    }

    private struct StoredRateLimitSample {
        var sampledAt: Date
        var usedPercent: Double
        var resetsAt: Date?
    }

    private struct ForecastPoint {
        var date: Date
        var usedPercent: Double
    }

    private func makeRateLimitForecast(
        bucket: RateLimitBucket,
        reference: Date,
        samples: [StoredRateLimitSample]
    ) -> RateLimitForecast? {
        var rawPoints = samples.map {
            ForecastPoint(date: $0.sampledAt, usedPercent: $0.usedPercent)
        }
        rawPoints.append(ForecastPoint(
            date: reference,
            usedPercent: min(100, max(0, bucket.usedPercent))
        ))

        let points = normalizedForecastPoints(rawPoints)
        guard points.count >= 3,
              let first = points.first,
              let last = points.last else { return nil }

        let observedDuration = last.date.timeIntervalSince(first.date)
        guard observedDuration >= 10 * 60,
              let burnRate = regressionBurnRate(for: points),
              burnRate >= 0.02 else { return nil }

        let remaining = max(0, 100 - bucket.usedPercent)
        let hoursToExhaustion = remaining / burnRate
        let estimatedExhaustionAt = reference.addingTimeInterval(hoursToExhaustion * 3_600)

        let projectedRemaining: Double?
        let willExhaustBeforeReset: Bool
        if let resetsAt = bucket.resetsAt, resetsAt > reference {
            let hoursUntilReset = resetsAt.timeIntervalSince(reference) / 3_600
            projectedRemaining = max(0, remaining - burnRate * hoursUntilReset)
            willExhaustBeforeReset = estimatedExhaustionAt < resetsAt
        } else {
            projectedRemaining = nil
            willExhaustBeforeReset = false
        }

        let confidence: RateLimitForecastConfidence
        if observedDuration >= 3 * 3_600, points.count >= 12 {
            confidence = .high
        } else if observedDuration >= 60 * 60, points.count >= 6 {
            confidence = .medium
        } else {
            confidence = .low
        }

        return RateLimitForecast(
            bucketID: bucket.id,
            sampleCount: points.count,
            observedDuration: observedDuration,
            burnRatePercentPerHour: burnRate,
            estimatedExhaustionAt: estimatedExhaustionAt,
            projectedRemainingAtReset: projectedRemaining,
            willExhaustBeforeReset: willExhaustBeforeReset,
            confidence: confidence,
            updatedAt: reference
        )
    }

    /// 同一时刻只保留最后一个值；检测到明显回落时，丢弃上一重置周期。
    private func normalizedForecastPoints(_ points: [ForecastPoint]) -> [ForecastPoint] {
        let sortedPoints = points.sorted { $0.date < $1.date }
        var normalized: [ForecastPoint] = []
        for point in sortedPoints {
            if let last = normalized.last,
               abs(point.date.timeIntervalSince(last.date)) < 1 {
                normalized[normalized.count - 1] = point
            } else if let last = normalized.last,
                      point.usedPercent + 5 < last.usedPercent {
                normalized = [point]
            } else {
                normalized.append(point)
            }
        }
        return normalized
    }

    private func regressionBurnRate(for points: [ForecastPoint]) -> Double? {
        guard let first = points.first, !points.isEmpty else { return nil }

        var hours: [Double] = []
        hours.reserveCapacity(points.count)
        var totalHours = 0.0
        var totalUsage = 0.0

        for point in points {
            let elapsedHours = point.date.timeIntervalSince(first.date) / 3_600
            hours.append(elapsedHours)
            totalHours += elapsedHours
            totalUsage += point.usedPercent
        }

        let count = Double(points.count)
        let meanHours = totalHours / count
        let meanUsage = totalUsage / count
        var numerator = 0.0
        var denominator = 0.0

        for index in points.indices {
            let hourDelta = hours[index] - meanHours
            numerator += hourDelta * (points[index].usedPercent - meanUsage)
            denominator += hourDelta * hourDelta
        }

        guard denominator > 0 else { return nil }
        return numerator / denominator
    }

    private func loadRateLimitSamples(
        bucketID: String,
        since cutoff: Date,
        matchingResetAt currentResetAt: Date?,
        from db: OpaquePointer
    ) -> [StoredRateLimitSample] {
        let sql = """
        SELECT sampled_at, used_percent, resets_at
        FROM rate_limit_samples
        WHERE bucket_id = ? AND sampled_at >= ?
        ORDER BY sampled_at ASC LIMIT 500
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        bind(bucketID, at: 1, to: statement)
        sqlite3_bind_double(statement, 2, cutoff.timeIntervalSince1970)

        var result: [StoredRateLimitSample] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let reset = double(at: 2, from: statement).map { Date(timeIntervalSince1970: $0) }
            let sameCycle: Bool
            if let currentResetAt {
                sameCycle = reset.map { abs($0.timeIntervalSince(currentResetAt)) <= 15 * 60 } ?? false
            } else {
                sameCycle = reset == nil
            }
            guard sameCycle else { continue }
            result.append(StoredRateLimitSample(
                sampledAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
                usedPercent: sqlite3_column_double(statement, 1),
                resetsAt: reset
            ))
        }
        return result
    }

    private func bind(_ value: String?, at index: Int32, to statement: OpaquePointer) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        value.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, sqliteTransient)
        }
    }

    private func bind(_ value: Int64?, at index: Int32, to statement: OpaquePointer) {
        if let value {
            sqlite3_bind_int64(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func string(at index: Int32, from statement: OpaquePointer) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private func int64(at index: Int32, from statement: OpaquePointer) -> Int64? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, index)
    }

    private func double(at index: Int32, from statement: OpaquePointer) -> Double? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_double(statement, index)
    }

    private func sqliteMessage(_ db: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(db))
    }

    private func csvField(_ value: String) -> String {
        var safe = value
        if let first = safe.first, ["=", "+", "-", "@"].contains(first) {
            safe.insert("'", at: safe.startIndex)
        }
        return "\"\(safe.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func csvRow(
        for task: TaskRecord,
        formatter: ISO8601DateFormatter
    ) -> String {
        let state = task.runState?.rawValue ?? (task.succeeded ? "成功" : "失败")
        let tokenUsage = task.tokenUsage.map { String($0) } ?? ""
        let startedAt = task.startedAt.map { formatter.string(from: $0) } ?? ""
        let fields: [String] = [
            task.id,
            task.projectName,
            task.projectPath ?? "",
            task.gitBranch ?? "",
            task.model ?? "",
            state,
            tokenUsage,
            String(format: "%.0f", task.durationSeconds),
            String(task.filesChanged),
            task.summary ?? "",
            startedAt,
            formatter.string(from: task.finishedAt)
        ]
        return fields.map { csvField($0) }.joined(separator: ",")
    }
}
