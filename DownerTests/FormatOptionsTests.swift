import Foundation
import Testing

@testable import Downer

struct FormatOptionsTests {
    private func options(
        _ type: DownloadType, h264: Bool = false, resolution: String = "1080",
        container: String = "mkv", extra: [String] = []
    ) -> JobOptions {
        JobOptions(
            type: type, resolution: resolution, container: container,
            audioQuality: "source", audioFormat: "opus",
            folder: URL(fileURLWithPath: "/tmp"),
            compatibilityH264: h264, extraArguments: extra)
    }

    // MARK: H.264

    @Test func bothDefaultKeepsChosenContainer() {
        let a = YtDlpArguments.formatArguments(for: options(.both))
        #expect(a == ["-f", "bestvideo[height<=1080]+bestaudio", "--merge-output-format", "mkv"])
    }

    @Test func bothH264ForcesMp4AndSorts() {
        let a = YtDlpArguments.formatArguments(for: options(.both, h264: true))
        #expect(a == [
            "-f", "bestvideo[height<=1080]+bestaudio",
            "--merge-output-format", "mp4",
            "-S", "vcodec:h264,lang,quality,res,fps,hdr:12,acodec:aac",
        ])
    }

    @Test func videoDefaultAndH264() {
        let off = YtDlpArguments.formatArguments(for: options(.video, resolution: "720"))
        #expect(off == ["-f", "bestvideo[height<=720][acodec=none]", "--remux-video", "mkv"])
        let on = YtDlpArguments.formatArguments(for: options(.video, h264: true, resolution: "720"))
        #expect(on == [
            "-f", "bestvideo[height<=720][acodec=none]", "--remux-video", "mp4",
            "-S", "vcodec:h264,lang,quality,res,fps,hdr:12",
        ])
    }

    @Test func h264OverridesChosenContainer() {
        let a = YtDlpArguments.formatArguments(for: options(.both, h264: true, container: "webm"))
        #expect(a.contains("mp4") && !a.contains("webm/mkv"))
    }

    @Test func movNeedsH264AndAac() {
        let both = YtDlpArguments.formatArguments(for: options(.both, container: "mov"))
        #expect(both == [
            "-f", "bestvideo[height<=1080]+bestaudio", "--merge-output-format", "mov",
            "-S", "vcodec:h264,lang,quality,res,fps,hdr:12,acodec:aac",
        ])
        let video = YtDlpArguments.formatArguments(for: options(.video, resolution: "720", container: "mov"))
        #expect(video == [
            "-f", "bestvideo[height<=720][acodec=none]", "--remux-video", "mov",
            "-S", "vcodec:h264,lang,quality,res,fps,hdr:12",
        ])
    }

    @Test func webmMergeFallsBackToMkv() {
        let both = YtDlpArguments.formatArguments(for: options(.both, container: "webm"))
        #expect(both == ["-f", "bestvideo[height<=1080]+bestaudio", "--merge-output-format", "webm/mkv"])
        let video = YtDlpArguments.formatArguments(for: options(.video, resolution: "720", container: "webm"))
        #expect(video == ["-f", "bestvideo[height<=720][acodec=none]", "--remux-video", "webm"])
    }

    @Test func mp4AndMkvStayUnsorted() {
        for c in ["mp4", "mkv"] {
            #expect(!YtDlpArguments.formatArguments(for: options(.both, container: c)).contains("-S"))
        }
    }

    @Test func audioIgnoresH264() {
        #expect(
            YtDlpArguments.formatArguments(for: options(.audio, h264: true))
                == YtDlpArguments.formatArguments(for: options(.audio)))
    }

    // MARK: tokenize

    private func tokens(_ s: String) -> [String]? {
        if case .success(let t) = ExtraArguments.tokenize(s) { return t }
        return nil
    }

    @Test func tokenizeSplitsOnWhitespace() {
        #expect(tokens("  -t   mp4 ") == ["-t", "mp4"])
        #expect(tokens("") == [])
    }

    @Test func tokenizeQuotesAndEscapes() {
        #expect(tokens(#"--user-agent "My Agent 1.0""#) == ["--user-agent", "My Agent 1.0"])
        #expect(tokens("--x 'a b\\c'") == ["--x", "a b\\c"])
        #expect(tokens(#"a\ b"#) == ["a b"])
        #expect(tokens(#""a \"q\" b""#) == [#"a "q" b"#])
        #expect(tokens(#"'' x"#) == ["", "x"])
        #expect(tokens("a$(whoami);b") == ["a$(whoami);b"])
    }

    @Test func tokenizeUnterminatedQuoteFails() {
        #expect(tokens("--x 'oops") == nil)
        #expect(tokens("--x \"oops") == nil)
    }

    // MARK: validate (allowlist)

    private func refused(_ s: String) -> Bool {
        guard let t = tokens(s) else { return true }
        return ExtraArguments.validate(t) != nil
    }

    /// Everything the security review found, plus the options that must never get through.
    @Test func refusesEveryReviewedBypass() {
        for s in [
            "--alias x ' --cookies /tmp/c.txt' --x", "--ali x ' -v'", "' --cookies' /tmp/c.txt",
            #"--use-postprocessor "Exec:echo hi;exec_cmd=touch /tmp/p""#, "--use-postprocessors x",
            "--update-to x", "-U", "--update", "--no-update", "--write-info-json", "--embed-info-json",
            "--clean-info-json", "--no-clean-info-json", "--load-info-json x", "--write-comments", "--get-comments",
            "--downloader curl", "--external-downloader curl", "--downloader-args x", "--external-downloader-args x",
            #"--ppa "ffmpeg:-report""#, "--postprocessor-args x", "--js-runtimes deno:/tmp/x", "--remote-components x",
            "--plugin-dirs /tmp", "--no-plugin-dirs", "-I 5-8", "--playlist-items 5-8", "--playlist-start 2",
            "--playlist-end 3", "--playlist-reverse", "--playlist-random", "--lazy-playlist", "https://x.com",
            "--cookies-from chrome", "--verb", "--cookies x", "--cookies=x", "--cookies-from-browser chrome",
            "--no-cookies", "--no-cookies-from-browser", "--no-check-certificates", "--legacy-server-connect",
            "--client-certificate x", "--client-certificate-key x", "--enable-file-urls", "-a /etc/hosts",
            "--batch-file x", "--cache-dir /tmp", "--rm-cache-dir", "--config-locations x", "--config-location x",
            "--ignore-config", "--no-config", "--netrc", "--netrc-location x", "--netrc-cmd x", "-u bob", "-p x",
            "--username bob", "--password x", "--twofactor 1", "-2 1", "--video-password x", "-o x", "-O x", "-P /x",
            "--output x", "--paths x", "--print x", "--print-to-file a b", "-q", "-v", "--quiet", "--verbose",
            "--print-traffic", "--dump-pages", "--write-pages", "-s", "-j", "-J", "-F", "--list-formats",
            "--list-subs", "-h", "--help", "--version", "--simulate", "--skip-download", "--ffmpeg-location /x",
            "--progress-template x", "--newline", "--no-progress", "--parse-metadata a:b", "--replace-in-metadata a b c",
            "--sponsorblock-api http://x", "--download-archive x", "--write-link", "--write-url-link",
            "--write-description", "--exec x", "--exec-before-download x", "--add-headers 'Cookie: a=b'",
            "--extractor-args youtubepot-bgutilscript:script_path=/tmp/x", "--extractor-args youtube:po_token=abc",
            "--extractor-args youtube:innertube_host=evil.example", "--extractor-args youtube:player_client=/tmp/x",
            "--extractor-args nocolon", "--",
        ] { #expect(refused(s), "\(s)") }
    }

    @Test func refusesAbbreviationsAndBundlesWithRefusedLetters() {
        for s in [
            "--cookies-from-b chrome", "--cookies-from=chrome", "--verb", "--print-tr", "--exec-b x", "--cook x",
            "--limit x", "--embed-sub", "--no-mtim", "-4v", "-xo", "-xofile", "-qs", "-sv", "-4vq", "-iv",
        ] { #expect(refused(s), "\(s)") }
    }

    @Test func refusesLoneDoubleDash() {
        #expect(ExtraArguments.validate(["--"])?.reason.contains("-- would stop Downer") == true)
        #expect(ExtraArguments.parse("--limit-rate 2M -- -o x").isEmpty)
    }

    @Test func allowsCommonOptions() {
        for s in [
            "-t mp4", "-t aac", "-t sleep", "--limit-rate 2M", "-r 2M", "-S \"-vcodec\"", "-S res:720", "-N4", "-N 4",
            "-f bestvideo+bestaudio", "-fbestvideo[height<=720]", "--embed-subs --sub-langs en", "--sub-langs=en.*,ja",
            "--proxy socks5://127.0.0.1:1080", "-4", "-4x", "-x --audio-format mp3", "--no-mtime", "--embed-thumbnail",
            "--embed-metadata", "--add-metadata", "--sponsorblock-remove sponsor,selfpromo", "--retries infinite",
            "--download-sections \"*10:00-12:00\"", "--match-filters \"!is_live\"", "--no-overwrites", "-w",
            "--extractor-args youtube:player_client=web,tv", "--concurrent-fragments 4", "-i", "--merge-output-format mkv",
        ] { #expect(!refused(s), "\(s)") }
    }

    @Test func aValueMayStartWithADash() {
        #expect(ExtraArguments.parse("-S -vcodec") == ["-S", "-vcodec"])
        #expect(ExtraArguments.parse("-f -x") == ["-f", "-x"])  // a value, not a flag
    }

    @Test func valuesAreChecked() {
        #expect(refused("-t ../x"))
        #expect(refused("-t mp5"))
        #expect(refused("-tmp4 x"))  // "mp4" attached, then a stray word
        #expect(!refused("-tmp4"))
        #expect(refused("--limit-rate"))  // missing value
        #expect(refused("--no-mtime=1"))  // a flag with a value
    }

    @Test func strayWordsAreRefused() {
        let reason = ExtraArguments.validate(tokens("-t mp4 https://x.com") ?? [])?.reason
        #expect(reason?.contains("Links go in the link field") == true)
        #expect(refused("hello"))
    }

    @Test func smartQuotesAndDashesAreNormalised() {
        #expect(ExtraArguments.parse("\u{201C}-S\u{201D} \u{201C}res:720\u{201D}") == ["-S", "res:720"])
        #expect(ExtraArguments.parse("-f \u{2018}best\u{2019}") == ["-f", "best"])
        #expect(ExtraArguments.parse("\u{2014}limit-rate 2M") == ["--limit-rate", "2M"])
        #expect(ExtraArguments.parse("\u{2013}N 4") == ["-N", "4"])
        // a normalised dash does not bypass anything
        #expect(ExtraArguments.parse("\u{2014}cookies x").isEmpty)
        #expect(ExtraArguments.parse("\u{2014}alias a b").isEmpty)
    }

    @Test func tokensAreTrimmed() {
        #expect(ExtraArguments.validate([" --cookies", "x"]) != nil)
        #expect(ExtraArguments.validate(["\t--exec"]) != nil)
        #expect(ExtraArguments.validate([" --no-mtime "]) == nil)
    }

    @Test func refusalsHaveReasons() {
        #expect(ExtraArguments.validate(["--cookies", "x"])?.reason.contains("Sign-in") == true)
        #expect(ExtraArguments.validate(["-o", "x"])?.reason.contains("managed by Downer") == true)
        #expect(ExtraArguments.validate(["--alias", "a", "b"])?.reason.contains("isn't allowed") == true)
        let other = ExtraArguments.validate(["--proxy-evil"])?.reason
        #expect(other?.contains("Not supported in Downer: --proxy-evil") == true)
        #expect(other?.contains("Only common download options are allowed") == true)
    }

    // MARK: parse / build

    @Test func parseReturnsEmptyWhenInvalid() {
        #expect(ExtraArguments.parse("-t mp4") == ["-t", "mp4"])
        #expect(ExtraArguments.parse("-t mp4 --exec 'rm -rf x'").isEmpty)
        #expect(ExtraArguments.parse("--x 'unterminated").isEmpty)
        #expect(ExtraArguments.parse("").isEmpty)
    }

    @Test func extraArgumentsStayBeforeDownersFlags() {
        let o = options(.both, h264: true, extra: ["--limit-rate", "2M"])
        let args = YtDlpArguments.build(
            for: o, purpose: .download(pathFile: "/tmp/p", ffmpegDirectory: "/tmp/f", outputFolder: "/tmp/o", only: nil),
            useCookies: false, url: "https://x")
        let extra = args.firstIndex(of: "--limit-rate")!
        #expect(args.firstIndex(of: "-S")! < extra)
        #expect(extra < args.firstIndex(of: "--print-to-file")!)
        #expect(extra < args.firstIndex(of: "--newline")!)
        #expect(args.last == "https://x")
    }

    @Test func probeGetsOnlyConnectionArgumentsAndNoFormat() {
        let o = options(.both, h264: true, extra: ["--limit-rate", "2M", "--proxy", "socks5://127.0.0.1:1080"])
        let args = YtDlpArguments.build(for: o, purpose: .probe(only: nil), useCookies: false, url: "u")
        #expect(!args.contains("--limit-rate") && !args.contains("2M"))
        #expect(args.prefix(2) == ["--proxy", "socks5://127.0.0.1:1080"])
        #expect(!args.contains("-S"))
        // the download still gets every extra argument
        let dl = YtDlpArguments.build(
            for: o, purpose: .download(pathFile: "/p", ffmpegDirectory: "/f", outputFolder: "/o", only: nil),
            useCookies: false, url: "u")
        #expect(dl.contains("--limit-rate") && dl.contains("--proxy"))
    }
}

/// The quick look-up must not be stalled, emptied or failed by options meant for the download.
struct LookupArgumentsTests {
    func lookup(_ text: String) -> [String] {
        guard case .success(let tokens) = ExtraArguments.check(try! ExtraArguments.tokenize(text).get()) else {
            Issue.record("refused: \(text)")
            return []
        }
        return ExtraArguments.forLookup(tokens)
    }

    @Test func waitsFiltersAndFormatsStayWithTheDownload() {
        #expect(lookup("--wait-for-video 60") == [])
        #expect(lookup("--sleep-requests 5 --sleep-interval 3") == [])
        #expect(lookup("--match-filters 'duration>60'") == [])
        #expect(lookup("-f 'bv*[height<=480]+ba' -S res") == [])
        #expect(lookup("--age-limit 18 --date 20240101") == [])
        #expect(lookup("--split-chapters --embed-subs --limit-rate 2M") == [])
    }

    @Test func connectionOptionsReachTheLookup() {
        #expect(lookup("--proxy http://p:8080") == ["--proxy", "http://p:8080"])
        #expect(lookup("--proxy=http://p:8080") == ["--proxy=http://p:8080"])
        #expect(lookup("--extractor-args youtube:player_client=web") == ["--extractor-args", "youtube:player_client=web"])
        #expect(lookup("-4") == ["-4"])
        #expect(lookup("--force-ipv6 --socket-timeout 20 --xff US") == ["--force-ipv6", "--socket-timeout", "20", "--xff", "US"])
        #expect(lookup("--source-address 10.0.0.2 --geo-verification-proxy http://g --extractor-retries 5")
            == ["--source-address", "10.0.0.2", "--geo-verification-proxy", "http://g", "--extractor-retries", "5"])
    }

    @Test func mixedArgumentsKeepOrderAndValuesStayPaired() {
        #expect(lookup("--limit-rate 2M --proxy http://p -f best --wait-for-video 30 -6")
            == ["--proxy", "http://p", "-6"])
        // a value that looks like a lookup option is still the value of the option before it
        #expect(lookup("--sub-langs --proxy") == [])
    }

    @Test func shortBundlesKeepOnlyTheLettersThatApply() {
        #expect(lookup("-4x") == ["-4"])
        #expect(lookup("-4f best") == ["-4"])  // -f takes "best"; it must not leak through
        #expect(lookup("-4fbest") == ["-4"])
        #expect(lookup("-x -R 3 -6") == ["-6"])
        #expect(lookup("-N 4") == [])
    }

    @Test func everyLookupNameIsAnAllowedOption() {
        let allowed = Set(ExtraArguments.allowedNames)
        for name in ExtraArguments.lookupNames { #expect(allowed.contains(name), "\(name)") }
    }
}
