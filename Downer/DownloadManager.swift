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
    /// The names the running download is writing, and when it began: what a cancel cleans up.
    private var startedFile: URL?
    private var runStarted = Date()
    private var runDirectory: URL?
    /// "Chrome sign-in · " while the running job uses a browser's cookies; fixed when the run starts, so
    /// the many progress lines don't look the browser up again.
    private var cookiePrefix = ""
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
    /// Links waiting for the person to choose (video or playlist, or a large playlist), in queue order.
    var pendingChoices: [DownloadJob] { jobs.filter { $0.state == .needsChoice } }
    var needsChoice: Bool { jobs.contains { $0.state == .needsChoice } }
    /// Something is running, waiting to run, or waiting for an answer: the queue is not finished.
    var hasPendingWork: Bool { isActive || needsChoice }

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
    /// `setting`: Settings → Downloads (passed in by tests).
    @discardableResult
    func add(_ text: String, setting: PlaylistLinkChoice = .current()) -> Int {
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
        var asking = 0
        let options = JobOptions.current()
        for link in links {
            var job = DownloadJob(url: link, options: options)
            job.kind = LinkScope.classify(link)
            switch QueueLogic.playlistDecision(for: job.kind, setting: setting) {
            case .ask:
                job.state = .needsChoice
                job.question = Self.firstQuestion(for: job.kind)
            case .go(let scope):
                job.scope = scope
            }
            if QueueLogic.isDuplicate(url: link, scope: job.scope, in: jobs) { continue }
            jobs.append(job)
            if job.state == .needsChoice {
                asking += 1  // looked up only once the person has chosen
            } else {
                toResolve.append(job.id)
            }
            added += 1
        }
        if added > 0 { stopQueue = false }  // new links after a Cancel All still run
        if added == 0 {
            status = "Already in the queue."
        } else if asking == added {
            status = "Choose what to download."
            return added
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

    // MARK: Choosing
    /// The question a link asks before it is looked up, if any: a video inside a list asks "video or
    /// list?", and a link to a whole Mix asks before it downloads.
    nonisolated static func firstQuestion(for kind: LinkKind) -> JobQuestion? {
        switch kind {
        case .videoInList(let isMix): return .scope(isMix: isMix)
        case .mix: return .wholeMix
        case .video, .playlist, .other: return nil
        }
    }

    /// Answers "just the video or the whole list?" (or "the whole Mix?", always with `.playlist`) for a
    /// link waiting on it. `remember` makes the answer the default in Settings → Downloads.
    func choose(_ id: UUID, scope: PlaylistScope, remember: Bool = false) {
        guard let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].state == .needsChoice else { return }
        switch jobs[i].question {
        case .scope:
            if remember {
                UserDefaults.standard.set(
                    (scope == .video ? PlaylistLinkChoice.video : .playlist).rawValue,
                    forKey: PlaylistLinkChoice.storageKey)
            }
        case .wholeMix where scope == .playlist:
            break
        default:
            return
        }
        if QueueLogic.isDuplicate(url: jobs[i].url, scope: scope, in: jobs, except: id) {
            jobs.remove(at: i)
            if jobs.isEmpty {
                status = "Idle"
            } else if runningID == nil, !hasPendingWork {
                finishQueue()
            } else {
                status = "Already in the queue."
            }
            return
        }
        idleTask?.cancel()
        // Choosing a whole Mix already accepts that it is long (its look-up rarely finishes in time),
        // so it is not asked about again. A normal playlist can still be confirmed once its size is known.
        if scope == .playlist, jobs[i].kind.isMix { jobs[i].sizeConfirmed = true }
        jobs[i].scope = scope
        jobs[i].question = nil
        jobs[i].state = .queued
        jobs[i].isResolving = true
        stopQueue = false
        toResolve.append(id)
        if !isDownloading { status = "Checking link…" }
        resolveNext()
    }

    /// The same answer for every link that is waiting on "video or list?".
    func chooseAll(_ scope: PlaylistScope) {
        for job in pendingChoices {
            if case .scope = job.question { choose(job.id, scope: scope) }
        }
    }

    /// Yes to a large playlist: download every video.
    func confirmSize(_ id: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].state == .needsChoice,
            case .size = jobs[i].question
        else { return }
        idleTask?.cancel()
        jobs[i].question = nil
        jobs[i].sizeConfirmed = true
        jobs[i].state = .queued
        stopQueue = false
        pump()
    }

    /// Removes a link that is waiting for an answer. Returns the link when it was asked about before
    /// being looked up, so the view can put it back in its field.
    @discardableResult
    func cancelChoice(_ id: UUID) -> String? {
        guard let job = jobs.first(where: { $0.id == id }), job.state == .needsChoice else { return nil }
        remove(id)
        if case .size = job.question { return nil }
        return job.url
    }

    /// Queues the other choice for a video-in-a-list link: the whole list after just the video, or the
    /// other way round, so a wrong pick never means pasting the link again.
    func addOtherChoice(of id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }), job.kind.isVideoInList, let scope = job.scope?.other
        else { return }
        guard !QueueLogic.isDuplicate(url: job.url, scope: scope, in: jobs) else {
            status = "Already in the queue."
            return
        }
        if !isActive {
            jobs.removeAll { $0.isFinished && $0.id != id }
            hadError = jobs.contains { $0.state == .failed }
        }
        var other = DownloadJob(url: job.url, options: JobOptions.current())
        other.kind = job.kind
        other.scope = scope
        jobs.append(other)
        idleTask?.cancel()
        stopQueue = false
        toResolve.append(other.id)
        if !isDownloading { status = "Checking link…" }
        resolveNext()
    }

    // MARK: Controlling
    /// Stop the download in progress; the queue carries on with the next one.
    func cancelCurrent() {
        guard process != nil else { return }
        wasCancelled = true
        Self.terminateTree(process)
    }

    /// yt-dlp's helpers (ffmpeg while merging) first, so none of them keeps writing after yt-dlp is gone.
    private static func terminateTree(_ process: Process?) {
        guard let process, process.isRunning else { return }
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        kill.arguments = ["-TERM", "-P", String(process.processIdentifier)]
        try? kill.run()
        kill.waitUntilExit()
        process.terminate()
    }

    /// Stop everything, including what is waiting.
    func cancelAll() {
        stopQueue = true
        // a look-up in flight must stop too, and must never go on to the cookie probe
        abandonProbe()
        toResolve.removeAll()
        for i in jobs.indices where jobs[i].state == .queued || jobs[i].state == .needsChoice {
            jobs[i].state = .cancelled
            jobs[i].isResolving = false
            jobs[i].question = nil
        }
        startNotes.removeAll()
        if process != nil {
            wasCancelled = true
            Self.terminateTree(process)
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
            let wasAsking = jobs.first { $0.id == id }?.state == .needsChoice
            if wasProbing { abandonProbe() }  // stops yt-dlp and skips the cookie retry
            toResolve.removeAll { $0 == id }
            startNotes[id] = nil
            jobs.removeAll { $0.id == id }
            if jobs.isEmpty {
                status = "Idle"
            } else if wasAsking, runningID == nil, !hasPendingWork {
                finishQueue()  // that was the last question: say how the rest went
            }
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
        idleTask?.cancel()
        // a link cancelled while it was still waiting for its choice asks again: without a choice,
        // yt-dlp would download the whole list
        if jobs[i].scope == nil, let question = Self.firstQuestion(for: jobs[i].kind) {
            jobs[i].state = .needsChoice
            jobs[i].question = question
            jobs[i].isResolving = true
        } else if jobs[i].only == nil, let size = jobs[i].listedSize,
            let question = QueueLogic.sizeQuestion(
                count: size.count, timedOut: size.partial, alreadyConfirmed: jobs[i].sizeConfirmed)
        {
            // cancelled before its size was confirmed: confirm it now
            jobs[i].state = .needsChoice
            jobs[i].question = question
        }
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
        if DependencyManager.shared.isBusy {
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
            let url = job.ytDlpURL
            let only = job.only
            var options = job.options
            // decided for the yt-dlp that will actually run, not when the link was added
            options.jsRuntimePath = DependencyManager.jsRuntimePath(forYtDlpAt: path)
            options.playlistScope = job.scope
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
                jobs[i].playlistTitle = result.playlistTitle.flatMap { $0.isEmpty ? nil : $0 }
            }
            if let result, jobs[i].state == .queued {
                if let name = result.playlistTitle, result.titles.count > 1 {
                    jobs[i].playlist = PlaylistProgress(
                        title: name,
                        items: result.titles.enumerated().map {
                            PlaylistItem(id: $0.offset + 1, title: $0.element)
                        },
                        current: nil, speed: nil)
                }
                // A very long playlist is confirmed once before it starts. So is one whose look-up ran out
                // of time, since its real size is unknown. (A single video that was slow to look up is not.)
                let job = jobs[i]
                let isList = result.titles.count > 1 || job.scope == .playlist || job.kind == .playlist || job.kind == .mix
                if isList {
                    jobs[i].listedSize = .init(count: result.titles.count, partial: result.timedOut)
                    if let question = QueueLogic.sizeQuestion(
                        count: result.titles.count, timedOut: result.timedOut, alreadyConfirmed: job.sizeConfirmed)
                    {
                        jobs[i].state = .needsChoice
                        jobs[i].question = question
                        // it may have been added a while ago, from a window that has been closed since
                        NotificationCenter.default.post(name: .downerQuestionWaiting, object: nil)
                    }
                }
            }
        }
        resolveNext()
    }

    struct ProbeResult {
        var playlistTitle: String?
        var titles: [String]
        /// The look-up hit its time limit; `titles` is what it had listed by then.
        var timedOut = false
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
        let errors = LockedText()
        let errorDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            errors.set(ErrorLog(output: errorPipe.fileHandleForReading.readDataToEndOfFile()).text)
            errorDone.signal()
        }

        // a link that never answers must not hold up the queue; with cookies, leave time for the Keychain prompt
        let timedOut = LockedFlag()
        let watchdog = DispatchWorkItem {
            if proc.isRunning {
                timedOut.set()
                proc.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(
            deadline: .now() + QueueLogic.probeTimeout(useCookies: useCookies), execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        watchdog.cancel()
        errorDone.wait()
        let errorText = errors.value
        // A long playlist can outlast the time limit: keep what was listed (yt-dlp prints each entry as
        // it goes), so the queue shows those videos and the playlist can still be confirmed.
        if timedOut.isSet, !control.isCancelled {
            var partial = parse(data) ?? ProbeResult(titles: [])
            partial.timedOut = true
            return (partial, errorText)
        }
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
            if needsChoice {
                status = "Choose what to download."  // the queue carries on once they answer
            } else {
                finishQueue()
            }
            return
        }
        // a tool is being updated or installed: wait, and carry on when it is done
        if DependencyManager.shared.isBusy {
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
        let ytDlpPath = Self.path(for: .ytDlp)
        // decided for the yt-dlp that will actually run (it may have been changed since the link was added)
        options.jsRuntimePath = DependencyManager.jsRuntimePath(forYtDlpAt: ytDlpPath)
        options.playlistScope = job.scope
        let fm = FileManager.default
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
        let startedFile = fm.temporaryDirectory.appendingPathComponent("downer-started-\(UUID().uuidString).txt")
        self.startedFile = startedFile
        runStarted = Date()
        // cookies only once this job has hit a sign-in wall (see finished(code:job:))
        let args = YtDlpArguments.build(
            for: options,
            purpose: .download(
                pathFile: pathFile.path,
                ffmpegDirectory: (ffmpegPath as NSString).deletingLastPathComponent,
                outputFolder: job.options.folder.path,
                only: job.only,
                startedFile: startedFile.path,
                playlistFolder: options.playlistFolders && job.playlistTitle != nil),
            useCookies: job.needsCookies, url: job.ytDlpURL)

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
        errorLog = ErrorLog()
        cookiePrefix = job.needsCookies ? (browser.map { "\($0.displayName) sign-in · " } ?? "") : ""
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
        return (jobs.count > 1 ? "Link \(running + 1) of \(jobs.count) · " : "") + cookiePrefix
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
        // a cancelled download leaves its partial files in the destination: remove them (a failed one
        // keeps them, so a retry can carry on)
        let started = startedFile
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
            .split(whereSeparator: \.isNewline).map { URL(fileURLWithPath: String($0)) } ?? []
        if let startedFile { try? FileManager.default.removeItem(at: startedFile) }
        startedFile = nil
        if wasCancelled {
            PartialFiles.clean(
                after: started, destination: jobs.first(where: { $0.id == id })?.options.folder,
                since: runStarted)
        }
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
        // a sign-in ERROR in the run triggers the cookie retry (see requiresSignIn); the hint agrees with it
        let signInSeen = failedRun && ErrorHint.requiresSignIn(errorLog)
        let hint = failedRun
            ? ErrorHint.forFailedRun(errorLog, cookiesBrowser: currentBrowser, usedCookies: usedCookies)
                .map { $0.resolvingMissingBrowser(cookiesEnabled: UserDefaults.standard.bool(forKey: "cookiesEnabled")) }
            : nil
        let lastErrorReason = errorLog.lastError.map { PlaylistTracker.reason(from: $0) }
        let failedItems = jobs[i].playlist?.failed ?? []
        let action = QueueLogic.nextAction(
            FinishFacts(
                wasCancelled: wasCancelled, exitCode: code, isPlaylist: jobs[i].playlist != nil,
                failedItems: failedItems.count,
                allFailuresTransient: failedItems.allSatisfy { DownloadJob.isTransient($0.detail) },
                signInSeen: signInSeen, cookieBrowserAvailable: currentBrowser != nil,
                needsCookies: usedCookies, autoRetried: jobs[i].autoRetried,
                lastErrorTransient: DownloadJob.isTransient(lastErrorReason)))
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
                hint?.message ?? lastErrorReason ?? "Failed (code \(code))"
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
        if !hasPendingWork { status = "Idle" }  // never over a question that is still waiting
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

extension Notification.Name {
    /// A link started waiting for an answer after it was looked up (a large playlist), so the question
    /// should be brought into view.
    static let downerQuestionWaiting = Notification.Name("DownerQuestionWaiting")
}
