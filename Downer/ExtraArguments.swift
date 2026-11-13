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

    nonisolated static func validate(_ tokens: [String]) -> ExtraArgumentsError? {
        for token in tokens where token.hasPrefix("-") && token != "-" && token != "--" {
            let isLong = token.hasPrefix("--")
            for rule in rules {
                switch rule {
                case .long(let flag, let reason):
                    if token == flag || token.hasPrefix(flag + "=") { return .init(reason: reason) }
                case .short(let letter, let reason):
                    // -o, -ofile and -o=file all start with the flag letter.
                    if !isLong, token.dropFirst().first == letter { return .init(reason: reason) }
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
