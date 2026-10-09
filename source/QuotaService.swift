import Foundation
import Darwin

// A read-only client of the public Codex app-server protocol.
// https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt
// Authentication stays inside Codex. This client never reads auth.json, submits a
// model turn, redeems reset credits, or persists account identifiers/credentials.

enum QuotaFreshness: String { case live, cached, stale, unavailable }

enum QuotaIssue: Error, Equatable {
    case cliNotFound, notSignedIn, unsupportedAccount, timeout, connectionFailed
    case invalidResponse, cancelled

    var message: String {
        switch self {
        case .cliNotFound: return "未找到 Codex，请先安装并登录 Codex 或 ChatGPT 桌面版。"
        case .notSignedIn: return "请先在 Codex 中登录 ChatGPT 账户，再刷新。"
        case .unsupportedAccount: return "当前登录方式不提供 ChatGPT 套餐额度。"
        case .timeout: return "查询超时，请检查网络后重试。"
        case .connectionFailed: return "暂时无法读取 Codex 额度，请确认已登录并检查网络。"
        case .invalidResponse: return "当前 Codex 未提供可识别的额度，请更新后重试。"
        case .cancelled: return "查询已取消。"
        }
    }
}

struct QuotaResetCredit: Codable {
    let status: String
    let resetType: String
    let expiresAt: Date?
}

struct QuotaResetCredits: Codable {
    // The service can cap details. Never infer this count from details.count.
    let availableCount: Int
    let details: [QuotaResetCredit]?
}

struct QuotaSnapshot: Codable {
    let weeklyRemainingPercent: Double?
    let weeklyResetsAt: Date?
    let resetCredits: QuotaResetCredits?
    let fetchedAt: Date

    fileprivate func isReusable(at now: Date, maxAge: TimeInterval) -> Bool {
        let age = now.timeIntervalSince(fetchedAt)
        guard age >= 0, age < maxAge else { return false }
        if let reset = weeklyResetsAt, reset <= now { return false }
        if resetCredits?.details?.contains(where: {
            $0.status == "available" && $0.expiresAt.map { $0 <= now } == true
        }) == true { return false }
        return true
    }
}

struct QuotaReading {
    let snapshot: QuotaSnapshot?
    let freshness: QuotaFreshness
    let issue: QuotaIssue?
}

/// All process work runs on a private queue. Completion always runs on main.
/// Concurrent refreshes coalesce into one request; cancel stops only our child.
final class QuotaService {
    private let queue = DispatchQueue(label: "local.doro.quota", qos: .utility)
    private let cacheURL: URL?
    private let timeout: TimeInterval
    private let executableOverride: URL?
    private var cache: QuotaSnapshot?
    private var cacheLoaded = false
    private var cacheWasVerifiedThisRun = false
    private var request: QuotaRequest?
    private var completions: [(QuotaReading) -> Void] = []
    private let cacheLifetime: TimeInterval = 60

    init(cacheURL: URL? = nil, timeout: TimeInterval = 15, executableURL: URL? = nil) {
        self.cacheURL = cacheURL
        self.timeout = timeout
        self.executableOverride = executableURL
    }

    func fetch(forceRefresh: Bool = false, completion: @escaping (QuotaReading) -> Void) {
        queue.async { [self] in
            if request != nil { completions.append(completion); return }
            loadCache()
            if !forceRefresh, cacheWasVerifiedThisRun, let cache,
               cache.isReusable(at: Date(), maxAge: cacheLifetime) {
                DispatchQueue.main.async {
                    completion(QuotaReading(snapshot: cache, freshness: .cached, issue: nil))
                }
                return
            }
            completions.append(completion)
            guard let executable = executableOverride ?? Self.findCodex() else {
                finish(.failure(.cliNotFound)); return
            }
            let active = QuotaRequest(executable: executable, queue: queue, timeout: timeout)
            request = active
            active.start { [weak self] result in self?.finish(result) }
        }
    }

    func cancel() {
        queue.async { [weak self] in self?.request?.cancel() }
    }

    /// Call from applicationWillTerminate. Sends the kill before app exit, with
    /// no process wait or network work; an async cancel may never run at exit.
    func shutdown() {
        queue.sync { request?.shutdown() }
    }

    private func loadCache() {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL), data.count < 64_000,
              let saved = try? JSONDecoder().decode(QuotaSnapshot.self, from: data),
              (0...86_400).contains(Date().timeIntervalSince(saved.fetchedAt)) else { return }
        // Disk snapshots are never returned as current before a successful RPC.
        cache = saved
    }

    private func finish(_ result: Result<QuotaSnapshot, QuotaIssue>) {
        request = nil
        let reading: QuotaReading
        switch result {
        case .success(let snapshot):
            cache = snapshot
            cacheWasVerifiedThisRun = true
            if let cacheURL, let data = try? JSONEncoder().encode(snapshot) {
                try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: cacheURL, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
            }
            reading = QuotaReading(snapshot: snapshot, freshness: .live, issue: nil)
        case .failure(let issue):
            cacheWasVerifiedThisRun = false
            // Never show a previous account's quota after a sign-out/auth failure.
            if issue == .notSignedIn || issue == .unsupportedAccount {
                cache = nil
                if let cacheURL { try? FileManager.default.removeItem(at: cacheURL) }
            }
            reading = QuotaReading(snapshot: cache, freshness: cache == nil ? .unavailable : .stale, issue: issue)
        }
        let callbacks = completions
        completions.removeAll()
        DispatchQueue.main.async { callbacks.forEach { $0(reading) } }
    }

    static func findCodex() -> URL? {
        let user = FileManager.default.homeDirectoryForCurrentUser.path
        // Finder-launched applications have a minimal PATH. Prefer the installed
        // desktop binary, then standard CLI locations; never search the cwd.
        var paths: [String] = []
        for base in ["/Applications", "\(user)/Applications"] {
            for name in ["ChatGPT", "Codex"] {
                paths += [
                    "\(base)/\(name).app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                    "\(base)/\(name).app/Contents/Resources/codex-cli/bin/codex",
                    "\(base)/\(name).app/Contents/Resources/codex"
                ]
            }
        }
        paths += ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(user)/.local/bin/codex", "\(user)/.npm-global/bin/codex"]
        paths += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
            .filter { $0.hasPrefix("/") }.map { "\($0)/codex" }
        return paths.first(where: { path in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &directory)
                && !directory.boolValue && FileManager.default.isExecutableFile(atPath: path)
        }).map(URL.init(fileURLWithPath:))
    }

    /// Exposed internally for deterministic tests against versioned RPC fixtures.
    static func parse(_ data: Data, fetchedAt: Date = Date()) throws -> QuotaSnapshot {
        let response = try JSONDecoder().decode(RateLimitsResponse.self, from: data)
        guard response.rateLimits != nil || response.rateLimitsByLimitId != nil
                || response.rateLimitResetCredits != nil else { throw QuotaIssue.invalidResponse }
        let bucket: RateBucket?
        if let buckets = response.rateLimitsByLimitId {
            bucket = buckets["codex"]
        } else {
            let legacy = response.rateLimits
            bucket = legacy?.limitId == nil || legacy?.limitId == "codex" ? legacy : nil
        }
        // A secondary window is not necessarily weekly. Match the actual duration.
        let weekly = [bucket?.primary, bucket?.secondary].compactMap { $0 }
            .first { $0.windowDurationMins == 7 * 24 * 60 }
        let remaining = weekly?.usedPercent.flatMap { $0.isFinite ? max(0, min(100, 100 - $0)) : nil }
        let cards = response.rateLimitResetCredits.flatMap { summary -> QuotaResetCredits? in
            guard let count = summary.availableCount, count >= 0 else { return nil }
            return QuotaResetCredits(availableCount: count, details: summary.credits?.map {
                QuotaResetCredit(status: $0.status ?? "unknown", resetType: $0.resetType ?? "unknown",
                                 expiresAt: $0.expiresAt.map(Date.init(timeIntervalSince1970:)))
            })
        }
        return QuotaSnapshot(weeklyRemainingPercent: remaining,
                             weeklyResetsAt: weekly?.resetsAt.map(Date.init(timeIntervalSince1970:)),
                             resetCredits: cards, fetchedAt: fetchedAt)
    }
}

private struct RateLimitsResponse: Decodable {
    let rateLimits: RateBucket?
    let rateLimitsByLimitId: [String: RateBucket]?
    let rateLimitResetCredits: ResetSummary?
}
private struct RateBucket: Decodable {
    let limitId: String?
    let primary: RateWindow?
    let secondary: RateWindow?
}
private struct RateWindow: Decodable {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: TimeInterval?
}
private struct ResetSummary: Decodable {
    let availableCount: Int?
    let credits: [ResetDetail]?
}
private struct ResetDetail: Decodable {
    let status: String?
    let resetType: String?
    let expiresAt: TimeInterval?
}

private final class QuotaRequest {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let queue: DispatchQueue
    private let timeout: TimeInterval
    private var buffer = Data()
    private var timer: DispatchWorkItem?
    private var completion: ((Result<QuotaSnapshot, QuotaIssue>) -> Void)?
    private var finished = false
    private var initialized = false

    init(executable: URL, queue: DispatchQueue, timeout: TimeInterval) {
        self.queue = queue
        self.timeout = timeout
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = input
        process.standardOutput = output
        // A CLI that exits between handshake writes must not SIGPIPE the app.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        // No account data, bearer tokens, or diagnostic text enters our logs.
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["RUST_LOG"] = "error"
        process.environment = environment
    }

    func start(completion: @escaping (Result<QuotaSnapshot, QuotaIssue>) -> Void) {
        self.completion = completion
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.queue.async { [weak self] in self?.receive(data) }
        }
        process.terminationHandler = { [weak self] _ in
            self?.queue.async { [weak self] in
                // EOF may be queued behind termination; only fail after pending reads.
                self?.queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.finish(.failure(.connectionFailed))
                }
            }
        }
        do { try process.run() } catch { finish(.failure(.connectionFailed)); return }
        let expiry = DispatchWorkItem { [weak self] in self?.finish(.failure(.timeout)) }
        timer = expiry
        queue.asyncAfter(deadline: .now() + timeout, execute: expiry)
        send(["id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "doro_quota", "title": "Doro Quota", "version": "1.0"]
        ]])
    }

    func cancel() { finish(.failure(.cancelled)) }

    func shutdown() {
        if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        finish(.failure(.cancelled))
    }

    private func send(_ message: [String: Any]) {
        guard !finished else { return }
        do {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        } catch { finish(.failure(.connectionFailed)) }
    }

    private func receive(_ data: Data) {
        guard !finished else { return }
        guard !data.isEmpty else { finish(.failure(.connectionFailed)); return }
        buffer.append(data)
        guard buffer.count <= 1_048_576 else { finish(.failure(.invalidResponse)); return }
        while let newline = buffer.firstIndex(of: 10), !finished {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
                finish(.failure(.invalidResponse)); return
            }
            guard let id = message["id"] as? Int else { continue }
            guard id == 1 || id == 2 || id == 3 else { continue }
            if let error = message["error"] as? [String: Any] {
                let text = (error["message"] as? String ?? "").lowercased()
                let issue: QuotaIssue
                if text.contains("not logged") || text.contains("not signed") || text.contains("unauthorized") || text.contains("401") {
                    issue = .notSignedIn
                } else if text.contains("chatgpt authentication") || text.contains("not supported") || text.contains("api key") {
                    issue = .unsupportedAccount
                } else { issue = .connectionFailed }
                finish(.failure(issue)); return
            }
            guard let result = message["result"] as? [String: Any] else {
                finish(.failure(.invalidResponse)); return
            }
            if id == 1 {
                guard !initialized else { finish(.failure(.invalidResponse)); return }
                initialized = true
                send(["method": "initialized", "params": [:]])
                send(["id": 2, "method": "account/read", "params": ["refreshToken": false]])
            } else if id == 2 {
                guard initialized else { finish(.failure(.invalidResponse)); return }
                guard let account = result["account"] as? [String: Any] else {
                    finish(.failure(.notSignedIn)); return
                }
                let type = account["type"] as? String
                guard type != "apiKey", type != "amazonBedrock" else {
                    finish(.failure(.unsupportedAccount)); return
                }
                send(["id": 3, "method": "account/rateLimits/read"])
            } else {
                guard initialized else { finish(.failure(.invalidResponse)); return }
                do {
                    let data = try JSONSerialization.data(withJSONObject: result)
                    finish(.success(try QuotaService.parse(data)))
                } catch { finish(.failure(.invalidResponse)) }
            }
        }
    }

    private func finish(_ result: Result<QuotaSnapshot, QuotaIssue>) {
        guard !finished else { return }
        finished = true
        timer?.cancel()
        timer = nil
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            // A failed or obsolete CLI must not outlive a cancelled request.
            let child = process
            queue.asyncAfter(deadline: .now() + 0.5) {
                if child.isRunning { Darwin.kill(child.processIdentifier, SIGKILL) }
            }
        }
        let callback = completion
        completion = nil
        buffer.removeAll()
        callback?(result)
    }

    deinit {
        timer?.cancel()
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }
}
