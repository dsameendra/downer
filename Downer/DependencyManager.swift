//
//  DependencyManager.swift
//  Downer
//
//  Finds yt-dlp, ffmpeg, ffprobe and deno, installs and updates them from
//  Settings: through Homebrew when it is present, or (yt-dlp and deno) by
//  downloading the official standalone release into Application Support.
//

import AppKit
import CryptoKit
import Foundation

enum Tool: String, CaseIterable, Identifiable {
    case ytDlp, ffmpeg, ffprobe, deno

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ytDlp: return "yt-dlp"
        case .ffmpeg: return "ffmpeg"
        case .ffprobe: return "ffprobe"
        case .deno: return "deno"
        }
    }

    /// Downloads work without the recommended tools; they only get better with them.
    var isRequired: Bool { self != .deno }

    var subtitle: String {
        self == .deno ? "JavaScript runtime. Recommended for YouTube." : ""
    }

    /// ffmpeg has no standalone download Downer can fetch.
    var needsHomebrew: Bool { self == .ffmpeg || self == .ffprobe }

    /// The AppStorage key the download code already reads.
    var defaultsKey: String {
        switch self {
        case .ytDlp: return "ytDlpPath"
        case .ffmpeg: return "ffmpegPath"
        case .ffprobe: return "ffprobePath"
        case .deno: return "denoPath"
        }
    }

    var defaultPath: String { "/opt/homebrew/bin/" + title }

    /// ffprobe ships inside the ffmpeg formula, so both install together.
    var installGroup: Tool { self == .ffprobe ? .ffmpeg : self }

    var brewFormula: String {
        switch self {
        case .ytDlp: return "yt-dlp"
        case .ffmpeg, .ffprobe: return "ffmpeg"
        case .deno: return "deno"
        }
    }
}

/// How a tool gets updated, decided from where it is installed.
enum UpdateMethod: Equatable {
    case brew(formula: String)
    /// The tool updates itself; these are the arguments to run it with.
    case selfUpdate(args: [String])
    /// A path the user picked: Downer does not know how to update it.
    case manual
}

struct ToolStatus: Equatable {
    var path: String?
    var version: String?
    var isInstalled: Bool { path != nil }
}

enum InstallError: LocalizedError {
    case needsHomebrew
    case brewFailed(String)
    case download(String)
    case updateFailed(String)
    case busyDownloading
    case checksum

    var errorDescription: String? {
        switch self {
        case .needsHomebrew:
            return "ffmpeg is installed with Homebrew. Install Homebrew first, then try again."
        case .brewFailed(let detail):
            return "Homebrew could not finish. \(detail)"
        case .download(let detail):
            return "The download failed. \(detail)"
        case .updateFailed(let detail):
            return "The update did not finish. \(detail)"
        case .busyDownloading:
            return "Wait for the downloads to finish before updating."
        case .checksum:
            return "The download didn't match its published checksum, so it was not installed."
        }
    }
}

@MainActor
final class DependencyManager: ObservableObject {
    static let shared = DependencyManager()

    @Published private(set) var status: [Tool: ToolStatus] = [:]
    /// Tools being installed or updated right now. DownloadManager waits while this is not empty.
    @Published private(set) var installing: Set<Tool> = []
    @Published private(set) var log = ""
    @Published private(set) var failure: String?
    /// The outcome of the last update, shown under the list.
    @Published private(set) var notice: String?

    private var activationObserver: NSObjectProtocol?

    private init() {
        refresh()
        // pick up installs done outside the app when the user comes back to it
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: Queries
    /// Required tools that are not installed. Downloads cannot run without these.
    var missing: [Tool] {
        Tool.allCases.filter { $0.isRequired && status[$0]?.isInstalled == false }
    }

    /// Recommended tools that are not installed. Never blocks a download.
    var recommendedMissing: [Tool] {
        Tool.allCases.filter { !$0.isRequired && status[$0]?.isInstalled == false }
    }

    var hasCheckedOnce: Bool { !status.isEmpty }

    var brewPath: String? {
        #if DOWNER_TEST_NO_BREW
            return nil  // lets tests exercise the no-Homebrew install path
        #endif
        return ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    /// True while any tool is being installed or updated (its binary may be swapped).
    var isBusy: Bool { !installing.isEmpty }

    func isInstalling(_ tool: Tool) -> Bool {
        installing.contains(tool.installGroup)
    }

    // MARK: Detection
    /// Each refresh takes a number; only the newest one may publish, so a slow older run
    /// can never overwrite a newer result (or the paths saved for the download code).
    private var refreshGeneration = 0

    func refresh() {
        refreshGeneration += 1
        let generation = refreshGeneration
        Task {
            var result: [Tool: ToolStatus] = [:]
            for tool in Tool.allCases {
                let path = await Task.detached { Self.locate(tool) }.value
                var version: String?
                if let path {
                    version = await Task.detached { Self.version(of: tool, at: path) }.value
                }
                result[tool] = ToolStatus(path: path, version: version)
            }
            guard generation == refreshGeneration else { return }
            for tool in Tool.allCases {
                // keep the download code pointed at a working binary
                if let path = result[tool]?.path, path != Self.configuredPath(tool) {
                    UserDefaults.standard.set(path, forKey: tool.defaultsKey)
                }
            }
            // Cached so JobOptions.current can gate version-specific flags without blocking.
            if let v = result[.ytDlp]?.version {
                UserDefaults.standard.set(v, forKey: Self.ytDlpVersionKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.ytDlpVersionKey)
            }
            status = result
        }
    }

    nonisolated static let ytDlpVersionKey = "ytDlpVersion"

    /// `--js-runtimes` first appeared in yt-dlp 2025.11.12; older builds reject it
    /// as an unknown option, which would fail every download. Unknown version = no.
    nonisolated static func supportsJsRuntimes(_ version: String?) -> Bool {
        guard let token = version?.split(whereSeparator: \.isWhitespace).first else { return false }
        let parts = token.split(separator: ".").map { Int($0) }
        guard parts.count >= 3, parts.allSatisfy({ $0 != nil }) else { return false }
        let numbers = parts.compactMap { $0 }
        let minimum = [2025, 11, 12]
        for (a, b) in zip(numbers, minimum) where a != b { return a > b }
        return true
    }

    nonisolated static var managedBinDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downer/bin", isDirectory: true)
    }

    nonisolated static func configuredPath(_ tool: Tool) -> String {
        UserDefaults.standard.string(forKey: tool.defaultsKey) ?? tool.defaultPath
    }

    nonisolated static func locate(_ tool: Tool) -> String? {
        let fm = FileManager.default
        let configured = configuredPath(tool)
        if fm.isExecutableFile(atPath: configured) { return configured }
        let dirs = [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
            managedBinDirectory.path, NSHomeDirectory() + "/.deno/bin",
        ]
        return dirs.map { $0 + "/" + tool.title }.first { fm.isExecutableFile(atPath: $0) }
    }

    nonisolated private static func version(of tool: Tool, at path: String) -> String? {
        let args = tool == .ffmpeg || tool == .ffprobe ? ["-version"] : ["--version"]
        guard let out = capture(path, args) else { return nil }
        let first = out.split(separator: "\n").first.map(String.init) ?? ""
        if tool == .ytDlp { return first.trimmingCharacters(in: .whitespaces) }
        if tool == .deno {  // "deno 2.1.4 (stable, release, aarch64-apple-darwin)"
            let parts = first.split(separator: " ")
            return parts.count > 1 ? String(parts[1]) : nil
        }
        // "ffmpeg version 7.1 Copyright …"
        let parts = first.split(separator: " ")
        return parts.count > 2 ? String(parts[2]) : nil
    }

    nonisolated private static func capture(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    // MARK: Install
    func install(_ tool: Tool) {
        let group = tool.installGroup
        guard !installing.contains(group) else { return }
        installing.insert(group)
        failure = nil
        notice = nil
        log = "Starting…"

        Task {
            do {
                if let brew = brewPath {
                    try await runBrew(brew, ["install", group.brewFormula])
                } else if group == .ytDlp {
                    try await downloadYtDlp()
                } else if group == .deno {
                    try await downloadDeno()
                } else {
                    throw InstallError.needsHomebrew
                }
            } catch {
                failure = error.localizedDescription
            }
            installing.remove(group)
            log = ""
            refresh()
        }
    }

    func openHomebrewSite() {
        if let url = URL(string: "https://brew.sh") { NSWorkspace.shared.open(url) }
    }

    private func setLog(_ text: String) {
        let line = text
            .split(whereSeparator: \.isNewline)
            .last
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if !line.isEmpty { log = String(line.prefix(90)) }
    }

    private func runBrew(_ brew: String, _ arguments: [String]) async throws {
        // an upgrade needs brew's own index refresh, or it never sees a new release
        let upgrading = arguments.first == "upgrade"
        let (status, output) = try await run(brew, arguments, brewEnvironment: !upgrading)
        if status != 0 {
            throw InstallError.brewFailed(
                Self.lastMessage(in: output).map { "\($0) (exit \(status))" } ?? "(exit \(status))")
        }
    }

    /// Runs a process, streaming its last output line into the log.
    private func run(_ path: String, _ arguments: [String], brewEnvironment: Bool = false)
        async throws -> (status: Int32, output: String)
    {
        try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<(status: Int32, output: String), Error>) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = arguments
            proc.environment = Self.processEnvironment(
                base: ProcessInfo.processInfo.environment, brewEnvironment: brewEnvironment)

            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            let collected = LockedText()
            pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
                let data = h.availableData
                guard !data.isEmpty else {
                    h.readabilityHandler = nil
                    return
                }
                guard let s = String(data: data, encoding: .utf8) else { return }
                collected.append(s)
                Task { @MainActor in
                    self?.setLog(s)
                }
            }
            proc.terminationHandler = { p in
                pipe.fileHandleForReading.readabilityHandler = nil
                // anything the handler had not picked up yet
                if let rest = try? pipe.fileHandleForReading.readToEnd(),
                    let s = String(data: rest, encoding: .utf8)
                {
                    collected.append(s)
                }
                cont.resume(returning: (p.terminationStatus, collected.value))
            }
            do { try proc.run() } catch {
                cont.resume(throwing: InstallError.updateFailed(error.localizedDescription))
            }
        }
    }

    // MARK: Verified downloads

    /// Fetches a small text file (a checksum list) over HTTPS.
    private func fetchText(_ url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw InstallError.download("GitHub answered \(http.statusCode).")
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Downloads `url`, and refuses it unless its SHA-256 equals `expected`.
    private func downloadVerified(_ url: URL, expectedHash: String) async throws -> URL {
        let (tmp, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            try? FileManager.default.removeItem(at: tmp)
            throw InstallError.download("GitHub answered \(http.statusCode).")
        }
        guard (try? Self.sha256Hex(of: tmp)) == expectedHash else {
            try? FileManager.default.removeItem(at: tmp)
            throw InstallError.checksum
        }
        return tmp
    }

    private func downloadYtDlp() async throws {
        setLog("Downloading yt-dlp…")
        let base = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/"
        guard let binary = URL(string: base + "yt-dlp_macos"), let sums = URL(string: base + "SHA2-256SUMS")
        else { return }
        do {
            let list = try await fetchText(sums)
            guard let expected = Self.expectedHash(in: list, for: "yt-dlp_macos") else { throw InstallError.checksum }
            let tmp = try await downloadVerified(binary, expectedHash: expected)
            try Self.installAtomically(tmp, to: Self.managedBinDirectory.appendingPathComponent("yt-dlp"))
        } catch let error as InstallError {
            throw error
        } catch {
            throw InstallError.download(error.localizedDescription)
        }
    }

    private func downloadDeno() async throws {
        setLog("Downloading deno…")
        #if arch(arm64)
            let asset = "deno-aarch64-apple-darwin.zip"
        #else
            let asset = "deno-x86_64-apple-darwin.zip"
        #endif
        let base = "https://github.com/denoland/deno/releases/latest/download/"
        guard let archive = URL(string: base + asset), let sum = URL(string: base + asset + ".sha256sum")
        else { return }
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("downer-deno-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: scratch) }
        do {
            let list = try await fetchText(sum)
            guard let expected = Self.expectedHash(in: list, for: asset, allowBare: true) else {
                throw InstallError.checksum
            }
            let tmp = try await downloadVerified(archive, expectedHash: expected)
            try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
            let zip = scratch.appendingPathComponent("deno.zip")
            try fm.moveItem(at: tmp, to: zip)
            let (status, output) = try await run(
                "/usr/bin/ditto", ["-x", "-k", zip.path, scratch.path])
            guard status == 0 else { throw InstallError.download(output) }
            let unpacked = scratch.appendingPathComponent("deno")
            guard fm.fileExists(atPath: unpacked.path) else {
                throw InstallError.download("The archive did not contain deno.")
            }
            try Self.installAtomically(unpacked, to: Self.managedBinDirectory.appendingPathComponent("deno"))
        } catch let error as InstallError {
            throw error
        } catch {
            throw InstallError.download(error.localizedDescription)
        }
    }

    /// SHA-256 of a file as lowercase hex, read in chunks.
    nonisolated static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The hash for `asset` from `sha256sum`-style text ("<hash>  <name>"). A line with only a hash
    /// counts when `allowBare` (a checksum file that belongs to a single asset).
    nonisolated static func expectedHash(in text: String, for asset: String, allowBare: Bool = false) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard let first = parts.first else { continue }
            let hash = first.lowercased()
            guard hash.count == 64, hash.allSatisfy(\.isHexDigit) else { continue }
            if parts.count == 1 {
                if allowBare { return hash }
                continue
            }
            let name = parts[1].hasPrefix("*") ? String(parts[1].dropFirst()) : String(parts[1])
            if name == asset { return hash }
        }
        return nil
    }

    /// Puts `source` at `dest` in one step: it is staged next to `dest` (same volume), made
    /// executable, then swapped in, so `dest` is always either the old or the new complete file.
    nonisolated static func installAtomically(_ source: URL, to dest: URL) throws {
        let fm = FileManager.default
        let directory = dest.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let staged = directory.appendingPathComponent(".\(dest.lastPathComponent).\(UUID().uuidString).new")
        defer { try? fm.removeItem(at: staged) }
        try fm.moveItem(at: source, to: staged)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.path)
        if fm.fileExists(atPath: dest.path) {
            _ = try fm.replaceItemAt(dest, withItemAt: staged)
        } else {
            try fm.moveItem(at: staged, to: dest)
        }
    }

    // MARK: Update
    /// Where a tool came from, judged by its (symlink-resolved) path.
    nonisolated static func updateMethod(
        for tool: Tool, resolvedPath: String, managedDir: String, home: String = NSHomeDirectory()
    ) -> UpdateMethod {
        // the official install script puts deno here; it replaces itself in place
        if tool == .deno, resolvedPath == home + "/.deno/bin/deno" { return .selfUpdate(args: ["upgrade"]) }
        let managedPrefix = managedDir.hasSuffix("/") ? managedDir : managedDir + "/"
        if resolvedPath.hasPrefix(managedPrefix) {
            switch tool {
            case .ytDlp: return .selfUpdate(args: ["-U"])
            case .deno: return .selfUpdate(args: ["upgrade"])
            case .ffmpeg, .ffprobe: return .manual
            }
        }
        // Homebrew only when the file really lives in its Cellar (a symlink from bin/ or opt/ resolves
        // there). Other things under /opt/homebrew, such as pip or npm installs, are not brew's to upgrade.
        if let formula = brewFormula(inResolvedPath: resolvedPath) { return .brew(formula: formula) }
        return .manual
    }

    /// The formula whose Cellar folder holds `path` ("…/Cellar/<formula>/<version>/…"), if it looks sane.
    nonisolated static func brewFormula(inResolvedPath path: String) -> String? {
        let roots = ["/opt/homebrew/Cellar/", "/usr/local/Cellar/", "/home/linuxbrew/.linuxbrew/Cellar/"]
        guard let root = roots.first(where: { path.hasPrefix($0) }) else { return nil }
        let parts = path.dropFirst(root.count).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 3, let name = parts.first.map(String.init), !name.isEmpty, !name.hasPrefix("-"),
            name.allSatisfy({ $0.isLetter || $0.isNumber || "@._+-".contains($0) }),
            !name.contains("..")
        else { return nil }
        return name
    }

    func updateMethod(for tool: Tool) -> UpdateMethod? {
        guard let path = status[tool]?.path else { return nil }
        let managed = Self.managedBinDirectory.path
        // a managed binary is judged by where Downer put it, anything else by where its symlink leads
        let judged = path.hasPrefix(managed + "/") ? path : (path as NSString).resolvingSymlinksInPath
        let method = Self.updateMethod(for: tool, resolvedPath: judged, managedDir: managed)
        if case .brew = method, brewPath == nil { return .manual }
        return method
    }

    /// Updating swaps the tool's binary, so it waits until no download is using one.
    nonisolated static func canUpdate(downloadsActive: Bool, installing: Set<Tool>, tool: Tool) -> Bool {
        !downloadsActive && !installing.contains(tool.installGroup)
    }

    func update(_ tool: Tool) {
        let group = tool.installGroup
        guard !installing.contains(group), let method = updateMethod(for: tool),
            let path = status[tool]?.path
        else { return }
        guard Self.canUpdate(downloadsActive: DownloadManager.shared.isActive, installing: installing, tool: tool)
        else {
            failure = InstallError.busyDownloading.localizedDescription
            notice = nil
            return
        }
        installing.insert(group)
        failure = nil
        notice = nil
        log = "Updating \(group.title)…"

        Task {
            do {
                // read now: the cached version can be stale if an earlier refresh is still running
                let before = await Task.detached { Self.version(of: tool, at: path) }.value
                switch method {
                case .brew(let formula):
                    guard let brew = brewPath else { throw InstallError.needsHomebrew }
                    try await runBrew(brew, ["upgrade", formula])
                case .selfUpdate(let args):
                    let (code, output) = try await run(path, args)
                    if let problem = Self.selfUpdateFailure(code: code, output: output) {
                        throw InstallError.updateFailed(problem)
                    }
                case .manual:
                    break
                }
                let after = await Task.detached { Self.version(of: tool, at: path) }.value
                guard after != nil else {
                    throw InstallError.updateFailed("\(group.title) did not start afterwards.")
                }
                notice = Self.updateNotice(title: group.title, before: before, after: after)
            } catch {
                failure = error.localizedDescription
            }
            installing.remove(group)
            log = ""
            refresh()
        }
    }

    // MARK: Update output (pure, so it can be tested)

    /// Colour codes and blank lines removed, last line kept.
    nonisolated static func lastMessage(in output: String) -> String? {
        let clean = output.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        let line = clean.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        return line.map { String($0.prefix(120)) }
    }

    /// Why a `yt-dlp -U` / `deno upgrade` run failed, or nil when it worked.
    /// yt-dlp can print an ERROR line and still exit 0, so the text is checked too.
    nonisolated static func selfUpdateFailure(code: Int32, output: String) -> String? {
        let message = lastMessage(in: output)
        if code != 0 { return message ?? "(exit \(code))" }
        let errorLine = output.split(whereSeparator: \.isNewline)
            .first { $0.hasPrefix("ERROR:") }
        return errorLine.map { String($0.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
    }

    nonisolated static func updateNotice(title: String, before: String?, after: String?) -> String {
        if let after, after != before { return "\(title) updated to \(after)" }
        return "\(title) is already up to date"
    }

    /// The environment tools run with. A GUI app starts with a bare PATH and may lack
    /// HOME-style variables, so brew's own directory is added and colours are turned off.
    nonisolated static func processEnvironment(
        base: [String: String], brewEnvironment: Bool
    ) -> [String: String] {
        var env = base
        if brewEnvironment { env["HOMEBREW_NO_AUTO_UPDATE"] = "1" }
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["NONINTERACTIVE"] = "1"
        env["NO_COLOR"] = "1"
        let wanted = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var parts = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in wanted where !parts.contains(dir) { parts.append(dir) }
        env["PATH"] = parts.joined(separator: ":")
        if env["HOME"] == nil { env["HOME"] = NSHomeDirectory() }
        return env
    }
}

/// Collects process output from a readability handler's background queue.
private final class LockedText: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    func append(_ s: String) { lock.lock(); text += s; lock.unlock() }
    var value: String { lock.lock(); defer { lock.unlock() }; return text }
}
