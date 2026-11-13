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
        let off = hint("Sign in to confirm you're not a bot")
        #expect(off?.message == "YouTube wants a signed-in session. Turn on Sign-in in Settings.")
        #expect(off?.needsSignInSetting == true)
        let used = hint("Sign in to confirm you're not a bot", .chrome, used: true)
        #expect(used?.message == "Still blocked. Make sure you're signed in to YouTube in Chrome.")
        #expect(used?.needsSignInSetting == false)
    }

    @Test func safariAccess() {
        #expect(hint("PermissionError: Operation not permitted: '/x/Cookies.binarycookies'", .safari) == .safariAccess)
        #expect(hint("[Errno 13] Permission denied: Cookies.binarycookies") == .safariAccess)
        #expect(hint("Operation not permitted: '/tmp/file'") == nil)
        #expect(hint("Cookies.binarycookies") == nil)
        #expect(ErrorHint.safariAccess.message
            == "Safari's cookies need Full Disk Access for Downer — or choose another browser in Settings.")
    }

    @Test func keychain() {
        for text in ["find-generic-password failed", "Cannot decrypt v10 cookies", "failed to decrypt cookie"] {
            #expect(hint(text, .brave) == .keychain(browser: .brave))
        }
        #expect(hint("failed to decrypt cookie", .brave)?.message
            == "Downer couldn't unlock Brave's cookies — allow the Keychain prompt, or choose another browser.")
    }

    @Test func browserNotFound() {
        let h = hint("ERROR: could not find firefox cookies database in /x", .firefox)
        #expect(h == .browserNotFound(browser: .firefox))
        #expect(h?.message == "Couldn't find Firefox's cookies. Is it installed and have you signed in?")
        #expect(hint("could not find the video") == nil)
    }

    @Test func outdated() {
        for text in [
            "Requested format is not available", "HTTP Error 403: Forbidden",
            "n challenge solving failed", "Signature solving failed",
        ] {
            #expect(hint(text) == .outdated, "\(text)")
        }
        #expect(ErrorHint.outdated.message == "yt-dlp may be out of date — update it in Settings → Requirements.")
    }

    @Test func rateLimitedAndUnavailable() {
        #expect(hint("This content isn't available, try again later") == .rateLimited)
        #expect(hint("rate-limited by YouTube") == .rateLimited)
        #expect(ErrorHint.rateLimited.message == "YouTube is rate-limiting requests. Try again in a while.")
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
}
