//
//  UpdateChecker.swift
//  Downer
//
//  Asks GitHub whether a newer release exists. It never downloads or installs
//  anything: it only reports the result and opens the release page.
//

import AppKit
import SwiftUI

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    struct Release: Equatable {
        let tag: String
        let version: String
        let url: URL
    }

    static let autoCheckKey = "autoCheckUpdates"
    static let lastCheckKey = "lastUpdateCheck"
    private static let endpoint = URL(string: "https://api.github.com/repos/dsameendra/downer/releases/latest")!

    @Published private(set) var latest: Release?
    @Published private(set) var isChecking = false
    @Published private(set) var lastError: String?
    /// True once a check has finished without an error.
    @Published private(set) var hasChecked = false

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var updateAvailable: Bool {
        guard let latest else { return false }
        return Self.isNewer(latest.version, than: Self.currentVersion)
    }

    // MARK: Launch

    /// On when the key is missing; checks at most once a day.
    func checkOnLaunchIfDue() {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: Self.autoCheckKey) as? Bool ?? true
        guard enabled else { return }
        if let last = defaults.object(forKey: Self.lastCheckKey) as? Date,
            Date().timeIntervalSince(last) < 24 * 60 * 60
        { return }
        Task { await check() }
    }

    // MARK: Check

    func check() async {
        guard !isChecking else { return }
        isChecking = true
        lastError = nil
        defer { isChecking = false }

        var request = URLRequest(url: Self.endpoint, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Downer-UpdateCheck", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw CheckError.http(http.statusCode)
            }
            latest = try Self.parse(data)
            hasChecked = true
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
        } catch {
            lastError = (error as? CheckError)?.message ?? "Couldn't reach GitHub."
        }
    }

    func openReleasePage() {
        if let url = latest?.url { NSWorkspace.shared.open(url) }
    }

    private enum CheckError: Error {
        case http(Int)
        case malformed

        var message: String {
            switch self {
            case .http(404): return "No release found."
            case .http(403), .http(429): return "GitHub is rate limiting. Try again later."
            case .http(let code): return "GitHub answered \(code)."
            case .malformed: return "Unexpected reply from GitHub."
            }
        }
    }

    private nonisolated static func parse(_ data: Data) throws -> Release {
        struct Payload: Decodable {
            let tag_name: String
            let html_url: URL
        }
        guard let p = try? JSONDecoder().decode(Payload.self, from: data),
            p.html_url.scheme == "https"
        else { throw CheckError.malformed }
        let version = p.tag_name.hasPrefix("v") ? String(p.tag_name.dropFirst()) : p.tag_name
        return Release(tag: p.tag_name, version: version, url: p.html_url)
    }

    // MARK: Versions

    /// Numeric dotted compare. "2.10.0" > "2.9.1", "2.1" == "2.1.0".
    /// A suffix after "-" or "+" (2.1.0-beta) is ignored.
    nonisolated static func isNewer(_ remote: String, than local: String) -> Bool {
        let a = components(remote)
        let b = components(local)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private nonisolated static func components(_ version: String) -> [Int] {
        var core = Substring(version.trimmingCharacters(in: .whitespaces))
        if core.hasPrefix("v") || core.hasPrefix("V") { core = core.dropFirst() }
        if let cut = core.firstIndex(where: { $0 == "-" || $0 == "+" }) { core = core[..<cut] }
        return core.split(separator: ".").map { Int($0) ?? 0 }
    }
}

/// Small capsule shown when a newer release exists. Opens the release page.
struct UpdateBadge: View {
    @ObservedObject private var updates = UpdateChecker.shared

    var body: some View {
        if updates.updateAvailable, let release = updates.latest {
            Button("Update available") { updates.openReleasePage() }
                .buttonStyle(PillButtonStyle())
                .help("Downer \(release.version) is available. Opens the release page.")
                .transition(.opacity)
        }
    }
}
