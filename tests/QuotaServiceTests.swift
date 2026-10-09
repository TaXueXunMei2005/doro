import Foundation
import Darwin

@main
struct QuotaServiceTests {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fatalError(message) }
    }

    static func parse(_ json: String) throws -> QuotaSnapshot {
        try QuotaService.parse(Data(json.utf8), fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    static func fixture(_ directory: URL, body: String) throws -> URL {
        let url = directory.appendingPathComponent(UUID().uuidString + ".sh")
        try ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    static func fetch(_ service: QuotaService, force: Bool = true) -> QuotaReading {
        var answer: QuotaReading?
        service.fetch(forceRefresh: force) { value in
            require(Thread.isMainThread, "Completion must be on main")
            answer = value
        }
        let deadline = Date().addingTimeInterval(5)
        while answer == nil && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        require(answer != nil, "Completion did not arrive")
        return answer!
    }

    static func main() throws {
        let fixtureJSON = """
        {"rateLimits":{"limitId":"codex","secondary":{"usedPercent":99,"windowDurationMins":10080}},
         "rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":4,"windowDurationMins":300},"secondary":{"usedPercent":23,"windowDurationMins":10080,"resetsAt":1900000000}},"other":{"secondary":{"usedPercent":80,"windowDurationMins":10080}}},
         "rateLimitResetCredits":{"availableCount":3,"credits":[{"status":"available","resetType":"codexRateLimits","expiresAt":1901000000}]}}
        """
        let parsed = try parse(fixtureJSON)
        require(parsed.weeklyRemainingPercent == 77, "Must prefer the codex multi-bucket view")
        require(parsed.weeklyResetsAt?.timeIntervalSince1970 == 1_900_000_000, "Unix seconds must be preserved")
        require(parsed.resetCredits?.availableCount == 3, "Available count is authoritative")
        require(parsed.resetCredits?.details?.count == 1, "Capped details must not change count")
        require(parsed.resetCredits?.details?.first?.expiresAt?.timeIntervalSince1970 == 1_901_000_000, "Credit expiry must be decoded")

        let missing = try parse("""
        {"rateLimits":{"primary":{"usedPercent":0,"windowDurationMins":300},"secondary":{"usedPercent":70},"credits":{"hasCredits":true,"balance":"10","unlimited":false}}}
        """)
        require(missing.weeklyRemainingPercent == nil, "Unknown duration is not weekly")
        require(missing.resetCredits == nil, "Workspace credits are not reset cards")
        let countOnly = try parse("""
        {"rateLimits":{},"rateLimitResetCredits":{"availableCount":2,"credits":null}}
        """)
        require(countOnly.resetCredits?.details == nil, "Missing details must remain unknown")
        let zero = try parse("""
        {"rateLimits":{"primary":{"usedPercent":120,"windowDurationMins":10080}},"rateLimitResetCredits":{"availableCount":0,"credits":[]}}
        """)
        require(zero.weeklyRemainingPercent == 0, "Remaining percentage must clamp")
        require(zero.resetCredits?.availableCount == 0, "Known zero cards must remain zero")
        do { _ = try parse("{}"); fatalError("Empty payload accepted") } catch {}

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("doro-quota-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let wireResult = fixtureJSON.replacingOccurrences(of: "\n", with: "")
        let good = try fixture(temp, body: """
        read -r request
        printf '%s\\n' '{"id":1,"result":{}}'
        read -r initialized
        read -r account
        printf '%s\\n' '{"id":2,"result":{"account":{"type":"chatgpt"}}}'
        read -r quota
        printf '%s\\n' '{"id":3,"result":\(wireResult)}'
        exec /bin/sleep 30
        """)
        let cacheURL = temp.appendingPathComponent("quota.json")
        let liveService = QuotaService(cacheURL: cacheURL, timeout: 1, executableURL: good)
        let live = fetch(liveService)
        require(live.freshness == .live && live.snapshot?.weeklyRemainingPercent == 77, "Live RPC failed")
        require(fetch(liveService, force: false).freshness == .cached, "Recent verified result should cache")

        let pidFile = temp.appendingPathComponent("child.pid")
        let hanging = try fixture(temp, body: "echo $$ > '\(pidFile.path)'\nexec /bin/sleep 30\n")
        let staleService = QuotaService(cacheURL: cacheURL, timeout: 0.1, executableURL: hanging)
        let stale = fetch(staleService, force: false)
        require(stale.freshness == .stale && stale.issue == .timeout, "Disk cache must not pretend to be live")
        let unavailableService = QuotaService(timeout: 1, executableURL: hanging)
        let unavailable = fetch(unavailableService)
        require(unavailable.freshness == .unavailable && unavailable.snapshot == nil, "Timeout without cache should be unknown")
        let timedOutPID = Int32(try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
        RunLoop.main.run(until: Date().addingTimeInterval(0.7))
        require(Darwin.kill(timedOutPID, 0) == -1, "Timed-out child process must be cleaned up")

        let exitsEarly = try fixture(temp, body: "exit 0\n")
        let exited = fetch(QuotaService(timeout: 1, executableURL: exitsEarly))
        require(exited.issue == .connectionFailed && exited.snapshot == nil, "Early process exit must return an error without killing the app")

        let noLogin = try fixture(temp, body: """
        read -r request
        printf '%s\\n' '{"id":1,"result":{}}'
        read -r initialized
        read -r account
        printf '%s\\n' '{"id":2,"result":{"account":null,"requiresOpenaiAuth":true}}'
        exec /bin/sleep 30
        """)
        let signedOut = fetch(QuotaService(cacheURL: cacheURL, timeout: 1, executableURL: noLogin))
        require(signedOut.issue == .notSignedIn && signedOut.snapshot == nil, "Sign-out must clear previous account cache")
        require(!FileManager.default.fileExists(atPath: cacheURL.path), "Sign-out must clear persistent cache")

        let cancelService = QuotaService(timeout: 2, executableURL: hanging)
        var cancellations: [QuotaReading] = []
        cancelService.fetch { cancellations.append($0) }
        cancelService.fetch { cancellations.append($0) }
        cancelService.cancel()
        let deadline = Date().addingTimeInterval(3)
        while cancellations.count < 2 && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        require(cancellations.count == 2 && cancellations.allSatisfy { $0.issue == .cancelled }, "Cancellation must complete coalesced callers once")
        print("Quota service: parser, RPC handshake, main-thread callbacks, cache, timeout, sign-out, and cancellation checks passed.")
    }
}
