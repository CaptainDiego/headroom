import AppKit
import ServiceManagement

// MARK: - Models

struct UsageLimit: Decodable {
    let kind: String
    let percent: Double
    let resets_at: String?

    var title: String {
        switch kind {
        case "session": return "Current session (5h)"
        case "weekly_all": return "Weekly · all models"
        case "weekly_opus": return "Weekly · Opus"
        case "weekly_sonnet": return "Weekly · Sonnet"
        default: return kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    var resetDate: Date? { resets_at.flatMap(parseISO) }
}

struct BreakdownRow: Decodable {
    let key: String
    let display_name: String
    let percent: Double
}

struct UsageResponse: Decodable {
    struct Breakdown: Decodable { let rows: [BreakdownRow]? }
    let limits: [UsageLimit]?
    let seven_day_breakdown: Breakdown?
}

private let isoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let isoPlain = ISO8601DateFormatter()
private let dayFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "EEE h:mm a"; return f
}()

func parseISO(_ s: String) -> Date? { isoFrac.date(from: s) ?? isoPlain.date(from: s) }

// MARK: - Credentials (read from Claude Code's keychain entry)

struct Credentials { let token: String; let plan: String? }

/// Blocking: spawns /usr/bin/security. Call off the main thread.
/// Using the `security` binary inherits the item's existing ACL, so there's no keychain prompt.
func readCredentials() -> Credentials? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()  // read before wait: avoids pipe-buffer deadlock
    p.waitUntilExit()
    guard p.terminationStatus == 0,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let oauth = json["claudeAiOauth"] as? [String: Any],
          let token = oauth["accessToken"] as? String else { return nil }
    return Credentials(token: token, plan: oauth["subscriptionType"] as? String)
}

/// Refuses redirects so the bearer token can never be forwarded to another host.
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

// Ephemeral: no disk cache, cookies or credential storage.
private let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)

enum FetchResult {
    case noLogin
    case failed(plan: String?, message: String)
    case ok(plan: String?, UsageResponse)
}

/// Reads the token and fetches usage off the main thread; `done` runs on the main queue.
func fetchUsage(_ done: @escaping (FetchResult) -> Void) {
    DispatchQueue.global(qos: .utility).async {
        let finish = { (r: FetchResult) in DispatchQueue.main.async { done(r) } }
        guard let creds = readCredentials() else { return finish(.noLogin) }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 20)
        req.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("headroom/1.0", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: req) { data, resp, err in
            let fail = { (m: String) in finish(.failed(plan: creds.plan, message: m)) }
            if let err { return fail(err.localizedDescription) }
            switch (resp as? HTTPURLResponse)?.statusCode ?? 0 {
            case 200: break
            case 401: return fail("Token expired. Open Claude Code once to refresh it.")
            case let code: return fail("HTTP \(code)")
            }
            do { finish(.ok(plan: creds.plan, try JSONDecoder().decode(UsageResponse.self, from: data ?? Data()))) }
            catch { fail(error.localizedDescription) }
        }.resume()
    }
}

// MARK: - Views
// Plain AppKit on purpose: SwiftUI's MenuBarExtra cost ~9 MB the first time the panel
// opened and never gave it back. The panel here is built on open and dropped on close.

func resetText(_ d: Date?, now: Date) -> String {
    guard let d else { return "" }
    let secs = Int(d.timeIntervalSince(now))
    if secs <= 0 { return "Resetting…" }
    if secs < 86400 {
        let h = secs / 3600, m = secs % 3600 / 60
        return h > 0 ? "Resets in \(h)h \(m)m" : "Resets in \(m)m"
    }
    return "Resets \(dayFormatter.string(from: d))"
}

func label(_ s: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor,
           digits: Bool = false) -> NSTextField {
    let l = NSTextField(labelWithString: s)
    l.font = digits ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
    l.textColor = color
    return l
}

func row(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
    let s = NSStackView(views: views)
    s.spacing = spacing
    return s
}

func spacer() -> NSView {
    let v = NSView()
    v.setContentHuggingPriority(.init(1), for: .horizontal)
    return v
}

final class BarView: NSView {
    let fraction: CGFloat, color: NSColor, thickness: CGFloat
    init(percent: Double, color: NSColor, thickness: CGFloat) {
        fraction = CGFloat(min(max(percent, 0), 100) / 100); self.color = color; self.thickness = thickness
        super.init(frame: .zero)
        setContentHuggingPriority(.init(1), for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: thickness) }
    override func draw(_ dirtyRect: NSRect) {
        let r = thickness / 2
        NSColor.labelColor.withAlphaComponent(0.1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: r, yRadius: r).fill()
        guard fraction > 0 else { return }
        var fill = bounds; fill.size.width = max(bounds.width * fraction, thickness)
        color.setFill()
        NSBezierPath(roundedRect: fill, xRadius: r, yRadius: r).fill()
    }
}

final class PillView: NSView {
    init(_ text: String) {
        super.init(frame: .zero)
        let l = label(text, size: 10, weight: .semibold)
        l.translatesAutoresizingMaskIntoConstraints = false
        addSubview(l)
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6), l.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            l.topAnchor.constraint(equalTo: topAnchor, constant: 2), l.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    }
}

// MARK: - App

@main
@MainActor
final class Headroom: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = Headroom()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    var limits: [UsageLimit] = []
    var breakdown: [BreakdownRow] = []
    var plan: String?
    var error: String?
    var lastUpdated: Date?
    var loading = false
    var loginError: String?
    var showIcon = UserDefaults.standard.object(forKey: "showIcon") as? Bool ?? true

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    let panelItem = NSMenuItem()
    var countdowns: [(NSTextField, Date?)] = []   // only while the panel is open
    var countdownTimer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        menu.delegate = self
        menu.addItem(panelItem)
        statusItem.menu = menu
        updateTitle()
        // Enable launch-at-login once on first run; afterwards respect the user's choice.
        if !UserDefaults.standard.bool(forKey: "didSetupLogin") {
            UserDefaults.standard.set(true, forKey: "didSetupLogin")
            try? SMAppService.mainApp.register()
        }
        refresh()
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func updateTitle() {
        var t = showIcon ? "✳︎ " : ""
        if limits.isEmpty { t += "—" } else {
            let pct = { (k: String) in self.limits.first { $0.kind == k }.map { "\(Int($0.percent))%" } ?? "–" }
            t += "\(pct("session")) · \(pct("weekly_all"))"
            if error != nil { t += " ⚠︎" }   // flag stale numbers
        }
        statusItem.button?.title = t
    }

    @objc func refresh() {
        guard !loading else { return }   // timer + button can overlap
        loading = true
        stateChanged()
        fetchUsage { [self] result in
            switch result {
            case .noLogin:
                error = "No Claude Code login found. Run `claude` and log in."
            case .failed(let p, let message):
                plan = p; error = message
            case .ok(let p, let r):
                plan = p
                limits = r.limits ?? []
                breakdown = (r.seven_day_breakdown?.rows ?? []).filter { $0.percent > 0 }
                lastUpdated = Date()
                error = nil
            }
            loading = false
            stateChanged()
        }
    }

    func stateChanged() {
        updateTitle()
        if panelItem.view != nil { panelItem.view = buildPanel() }   // panel is open: redraw it
    }

    // MARK: Panel (exists only while the menu is open)

    func menuWillOpen(_ menu: NSMenu) {
        panelItem.view = buildPanel()
        // Keep the countdown live between 5-minute fetches.
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.countdowns.forEach { $0.0.stringValue = resetText($0.1, now: Date()) } }
        }
        RunLoop.main.add(t, forMode: .common)   // .common: the menu runs the loop in event-tracking mode
        countdownTimer = t
    }

    func menuDidClose(_ menu: NSMenu) {
        countdownTimer?.invalidate(); countdownTimer = nil
        countdowns = []
        panelItem.view = nil
    }

    func buildPanel() -> NSView {
        countdowns = []
        var rows: [NSView] = []

        var header: [NSView] = [label("Claude Usage", size: NSFont.systemFontSize, weight: .semibold), spacer()]
        if let plan { header.append(PillView(plan.capitalized)) }
        rows.append(row(header))

        if let error {
            rows.append(errorLabel(error, size: 11))
        }
        let now = Date()
        for limit in limits {
            let color: NSColor = limit.percent >= 90 ? .systemRed : limit.percent >= 70 ? .systemOrange : .controlAccentColor
            let reset = label(resetText(limit.resetDate, now: now), size: 10, color: .secondaryLabelColor)
            countdowns.append((reset, limit.resetDate))
            let v = NSStackView(views: [
                row([label(limit.title, size: 12, weight: .medium), spacer(),
                     label("\(Int(limit.percent))%", size: 12, weight: .semibold, digits: true)]),
                BarView(percent: limit.percent, color: color, thickness: 6),
                reset,
            ])
            v.orientation = .vertical; v.alignment = .leading; v.spacing = 4
            v.arrangedSubviews.prefix(2).forEach { $0.widthAnchor.constraint(equalTo: v.widthAnchor).isActive = true }
            rows.append(v)
        }
        if !breakdown.isEmpty {
            rows.append(separator())
            rows.append(label("This week by surface", size: 11, weight: .medium, color: .secondaryLabelColor))
            // Share of this week's usage (rows sum to ~100%), not % of the limit.
            for b in breakdown {
                let name = label(b.display_name, size: 11)
                name.lineBreakMode = .byTruncatingTail
                name.widthAnchor.constraint(equalToConstant: 80).isActive = true
                let pct = label("\(Int(b.percent))%", size: 11, color: .secondaryLabelColor, digits: true)
                pct.alignment = .right
                pct.widthAnchor.constraint(equalToConstant: 32).isActive = true
                rows.append(row([name, BarView(percent: b.percent, color: .secondaryLabelColor, thickness: 4), pct]))
            }
        }
        rows.append(separator())
        // The user can also change this in System Settings, so it is re-read whenever the panel is built.
        let login = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let icon = NSButton(checkboxWithTitle: "Show ✳︎ in menu bar", target: self, action: #selector(toggleIcon))
        icon.state = showIcon ? .on : .off
        for b in [login, icon] { b.font = .systemFont(ofSize: 11); rows.append(b) }
        if let loginError {
            rows.append(errorLabel(loginError, size: 10))
        }
        rows.append(separator())

        var footer: [NSView] = []
        if let lastUpdated {
            let f = DateFormatter(); f.timeStyle = .short
            footer.append(label("Updated \(f.string(from: lastUpdated))", size: 10, color: .secondaryLabelColor))
        }
        footer.append(spacer())
        let refreshButton = iconButton("arrow.clockwise", "Refresh", #selector(refresh))
        refreshButton.isEnabled = !loading
        footer += [refreshButton, iconButton("safari", "Open usage page", #selector(openUsagePage)),
                   iconButton("power", "Quit", #selector(quit))]
        rows.append(row(footer))

        let panel = NSStackView(views: rows)
        panel.orientation = .vertical; panel.alignment = .leading; panel.spacing = 12
        panel.edgeInsets = NSEdgeInsets(top: 9, left: 14, bottom: 9, right: 14)   // the menu adds ~5pt above and below
        for v in rows { v.widthAnchor.constraint(equalTo: panel.widthAnchor, constant: -28).isActive = true }
        panel.widthAnchor.constraint(equalToConstant: 280).isActive = true
        panel.frame.size = panel.fittingSize
        return panel
    }

    func errorLabel(_ text: String, size: CGFloat) -> NSView {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: size); l.textColor = .systemRed; l.isSelectable = false
        l.preferredMaxLayoutWidth = 252   // panel width minus insets, so fittingSize accounts for wrapping
        return l
    }

    func separator() -> NSView {
        let b = NSBox(); b.boxType = .separator; return b
    }

    func iconButton(_ symbol: String, _ help: String, _ action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: help)!, target: self, action: action)
        b.isBordered = false
        b.toolTip = help
        return b
    }

    @objc func toggleLogin(_ sender: NSButton) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch { loginError = error.localizedDescription }
        stateChanged()
    }

    @objc func toggleIcon(_ sender: NSButton) {
        showIcon = sender.state == .on
        UserDefaults.standard.set(showIcon, forKey: "showIcon")
        updateTitle()
    }

    @objc func openUsagePage() {
        menu.cancelTracking()
        NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
    }

    @objc func quit() { NSApp.terminate(nil) }
}
