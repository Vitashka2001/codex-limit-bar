import Foundation
import CodexLimitCore

final class CodexAppServerClient: @unchecked Sendable {
    enum ConnectionState: Equatable {
        case connecting
        case connected
        case failed(String)
    }

    var onSnapshot: ((RateLimitSnapshot) -> Void)?
    var onAccount: ((CodexAccount?) -> Void)?
    var onStateChange: ((ConnectionState) -> Void)?
    var onLoginStarted: ((URL) -> Void)?
    var onLoginFinished: ((_ success: Bool, _ error: String?) -> Void)?

    private enum RequestKind {
        case account
        case rateLimits
        case login
        case cancelLogin
    }

    private let ioQueue = DispatchQueue(label: "com.vitashka2001.CodexLimitBar.app-server")
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var readBuffer = Data()
    private var nextRequestID = 1
    private var initialized = false
    private var pendingRequests: [Int: RequestKind] = [:]
    private var activeLoginID: String?
    private let tracingEnabled = ProcessInfo.processInfo.environment["CODEX_LIMIT_BAR_TRACE"] == "1"

    func start() {
        ioQueue.async { [weak self] in
            self?.startProcess()
        }
    }

    func stop() {
        ioQueue.async { [weak self] in
            self?.tearDown()
        }
    }

    func refresh() {
        ioQueue.async { [weak self] in
            guard let self else { return }
            if self.process == nil {
                self.startProcess()
            } else {
                self.requestAccount()
                self.requestRateLimits()
            }
        }
    }

    func startChatGPTLogin() {
        ioQueue.async { [weak self] in
            guard let self else { return }
            guard self.initialized, self.process?.isRunning == true else {
                self.emitLoginFinished(success: false, error: "Codex app-server is not connected")
                return
            }
            guard self.activeLoginID == nil else { return }
            _ = self.sendRequest(
                method: "account/login/start",
                params: ["type": "chatgpt"],
                kind: .login
            )
        }
    }

    func cancelLogin() {
        ioQueue.async { [weak self] in
            guard let self, let loginID = self.activeLoginID else { return }
            _ = self.sendRequest(
                method: "account/login/cancel",
                params: ["loginId": loginID],
                kind: .cancelLogin
            )
        }
    }

    private func startProcess() {
        guard process == nil else { return }
        emitState(.connecting)

        guard let codexPath = CodexBinaryLocator.find() else {
            emitState(.failed("Codex executable not found"))
            return
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let client = self else { return }
            client.ioQueue.async { [weak client] in
                client?.consume(data)
            }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        process.terminationHandler = { [weak self] _ in
            guard let client = self else { return }
            client.ioQueue.async { [weak client] in
                client?.tearDown()
                client?.emitState(.failed("Codex app-server stopped"))
            }
        }

        do {
            try process.run()
            self.process = process
            inputPipe = input
            outputPipe = output
            errorPipe = errors
            send([
                "id": 0,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "codex-limit-bar",
                        "title": "Codex Limit Bar",
                        "version": Bundle.main.object(
                            forInfoDictionaryKey: "CFBundleShortVersionString"
                        ) as? String ?? "1.0.0",
                    ],
                ],
            ])
        } catch {
            tearDown()
            emitState(.failed("Could not start Codex app-server"))
        }
    }

    private func consume(_ data: Data) {
        readBuffer.append(data)
        while let newline = readBuffer.firstIndex(of: 0x0A) {
            let line = readBuffer[..<newline]
            readBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            handleMessage(Data(line))
        }
    }

    private func handleMessage(_ data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if (root["id"] as? NSNumber)?.intValue == 0, !initialized {
            initialized = true
            trace("initialized")
            send(["method": "initialized", "params": [:]])
            emitState(.connected)
            requestAccount()
            requestRateLimits()
            return
        }

        if let method = root["method"] as? String {
            handleNotification(method: method, root: root)
            return
        }

        guard let requestID = (root["id"] as? NSNumber)?.intValue,
              let requestKind = pendingRequests.removeValue(forKey: requestID) else {
            return
        }

        if let error = root["error"] as? [String: Any] {
            handleRequestError(error, kind: requestKind)
            return
        }

        switch requestKind {
        case .account:
            let account = try? CodexAccount.decodeAppServerMessage(data)
            trace(account == nil ? "account: signed-out" : "account: received")
            DispatchQueue.main.async { [weak self] in
                self?.onAccount?(account ?? nil)
            }
        case .rateLimits:
            if let snapshot = try? RateLimitSnapshot.decodeAppServerMessage(data) {
                trace("rate-limits: \(snapshot.windows.count) window(s)")
                DispatchQueue.main.async { [weak self] in
                    self?.onSnapshot?(snapshot)
                }
            } else {
                trace("rate-limits: unavailable")
            }
        case .login:
            handleLoginStart(root)
        case .cancelLogin:
            break
        }
    }

    private func handleNotification(method: String, root: [String: Any]) {
        switch method {
        case "account/rateLimits/updated":
            requestRateLimits()
        case "account/updated":
            requestAccount()
            requestRateLimits()
        case "account/login/completed":
            guard let params = root["params"] as? [String: Any] else { return }
            let notificationLoginID = params["loginId"] as? String
            guard let expectedLoginID = activeLoginID,
                  notificationLoginID == nil || notificationLoginID == expectedLoginID else {
                return
            }
            activeLoginID = nil
            let success = (params["success"] as? Bool) == true
            let error = params["error"] as? String
            emitLoginFinished(success: success, error: error)
            if success {
                requestAccount()
                requestRateLimits()
            }
        default:
            break
        }
    }

    private func handleLoginStart(_ root: [String: Any]) {
        guard let result = root["result"] as? [String: Any],
              result["type"] as? String == "chatgpt",
              let loginID = result["loginId"] as? String,
              let authURLString = result["authUrl"] as? String,
              let authURL = URL(string: authURLString) else {
            emitLoginFinished(success: false, error: "Codex returned an invalid login response")
            return
        }

        activeLoginID = loginID
        DispatchQueue.main.async { [weak self] in
            self?.onLoginStarted?(authURL)
        }
    }

    private func handleRequestError(_ error: [String: Any], kind: RequestKind) {
        let message = error["message"] as? String ?? "Unknown Codex error"
        if kind == .login {
            activeLoginID = nil
            emitLoginFinished(success: false, error: message)
        }
    }

    private func requestAccount() {
        guard initialized, process?.isRunning == true else { return }
        _ = sendRequest(
            method: "account/read",
            params: ["refreshToken": false],
            kind: .account
        )
    }

    private func requestRateLimits() {
        guard initialized, process?.isRunning == true else { return }
        _ = sendRequest(method: "account/rateLimits/read", params: [:], kind: .rateLimits)
    }

    @discardableResult
    private func sendRequest(method: String, params: [String: Any], kind: RequestKind) -> Int {
        let requestID = nextRequestID
        nextRequestID += 1
        pendingRequests[requestID] = kind
        send(["id": requestID, "method": method, "params": params])
        return requestID
    }

    private func send(_ object: [String: Any]) {
        guard let handle = inputPipe?.fileHandleForWriting,
              var data = try? JSONSerialization.data(withJSONObject: object) else {
            return
        }
        data.append(0x0A)
        handle.write(data)
    }

    private func emitState(_ state: ConnectionState) {
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(state)
        }
    }

    private func emitLoginFinished(success: Bool, error: String?) {
        DispatchQueue.main.async { [weak self] in
            self?.onLoginFinished?(success, error)
        }
    }

    private func trace(_ message: String) {
        guard tracingEnabled,
              let data = "[CodexLimitBar] \(message)\n".data(using: .utf8) else {
            return
        }
        try? FileHandle.standardError.write(contentsOf: data)
    }

    private func tearDown() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        if process?.isRunning == true {
            process?.terminationHandler = nil
            process?.terminate()
        }
        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        initialized = false
        pendingRequests.removeAll(keepingCapacity: true)
        activeLoginID = nil
        readBuffer.removeAll(keepingCapacity: true)
    }
}

private enum CodexBinaryLocator {
    static func find() -> String? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        var candidates: [String] = []

        if let override = ProcessInfo.processInfo.environment["CODEX_BINARY"] {
            candidates.append(override)
        }

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/codex" }
        }

        candidates += [
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.codex/bin/codex",
        ]

        let architectures = ["macos-aarch64", "macos-x86_64"]
        for extensionsRoot in ["\(home)/.vscode/extensions", "\(home)/.cursor/extensions"] {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: extensionsRoot) else {
                continue
            }
            for entry in entries.filter({ $0.hasPrefix("openai.chatgpt-") }).sorted().reversed() {
                for architecture in architectures {
                    candidates.append("\(extensionsRoot)/\(entry)/bin/\(architecture)/codex")
                }
            }
        }

        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }
}
