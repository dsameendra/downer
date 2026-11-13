//
//  ExtraArguments.swift
//  Downer
//
//  Turns the "Extra yt-dlp arguments" text into argument tokens. Only a short list of
//  common, harmless download options is accepted; everything else is refused. (A blocklist
//  kept leaking: --alias, --use-postprocessor, --update-to, --write-info-json ... each
//  reach code execution, the cookie jar or the managed binary.) Nothing here runs a shell.
//

import Foundation

struct ExtraArgumentsError: Error, Equatable {
    let reason: String
}

enum ExtraArguments {
    // MARK: Tokenize

    /// Shell-like splitting: whitespace, 'single' and "double" quotes, backslash escapes.
    /// Smart quotes are treated as plain quotes, and each token is trimmed.
    nonisolated static func tokenize(_ text: String) -> Result<[String], ExtraArgumentsError> {
        var tokens: [String] = []
        var current = ""
        var started = false
        var quote: Character? = nil
        var escaping = false

        for ch in normalizeQuotes(text) {
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
        return .success(tokens.map(normalize))
    }

    /// macOS text fields swap straight quotes for curly ones.
    private nonisolated static func normalizeQuotes(_ text: String) -> String {
        var out = text
        for (from, to) in [("\u{201C}", "\""), ("\u{201D}", "\""), ("\u{2018}", "'"), ("\u{2019}", "'")] {
            out = out.replacingOccurrences(of: from, with: to)
        }
        return out
    }

    /// Trims the token and turns dash look-alikes at its start (what autocorrect makes of `--`) into `-`.
    private nonisolated static func normalize(_ raw: String) -> String {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var lead = ""
        let hyphens: Set<Character> = ["\u{2010}", "\u{2011}", "\u{2012}", "\u{2212}"]
        while let first = token.first {
            if first == "-" || hyphens.contains(first) {
                lead += "-"
            } else if first == "\u{2014}" {  // em dash
                lead += "--"
            } else if first == "\u{2013}" {  // en dash: `--name` if that is a real option, else `-X`
                let rest = String(token.dropFirst().prefix { $0 != "=" })
                lead += longOptions["--" + rest] != nil ? "--" : "-"
            } else {
                break
            }
            token.removeFirst()
        }
        return lead + token
    }

    // MARK: Allowlist

    private struct Option {
        let names: [String]
        let takesValue: Bool
    }

    private nonisolated static func flags(_ names: String...) -> Option { Option(names: names, takesValue: false) }
    private nonisolated static func valued(_ names: String...) -> Option { Option(names: names, takesValue: true) }

    /// Every option Downer lets through, checked against `yt-dlp 2026.08.19`'s own parser
    /// (name exists, takes a value or not). None of them runs commands, reads or writes
    /// files outside the download, touches cookies or logins, or changes how Downer tracks a download.
    private nonisolated static let allowed: [Option] = [
        // format selection and sorting
        valued("-f", "--format"), valued("-S", "--format-sort"), flags("--format-sort-reset"),
        flags("--format-sort-force"), flags("--no-format-sort-force"),
        flags("--prefer-free-formats"), flags("--no-prefer-free-formats"),
        flags("--check-formats"), flags("--check-all-formats"), flags("--no-check-formats"),
        flags("--video-multistreams"), flags("--no-video-multistreams"),
        flags("--audio-multistreams"), flags("--no-audio-multistreams"),
        valued("--merge-output-format"), valued("-t", "--preset-alias"),
        // audio and containers
        flags("-x", "--extract-audio"), valued("--audio-format"), valued("--audio-quality"),
        valued("--remux-video"), valued("--recode-video"),
        flags("-k", "--keep-video"), flags("--no-keep-video"),
        flags("--post-overwrites"), flags("--no-post-overwrites"),
        // network
        valued("-r", "--limit-rate"), valued("--throttled-rate"), valued("-R", "--retries"),
        valued("--fragment-retries"), valued("--file-access-retries"), valued("--extractor-retries"),
        valued("--retry-sleep"), valued("-N", "--concurrent-fragments"), valued("--http-chunk-size"),
        valued("--socket-timeout"), valued("--source-address"), valued("--proxy"),
        valued("--geo-verification-proxy"), valued("--xff"),
        flags("-4", "--force-ipv4"), flags("-6", "--force-ipv6"),
        valued("--sleep-requests"), valued("--sleep-interval"), valued("--max-sleep-interval"),
        valued("--sleep-subtitles"),
        flags("--skip-unavailable-fragments"), flags("--abort-on-unavailable-fragments"),
        flags("--keep-fragments"), flags("--no-keep-fragments"),
        flags("--hls-use-mpegts"), flags("--no-hls-use-mpegts"),
        // subtitles and thumbnails
        flags("--write-subs"), flags("--no-write-subs"), flags("--write-auto-subs"),
        flags("--no-write-auto-subs"), valued("--sub-langs"), valued("--sub-format"),
        flags("--embed-subs"), flags("--no-embed-subs"), valued("--convert-subs"),
        flags("--write-thumbnail"), flags("--no-write-thumbnail"), flags("--write-all-thumbnails"),
        flags("--embed-thumbnail"), flags("--no-embed-thumbnail"), valued("--convert-thumbnails"),
        // metadata, chapters, SponsorBlock
        flags("--embed-metadata", "--add-metadata"), flags("--no-embed-metadata"),
        flags("--embed-chapters"), flags("--no-embed-chapters"),
        flags("--split-chapters"), flags("--no-split-chapters"),
        valued("--remove-chapters"), flags("--no-remove-chapters"),
        flags("--force-keyframes-at-cuts"), flags("--no-force-keyframes-at-cuts"),
        valued("--sponsorblock-mark"), valued("--sponsorblock-remove"),
        valued("--sponsorblock-chapter-title"), flags("--no-sponsorblock"),
        // files
        flags("--mtime"), flags("--no-mtime"),
        flags("--restrict-filenames"), flags("--no-restrict-filenames"),
        flags("--windows-filenames"), flags("--no-windows-filenames"), valued("--trim-filenames"),
        flags("-w", "--no-overwrites"), flags("--force-overwrites"), flags("--no-force-overwrites"),
        flags("-c", "--continue"), flags("--no-continue"), flags("--part"), flags("--no-part"),
        // what to download
        valued("--download-sections"), valued("--age-limit"),
        valued("--match-filters"), flags("--no-match-filters"),
        valued("--break-match-filters"), flags("--no-break-match-filters"),
        valued("--min-filesize"), valued("--max-filesize"),
        valued("--date"), valued("--datebefore"), valued("--dateafter"),
        flags("--live-from-start"), flags("--no-live-from-start"),
        valued("--wait-for-video"), flags("--no-wait-for-video"),
        flags("-i", "--ignore-errors"), flags("--no-abort-on-error"), flags("--abort-on-error"),
        // site tweaks, checked separately
        valued("--extractor-args"),
    ]

    private nonisolated static let longOptions: [String: Option] = {
        var table: [String: Option] = [:]
        for option in allowed { for name in option.names where name.hasPrefix("--") { table[name] = option } }
        return table
    }()

    private nonisolated static let shortOptions: [Character: Option] = {
        var table: [Character: Option] = [:]
        for option in allowed {
            for name in option.names where !name.hasPrefix("--") { table[name.last!] = option }
        }
        return table
    }()

    /// The names the Settings footnote and the tests can show.
    nonisolated static var allowedNames: [String] { allowed.flatMap(\.names).sorted() }

    /// `-t` presets. Each one expands to harmless options (checked in yt-dlp's `_PRESET_ALIASES`).
    nonisolated static let presets: Set<String> = ["mp3", "aac", "mp4", "mkv", "sleep"]

    /// Extractor arguments that only choose clients, languages and formats. Anything that could
    /// point yt-dlp at a script, a program or another host (script_path, youtubepot-*, innertube_host,
    /// api, po_token ...) is not on this list.
    private nonisolated static let extractorArgKeys: Set<String> = [
        "player_client", "player_skip", "webpage_skip", "skip", "lang", "formats",
        "include_duplicate_formats", "approximate_date", "raise_incomplete_data", "check_all",
        "comment_sort", "max_comments",
    ]

    // MARK: Validate

    private nonisolated static let generic = "Only common download options are allowed (see the README)."
    private nonisolated static let managed = "is managed by Downer (it tracks progress and where files are saved)"
    private nonisolated static let noRun = "can run commands or change Downer's tools, which isn't allowed here"
    private nonisolated static let cookieReason = "Cookies are controlled by the Sign-in setting"

    /// A specific reason where one helps; otherwise the generic one.
    private nonisolated static func refusal(_ shown: String, name: String) -> ExtraArgumentsError {
        let cookieFiles = ["--add-headers", "--print-traffic", "--dump-pages", "--write-pages", "--write-info-json",
                           "--embed-info-json", "--load-info-json", "-v", "--verbose"]
        let run = ["--alias", "--ali", "--use-postprocessor", "--use-postprocessors", "--exec", "--exec-before-download",
                   "--update", "-U", "--update-to", "--plugin-dirs", "--js-runtimes", "--remote-components",
                   "--downloader", "--external-downloader", "--downloader-args", "--external-downloader-args",
                   "--postprocessor-args", "--ppa", "--netrc-cmd", "--config-locations", "--config-location",
                   "--enable-file-urls", "-a", "--batch-file"]
        let output = ["-o", "--output", "-O", "-P", "--paths", "--print", "--print-to-file", "-q", "--quiet",
                      "--progress-template", "--newline", "--no-newline", "--no-progress", "--ffmpeg-location",
                      "-I", "--playlist-items", "--playlist-start", "--playlist-end", "--download-archive"]
        if name.hasPrefix("--cookies") || name.hasPrefix("--no-cookies") {
            return .init(reason: "\(shown): \(cookieReason)")
        }
        if cookieFiles.contains(name) { return .init(reason: "\(shown) could expose or save your cookies") }
        if run.contains(name) || name.hasPrefix("--client-certificate") || name.hasPrefix("--exec") {
            return .init(reason: "\(shown) \(noRun)")
        }
        if output.contains(name) { return .init(reason: "\(shown) \(managed)") }
        return .init(reason: "Not supported in Downer: \(shown). \(generic)")
    }

    /// The tokens to hand to yt-dlp, or why they were refused.
    nonisolated static func check(_ rawTokens: [String]) -> Result<[String], ExtraArgumentsError> {
        let tokens = rawTokens.map(normalize)
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            i += 1
            if token == "--" { return .failure(.init(reason: "-- would stop Downer's own options from working")) }
            guard token.hasPrefix("-"), token != "-" else {
                return .failure(.init(reason: "Links go in the link field, not here (“\(token.prefix(40))”)"))
            }
            var option: Option?
            var value: String?
            var shown = token
            if token.hasPrefix("--") {
                let parts = token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let name = String(parts[0])
                shown = name
                guard let found = longOptions[name] else { return .failure(refusal(name, name: name)) }
                option = found
                if parts.count == 2 {
                    guard found.takesValue else {
                        return .failure(.init(reason: "\(name) doesn't take a value"))
                    }
                    value = String(parts[1])
                }
            } else {
                // Bundled shorts (-4x): every letter must be allowed; one that takes a value ends the bundle.
                let letters = Array(token.dropFirst())
                for (index, letter) in letters.enumerated() {
                    guard let found = shortOptions[letter] else {
                        return .failure(refusal("-\(letter)", name: "-\(letter)"))
                    }
                    shown = "-\(letter)"
                    option = found
                    if found.takesValue {
                        let attached = String(letters[(index + 1)...])
                        if !attached.isEmpty { value = attached }
                        break
                    }
                }
            }
            guard let option else { continue }
            guard option.takesValue else { continue }
            if value == nil {
                guard i < tokens.count else { return .failure(.init(reason: "\(shown) needs a value")) }
                value = tokens[i]  // the next token is the value, even when it starts with “-”
                i += 1
            }
            if let problem = problem(withValue: value ?? "", for: option) {
                return .failure(.init(reason: "\(shown): \(problem)"))
            }
        }
        return .success(tokens)
    }

    private nonisolated static func problem(withValue value: String, for option: Option) -> String? {
        if value.contains("\0") { return "invalid value" }
        if option.names.contains("--preset-alias") {
            return presets.contains(value) ? nil : "only \(presets.sorted().joined(separator: ", ")) are allowed"
        }
        if option.names.contains("--extractor-args") { return extractorArgsProblem(value) }
        return nil
    }

    /// `IE_KEY:key=value,value;key2=value`
    private nonisolated static func extractorArgsProblem(_ value: String) -> String? {
        let parts = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let allowedKeyChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_+-"))
        guard parts.count == 2, !parts[0].isEmpty,
            parts[0].unicodeScalars.allSatisfy(allowedKeyChars.contains),
            !parts[0].lowercased().hasPrefix("youtubepot")
        else { return "use the form site:key=value, such as youtube:player_client=web" }
        for pair in parts[1].split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = kv[0].trimmingCharacters(in: .whitespaces).lowercased()
            guard extractorArgKeys.contains(key) else { return "“\(key)” isn't an allowed setting" }
            if kv.count == 2, kv[1].contains(where: { "/\\~$`".contains($0) }) {
                return "values that look like paths or addresses aren't allowed"
            }
        }
        return nil
    }

    nonisolated static func validate(_ tokens: [String]) -> ExtraArgumentsError? {
        if case .failure(let error) = check(tokens) { return error }
        return nil
    }

    /// Tokens that are safe to hand to yt-dlp; [] when the text is invalid.
    nonisolated static func parse(_ text: String) -> [String] {
        guard case .success(let tokens) = tokenize(text), case .success(let safe) = check(tokens) else { return [] }
        return safe
    }
}
