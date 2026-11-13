//
//  CookiesAndErrorsTests.swift
//  DownerTests
//

import Foundation
import Testing
@testable import Downer

struct ErrorHintTests {
    func hint(_ text: String, _ browser: CookieBrowser? = nil, used: Bool = false) -> ErrorHint? {
        ErrorHint.classify(text, cookiesBrowser: browser, usedCookies: used)
    }

    @Test func signInPhrases() {
        for text in [
            "ERROR: [youtube] abc: Sign in to confirm you’re not a bot. Use --cookies-from-browser or --cookies",
            "ERROR: Sign in to confirm your age. This video may be inappropriate",
            "This video is age-restricted",
            "Use --cookies-from-browser for authentication",
        ] {
            #expect(hint(text)?.isSignIn == true, "\(text)")
        }
    }

    @Test func signInMessages() {
        let off = hint("ERROR: [youtube] x: Sign in to confirm you're not a bot")
        #expect(off?.message == "YouTube wants you signed in. Turn on Sign-in in Settings.")
        #expect(hint("Sign in to confirm you're not a bot")?.message == "This site wants you signed in. Turn on Sign-in in Settings.")
        #expect(off?.needsSignInSetting == true)
        let used = hint("[youtube] Sign in to confirm you're not a bot", .chrome, used: true)
        #expect(used?.message == "Still blocked. Sign in to YouTube in Chrome, then retry.")
        #expect(used?.needsSignInSetting == false)
    }

    @Test func safariAccess() {
        #expect(hint("PermissionError: Operation not permitted: '/x/Cookies.binarycookies'", .safari) == .safariAccess)
        #expect(hint("[Errno 13] Permission denied: Cookies.binarycookies") == .safariAccess)
        #expect(hint("Operation not permitted: '/tmp/file'") == nil)
        #expect(hint("Cookies.binarycookies") == nil)
        #expect(ErrorHint.safariAccess.message == "Downer needs Full Disk Access to use Safari's sign-in.")
        #expect(ErrorHint.safariAccess.needsFullDiskAccess)
        #expect(!ErrorHint.keychain(browser: .safari).needsFullDiskAccess)
    }

    @Test func keychain() {
        for text in ["find-generic-password failed", "Cannot decrypt v10 cookies", "failed to decrypt cookie"] {
            #expect(hint(text, .brave) == .keychain(browser: .brave))
        }
        #expect(hint("failed to decrypt cookie", .brave)?.message
            == "Allow Keychain access to use Brave's sign-in.")
    }

    @Test func browserNotFound() {
        let h = hint("ERROR: could not find firefox cookies database in /x", .firefox)
        #expect(h == .browserNotFound(browser: .firefox))
        #expect(h?.message == "Couldn't find Firefox's cookies. Open Firefox, sign in, then retry.")
        #expect(hint("could not find the video") == nil)
    }

    @Test func outdated() {
        for text in [
            "Requested format is not available", "HTTP Error 403: Forbidden",
            "n challenge solving failed", "Signature solving failed",
        ] {
            #expect(hint(text) == .outdated, "\(text)")
        }
        #expect(ErrorHint.outdated.message == "yt-dlp may be out of date. Update it in Settings.")
    }

    @Test func rateLimitedAndUnavailable() {
        #expect(hint("This content isn't available, try again later") == .rateLimited)
        #expect(hint("rate-limited by YouTube") == .rateLimited)
        #expect(ErrorHint.rateLimited.message == "The site is limiting requests. Try again later.")
        for text in ["Video unavailable", "Private video", "This video is not available"] {
            #expect(hint(text) == .unavailable, "\(text)")
        }
        #expect(ErrorHint.unavailable.message == "This video is unavailable.")
    }

    @Test func caseInsensitive() {
        #expect(hint("SIGN IN TO CONFIRM YOU'RE NOT A BOT")?.isSignIn == true)
        #expect(hint("video UNAVAILABLE") == .unavailable)
        #expect(hint("HTTP error 403") == .outdated)
    }

    @Test func cookieAccessWinsOverSignIn() {
        let both = "ERROR: Operation not permitted: Cookies.binarycookies\nSign in to confirm you're not a bot"
        #expect(hint(both, .safari, used: true) == .safariAccess)
        #expect(hint("failed to decrypt cookie\nnot a bot", .chrome, used: true) == .keychain(browser: .chrome))
        #expect(hint("could not find chrome cookies database\nnot a bot", .chrome) == .browserNotFound(browser: .chrome))
    }

    @Test func signInWinsOverUnavailableAndOutdated() {
        #expect(hint("Video unavailable. Sign in to confirm your age")?.isSignIn == true)
        #expect(hint("HTTP Error 403\nnot a bot")?.isSignIn == true)
    }

    @Test func unknownTextIsNil() {
        #expect(hint("") == nil)
        #expect(hint("ERROR: something strange happened") == nil)
        #expect(hint("[download] 42% of 10MiB") == nil)
    }

    @Test func messagesAreShort() {
        let all: [ErrorHint] = [
            .signIn(browser: nil, usedCookies: false), .signIn(browser: .brave, usedCookies: true),
            .safariAccess, .keychain(browser: .brave), .browserNotFound(browser: .chromium),
            .outdated, .rateLimited, .unavailable,
        ]
        for hint in all { #expect(hint.message.count <= 80, "\(hint.message)") }
    }

    @Test func missingBrowserFallsBackToGenericName() {
        #expect(ErrorHint.keychain(browser: nil).message.contains("your browser"))
    }
}

struct CookieBrowserTests {
    @Test func bundleIdentifiers() {
        let expected: [CookieBrowser: String] = [
            .safari: "com.apple.Safari", .chrome: "com.google.Chrome", .firefox: "org.mozilla.firefox",
            .brave: "com.brave.Browser", .edge: "com.microsoft.edgemac", .chromium: "org.chromium.Chromium",
            .vivaldi: "com.vivaldi.Vivaldi", .opera: "com.operasoftware.Opera",
        ]
        for browser in CookieBrowser.allCases { #expect(browser.bundleIdentifier == expected[browser]) }
    }

    @Test func permissionNotes() {
        #expect(CookieBrowser.firefox.permissionNote == "No extra permission needed.")
        #expect(CookieBrowser.safari.permissionNote.contains("Full Disk Access"))
        #expect(CookieBrowser.chrome.permissionNote.contains("“Chrome Safe Storage”"))
    }

    @Test func cookiesOnlyWhenAskedFor() {
        let o = JobOptions(
            type: .both, resolution: "1080", container: "mp4", audioQuality: "source",
            audioFormat: "opus", folder: URL(fileURLWithPath: "/tmp"), cookiesBrowser: .chrome)
        let off = YtDlpArguments.build(for: o, purpose: .probe(only: nil), useCookies: false, url: "https://e.com")
        let on = YtDlpArguments.build(for: o, purpose: .probe(only: nil), useCookies: true, url: "https://e.com")
        #expect(!off.contains("--cookies-from-browser"))
        #expect(on.contains("--cookies-from-browser"))
        for arg in off + on {
            #expect(arg != "--cookies" && arg != "-v" && arg != "--verbose" && arg != "--print-traffic")
        }
    }

    @Test func offByDefaultInJobOptions() {
        let suite = UserDefaults(suiteName: "downer-cookie-test-\(UUID().uuidString)")!
        #expect(JobOptions.current(suite).cookiesBrowser == nil)
        suite.set("chrome", forKey: "cookiesBrowser")
        #expect(JobOptions.current(suite).cookiesBrowser == nil)  // browser alone does not enable it
        suite.set(true, forKey: "cookiesEnabled")
        #expect(JobOptions.current(suite).cookiesBrowser == .chrome)
    }

    @Test func currentBrowserFollowsTheLiveSetting() {
        let suite = UserDefaults(suiteName: "downer-cookie-test-\(UUID().uuidString)")!
        #expect(CookieBrowser.current(suite) == nil)
        suite.set("safari", forKey: "cookiesBrowser")
        #expect(CookieBrowser.current(suite) == nil)  // browser alone does not enable it
        suite.set(true, forKey: "cookiesEnabled")
        #expect(CookieBrowser.current(suite) == .safari)
        suite.set("firefox", forKey: "cookiesBrowser")  // changed after a link was queued
        #expect(CookieBrowser.current(suite) == .firefox)
        suite.set(false, forKey: "cookiesEnabled")  // switched off: queued links must not use cookies
        #expect(CookieBrowser.current(suite) == nil)
        suite.set(true, forKey: "cookiesEnabled")
        suite.set("not-a-browser", forKey: "cookiesBrowser")
        #expect(CookieBrowser.current(suite) == nil)
    }
}

struct FullDiskAccessTests {
    @Test func candidatePathsTryLegacyThenContainer() {
        let paths = FullDiskAccess.candidatePaths(home: "/Users/x")
        #expect(paths == [
            "/Users/x/Library/Cookies/Cookies.binarycookies",
            "/Users/x/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies",
        ])
    }

    @Test func statusFromAttempts() {
        #expect(FullDiskAccess.status(fromAttempts: [ENOENT, nil]) == .granted)
        #expect(FullDiskAccess.status(fromAttempts: [nil, nil]) == .granted)
        #expect(FullDiskAccess.status(fromAttempts: [ENOENT, EPERM]) == .denied)
        #expect(FullDiskAccess.status(fromAttempts: [EACCES, ENOENT]) == .denied)
        #expect(FullDiskAccess.status(fromAttempts: [ENOENT, ENOENT]) == .noCookieFile)
        #expect(FullDiskAccess.status(fromAttempts: []) == .noCookieFile)
    }

    @Test func settingsLinksTargetFullDiskAccess() {
        #expect(FullDiskAccess.settingsURLs.count == 2)
        for url in FullDiskAccess.settingsURLs {
            #expect(url.scheme == "x-apple.systempreferences")
            #expect(url.absoluteString.hasSuffix("?Privacy_AllFiles"))
        }
    }
}

struct YtDlpEnvironmentTests {
    @Test func homeIsForcedAndXdgDropped() {
        let base = [
            "HOME": "/private/tmp/fake", "XDG_CONFIG_HOME": "/x", "XDG_DATA_HOME": "/y",
            "PATH": "/usr/bin", "LANG": "en_US.UTF-8", "TMPDIR": "/var/folders/t/",
        ]
        let env = YtDlpEnvironment.make(base: base, ffmpegDirectory: "/opt/homebrew/bin", home: "/Users/x")
        #expect(env["HOME"] == "/Users/x")
        #expect(env.keys.allSatisfy { !$0.hasPrefix("XDG_") })
        #expect(env["PATH"] == "/opt/homebrew/bin:/usr/bin")
        #expect(env["LANG"] == "en_US.UTF-8")
        #expect(env["TMPDIR"] == "/var/folders/t/")
    }

    @Test func pathUntouchedWithoutFfmpegDirectory() {
        let env = YtDlpEnvironment.make(base: ["PATH": "/usr/bin"], ffmpegDirectory: nil, home: "/Users/x")
        #expect(env["PATH"] == "/usr/bin")
    }
}

struct FailureReasonTests {
    @Test func prefixIsStripped() {
        #expect(PlaylistTracker.reason(from: "ERROR: [youtube] abc123: Video unavailable") == "Video unavailable")
    }

    @Test func longReasonsAreCapped() {
        let long = "ERROR: [youtube] abc123: " + String(repeating: "x", count: 400)
        #expect(PlaylistTracker.reason(from: long).count == 140)
    }
}

struct AutoRetryTests {
    @Test func webpageErrorsAreTransient() {
        #expect(DownloadJob.isTransient("Unable to download webpage: HTTP Error 503"))
        #expect(DownloadJob.isTransient("Unable to download webpage: HTTP Error 503: Service Unavailable"))
        #expect(DownloadJob.isTransient("Unable to download webpage: <urlopen error timed out>"))
        #expect(DownloadJob.isTransient("Unable to download video data: HTTP Error 502: Bad Gateway message"))
    }

    @Test func permanentErrorsAreNotRetried() {
        #expect(!DownloadJob.isTransient("Sign in to confirm your age. This video may be inappropriate"))
        #expect(!DownloadJob.isTransient("This video is age-restricted"))
        #expect(!DownloadJob.isTransient("Age verification is required"))
        #expect(!DownloadJob.isTransient("Video unavailable"))
        #expect(!DownloadJob.isTransient("Private video"))
        #expect(!DownloadJob.isTransient(nil))
    }
}
