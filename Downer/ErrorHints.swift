//
//  ErrorHints.swift
//  Downer
//
//  Turns yt-dlp's error text into a sentence that says what to do next.
//  The text is only inspected in memory; it is never stored or logged.
//

import Foundation

enum ErrorHint: Equatable {
    /// `youtube` is true only when the error text is tagged `[youtube…]`; other sites get neutral wording.
    case signIn(browser: CookieBrowser?, usedCookies: Bool, youtube: Bool = true)
    /// Sign-in is on, but the browser chosen for it is not installed (so no cookies could be used).
    case signInBrowserMissing
    case safariAccess
    case keychain(browser: CookieBrowser?)
    case browserNotFound(browser: CookieBrowser?)
    case outdated
    case rateLimited
    case unavailable

    /// Looks for known yt-dlp phrases (case-insensitive). Problems reading the browser's
    /// cookies are checked before sign-in, because they explain why a sign-in still failed.
    nonisolated static func classify(
        _ errorText: String, cookiesBrowser: CookieBrowser?, usedCookies: Bool
    ) -> ErrorHint? {
        let text = errorText.lowercased()
        func has(_ phrases: String...) -> Bool { phrases.contains { text.contains($0) } }

        if (has("operation not permitted") || has("permission denied")) && has("cookies.binarycookies") {
            return .safariAccess
        }
        if has("find-generic-password failed", "cannot decrypt v10 cookies", "failed to decrypt cookie") {
            return .keychain(browser: cookiesBrowser)
        }
        if has("could not find") && has("cookies database") {
            return .browserNotFound(browser: cookiesBrowser)
        }
        if has("not a bot", "use --cookies-from-browser", "confirm your age", "age-restricted", "sign in to confirm") {
            return .signIn(browser: cookiesBrowser, usedCookies: usedCookies, youtube: text.contains("[youtube"))
        }
        if has("rate-limited by youtube", "try again later") { return .rateLimited }
        if has(
            "requested format is not available", "http error 403", "n challenge solving failed",
            "signature solving failed")
        {
            return .outdated
        }
        if has("video unavailable", "private video", "this video is not available") { return .unavailable }
        return nil
    }

    /// Whether a failed run hit a sign-in wall, which is what lets Downer retry with the browser's cookies.
    /// Only ERROR lines decide: a sign-in WARNING next to some other failure (a network error, a missing
    /// video, or a format the person's own `-f` asked for) must never cause a cookie retry and its
    /// Keychain prompt.
    nonisolated static func requiresSignIn(_ log: ErrorLog) -> Bool {
        classify(log.errors.joined(separator: "\n"), cookiesBrowser: nil, usedCookies: false)?.isSignIn == true
    }

    /// The hint to show for a failed run. Cookie problems anywhere in the output win (they explain why a
    /// sign-in still failed, and yt-dlp often reports them as warnings). A sign-in hint is shown only when
    /// `requiresSignIn` agrees, so the hint and the cookie retry never disagree. Otherwise the last ERROR
    /// line decides, so one odd item in a playlist does not relabel the whole run; then all ERROR lines,
    /// then the warnings.
    nonisolated static func forFailedRun(
        _ log: ErrorLog, cookiesBrowser: CookieBrowser?, usedCookies: Bool
    ) -> ErrorHint? {
        func hint(_ text: String) -> ErrorHint? {
            classify(text, cookiesBrowser: cookiesBrowser, usedCookies: usedCookies)
        }
        let whole = hint(log.text)
        switch whole {
        case .safariAccess?, .keychain?, .browserNotFound?: return whole
        default: break
        }
        let last = log.lastError.flatMap(hint)
        if requiresSignIn(log), last == nil || last?.isSignIn == true {
            // the site tag may sit on an earlier line than the sign-in message
            return .signIn(
                browser: cookiesBrowser, usedCookies: usedCookies, youtube: log.text.lowercased().contains("[youtube"))
        }
        // a sign-in warning must not hide another warning's hint (an outdated yt-dlp, say)
        let otherWarnings = log.warnings.filter { hint($0)?.isSignIn != true }
        let fallback = [last, hint(log.errors.joined(separator: "\n")), hint(otherWarnings.joined(separator: "\n"))]
        return fallback.compactMap { $0 }.first { !$0.isSignIn }
    }

    /// A sign-in hint with no browser means Sign-in was off, unless it is on and its browser is gone.
    nonisolated func resolvingMissingBrowser(cookiesEnabled: Bool) -> ErrorHint {
        if cookiesEnabled, case .signIn(nil, _, _) = self { return .signInBrowserMissing }
        return self
    }

    var isSignIn: Bool {
        if case .signIn = self { return true }
        return false
    }

    /// One short sentence (about 70 characters or fewer) so it fits on two lines of the status line.
    var message: String {
        switch self {
        case .signIn(let browser, _, let youtube):
            let site = youtube ? "YouTube" : "the site"
            // With a browser chosen the run has (or will have) used it, so the cookies did not help.
            if browser == nil {
                return youtube
                    ? "YouTube wants you signed in. Turn on Sign-in in Settings."
                    : "This site wants you signed in. Turn on Sign-in in Settings."
            }
            return "Still blocked. Sign in to \(site) in \(Self.name(browser)), then retry."
        case .signInBrowserMissing:
            return "Your sign-in browser isn't installed. Choose another in Settings."
        case .safariAccess:
            return "Downer needs Full Disk Access to use Safari's sign-in."
        case .keychain(let browser):
            return "Allow Keychain access to use \(Self.name(browser))'s sign-in."
        case .browserNotFound(let browser):
            return "Couldn't find \(Self.name(browser))'s cookies. Open \(Self.name(browser)), sign in, then retry."
        case .outdated:
            return "yt-dlp may be out of date. Update it in Settings."
        case .rateLimited:
            return "The site is limiting requests. Try again later."
        case .unavailable:
            return "This video is unavailable."
        }
    }

    /// True when the fix is Full Disk Access, so the UI can offer to open that Settings pane.
    var needsFullDiskAccess: Bool { self == .safariAccess }

    /// True when the fix is the Sign-in switch, so the UI can offer to open Settings.
    var needsSignInSetting: Bool {
        if case .signIn(nil, _, _) = self { return true }
        return self == .signInBrowserMissing
    }

    nonisolated private static func name(_ browser: CookieBrowser?) -> String {
        browser?.displayName ?? "your browser"
    }
}
