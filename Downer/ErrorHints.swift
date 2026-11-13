//
//  ErrorHints.swift
//  Downer
//
//  Turns yt-dlp's error text into a sentence that says what to do next.
//  The text is only inspected in memory; it is never stored or logged.
//

import Foundation

enum ErrorHint: Equatable {
    case signIn(browser: CookieBrowser?, usedCookies: Bool)
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
            return .signIn(browser: cookiesBrowser, usedCookies: usedCookies)
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

    var isSignIn: Bool {
        if case .signIn = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .signIn(let browser, _):
            // With a browser chosen the run has (or will have) used it, so the cookies did not help.
            if browser == nil { return "YouTube wants a signed-in session. Turn on Sign-in in Settings." }
            return "Still blocked. Make sure you're signed in to YouTube in \(Self.name(browser))."
        case .safariAccess:
            return "Safari's cookies need Full Disk Access for Downer — or choose another browser in Settings."
        case .keychain(let browser):
            return "Downer couldn't unlock \(Self.name(browser))'s cookies — allow the Keychain prompt, or choose another browser."
        case .browserNotFound(let browser):
            return "Couldn't find \(Self.name(browser))'s cookies. Is it installed and have you signed in?"
        case .outdated:
            return "yt-dlp may be out of date — update it in Settings → Requirements."
        case .rateLimited:
            return "YouTube is rate-limiting requests. Try again in a while."
        case .unavailable:
            return "This video is unavailable."
        }
    }

    /// True when the fix is the Sign-in switch, so the UI can offer to open Settings.
    var needsSignInSetting: Bool {
        if case .signIn(nil, _) = self { return true }
        return false
    }

    nonisolated private static func name(_ browser: CookieBrowser?) -> String {
        browser?.displayName ?? "your browser"
    }
}
