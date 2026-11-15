//
//  QueueLogic.swift
//  Downer
//
//  The queue's small decision-making pieces, kept free of UI and processes so they can be tested:
//  the error buffer, the "what next after a run" decision, line splitting, the output pump that
//  delivers every line before the exit, and the cancellable look-up handle.
//

import Foundation

/// ERROR and WARNING lines of one run, in memory only. Errors and warnings are bounded separately,
/// so a flood of warnings can never push out the error that explains the failure.
struct ErrorLog: Equatable {
    static let maxErrors = 20
    static let maxWarnings = 20
    static let maxBytes = 8_192
    static let maxLineLength = 1_000

    private(set) var errors: [String] = []
    private(set) var warnings: [String] = []

    init() {}

    /// The ERROR and WARNING lines of a whole output.
    init(output: Data) {
        for line in String(decoding: output, as: UTF8.self).split(whereSeparator: \.isNewline) {
            consume(String(line))
        }
    }

    /// Keeps the line if it starts with ERROR or WARNING; anything else is ignored.
    mutating func consume(_ raw: String) {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ERROR") {
            Self.append(String(line.prefix(Self.maxLineLength)), to: &errors, maxCount: Self.maxErrors)
        } else if line.hasPrefix("WARNING") {
            Self.append(String(line.prefix(Self.maxLineLength)), to: &warnings, maxCount: Self.maxWarnings)
        }
    }

    private static func append(_ line: String, to list: inout [String], maxCount: Int) {
        list.append(line)
        var bytes = list.reduce(0) { $0 + $1.utf8.count }
        while list.count > 1, list.count > maxCount || bytes > maxBytes {
            bytes -= list.removeFirst().utf8.count
        }
    }

    var lastError: String? { errors.last }

    /// Errors first, then warnings: what the classifier reads.
    var text: String { (errors + warnings).joined(separator: "\n") }
}

/// What to do once a download process has exited.
enum FinishAction: Equatable {
    case cancelled
    /// A sign-in wall, and the person turned Sign-in on: run again with the browser's cookies (once).
    case retryWithCookies
    /// A playlist where only network failures remain: fetch just those again (once).
    case retryPlaylistFailures
    /// A single video that hit a network error: one more try.
    case retrySingle
    case playlistDone
    case playlistFailed
    case done
    case failed
}

struct FinishFacts: Equatable {
    var wasCancelled = false
    var exitCode: Int32 = 0
    var isPlaylist = false
    var failedItems = 0
    var allFailuresTransient = false
    /// Any sign-in ERROR anywhere in this run.
    var signInSeen = false
    var cookieBrowserAvailable = false
    var needsCookies = false
    var autoRetried = false
    var lastErrorTransient = false
}

enum QueueLogic {
    /// Pure decision for `finished(code:job:)`. Each retry kind is gated by a flag that the caller sets
    /// when it retries (`needsCookies`, `autoRetried`), so none can repeat: at most one of each per job.
    static func nextAction(_ f: FinishFacts) -> FinishAction {
        if f.wasCancelled { return .cancelled }
        let failedRun = f.exitCode != 0 || (f.isPlaylist && f.failedItems > 0)
        if failedRun, f.signInSeen, f.cookieBrowserAvailable, !f.needsCookies { return .retryWithCookies }
        if f.isPlaylist, !f.autoRetried, f.failedItems > 0, f.allFailuresTransient {
            return .retryPlaylistFailures
        }
        if !f.isPlaylist, f.exitCode != 0, !f.autoRetried, f.lastErrorTransient { return .retrySingle }
        if f.isPlaylist { return f.failedItems == 0 && f.exitCode == 0 ? .playlistDone : .playlistFailed }
        return f.exitCode == 0 ? .done : .failed
    }

    /// How long a look-up may run before it is stopped, so a link that never answers can't hold up the
    /// queue. With cookies, a Chromium browser's Keychain prompt may be waiting for the person, so allow
    /// time to read and answer it; stopping it early would only lead to a second prompt at download time.
    /// Two minutes is enough to read the prompt and type a password, without letting a site that hangs
    /// hold up the whole queue for long.
    nonisolated static func probeTimeout(useCookies: Bool) -> TimeInterval { useCookies ? 120 : 45 }

    // MARK: Video or playlist
    /// What a newly added link does: ask first, or go ahead with a scope (nil: no flag, yt-dlp decides).
    /// A Mix always asks unless the setting is Just the Video, because YouTube makes Mixes up on the fly
    /// and they can run to hundreds of videos.
    static func playlistDecision(for kind: LinkKind, setting: PlaylistLinkChoice) -> PlaylistDecision {
        switch kind {
        case .video, .playlist:
            return .go(nil)
        case .mix:
            return .ask  // a whole Mix is only ever downloaded when the person says so
        case .videoInList(let isMix):
            switch setting {
            case .ask: return .ask
            case .video: return .go(.video)
            case .playlist: return isMix ? .ask : .go(.playlist)
            }
        case .other:
            // other sites have no prompt; the setting still applies when it is a firm choice
            switch setting {
            case .ask: return .go(nil)
            case .video: return .go(.video)
            case .playlist: return .go(.playlist)
            }
        }
    }

    /// Playlists with at least this many videos are confirmed once before they download.
    static let largePlaylist = 200

    /// The size question for a looked-up playlist, if it needs one. `timedOut`: the look-up was stopped
    /// before it finished, so `count` is only what it had listed by then and the real size is unknown,
    /// which is asked about too: a list too long to look up in time is a long list.
    static func sizeQuestion(count: Int, timedOut: Bool, alreadyConfirmed: Bool) -> JobQuestion? {
        guard !alreadyConfirmed, timedOut || count >= largePlaylist else { return nil }
        return .size(count: count, atLeast: timedOut)
    }

    /// The same link with the same choice is already in the queue and not finished, so the same link can
    /// be queued once as a video and once as a list. A link still waiting for its choice (scope nil)
    /// matches another undecided copy, so pasting it twice asks once.
    static func isDuplicate(url: String, scope: PlaylistScope?, in jobs: [DownloadJob], except id: UUID? = nil) -> Bool {
        jobs.contains { $0.id != id && $0.url == url && !$0.isFinished && $0.scope == scope }
    }
}

enum PlaylistDecision: Equatable {
    case ask
    case go(PlaylistScope?)
}

/// Why a job is waiting for the person before it can go on.
enum JobQuestion: Equatable {
    /// A video inside a list: just the video, or the whole list?
    case scope(isMix: Bool)
    /// A link to a whole Mix: download all of it?
    case wholeMix
    /// A playlist of `count` videos (or more, if `atLeast`): download all of them?
    case size(count: Int, atLeast: Bool)
}

/// A flag shared between threads (a look-up stopped by its time limit).
final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    func set() {
        lock.lock()
        flag = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }
}

/// A string shared between threads (a look-up's error lines). In memory only.
final class LockedText: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func set(_ s: String) {
        lock.lock()
        text = s
        lock.unlock()
    }

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return text
    }
}

/// Collects pipe output as bytes and hands back only complete lines (yt-dlp separates progress
/// updates with \r or \n). Works on bytes so a multi-byte character split across two reads survives.
final class LineBuffer: @unchecked Sendable {
    private var pending = Data()

    func append(_ chunk: Data) -> [String] {
        pending.append(chunk)
        var lines: [String] = []
        var start = pending.startIndex
        for index in pending.indices where pending[index] == 0x0A || pending[index] == 0x0D {
            lines.append(String(decoding: pending[start..<index], as: UTF8.self))
            start = pending.index(after: index)
        }
        pending = Data(pending[start...])
        return lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The last line, if the output ended without a newline.
    func flush() -> [String] {
        defer { pending = Data() }
        let last = String(decoding: pending, as: UTF8.self)
        return last.trimmingCharacters(in: .whitespaces).isEmpty ? [] : [last]
    }
}

/// Reads a process's combined output on its own thread and delivers, in order, every line followed
/// by one `.exit` event. Nothing is read through a readability handler, so no output can be
/// dropped between the last read and the exit.
final class OutputPump: @unchecked Sendable {
    enum Event: Sendable, Equatable {
        case line(String)
        case exit(Int32)
    }

    let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private let lock = NSLock()
    private var exitSent = false

    init() {
        (events, continuation) = AsyncStream<Event>.makeStream(bufferingPolicy: .unbounded)
    }

    /// Call after `process.run()`. `process.terminationHandler` must not be in use elsewhere.
    func start(reading handle: FileHandle, process: Process) {
        // If something the tool spawned keeps the pipe open after it exits, do not wait for it forever.
        process.terminationHandler = { [self] p in exitSoon(p) }
        // A process that already ended before the handler was set never calls it, so check once more.
        // (Both may fire; only the first exit is sent.)
        if !process.isRunning { exitSoon(process) }
        let thread = Thread { [self] in
            let buffer = LineBuffer()
            var chunk = [UInt8](repeating: 0, count: 65_536)  // reused for every read
            // read(2) returns as soon as any output is there, so progress lines arrive live.
            // (FileHandle.read(upToCount:) waits until the whole count or the end of the output.)
            while let data = Self.readAvailable(handle, into: &chunk), !data.isEmpty {
                for line in buffer.append(data) { continuation.yield(.line(line)) }
            }
            for line in buffer.flush() { continuation.yield(.line(line)) }
            process.waitUntilExit()
            sendExit(process.terminationStatus)
        }
        thread.stackSize = 1 << 20
        thread.start()
    }

    /// Sends the exit a little after the process ended, giving the reader time to deliver the last lines.
    private func exitSoon(_ process: Process) {
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { self.sendExit(process.terminationStatus) }
    }

    /// What the pipe has now (waiting for at least one byte), read into `buffer`; empty at the end of the
    /// output, nil on error.
    static func readAvailable(_ handle: FileHandle, into buffer: inout [UInt8]) -> Data? {
        let capacity = buffer.count
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(handle.fileDescriptor, $0.baseAddress, capacity) }
            if count >= 0 { return Data(buffer[0..<count]) }
            if errno != EINTR { return nil }
        }
    }

    private func sendExit(_ code: Int32) {
        lock.lock()
        defer { lock.unlock() }
        guard !exitSent else { return }
        exitSent = true
        continuation.yield(.exit(code))
        continuation.finish()
    }
}

/// Lets the main actor stop a look-up that runs on a background task: it records the cancel and
/// terminates whichever yt-dlp process is running, and refuses to start another afterwards.
final class ProbeControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// Starts the process unless cancelled. Returns false if it was not started.
    func launch(_ proc: Process) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled, (try? proc.run()) != nil else { return false }
        process = proc
        return true
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning { process.terminate() }
    }

    func processEnded() {
        lock.lock()
        process = nil
        lock.unlock()
    }
}
