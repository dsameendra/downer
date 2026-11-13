//
//  QueueLogicTests.swift
//  DownerTests
//

import Foundation
import Testing
@testable import Downer

struct ErrorLogTests {
    @Test func keepsOnlyErrorsAndWarnings() {
        var log = ErrorLog()
        for line in ["[download] 5%", "WARNING: w", "ERROR: e", "  ERROR: padded  ", "chatter"] { log.consume(line) }
        #expect(log.errors == ["ERROR: e", "ERROR: padded"])
        #expect(log.warnings == ["WARNING: w"])
        #expect(log.lastError == "ERROR: padded")
    }

    @Test func warningFloodCannotPushOutTheSignInError() {
        var log = ErrorLog()
        for n in 0..<5_000 { log.consume("WARNING: [youtube] spam \(n) " + String(repeating: "x", count: 50)) }
        log.consume("ERROR: [youtube] abc: Sign in to confirm you're not a bot")
        for n in 0..<5_000 { log.consume("WARNING: more spam \(n)") }
        #expect(log.errors.count == 1)
        #expect(log.warnings.count <= ErrorLog.maxWarnings)
        #expect(log.text.utf8.count < 2 * ErrorLog.maxBytes + 100)
        #expect(ErrorHint.classify(log.text, cookiesBrowser: nil, usedCookies: false)?.isSignIn == true)
    }

    @Test func errorsAreBoundedKeepingTheLatest() {
        var log = ErrorLog()
        for n in 0..<100 { log.consume("ERROR: failure \(n)") }
        #expect(log.errors.count == ErrorLog.maxErrors)
        #expect(log.lastError == "ERROR: failure 99")
        var big = ErrorLog()
        for n in 0..<50 { big.consume("ERROR: " + String(repeating: "y", count: 900) + "\(n)") }
        #expect(big.errors.reduce(0) { $0 + $1.utf8.count } <= ErrorLog.maxBytes + 1_000)
        #expect(big.lastError?.hasSuffix("49") == true)
    }

    @Test func oneHugeLineIsTruncatedButKept() {
        var log = ErrorLog()
        log.consume("ERROR: " + String(repeating: "z", count: 100_000))
        #expect(log.errors.count == 1)
        #expect(log.errors[0].count == ErrorLog.maxLineLength)
    }
}

struct FinishActionTests {
    func facts(_ edit: (inout FinishFacts) -> Void) -> FinishAction {
        var f = FinishFacts(exitCode: 1)
        edit(&f)
        return QueueLogic.nextAction(f)
    }

    @Test func cancelledWinsOverEverything() {
        #expect(facts { $0.wasCancelled = true; $0.signInSeen = true; $0.cookieBrowserAvailable = true } == .cancelled)
    }

    @Test func signInRetriesOnceWithCookies() {
        #expect(facts { $0.signInSeen = true; $0.cookieBrowserAvailable = true } == .retryWithCookies)
        // already using cookies: no loop, the run just fails
        #expect(facts { $0.signInSeen = true; $0.cookieBrowserAvailable = true; $0.needsCookies = true } == .failed)
        // Sign-in off: never retry with cookies
        #expect(facts { $0.signInSeen = true } == .failed)
    }

    @Test func signInInAPlaylistThatMostlyWorked() {
        let a = facts {
            $0.isPlaylist = true; $0.exitCode = 0; $0.failedItems = 1
            $0.signInSeen = true; $0.cookieBrowserAvailable = true
        }
        #expect(a == .retryWithCookies)
    }

    @Test func networkRetryHappensOnce() {
        #expect(facts { $0.lastErrorTransient = true } == .retrySingle)
        #expect(facts { $0.lastErrorTransient = true; $0.autoRetried = true } == .failed)
        let list = facts { $0.isPlaylist = true; $0.failedItems = 2; $0.allFailuresTransient = true }
        #expect(list == .retryPlaylistFailures)
        let again = facts {
            $0.isPlaylist = true; $0.failedItems = 2; $0.allFailuresTransient = true; $0.autoRetried = true
        }
        #expect(again == .playlistFailed)
    }

    @Test func plainOutcomes() {
        #expect(facts { $0.exitCode = 0 } == .done)
        #expect(facts { $0.exitCode = 1 } == .failed)
        #expect(facts { $0.isPlaylist = true; $0.exitCode = 0 } == .playlistDone)
        #expect(facts { $0.isPlaylist = true; $0.exitCode = 0; $0.failedItems = 1 } == .playlistFailed)
        #expect(facts { $0.isPlaylist = true; $0.exitCode = 1 } == .playlistFailed)
    }

    @Test func eachRetryKindFiresAtMostOncePerJob() {
        // simulate the manager: every retry sets the flag that gates it
        var f = FinishFacts(exitCode: 1, signInSeen: true, cookieBrowserAvailable: true, lastErrorTransient: true)
        var actions: [FinishAction] = []
        for _ in 0..<10 {
            let action = QueueLogic.nextAction(f)
            actions.append(action)
            switch action {
            case .retryWithCookies: f.needsCookies = true
            case .retrySingle: f.autoRetried = true
            default: break
            }
            if action != .retryWithCookies && action != .retrySingle { break }
        }
        #expect(actions == [.retryWithCookies, .retrySingle, .failed])
    }

    @Test func cookieLookupLeavesTimeForTheKeychainPrompt() {
        #expect(QueueLogic.probeTimeout(useCookies: false) == 45)
        #expect(QueueLogic.probeTimeout(useCookies: true) >= 120)
    }
}

struct SiteWordingTests {
    @Test func youtubeGetsYouTubeWording() {
        let h = ErrorHint.classify(
            "ERROR: [youtube] abc: Sign in to confirm you're not a bot", cookiesBrowser: nil, usedCookies: false)
        #expect(h?.message == "YouTube wants you signed in. Turn on Sign-in in Settings.")
        let used = ErrorHint.classify(
            "ERROR: [youtube:tab] Sign in to confirm you're not a bot", cookiesBrowser: .chrome, usedCookies: true)
        #expect(used?.message == "Still blocked. Sign in to YouTube in Chrome, then retry.")
    }

    @Test func otherSitesGetNeutralWording() {
        for text in [
            "ERROR: [Instagram] x: login required. Use --cookies-from-browser or --cookies",
            "ERROR: [twitter] x: NSFW tweet requires authentication. Use --cookies-from-browser",
            "ERROR: [reddit] x: Use --cookies-from-browser for authentication",
        ] {
            let h = ErrorHint.classify(text, cookiesBrowser: nil, usedCookies: false)
            #expect(h?.message == "This site wants you signed in. Turn on Sign-in in Settings.", "\(text)")
            #expect(h?.needsSignInSetting == true)
        }
        let used = ErrorHint.classify("ERROR: [reddit] x: use --cookies-from-browser", cookiesBrowser: .safari, usedCookies: true)
        #expect(used?.message == "Still blocked. Sign in to the site in Safari, then retry.")
    }

    @Test func messagesStayShort() {
        let all: [ErrorHint] = [
            .signIn(browser: nil, usedCookies: false, youtube: false),
            .signIn(browser: .chromium, usedCookies: true, youtube: false),
            .signIn(browser: .chromium, usedCookies: true, youtube: true),
            .browserNotFound(browser: .chromium), .rateLimited,
        ]
        for hint in all { #expect(hint.message.count <= 70, "\(hint.message)") }
    }

    func log(_ lines: String...) -> ErrorLog {
        var log = ErrorLog()
        for line in lines { log.consume(line) }
        return log
    }

    @Test func displayFollowsTheLastErrorButCookieProblemsWin() {
        let mixed = log("ERROR: [youtube] a: Sign in to confirm you're not a bot", "ERROR: [youtube] b: Video unavailable")
        #expect(ErrorHint.forFailedRun(mixed, cookiesBrowser: nil, usedCookies: false) == .unavailable)
        // the trigger still sees the sign-in error anywhere in the run
        #expect(ErrorHint.requiresSignIn(mixed))

        let cookie = log("WARNING: failed to decrypt cookie", "ERROR: [youtube] b: Video unavailable")
        #expect(ErrorHint.forFailedRun(cookie, cookiesBrowser: .chrome, usedCookies: true) == .keychain(browser: .chrome))

        // an unknown last line falls back to the other ERROR lines
        let odd = log("ERROR: [youtube] a: Sign in to confirm you're not a bot", "ERROR: odd")
        #expect(ErrorHint.forFailedRun(odd, cookiesBrowser: nil, usedCookies: false)
            == .signIn(browser: nil, usedCookies: false, youtube: true))
    }
}

/// The cookie retry (and its Keychain prompt) only follows a real sign-in wall.
struct SignInTriggerTests {
    func log(_ lines: String...) -> ErrorLog {
        var log = ErrorLog()
        for line in lines { log.consume(line) }
        return log
    }

    @Test func aSignInErrorTriggersIt() {
        #expect(ErrorHint.requiresSignIn(log("ERROR: [youtube] x: Sign in to confirm you're not a bot")))
        #expect(ErrorHint.requiresSignIn(log("ERROR: [youtube] x: Sign in to confirm your age")))
        #expect(ErrorHint.requiresSignIn(
            log("ERROR: [Instagram] x: login required. Use --cookies-from-browser or --cookies")))
    }

    @Test func aSignInWarningNextToAnUnrelatedFailureDoesNot() {
        for error in [
            "ERROR: [youtube] x: Unable to download webpage: HTTP Error 503: Service Unavailable",
            "ERROR: [youtube] x: Video unavailable",
            "ERROR: unable to download video data: <urlopen error timed out>",
            "ERROR: Postprocessing: Conversion failed!",
        ] {
            let l = log("WARNING: [youtube] y: Sign in to confirm your age. Use --cookies-from-browser", error)
            #expect(!ErrorHint.requiresSignIn(l), "\(error)")
            // and the hint does not tell the person to turn on Sign-in either
            #expect(ErrorHint.forFailedRun(l, cookiesBrowser: .chrome, usedCookies: false)?.isSignIn != true, "\(error)")
            #expect(ErrorHint.forFailedRun(l, cookiesBrowser: nil, usedCookies: false)?.needsSignInSetting != true)
        }
    }

    /// "Requested format is not available" is also what the person's own `-f` gives when a video can't
    /// satisfy it, so a sign-in warning next to it is no reason to use cookies.
    @Test func aSignInWarningNextToAFormatErrorDoesNot() {
        let l = log(
            "WARNING: [youtube] x: Sign in to confirm you're not a bot. Use --cookies-from-browser",
            "ERROR: [youtube] x: Requested format is not available. Use --list-formats for a list of available formats")
        #expect(!ErrorHint.requiresSignIn(l))
        #expect(ErrorHint.forFailedRun(l, cookiesBrowser: .firefox, usedCookies: false) == .outdated)
    }

    /// One item hit an age check, but the run's last error says yt-dlp is out of date: say that.
    @Test func anOutdatedLastErrorIsNotRelabelledAsSignIn() {
        let l = log(
            "ERROR: [youtube] a: Sign in to confirm your age",
            "ERROR: [youtube] b: n challenge solving failed")
        #expect(ErrorHint.requiresSignIn(l))  // the age-checked item still gets the cookie retry
        #expect(ErrorHint.forFailedRun(l, cookiesBrowser: nil, usedCookies: false) == .outdated)
    }

    @Test func warningsAloneNeverTriggerIt() {
        #expect(!ErrorHint.requiresSignIn(log("WARNING: [youtube] x: Sign in to confirm you're not a bot")))
        #expect(!ErrorHint.requiresSignIn(log()))
    }

    @Test func aSignInWarningDoesNotHideAnotherWarningsHint() {
        let l = log(
            "WARNING: [youtube] x: Sign in to confirm your age",
            "WARNING: [youtube] x: n challenge solving failed: Some formats may be missing",
            "ERROR: something odd")
        #expect(ErrorHint.forFailedRun(l, cookiesBrowser: nil, usedCookies: false) == .outdated)
    }

    @Test func errorLogReadsAWholeOutput() {
        let l = ErrorLog(output: Data("[info] x\nWARNING: w\r\nERROR: e\nchatter\n".utf8))
        #expect(l.errors == ["ERROR: e"])
        #expect(l.warnings == ["WARNING: w"])
    }
}

@MainActor
struct ToolProcessTests {
    /// brew (or anything else) can leave a helper running that still holds the output pipe. The run must
    /// still finish, or `installing` never empties and every download waits forever.
    @Test(.timeLimit(.minutes(1))) func aHelperHoldingThePipeCannotHangTheRun() async throws {
        let start = Date()
        let result = try await DependencyManager.shared.run("/bin/sh", ["-c", "sleep 30 & echo started; exit 0"])
        #expect(result.status == 0)
        #expect(result.output.contains("started"))
        #expect(Date().timeIntervalSince(start) < 15)
    }

    @Test func outputAndStatusAreCollected() async throws {
        let result = try await DependencyManager.shared.run(
            "/bin/sh", ["-c", "echo one; echo two >&2; printf 'Error: last'; exit 4"])
        #expect(result.status == 4)
        #expect(result.output.split(separator: "\n").map(String.init) == ["one", "two", "Error: last"]
            || Set(result.output.split(separator: "\n").map(String.init)) == ["one", "two", "Error: last"])
    }

    @Test func aMissingProgramThrows() async {
        await #expect(throws: (any Error).self) {
            _ = try await DependencyManager.shared.run("/nonexistent/tool", [])
        }
    }
}

struct LineBufferTests {
    @Test func splitsOnReturnsAndNewlines() {
        let b = LineBuffer()
        #expect(b.append(Data("a\rb\nc".utf8)) == ["a", "b"])
        #expect(b.append(Data("d\n".utf8)) == ["cd"])
        #expect(b.flush().isEmpty)
    }

    @Test func flushReturnsUnterminatedLastLine() {
        let b = LineBuffer()
        _ = b.append(Data("x\nERROR: no newline".utf8))
        #expect(b.flush() == ["ERROR: no newline"])
    }

    @Test func multiByteCharacterSplitAcrossReadsSurvives() {
        let bytes = Array("héllo wörld\n".utf8)
        let b = LineBuffer()
        let cut = 2  // inside the two-byte "é"
        #expect(b.append(Data(bytes[..<cut])).isEmpty)
        #expect(b.append(Data(bytes[cut...])) == ["héllo wörld"])
    }
}

struct OutputPumpTests {
    func run(_ script: String) async -> [OutputPump.Event] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", script]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        let pump = OutputPump()
        try? proc.run()
        try? pipe.fileHandleForWriting.close()
        pump.start(reading: pipe.fileHandleForReading, process: proc)
        var events: [OutputPump.Event] = []
        for await e in pump.events { events.append(e) }
        return events
    }

    @Test func everyLineArrivesBeforeTheExit() async {
        let events = await run(
            "i=0; while [ $i -lt 2000 ]; do echo \"WARNING: spam $i\" >&2; i=$((i+1)); done; "
                + "echo 'ERROR: [youtube] x: Sign in to confirm you are not a bot' >&2; printf 'ERROR: last no newline'; exit 1")
        #expect(events.last == .exit(1))
        let lines = events.compactMap { e -> String? in if case .line(let l) = e { return l } else { return nil } }
        #expect(lines.count == 2002)
        #expect(lines[2000].hasPrefix("ERROR: [youtube]"))
        #expect(lines.last == "ERROR: last no newline")
        var log = ErrorLog()
        for l in lines { log.consume(l) }
        #expect(ErrorHint.classify(log.text, cookiesBrowser: .chrome, usedCookies: false)?.isSignIn == true)
    }

    /// Progress must show while a download runs, not in big batches: a line arrives as soon as it is
    /// written, long before the process ends or 64 KB pile up.
    @Test(.timeLimit(.minutes(1))) func linesArriveLiveNotInBatches() async {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", "echo '[download]   1.0% of 10MiB'; sleep 4; echo done"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        let pump = OutputPump()
        let start = Date()
        try? proc.run()
        try? pipe.fileHandleForWriting.close()
        pump.start(reading: pipe.fileHandleForReading, process: proc)
        var firstLineAfter: TimeInterval?
        var events: [OutputPump.Event] = []
        for await e in pump.events {
            if firstLineAfter == nil, case .line = e { firstLineAfter = Date().timeIntervalSince(start) }
            events.append(e)
        }
        #expect((firstLineAfter ?? 99) < 2)
        #expect(events == [.line("[download]   1.0% of 10MiB"), .line("done"), .exit(0)])
    }

    @Test func readAvailableReturnsWhatIsThere() throws {
        let pipe = Pipe()
        pipe.fileHandleForWriting.write(Data("abc".utf8))
        var buffer = [UInt8](repeating: 0, count: 16)
        #expect(OutputPump.readAvailable(pipe.fileHandleForReading, into: &buffer) == Data("abc".utf8))
        try pipe.fileHandleForWriting.close()
        #expect(OutputPump.readAvailable(pipe.fileHandleForReading, into: &buffer) == Data())
    }

    /// A process that ends before the reader is set up still gets its exit reported, even when a
    /// helper it started keeps the output open.
    @Test(.timeLimit(.minutes(1))) func anEarlyExitWithAHeldPipeStillEnds() async throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", "sleep 30 & echo early"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try proc.run()
        try? pipe.fileHandleForWriting.close()
        while proc.isRunning { try await Task.sleep(for: .milliseconds(20)) }  // ended before start()
        let pump = OutputPump()
        pump.start(reading: pipe.fileHandleForReading, process: proc)
        var events: [OutputPump.Event] = []
        for await e in pump.events { events.append(e) }
        #expect(events == [.line("early"), .exit(0)])
    }

    @Test func exitCodeIsReported() async {
        #expect(await run("exit 3") == [.exit(3)])
    }
}

struct ProbeControlTests {
    @Test func cancelBeforeLaunchRefusesToStart() {
        let control = ProbeControl()
        control.cancel()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sleep")
        proc.arguments = ["30"]
        #expect(!control.launch(proc))
        #expect(!proc.isRunning)
        #expect(control.isCancelled)
    }

    @Test func cancelTerminatesTheRunningProcess() {
        let control = ProbeControl()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sleep")
        proc.arguments = ["30"]
        #expect(control.launch(proc))
        #expect(proc.isRunning)
        control.cancel()
        proc.waitUntilExit()
        #expect(!proc.isRunning)
        #expect(proc.terminationReason == .uncaughtSignal)
    }
}
