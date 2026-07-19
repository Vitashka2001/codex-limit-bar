import Foundation

public struct CodexAccount: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case chatgpt
        case apiKey
        case amazonBedrock
        case unknown
    }

    public let kind: Kind
    public let email: String?
    public let planType: String?

    public init(kind: Kind, email: String?, planType: String?) {
        self.kind = kind
        self.email = email
        self.planType = planType
    }

    public static func decodeAppServerMessage(_ data: Data) throws -> CodexAccount? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any] else {
            return nil
        }

        guard let account = result["account"] as? [String: Any] else {
            return nil
        }

        let rawKind = account["type"] as? String ?? "unknown"
        return CodexAccount(
            kind: Kind(rawValue: rawKind) ?? .unknown,
            email: account["email"] as? String,
            planType: account["planType"] as? String
        )
    }
}
