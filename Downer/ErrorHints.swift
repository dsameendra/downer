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

    /// The hint to show for a failed run. Cookie problems anywhere in the output win (they explain why a
    /// sign-in still failed); otherwise the last ERROR line decides, so one odd item in a playlist does not
    /// relabel the whole run; the full text is the fallback.
    nonisolated static func classifyForDisplay(
        errorText: String, lastError: String?, cookiesBrowser: CookieBrowser?, usedCookies: Bool
    ) -> ErrorHint? {
        let whole = classify(errorText, cookiesBrowser: cookiesBrowser, usedCookies: usedCookies)
        switch whole {
        case .safariAccess?, .keychain?, .browserNotFound?: return whole
        default: break
        }
        if let lastError,
            let last = classify(lastError, cookiesBrowser: cookiesBrowser, usedCookies: usedCookies)
        {
            // keep the site wording from the whole run (the tag may sit on an earlier line)
            if case .signIn(let b, let u, _) = last, case .signIn(_, _, let y)? = whole {
                return .signIn(browser: b, usedCookies: u, youtube: y)
            }
            return last
        }
        return whole
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
        return false
    }

    nonisolated private static func name(_ browser: CookieBrowser?) -> String {
        browser?.displayName ?? "your browser"
    }
}
