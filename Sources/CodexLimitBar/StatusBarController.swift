import AppKit
import CodexLimitCore
import OSLog

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private static let monitoringDefaultsKey = "monitoringEnabled"

    private let statusItem = NSStatusBar.system.statusItem(withLength: 66)
    private let client = CodexAppServerClient()
    private let logger = Logger(subsystem: "com.vitashka2001.CodexLimitBar", category: "limits")
    private let gaugeView = LimitGaugeView(frame: NSRect(x: 0, y: 0, width: 388, height: 80))
    private let fiveHourItem = NSMenuItem(title: "5 часов: нет данных", action: nil, keyEquivalent: "")
    private let weeklyItem = NSMenuItem(title: "Неделя: нет данных", action: nil, keyEquivalent: "")
    private let accountItem = NSMenuItem(title: "Аккаунт: подключение", action: nil, keyEquivalent: "")
    private let fiveHourView = LimitInfoLineView(
        frame: NSRect(x: 0, y: 0, width: 388, height: 25),
        systemSymbolName: "clock"
    )
    private let weeklyView = LimitInfoLineView(
        frame: NSRect(x: 0, y: 0, width: 388, height: 25),
        systemSymbolName: "calendar"
    )
    private let accountView = LimitInfoLineView(
        frame: NSRect(x: 0, y: 0, width: 388, height: 25),
        systemSymbolName: "person.crop.circle"
    )
    private let monitoringItem = NSMenuItem(title: "Мониторинг лимитов", action: nil, keyEquivalent: "")
    private let switchAccountItem = NSMenuItem(title: "Сменить аккаунт Codex...", action: nil, keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "Запускать при входе", action: nil, keyEquivalent: "")
    private let refreshItem = NSMenuItem(title: "Обновить", action: nil, keyEquivalent: "r")
    private var refreshTimer: Timer?
    private var snapshot: RateLimitSnapshot?
    private var account: CodexAccount?
    private var monitoringEnabled = true
    private var clientConnected = false
    private var loginInProgress = false

    override init() {
        super.init()
        configureStatusItem()
        configureClient()
        let storedValue = UserDefaults.standard.object(forKey: Self.monitoringDefaultsKey) as? Bool
        setMonitoringEnabled(storedValue ?? true, persist: false)
        refreshLaunchAtLoginState()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        client.stop()
    }

    private func configureStatusItem() {
        let menu = NSMenu()
        menu.delegate = self

        let gaugeItem = NSMenuItem()
        gaugeItem.view = gaugeView
        menu.addItem(gaugeItem)
        menu.addItem(.separator())
        fiveHourItem.view = fiveHourView
        weeklyItem.view = weeklyView
        accountItem.view = accountView
        menu.addItem(fiveHourItem)
        menu.addItem(weeklyItem)
        menu.addItem(accountItem)
        menu.addItem(.separator())

        monitoringItem.target = self
        monitoringItem.action = #selector(toggleMonitoring)
        monitoringItem.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Мониторинг")
        menu.addItem(monitoringItem)

        switchAccountItem.target = self
        switchAccountItem.action = #selector(switchAccount)
        switchAccountItem.image = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: "Сменить аккаунт")
        menu.addItem(switchAccountItem)

        launchAtLoginItem.target = self
        launchAtLoginItem.action = #selector(toggleLaunchAtLogin)
        launchAtLoginItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Автозапуск")
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())

        refreshItem.target = self
        refreshItem.action = #selector(refreshNow)
        refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        menu.addItem(refreshItem)

        let quitItem = NSMenuItem(
            title: "Полностью выключить",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Выключить")
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageOnly
        updateInfo(fiveHourItem, view: fiveHourView, text: fiveHourItem.title)
        updateInfo(weeklyItem, view: weeklyView, text: weeklyItem.title)
        updateInfo(accountItem, view: accountView, text: accountItem.title)
        renderStatus(window: nil, stateText: "...", tooltip: "Лимиты Codex: подключение")
    }

    private func configureClient() {
        client.onSnapshot = { [weak self] snapshot in
            Task { @MainActor in
                self?.apply(snapshot)
            }
        }
        client.onAccount = { [weak self] account in
            Task { @MainActor in
                self?.apply(account)
            }
        }
        client.onStateChange = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .connecting:
                    self.clientConnected = false
                    self.updateInfo(self.accountItem, view: self.accountView, text: "Аккаунт: подключение")
                    self.gaugeView.update(remainingPercent: nil, title: "Подключение к Codex", subtitle: "Запрашиваем данные аккаунта")
                case .connected:
                    self.clientConnected = true
                    if self.snapshot == nil {
                        self.updateInfo(self.accountItem, view: self.accountView, text: "Аккаунт: подключен")
                    }
                case .failed(let message):
                    self.clientConnected = false
                    self.logger.error("Connection failed: \(message, privacy: .public)")
                    self.updateInfo(self.accountItem, view: self.accountView, text: "Аккаунт: Codex недоступен")
                    self.gaugeView.update(remainingPercent: nil, title: "Codex недоступен", subtitle: message)
                    self.renderStatus(window: nil, stateText: "--", tooltip: message)
                }
                self.updateActionAvailability()
            }
        }
        client.onLoginStarted = { [weak self] authURL in
            Task { @MainActor in
                guard let self else { return }
                self.loginInProgress = true
                self.switchAccountItem.title = "Отменить смену аккаунта"
                self.updateActionAvailability()
                guard NSWorkspace.shared.open(authURL) else {
                    self.client.cancelLogin()
                    self.showAlert(
                        title: "Не удалось открыть браузер",
                        message: "Откройте смену аккаунта ещё раз после проверки браузера по умолчанию."
                    )
                    return
                }
            }
        }
        client.onLoginFinished = { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                let wasInProgress = self.loginInProgress
                self.loginInProgress = false
                self.switchAccountItem.title = "Сменить аккаунт Codex..."
                self.updateActionAvailability()
                if success {
                    self.showAlert(
                        title: "Аккаунт Codex переключён",
                        message: "Новые лимиты уже запрашиваются. Изменение действует также в Codex и расширениях редактора."
                    )
                } else if wasInProgress, let error, !error.isEmpty {
                    self.showAlert(title: "Вход не завершён", message: error)
                }
            }
        }
    }

    private func apply(_ snapshot: RateLimitSnapshot) {
        self.snapshot = snapshot
        let selected = snapshot.displayWindow
        let title = selected.map { windowTitle($0) } ?? "Нет данных о лимитах"
        gaugeView.update(
            remainingPercent: selected?.remainingPercent,
            title: selected.map(windowLabel) ?? "Нет данных о лимитах",
            subtitle: selected.map(resetTitle) ?? "Codex не вернул доступное окно"
        )
        updateInfo(fiveHourItem, view: fiveHourView, text: detailTitle(label: "5 часов", window: snapshot.fiveHour))
        updateInfo(weeklyItem, view: weeklyView, text: detailTitle(label: "Неделя", window: snapshot.weekly))
        if account == nil, let planType = snapshot.planType {
            updateInfo(accountItem, view: accountView, text: "Аккаунт: \(displayPlan(planType))")
        }
        renderStatus(window: selected, stateText: nil, tooltip: "Лимиты Codex: \(title)")
        let duration = selected?.windowDurationMinutes ?? 0
        let remaining = selected?.remainingPercent ?? 0
        logger.info("Updated plan=\(snapshot.planType ?? "unknown", privacy: .public) windowMinutes=\(duration) remaining=\(remaining)")
    }

    private func apply(_ account: CodexAccount?) {
        self.account = account
        guard let account else {
            updateInfo(accountItem, view: accountView, text: "Аккаунт: вход не выполнен")
            return
        }

        let plan = account.planType.map(displayPlan)
        switch account.kind {
        case .chatgpt:
            let identity = account.email ?? "ChatGPT"
            updateInfo(
                accountItem,
                view: accountView,
                text: plan.map { "Аккаунт: \(identity) · \($0)" } ?? "Аккаунт: \(identity)"
            )
        case .apiKey:
            updateInfo(accountItem, view: accountView, text: "Аккаунт: API key")
        case .amazonBedrock:
            updateInfo(accountItem, view: accountView, text: "Аккаунт: Amazon Bedrock")
        case .unknown:
            updateInfo(accountItem, view: accountView, text: "Аккаунт: неизвестный тип")
        }
    }

    private func updateInfo(_ item: NSMenuItem, view: LimitInfoLineView, text: String) {
        item.title = text
        item.toolTip = text
        view.update(text)
    }

    private func renderStatus(window: RateLimitWindow?, stateText: String?, tooltip: String) {
        statusItem.button?.image = LimitStatusImage.make(window: window, stateText: stateText)
        statusItem.button?.toolTip = tooltip
        statusItem.button?.setAccessibilityLabel(tooltip)
    }

    private func windowTitle(_ window: RateLimitWindow) -> String {
        let label = windowLabel(window)
        return "\(label) · осталось \(Int(window.remainingPercent.rounded()))%"
    }

    private func windowLabel(_ window: RateLimitWindow) -> String {
        window.windowDurationMinutes == 300 ? "5 часов" :
            (window.windowDurationMinutes == 10_080 ? "Неделя" : "Лимит")
    }

    private func resetTitle(_ window: RateLimitWindow) -> String {
        guard let reset = window.resetsAt else { return "Время сброса недоступно" }
        return "Сброс \(Self.dateFormatter.string(from: reset))"
    }

    private func detailTitle(label: String, window: RateLimitWindow?) -> String {
        guard let window else { return "\(label): нет данных" }
        let remaining = Int(window.remainingPercent.rounded())
        guard let reset = window.resetsAt else {
            return "\(label): осталось \(remaining)%"
        }
        return "\(label): осталось \(remaining)% · сброс \(Self.dateFormatter.string(from: reset))"
    }

    private func displayPlan(_ plan: String) -> String {
        switch plan.lowercased() {
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "team": return "Team"
        case "business", "self_serve_business_usage_based": return "Business"
        case "enterprise", "enterprise_cbp_usage_based": return "Enterprise"
        case "free": return "Free"
        default: return plan.capitalized
        }
    }

    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        let client = self.client
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            client.refresh()
        }
    }

    private func setMonitoringEnabled(_ enabled: Bool, persist: Bool) {
        monitoringEnabled = enabled
        monitoringItem.state = enabled ? .on : .off
        if persist {
            UserDefaults.standard.set(enabled, forKey: Self.monitoringDefaultsKey)
        }

        if enabled {
            updateInfo(accountItem, view: accountView, text: "Аккаунт: подключение")
            gaugeView.update(remainingPercent: nil, title: "Подключение к Codex", subtitle: "Запрашиваем данные аккаунта")
            renderStatus(window: nil, stateText: "...", tooltip: "Лимиты Codex: подключение")
            client.start()
            startRefreshTimer()
        } else {
            refreshTimer?.invalidate()
            refreshTimer = nil
            client.stop()
            clientConnected = false
            snapshot = nil
            account = nil
            loginInProgress = false
            updateInfo(accountItem, view: accountView, text: "Аккаунт: мониторинг остановлен")
            updateInfo(fiveHourItem, view: fiveHourView, text: "5 часов: мониторинг остановлен")
            updateInfo(weeklyItem, view: weeklyView, text: "Неделя: мониторинг остановлен")
            gaugeView.update(remainingPercent: nil, title: "Мониторинг остановлен", subtitle: "Фоновый опрос выключен")
            renderStatus(window: nil, stateText: "off", tooltip: "Мониторинг лимитов Codex остановлен")
        }
        updateActionAvailability()
    }

    private func updateActionAvailability() {
        refreshItem.isEnabled = monitoringEnabled
        switchAccountItem.isEnabled = monitoringEnabled && (clientConnected || loginInProgress)
    }

    @objc private func refreshNow() {
        guard monitoringEnabled else { return }
        client.refresh()
    }

    @objc private func toggleMonitoring() {
        setMonitoringEnabled(!monitoringEnabled, persist: true)
    }

    @objc private func switchAccount() {
        if loginInProgress {
            client.cancelLogin()
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Сменить аккаунт Codex?"
        alert.informativeText = "После успешного входа изменится активный аккаунт Codex на этом Mac, включая Codex, CLI и расширения редакторов. Трекер не хранит пароли или токены."
        alert.addButton(withTitle: "Продолжить в браузере")
        alert.addButton(withTitle: "Отмена")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        loginInProgress = true
        switchAccountItem.title = "Запуск входа..."
        updateActionAvailability()
        client.startChatGPTLogin()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLoginManager.setEnabled(!LaunchAtLoginManager.isEnabled)
        } catch {
            showAlert(title: "Не удалось изменить автозапуск", message: error.localizedDescription)
        }
        refreshLaunchAtLoginState()
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginItem.state = LaunchAtLoginManager.isEnabled ? .on : .off
        launchAtLoginItem.title = "Запускать при входе"
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshLaunchAtLoginState()
        if monitoringEnabled {
            client.refresh()
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private final class LimitGaugeView: NSView {
    private var remainingPercent: Double?
    private var title = "Подключение к Codex"
    private var subtitle = "Запрашиваем данные аккаунта"

    override var isFlipped: Bool { true }

    func update(remainingPercent: Double?, title: String, subtitle: String) {
        self.remainingPercent = remainingPercent.map { min(100, max(0, $0)) }
        self.title = title
        self.subtitle = subtitle
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let percentParagraph = NSMutableParagraphStyle()
        percentParagraph.alignment = .right
        let percentAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: percentParagraph,
        ]

        title.draw(
            in: NSRect(x: 16, y: 11, width: bounds.width - 132, height: 19),
            withAttributes: titleAttributes
        )
        subtitle.draw(
            in: NSRect(x: 16, y: 35, width: bounds.width - 32, height: 16),
            withAttributes: subtitleAttributes
        )
        let percentText = remainingPercent.map { "\(Int($0.rounded()))%" } ?? "—"
        percentText.draw(
            in: NSRect(x: bounds.width - 108, y: 7, width: 92, height: 28),
            withAttributes: percentAttributes
        )

        let trackRect = NSRect(x: 14, y: bounds.height - 14, width: bounds.width - 28, height: 6)
        NSColor.tertiaryLabelColor.withAlphaComponent(0.24).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: 3, yRadius: 3).fill()

        if let remainingPercent, remainingPercent > 0 {
            let fillRect = NSRect(
                x: trackRect.minX,
                y: trackRect.minY,
                width: max(3, trackRect.width * remainingPercent / 100),
                height: trackRect.height
            )
            LimitPalette.color(for: remainingPercent).setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: 3, yRadius: 3).fill()
        }
    }
}

private final class LimitInfoLineView: NSView {
    private let iconView = NSImageView()
    private var text = ""

    init(frame frameRect: NSRect, systemSymbolName: String) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)

        iconView.frame = NSRect(x: 20, y: 6, width: 13, height: 13)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .secondaryLabelColor
        if let icon = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: nil) {
            icon.isTemplate = true
            iconView.image = icon
        }
        addSubview(iconView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func update(_ text: String) {
        self.text = text
        setAccessibilityLabel(text)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        text.draw(
            in: NSRect(x: 42, y: 5, width: bounds.width - 58, height: 16),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.labelColor.withAlphaComponent(0.78),
                .paragraphStyle: paragraph,
            ]
        )
    }
}

@MainActor
private enum LimitStatusImage {
    static func make(window: RateLimitWindow?, stateText: String?) -> NSImage {
        let size = NSSize(width: 64, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let prefix = window.map(shortLabel) ?? ""
            let value = window.map { "\(Int($0.remainingPercent.rounded()))%" } ?? (stateText ?? "--")
            let prefixAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let valueAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]

            let prefixWidth = prefix.size(withAttributes: prefixAttributes).width
            let valueWidth = value.size(withAttributes: valueAttributes).width
            let spacing: CGFloat = prefix.isEmpty ? 0 : 5
            let contentWidth = prefixWidth + spacing + valueWidth
            let contentX = (size.width - contentWidth) / 2
            prefix.draw(at: NSPoint(x: contentX, y: 5), withAttributes: prefixAttributes)
            value.draw(
                at: NSPoint(x: contentX + prefixWidth + spacing, y: 4),
                withAttributes: valueAttributes
            )

            let trackRect = NSRect(x: 1, y: 0, width: size.width - 2, height: 2)
            NSColor.tertiaryLabelColor.withAlphaComponent(0.28).setFill()
            NSBezierPath(roundedRect: trackRect, xRadius: 1, yRadius: 1).fill()
            if let window, window.remainingPercent > 0 {
                let fillRect = NSRect(
                    x: trackRect.minX,
                    y: trackRect.minY,
                    width: max(3, trackRect.width * window.remainingPercent / 100),
                    height: trackRect.height
                )
                LimitPalette.color(for: window.remainingPercent).setFill()
                NSBezierPath(roundedRect: fillRect, xRadius: 1, yRadius: 1).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func shortLabel(_ window: RateLimitWindow) -> String {
        window.windowDurationMinutes == 300 ? "5h" :
            (window.windowDurationMinutes == 10_080 ? "7d" : "")
    }
}

private enum LimitPalette {
    static func color(for remainingPercent: Double) -> NSColor {
        switch remainingPercent {
        case 50...:
            return .systemGreen
        case 20..<50:
            return .systemOrange
        default:
            return .systemRed
        }
    }
}
