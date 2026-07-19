import Foundation

public enum RateLimitIndicatorLevel: Equatable, Sendable {
    case green
    case yellow
    case red

    public init(remainingPercent: Double) {
        switch remainingPercent {
        case 50...:
            self = .green
        case 20..<50:
            self = .yellow
        default:
            self = .red
        }
    }
}

public struct RateLimitWindow: Equatable, Sendable {
    public let usedPercent: Double
    public let windowDurationMinutes: Int
    public let resetsAt: Date?

    public init(usedPercent: Double, windowDurationMinutes: Int, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Double {
        min(100, max(0, 100 - usedPercent))
    }
}

public struct RateLimitSnapshot: Equatable, Sendable {
    public let planType: String?
    public let windows: [RateLimitWindow]
    public let fetchedAt: Date

    public init(planType: String?, windows: [RateLimitWindow], fetchedAt: Date = Date()) {
        self.planType = planType
        self.windows = windows
        self.fetchedAt = fetchedAt
    }

    public var fiveHour: RateLimitWindow? {
        windows.first { $0.windowDurationMinutes == 300 }
    }

    public var weekly: RateLimitWindow? {
        windows.first { $0.windowDurationMinutes == 10_080 }
    }

    public var displayWindow: RateLimitWindow? {
        windows.min { $0.windowDurationMinutes < $1.windowDurationMinutes }
    }

    public static func decodeAppServerMessage(_ data: Data) throws -> RateLimitSnapshot? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let limits = result["rateLimits"] as? [String: Any] else {
            return nil
        }

        var windows: [RateLimitWindow] = []
        if let primary = parseWindow(limits["primary"]) {
            windows.append(primary)
        }
        if let secondary = parseWindow(limits["secondary"]) {
            windows.append(secondary)
        }

        guard !windows.isEmpty else { return nil }
        return RateLimitSnapshot(
            planType: limits["planType"] as? String,
            windows: windows
        )
    }

    private static func parseWindow(_ value: Any?) -> RateLimitWindow? {
        guard let object = value as? [String: Any],
              let used = number(object["usedPercent"]),
              let duration = number(object["windowDurationMins"]) else {
            return nil
        }

        let resetTimestamp = number(object["resetsAt"])
        return RateLimitWindow(
            usedPercent: used,
            windowDurationMinutes: Int(duration),
            resetsAt: resetTimestamp.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
