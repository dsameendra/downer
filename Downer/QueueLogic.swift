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

    /// Downloads and look-ups wait while a tool is being installed or updated.
    static func mustWaitForInstall(_ installing: Set<Tool>) -> Bool { !installing.isEmpty }
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
        process.terminationHandler = { [self] p in
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { self.sendExit(p.terminationStatus) }
        }
        let thread = Thread { [self] in
            let buffer = LineBuffer()
            while let data = (try? handle.read(upToCount: 65_536)) ?? nil, !data.isEmpty {
                for line in buffer.append(data) { continuation.yield(.line(line)) }
            }
            for line in buffer.flush() { continuation.yield(.line(line)) }
            process.waitUntilExit()
            sendExit(process.terminationStatus)
        }
        thread.stackSize = 1 << 20
        thread.start()
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
