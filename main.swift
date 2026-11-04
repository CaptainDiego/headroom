import SwiftUI
import ServiceManagement

// MARK: - Models

struct UsageLimit: Decodable, Identifiable {
    let kind: String
    let percent: Double
    let resets_at: String?
    var id: String { kind }

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

struct BreakdownRow: Decodable, Identifiable {
    let key: String
    let display_name: String
    let percent: Double
    var id: String { key }
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

struct Credentials: Sendable { let token: String; let plan: String? }

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
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}

// Ephemeral: no disk cache, cookies or credential storage.
private let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)

// MARK: - Store

@MainActor
final class UsageStore: ObservableObject {
    @Published var limits: [UsageLimit] = []
    @Published var breakdown: [BreakdownRow] = []
    @Published var plan: String?
    @Published var error: String?
    @Published var lastUpdated: Date?
    @Published var loading = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var loginError: String?
    @Published var showIcon = UserDefaults.standard.object(forKey: "showIcon") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showIcon, forKey: "showIcon") }
    }
    private var timer: Timer?

    init() {
        // Enable launch-at-login once on first run; afterwards respect the user's choice.
        if !UserDefaults.standard.bool(forKey: "didSetupLogin") {
            UserDefaults.standard.set(true, forKey: "didSetupLogin")
            setLaunchAtLogin(true)
        }
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch { loginError = error.localizedDescription }
        syncLoginStatus()
    }

    /// The user can also change this in System Settings, so re-read it when the panel opens.
    func syncLoginStatus() { launchAtLogin = SMAppService.mainApp.status == .enabled }

    var menuTitle: String {
        var t = showIcon ? "✳︎ " : ""
        if limits.isEmpty { return t + "—" }
        let pct = { (k: String) in self.limits.first { $0.kind == k }.map { "\(Int($0.percent))%" } ?? "–" }
        t += "\(pct("session")) · \(pct("weekly_all"))"
        return error == nil ? t : t + " ⚠︎"   // flag stale numbers
    }

    func refresh() async {
        guard !loading else { return }   // timer + button can overlap
        loading = true; defer { loading = false }

        guard let creds = await Task.detached(operation: readCredentials).value else {
            error = "No Claude Code login found. Run `claude` and log in."
            return
        }
        plan = creds.plan

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 20)
        req.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("headroom/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await session.data(for: req)
            switch (resp as? HTTPURLResponse)?.statusCode ?? 0 {
            case 200: break
            case 401: error = "Token expired. Open Claude Code once to refresh it."; return
            case let code: error = "HTTP \(code)"; return
            }
            let r = try JSONDecoder().decode(UsageResponse.self, from: data)
            limits = r.limits ?? []
            breakdown = (r.seven_day_breakdown?.rows ?? []).filter { $0.percent > 0 }
            lastUpdated = Date()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Views

func barColor(_ pct: Double) -> Color { pct >= 90 ? .red : pct >= 70 ? .orange : .accentColor }

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

struct LimitRow: View {
    let limit: UsageLimit
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(limit.title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(limit.percent))%").font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }
            ProgressView(value: min(limit.percent, 100), total: 100).tint(barColor(limit.percent))
            // Keep the countdown live between 5-minute fetches.
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                Text(resetText(limit.resetDate, now: ctx.date)).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var store: UsageStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Claude Usage").font(.headline)
                Spacer()
                if let plan = store.plan {
                    Text(plan.capitalized)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
            }
            if let err = store.error {
                Text(err).font(.system(size: 11)).foregroundStyle(.red)
            }
            ForEach(store.limits) { LimitRow(limit: $0) }

            if !store.breakdown.isEmpty {
                Divider()
                Text("This week by surface").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                ForEach(store.breakdown) { row in
                    HStack {
                        Text(row.display_name)
                        Spacer()
                        Text("\(Int(row.percent))%").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11))
                }
            }
            Divider()
            Group {
                Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: store.setLaunchAtLogin))
                Toggle("Show ✳︎ in menu bar", isOn: $store.showIcon)
            }
            .font(.system(size: 11))
            if let e = store.loginError {
                Text(e).font(.system(size: 10)).foregroundStyle(.red)
            }
            Divider()
            HStack {
                if let t = store.lastUpdated {
                    Text("Updated \(t.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(store.loading).help("Refresh")
                Button { NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!) } label: {
                    Image(systemName: "safari")
                }.help("Open usage page")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("Quit")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 280)
        .onAppear(perform: store.syncLoginStatus)
    }
}

@main
struct HeadroomApp: App {
    @StateObject private var store = UsageStore()
    var body: some Scene {
        MenuBarExtra {
            ContentView(store: store)
        } label: {
            Text(store.menuTitle).monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}
