//
//  DownloadManager.swift
//  Downer
//
//  The download queue, shared by the main window and the menu bar popover.
//  Links (single videos or playlists, in any mix) are added at any time; they
//  are looked up, then downloaded one after another by yt-dlp, run with an
//  argument list (no shell). Output becomes per-job and per-video progress.
//

import AppKit
import Combine
import Foundation

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var jobs: [DownloadJob] = []
    @Published private(set) var status = "Idle"
    /// Increments each time a job finishes cleanly; views use it to celebrate once.
    @Published private(set) var completions = 0
    /// True when something in the queue failed, so the menu bar icon can ask for attention.
    @Published private(set) var hadError = false

    private var process: Process?
    private var runningID: UUID?
    private var tracker = PlaylistTracker()
    private var pathFile: URL?
    private var runDirectory: URL?
    private var lastErrorLine: String?
    /// ERROR and WARNING lines of the current run (in memory only, capped), used to pick an error hint.
    private var errorLog = ErrorLog()
    /// Shown instead of "Starting download…" when a job starts again after a retry, so the retry is visible.
    private var startNotes: [UUID: String] = [:]
    private var wasCancelled = false
    private var stopQueue = false
    private var idleTask: Task<Void, Never>?

    // look-ups run one at a time so pasting twenty links does not start twenty yt-dlps
    private var toResolve: [UUID] = []
    private var resolving = false
    private var probeControl: ProbeControl?
    private var probingID: UUID?
    private var installObserver: AnyCancellable?

    private init() {
        // A tool update/install may be running; when it ends, carry on with what is waiting.
        // (@Published emits before the change, so hop to the next turn to read the new value.)
        installObserver = DependencyManager.shared.$installing
            .filter { $0.isEmpty }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.stopQueue, self.runningID == nil,
                    self.jobs.contains(where: { $0.state == .queued })
                else { return }
                self.resolveNext()
            }
    }

    #if DEBUG
        /// Previews and screenshots only: show a queue without running anything.
        static var previewTrayOpen = false
        func loadPreview(jobs: [DownloadJob], status: String) {
            self.jobs = jobs
            self.status = status
        }
    #else
        static let previewTrayOpen = false
    #endif

    // MARK: Derived state
    var summary: QueueSummary { QueueSummary(jobs: jobs) }
    var isDownloading: Bool { runningID != nil }
    /// Something is running or waiting.
    var isActive: Bool { jobs.contains { $0.state == .running || $0.state == .queued } }
    /// A queue tray is warranted: more than one link, or a playlist.
    var needsTray: Bool { jobs.count > 1 || jobs.first?.isPlaylist == true }
    var runningJob: DownloadJob? { jobs.first { $0.id == runningID } }

    /// 0…1 across the whole queue while it is active.
    var progress: Double? { isActive ? summary.overall : nil }

    var lastFiles: [URL] { jobs.flatMap(\.files) }

    /// "3/14" while several videos are queued; nil for a lone video.
    var queueLabel: String? {
        let s = summary
        guard s.units > 1, let position = s.currentPosition else { return nil }
        return "\(position)/\(s.units)"
    }

    // MARK: Adding links
    /// Accepts one link or several separated by spaces or new lines. Returns how many were queued.
    @discardableResult
    func add(_ text: String) -> Int {
        let links = Self.links(in: text)
        guard !links.isEmpty else {
            status = "Paste a link to a video or playlist."
            return 0
        }
        idleTask?.cancel()

        // a fresh session: drop what finished last time
        if !isActive {
            jobs.removeAll { $0.isFinished }
            hadError = false
            stopQueue = false
        }

        var added = 0
        let options = JobOptions.current()
        for link in links {
            if jobs.contains(where: { $0.url == link && !$0.isFinished }) { continue }
            let job = DownloadJob(url: link, options: options)
            jobs.append(job)
            toResolve.append(job.id)
            added += 1
        }
        if added > 0 { stopQueue = false }  // new links after a Cancel All still run
        if added == 0 {
            status = "Already in the queue."
        } else if isDownloading {
            status = added == 1 ? "Added to the queue." : "Added \(added) to the queue."
        } else {
            status = "Checking link…"
        }
        resolveNext()
        return added
    }

    nonisolated static func links(in text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "<>\"',")) }
            .filter { raw in
                if raw.lowercased().hasPrefix("ytsearch") { return true }
                guard let url = URL(string: raw), let scheme = url.scheme?.lowercased() else { return false }
                return (scheme == "http" || scheme == "https") && url.host != nil
            }
    }

    // MARK: Controlling
    /// Stop the download in progress; the queue carries on with the next one.
    func cancelCurrent() {
        guard process != nil else { return }
        wasCancelled = true
        process?.terminate()
    }

    /// Stop everything, including what is waiting.
    func cancelAll() {
        stopQueue = true
        // a look-up in flight must stop too, and must never go on to the cookie probe
        abandonProbe()
        toResolve.removeAll()
        for i in jobs.indices where jobs[i].state == .queued {
            jobs[i].state = .cancelled
            jobs[i].isResolving = false
        }
        startNotes.removeAll()
        if process != nil {
            wasCancelled = true
            process?.terminate()
        } else {
            status = "Download cancelled."
            scheduleIdle()
        }
    }

    /// Move a waiting link to another place in the queue. Links that are running or finished stay put,
    /// and a waiting link never goes above them.
    func move(_ id: UUID, toIndex: Int) {
        let waiting = jobs.map { $0.state == .queued }
        guard let from = jobs.firstIndex(where: { $0.id == id }),
            let to = QueueOrder.destination(from: from, to: toIndex, waiting: waiting)
        else { return }
        jobs.insert(jobs.remove(at: from), at: to)
    }

    /// Remove a waiting or finished job, or stop a running one.
    func remove(_ id: UUID) {
        if id == runningID {
            cancelCurrent()
        } else {
            let wasProbing = id == probingID
            if wasProbing { abandonProbe() }  // stops yt-dlp and skips the cookie retry
            toResolve.removeAll { $0 == id }
            startNotes[id] = nil
            jobs.removeAll { $0.id == id }
            if jobs.isEmpty { status = "Idle" }
            if wasProbing { resolveNext() }  // the queue carries on with the next link
        }
    }

    /// Stops the look-up in flight (if any) and frees the look-up slot immediately.
    private func abandonProbe() {
        probeControl?.cancel()
        probeControl = nil
        probingID = nil
        resolving = false
    }

    func retry(_ id: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].isFinished, jobs[i].state != .done
        else { return }
        if let failed = jobs[i].playlist?.failed.map(\.id), !failed.isEmpty {
            jobs[i].only = failed
        } else {
            jobs[i].only = nil
            jobs[i].fraction = 0
            if var p = jobs[i].playlist {
                for k in p.items.indices where p.items[k].state != .done {
                    p.items[k].state = .queued
                    p.items[k].fraction = 0
                }
                jobs[i].playlist = p
            }
        }
        jobs[i].state = .queued
        jobs[i].detail = nil
        stopQueue = false
        hadError = jobs.contains { $0.state == .failed }
        pump()
    }

    func retryAllFailed() {
        for job in jobs where job.state == .failed || job.state == .cancelled { retry(job.id) }
    }

    /// Drop everything that has finished.
    func clearFinished() {
        jobs.removeAll { $0.isFinished }
        if jobs.isEmpty {
            hadError = false
            status = "Idle"
        }
    }

    /// Show one job's files in Finder.
    func reveal(job id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        if job.files.isEmpty {
            NSWorkspace.shared.open(job.options.folder)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(job.files)
        }
    }

    func revealFiles() {
        let files = lastFiles
        if files.isEmpty {
            NSWorkspace.shared.open(JobOptions.current().folder)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(files)
        }
    }

    // MARK: Looking links up
    private func resolveNext() {
        guard !resolving, !stopQueue else { return }
        if QueueLogic.mustWaitForInstall(DependencyManager.shared.installing) {
            if jobs.contains(where: { $0.state == .queued }) && runningID == nil {
                status = "Waiting for the update to finish…"
            }
            return
        }
        while let id = toResolve.first {
            toResolve.removeFirst()
            guard let job = jobs.first(where: { $0.id == id }), job.isResolving, job.state == .queued
            else { continue }
            resolving = true
            let control = ProbeControl()
            probeControl = control
            probingID = id
            let path = Self.path(for: .ytDlp)
            let url = job.url
            let only = job.only
            let options = job.options
            Task.detached { [weak self] in
                // always without cookies first; with them only after a sign-in failure
                var result = Self.probe(
                    url: url, ytDlp: path, options: options, only: only, useCookies: false, control: control)
                var usedCookies = false
                // the current Sign-in setting, not the one from when the link was added;
                // never for a look-up that was cancelled (the cookie probe can raise a Keychain prompt)
                if !control.isCancelled, result.value == nil, let browser = CookieBrowser.current(),
                    ErrorHint.classify(result.errorText, cookiesBrowser: browser, usedCookies: false)?.isSignIn == true
                {
                    var withCookies = options
                    withCookies.cookiesBrowser = browser
                    usedCookies = true
                    result = Self.probe(
                        url: url, ytDlp: path, options: withCookies, only: only, useCookies: true, control: control)
                }
                await self?.applyProbe(
                    result.value, usedCookies: usedCookies && result.value != nil, to: id, control: control)
            }
            return
        }
        pump()
    }

    private func applyProbe(_ result: ProbeResult?, usedCookies: Bool = false, to id: UUID, control: ProbeControl) {
        // a look-up that was cancelled or removed already freed its slot; its late answer is ignored
        guard probeControl === control else { return }
        probeControl = nil
        probingID = nil
        resolving = false
        if let i = jobs.firstIndex(where: { $0.id == id }) {
            jobs[i].isResolving = false
            if usedCookies { jobs[i].needsCookies = true }
            if let result {
                jobs[i].title = result.playlistTitle ?? result.titles.first
                if let name = result.playlistTitle, result.titles.count > 1, jobs[i].state == .queued {
                    jobs[i].playlist = PlaylistProgress(
                        title: name,
                        items: result.titles.enumerated().map {
                            PlaylistItem(id: $0.offset + 1, title: $0.element)
                        },
                        current: nil, speed: nil)
                }
            }
        }
        resolveNext()
    }

    struct ProbeResult {
        var playlistTitle: String?
        var titles: [String]
    }

    /// One quick yt-dlp call that lists titles without downloading anything.
    /// `errorText` is yt-dlp's stderr, kept in memory only so a sign-in failure can be recognised.
    nonisolated private static func probe(
        url: String, ytDlp: String, options: JobOptions, only: [Int]?, useCookies: Bool, control: ProbeControl
    ) -> (value: ProbeResult?, errorText: String) {
        guard let runDirectory = RunDirectory.make() else { return (nil, "") }
        defer { RunDirectory.remove(runDirectory) }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ytDlp)
        proc.currentDirectoryURL = runDirectory  // not the app's own folder: see RunDirectory
        proc.arguments = YtDlpArguments.build(
            for: options, purpose: .probe(only: only), useCookies: useCookies, url: url)
        proc.environment = YtDlpEnvironment.make(
            base: ProcessInfo.processInfo.environment, ffmpegDirectory: nil, home: FullDiskAccess.realHome())
        let pipe = Pipe()
        let errorPipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = errorPipe
        guard control.launch(proc) else { return (nil, "") }
        defer { control.processEnded() }
        try? pipe.fileHandleForWriting.close()
        try? errorPipe.fileHandleForWriting.close()

        // read stderr alongside stdout so neither pipe can fill up and stall yt-dlp
        let errors = ErrorCollector()
        let errorDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            errors.set(errorPipe.fileHandleForReading.readDataToEndOfFile())
            errorDone.signal()
        }

        // a link that never answers must not hold up the queue
        let watchdog = DispatchWorkItem { if proc.isRunning { proc.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 45, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        watchdog.cancel()
        errorDone.wait()
        let errorText = errors.text
        guard proc.terminationStatus == 0 else { return (nil, errorText) }
        return (parse(data), errorText)
    }

    nonisolated private static func parse(_ data: Data) -> ProbeResult? {
        let lines = (String(data: data, encoding: .utf8) ?? "")
            .split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else { return nil }
        var playlistTitle: String?
        var titles: [String] = []
        for line in lines {
            let parts = line.components(separatedBy: "\t")
            if parts.count >= 2 {
                if playlistTitle == nil, !parts[0].isEmpty, parts[0] != "NA" { playlistTitle = parts[0] }
                titles.append(parts[1])
            } else {
                titles.append(line)
            }
        }
        return ProbeResult(playlistTitle: playlistTitle, titles: titles)
    }

    // MARK: Running
    private func pump() {
        guard runningID == nil, !stopQueue else { return }
        guard let next = jobs.first(where: { $0.state == .queued }) else {
            finishQueue()
            return
        }
        // a tool is being updated or installed: wait, and carry on when it is done
        if QueueLogic.mustWaitForInstall(DependencyManager.shared.installing) {
            status = "Waiting for the update to finish…"
            return
        }
        // wait for the look-up so the job starts with real titles
        if next.isResolving {
            // a retried link whose look-up was cut short must be looked up again, or it would wait forever
            if probingID != next.id, !toResolve.contains(next.id) { toResolve.append(next.id) }
            status = "Checking link…"
            resolveNext()
            return
        }
        run(next.id)
    }

    private func run(_ id: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        // Sign-in may have been switched off (or changed) since this link was queued
        let browser = CookieBrowser.current()
        if jobs[i].needsCookies, browser == nil { jobs[i].needsCookies = false }
        let job = jobs[i]
        var options = job.options
        options.cookiesBrowser = browser
        let fm = FileManager.default
        let ytDlpPath = Self.path(for: .ytDlp)
        let ffmpegPath = Self.path(for: .ffmpeg)
        let ffprobePath = Self.path(for: .ffprobe)

        func stop(_ message: String) {
            jobs[i].state = .failed
            jobs[i].detail = message
            hadError = true
            status = message
            pump()  // a missing folder should not block the links that can still run
        }
        guard fm.fileExists(atPath: job.options.folder.path) else {
            stop("Destination folder not found.")
            return
        }
        guard fm.isExecutableFile(atPath: ytDlpPath) else {
            stop("yt‑dlp not found. Install it in Settings.")
            return
        }
        guard fm.isExecutableFile(atPath: ffmpegPath), fm.isExecutableFile(atPath: ffprobePath) else {
            stop("ffmpeg not found. Install it in Settings.")
            return
        }

        let pathFile = fm.temporaryDirectory.appendingPathComponent("downer-\(UUID().uuidString).txt")
        self.pathFile = pathFile
        // cookies only once this job has hit a sign-in wall (see finished(code:job:))
        let args = YtDlpArguments.build(
            for: options,
            purpose: .download(
                pathFile: pathFile.path,
                ffmpegDirectory: (ffmpegPath as NSString).deletingLastPathComponent,
                outputFolder: job.options.folder.path,
                only: job.only),
            useCookies: job.needsCookies, url: job.url)

        guard let workDirectory = RunDirectory.make() else {
            stop("Couldn't prepare a working folder.")
            return
        }
        self.runDirectory = workDirectory
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ytDlpPath)
        proc.arguments = args
        proc.currentDirectoryURL = workDirectory  // never the download folder: see RunDirectory
        proc.environment = YtDlpEnvironment.make(
            base: ProcessInfo.processInfo.environment,
            ffmpegDirectory: (ffmpegPath as NSString).deletingLastPathComponent,
            home: FullDiskAccess.realHome())

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        let output = OutputPump()

        tracker = job.playlist == nil && job.only == nil
            ? PlaylistTracker()
            : PlaylistTracker(retrying: job.only, keeping: job.playlist)
        wasCancelled = false
        lastErrorLine = nil
        errorLog = ErrorLog()
        jobs[i].state = .running
        jobs[i].detail = nil
        jobs[i].suggestsSignInSetting = false
        jobs[i].suggestsFullDiskAccess = false
        runningID = id
        process = proc
        status = queuePrefix() + (startNotes.removeValue(forKey: id) ?? "Starting download…")

        do {
            try proc.run()
        } catch {
            process = nil
            runningID = nil
            RunDirectory.remove(runDirectory)
            runDirectory = nil
            stop("Couldn't start yt‑dlp. \(error.localizedDescription)")
            return
        }
        // our copy of the write end must close, or the reader never sees the end of the output
        try? pipe.fileHandleForWriting.close()
        output.start(reading: pipe.fileHandleForReading, process: proc)
        // one consumer handles every line and then the exit, in order, so the last ERROR line is never lost
        Task { @MainActor [weak self] in
            for await event in output.events {
                switch event {
                case .line(let line): self?.handle(line: line, job: id)
                case .exit(let code): self?.finished(code: code, job: id)
                }
            }
        }
    }

    nonisolated static func path(for tool: Tool) -> String {
        UserDefaults.standard.string(forKey: tool.defaultsKey) ?? tool.defaultPath
    }

    // MARK: Output
    private func handle(line raw: String, job id: UUID) {
        guard id == runningID, let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ERROR") { lastErrorLine = line }
        errorLog.consume(line)

        tracker.consume(line)
        if tracker.progress != jobs[i].playlist { jobs[i].playlist = tracker.progress }
        if let p = jobs[i].playlist {
            jobs[i].speed = p.speed
        } else {
            jobs[i].fraction = max(jobs[i].fraction, tracker.fileFraction)
            jobs[i].speed = tracker.fileSpeed
            if jobs[i].title == nil { jobs[i].title = tracker.fileTitle }
        }

        // "[download]  42.3% of  120.00MiB at  3.20MiB/s ETA 00:24"
        if line.hasPrefix("[download]"), let pct = Self.percent(in: line) {
            let prefix = queuePrefix()
            if let p = jobs[i].playlist {
                let current = p.current.map { "Item \($0) of \(p.total)" } ?? "Playlist"
                var text = prefix + "\(current) · \(Int(pct.rounded()))%"
                if let speed = p.speed { text += " · \(speed)" }
                status = text
            } else {
                var text = prefix + "Downloading \(Int((jobs[i].fraction * 100).rounded()))%"
                if let speed = Self.value(after: " at ", in: line) { text += " · \(speed)" }
                if let eta = Self.value(after: "ETA ", in: line) { text += " · \(eta) left" }
                status = text
            }
            return
        }
        // Only yt-dlp's own tagged lines are worth showing; ffmpeg chatter is not.
        guard line.hasPrefix("[") || line.hasPrefix("Deleting original file") else { return }
        if line.hasPrefix("[Merger]") || line.hasPrefix("[VideoRemuxer]") {
            status = queuePrefix() + "Merging…"
        } else if line.hasPrefix("[ExtractAudio]") {
            status = queuePrefix() + "Converting audio…"
        } else if line.hasPrefix("[download] Downloading item"), let p = jobs[i].playlist, let current = p.current {
            status = queuePrefix() + "Item \(current) of \(p.total)"
        } else if line.hasPrefix("[download]") || line.contains("%(filepath)s") {
            return
        } else if line.hasPrefix("Deleting original file") {
            status = queuePrefix() + "Finishing…"
        } else if jobs[i].playlist == nil {
            status = queuePrefix() + line
        }
    }

    /// "Link 2 of 5 · " when several links are queued.
    /// Also says "Safari sign-in · " while the running job borrows a browser's cookies.
    private func queuePrefix() -> String {
        guard let running = jobs.firstIndex(where: { $0.id == runningID }) else { return "" }
        var prefix = jobs.count > 1 ? "Link \(running + 1) of \(jobs.count) · " : ""
        if jobs[running].needsCookies, let browser = CookieBrowser.current() {
            prefix += "\(browser.displayName) sign-in · "
        }
        return prefix
    }

    private func finished(code: Int32, job id: UUID) {
        guard id == runningID else { return }
        process = nil
        runningID = nil
        tracker.finish(exitCode: code, cancelled: wasCancelled)

        let files = pathFile
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
            .split(whereSeparator: \.isNewline).map { URL(fileURLWithPath: String($0)) } ?? []
        if let pathFile { try? FileManager.default.removeItem(at: pathFile) }
        pathFile = nil
        RunDirectory.remove(runDirectory)
        runDirectory = nil

        guard let i = jobs.firstIndex(where: { $0.id == id }) else {
            pump()
            return
        }
        if tracker.progress != nil { jobs[i].playlist = tracker.progress }
        jobs[i].files += files
        jobs[i].speed = nil

        let failedRun = code != 0 || !(jobs[i].playlist?.failed.isEmpty ?? true)
        let currentBrowser = CookieBrowser.current()
        let usedCookies = jobs[i].needsCookies
        // any sign-in ERROR in the run triggers the cookie retry; the shown hint follows the last ERROR line
        let signInSeen = failedRun
            && ErrorHint.classify(errorLog.text, cookiesBrowser: currentBrowser, usedCookies: usedCookies)?.isSignIn == true
        let hint = failedRun
            ? ErrorHint.classifyForDisplay(
                errorText: errorLog.text, lastError: errorLog.lastError,
                cookiesBrowser: currentBrowser, usedCookies: usedCookies)
                .map { $0.resolvingMissingBrowser(cookiesEnabled: UserDefaults.standard.bool(forKey: "cookiesEnabled")) }
            : nil
        let failedItems = jobs[i].playlist?.failed ?? []
        let action = QueueLogic.nextAction(
            FinishFacts(
                wasCancelled: wasCancelled, exitCode: code, isPlaylist: jobs[i].playlist != nil,
                failedItems: failedItems.count,
                allFailuresTransient: failedItems.allSatisfy { DownloadJob.isTransient($0.detail) },
                signInSeen: signInSeen, cookieBrowserAvailable: currentBrowser != nil,
                needsCookies: usedCookies, autoRetried: jobs[i].autoRetried,
                lastErrorTransient: DownloadJob.isTransient(lastErrorLine.map { PlaylistTracker.reason(from: $0) })))
        switch action {
        case .cancelled:
            jobs[i].state = .cancelled
        case .retryWithCookies:
            // a sign-in wall and the person opted in: run this job once more with their browser's cookies
            jobs[i].needsCookies = true
            if !failedItems.isEmpty { jobs[i].only = failedItems.map(\.id) }
            jobs[i].state = .queued
            let name = currentBrowser?.displayName ?? "browser"
            startNotes[id] = "Retrying…"  // the row's status then reads "\(name) sign-in · Retrying…"
            status = "Signing in with \(name)…"
        case .retryPlaylistFailures:
            // a network hiccup: try just the failed videos once more
            jobs[i].autoRetried = true
            jobs[i].only = failedItems.map(\.id)
            jobs[i].state = .queued
            startNotes[id] = "Retrying \(failedItems.count) that hit a network error…"
            status = "Retrying \(failedItems.count) that hit a network error…"
        case .retrySingle:
            jobs[i].autoRetried = true
            jobs[i].state = .queued
            startNotes[id] = "Retrying after a network error…"
            status = "Retrying after a network error…"
        case .playlistDone:
            jobs[i].state = .done
            completions += 1
        case .playlistFailed:
            if let playlist = jobs[i].playlist {
                jobs[i].state = .failed
                jobs[i].detail = "\(playlist.doneCount) of \(playlist.total) downloaded."
                    + (hint.map { " " + $0.message } ?? "")
                jobs[i].suggestsSignInSetting = hint?.needsSignInSetting ?? false
                jobs[i].suggestsFullDiskAccess = hint?.needsFullDiskAccess ?? false
                hadError = true
            }
        case .done:
            jobs[i].state = .done
            jobs[i].fraction = 1
            completions += 1
        case .failed:
            jobs[i].state = .failed
            jobs[i].detail =
                hint?.message ?? lastErrorLine.map { PlaylistTracker.reason(from: $0) } ?? "Failed (code \(code))"
            jobs[i].suggestsSignInSetting = hint?.needsSignInSetting ?? false
            jobs[i].suggestsFullDiskAccess = hint?.needsFullDiskAccess ?? false
            hadError = true
        }
        let stopped = stopQueue && wasCancelled
        wasCancelled = false
        if stopped {
            // Cancel All: pump() will not run, so say so here
            status = "Download cancelled."
            scheduleIdle()
        }
        pump()
    }

    /// Nothing left to run: describe how it went.
    private func finishQueue() {
        guard !jobs.isEmpty else { return }
        let s = summary
        if jobs.allSatisfy({ $0.state == .cancelled }) {
            status = "Download cancelled."
        } else if jobs.contains(where: { $0.state == .failed }) {
            if jobs.count == 1, !jobs[0].isPlaylist {
                status = "Download failed. " + (jobs[0].detail ?? "")
            } else {
                let failed = max(s.failedUnits, jobs.filter { $0.state == .failed }.count)
                status = "\(s.doneUnits) of \(s.units) downloaded · \(failed) failed"
            }
            return  // keep the summary on screen until the next attempt
        } else if jobs.count == 1 {
            status = jobs[0].isPlaylist ? "Playlist completed." : "Download completed."
        } else {
            status = "All \(s.units) downloads completed."
        }
        scheduleIdle()
    }

    /// Return to "Idle" a little while after a clean finish.
    private func scheduleIdle() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.resetIfIdle()
        }
    }

    private func resetIfIdle() {
        if !isActive { status = "Idle" }
    }

    // MARK: Parsing helpers
    nonisolated private static func percent(in line: String) -> Double? {
        guard let r = line.range(of: #"(\d+(?:\.\d+)?)%"#, options: .regularExpression) else {
            return nil
        }
        return Double(line[r].dropLast())
    }

    nonisolated private static func value(after marker: String, in line: String) -> String? {
        guard let r = line.range(of: marker) else { return nil }
        let rest = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
        return rest.split(separator: " ").first.map(String.init)
    }
}

/// Holds a look-up's stderr between threads. Kept in memory only, never written anywhere.
/// Only ERROR and WARNING lines are kept, bounded separately (see `ErrorLog`).
private final class ErrorCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""

    func set(_ data: Data) {
        var log = ErrorLog()
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            log.consume(String(line))
        }
        lock.lock()
        value = log.text
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
