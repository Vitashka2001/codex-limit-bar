import Foundation

enum LaunchAtLoginManager {
    private static let label = "com.vitashka2001.CodexLimitBar"
    private static let legacyLabel = "com.local.CodexLimitBar"

    static var isEnabled: Bool {
        agentURLs.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func setEnabled(_ enabled: Bool) throws {
        let fileManager = FileManager.default
        if enabled {
            guard let executableURL = Bundle.main.executableURL else {
                throw LaunchAtLoginError.executableNotFound
            }

            try fileManager.createDirectory(
                at: agentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try removeLegacyAgent(using: fileManager)
            let propertyList: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executableURL.path],
                "RunAtLoad": true,
                "ProcessType": "Interactive",
            ]
            let data = try PropertyListSerialization.data(
                fromPropertyList: propertyList,
                format: .xml,
                options: 0
            )
            try data.write(to: agentURL, options: .atomic)
        } else {
            for url in agentURLs where fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private static var agentURL: URL {
        agentURL(label: label)
    }

    private static var agentURLs: [URL] {
        [agentURL(label: label), agentURL(label: legacyLabel)]
    }

    private static func agentURL(label: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    private static func removeLegacyAgent(using fileManager: FileManager) throws {
        let legacyURL = agentURL(label: legacyLabel)
        if fileManager.fileExists(atPath: legacyURL.path) {
            try fileManager.removeItem(at: legacyURL)
        }
    }
}

private enum LaunchAtLoginError: LocalizedError {
    case executableNotFound

    var errorDescription: String? {
        "Не удалось определить исполняемый файл приложения."
    }
}
