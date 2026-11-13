//
//  ExtraArguments.swift
//  Downer
//
//  Turns the "Extra yt-dlp arguments" text into argument tokens, and refuses
//  the ones that would break Downer or leak cookies. Nothing here ever runs a shell.
//

import Foundation

struct ExtraArgumentsError: Error, Equatable {
    let reason: String
}

enum ExtraArguments {
    /// Shell-like splitting: whitespace, 'single' and "double" quotes, backslash escapes.
    nonisolated static func tokenize(_ text: String) -> Result<[String], ExtraArgumentsError> {
        var tokens: [String] = []
        var current = ""
        var started = false
        var quote: Character? = nil
        var escaping = false

        for ch in text {
            if escaping {
                current.append(ch)
                escaping = false
            } else if ch == "\\" && quote != "'" {
                escaping = true
                started = true
            } else if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
            } else if ch == "'" || ch == "\"" {
                quote = ch
                started = true
            } else if ch.isWhitespace {
                if started { tokens.append(current) }
                current = ""
                started = false
            } else {
                current.append(ch)
                started = true
            }
        }
        if quote != nil { return .failure(.init(reason: "Missing a closing quote")) }
        if escaping { return .failure(.init(reason: "Ends with a lone backslash")) }
        if started { tokens.append(current) }
        return .success(tokens)
    }

    private enum Rule {
        case long(String, String)  // flag, reason
        case short(Character, String)
    }

    private nonisolated static let managed = "is managed by Downer (it tracks progress and where files are saved)"
    private nonisolated static let cookies = "Cookies are controlled by the Sign-in setting"
    private nonisolated static let noDownload = "would stop anything being downloaded"
    private nonisolated static let noRun = "runs commands, which Downer doesn't allow here"

    private nonisolated static let rules: [Rule] = [
        .short("o", "-o \(managed)"), .long("--output", "--output \(managed)"),
        .short("O", "-O \(managed)"), .long("--print", "--print \(managed)"),
        .short("P", "-P \(managed)"), .long("--paths", "--paths \(managed)"),
        .long("--print-to-file", "--print-to-file \(managed)"),
        .short("q", "-q \(managed)"), .long("--quiet", "--quiet \(managed)"),
        .long("--progress-template", "--progress-template \(managed)"),
        .long("--no-newline", "--no-newline \(managed)"),
        .long("--no-progress", "--no-progress \(managed)"),
        .short("s", "-s \(noDownload)"), .long("--simulate", "--simulate \(noDownload)"),
        .long("--skip-download", "--skip-download \(noDownload)"),
        .short("j", "-j prints data instead of downloading"),
        .long("--dump-json", "--dump-json prints data instead of downloading"),
        .short("J", "-J prints data instead of downloading"),
        .long("--dump-single-json", "--dump-single-json prints data instead of downloading"),
        .long("--ffmpeg-location", "--ffmpeg-location \(managed)"),
        .long("--cookies", cookies), .long("--cookies-from-browser", cookies),
        .long("--no-cookies-from-browser", cookies), .long("--no-cookies", cookies),
        .long("--print-traffic", "--print-traffic can print your cookies"),
        .long("--dump-pages", "--dump-pages can print your cookies"),
        .long("--write-pages", "--write-pages can save your cookies to disk"),
        .short("v", "-v can print your cookies"),
        .long("--verbose", "--verbose can print your cookies"),
        .long("--exec", "--exec \(noRun)"),
        .long("--exec-before-download", "--exec-before-download \(noRun)"),
        .long("--netrc-cmd", "--netrc-cmd \(noRun)"),
        .long("--config-locations", "--config-locations could load settings Downer can't check"),
    ]

    /// Short options that take a value, so the rest of a bundle like `-N4` is that value.
    /// Generated from `yt-dlp 2026.08.19 --help` (a short flag whose line shows a metavar).
    private nonisolated static let shortsTakingValue: Set<Character> = [
        "2", "I", "N", "O", "P", "R", "S", "a", "f", "o", "p", "r", "t", "u",
    ]

    /// Real yt-dlp options that are a prefix of a refused one. optparse prefers an exact
    /// match over an abbreviation, so these are fine to allow (found from `--help`).
    private nonisolated static let exactOptionsAllowed: Set<String> = ["--netrc", "--progress"]

    private nonisolated static let loneDashDashReason = "-- would stop Downer's own options from working"

    nonisolated static func validate(_ tokens: [String]) -> ExtraArgumentsError? {
        for token in tokens {
            if token == "--" { return .init(reason: loneDashDashReason) }
            guard token.hasPrefix("-"), token != "-" else { continue }

            if token.hasPrefix("--") {
                // yt-dlp (optparse) accepts any unambiguous abbreviation of a long option,
                // so --cookies-from-b or --verb must be refused like the full flag.
                let name = String(token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)[0])
                if exactOptionsAllowed.contains(name) { continue }
                for case .long(let flag, let reason) in rules where flag.hasPrefix(name) {
                    return .init(reason: reason)
                }
            } else {
                // Bundled short flags (-4v): walk the letters like optparse does,
                // stopping at an option that takes a value (the rest is that value).
                for letter in token.dropFirst() {
                    for case .short(let refusedLetter, let reason) in rules where refusedLetter == letter {
                        return .init(reason: reason)
                    }
                    if shortsTakingValue.contains(letter) { break }
                }
            }
        }
        return nil
    }

    /// Tokens that are safe to hand to yt-dlp; [] when the text is invalid.
    nonisolated static func parse(_ text: String) -> [String] {
        guard case .success(let tokens) = tokenize(text), validate(tokens) == nil else { return [] }
        return tokens
    }
}
