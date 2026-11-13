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

    // MARK: validate

    private func refused(_ s: String) -> Bool {
        guard let t = tokens(s) else { return true }
        return ExtraArguments.validate(t) != nil
    }

    @Test func refusesManagedFlags() {
        for s in [
            "-o x", "--output x", "--output=x", "-ofile", "-O x", "--print x", "--print-to-file a b",
            "-q", "--quiet", "--progress-template x", "--no-newline", "--no-progress", "-s",
            "--simulate", "--skip-download", "-j", "--dump-json", "-J", "--dump-single-json",
            "--ffmpeg-location=/x", "--paths home:/x", "-P /x",
        ] { #expect(refused(s), "\(s)") }
    }

    @Test func refusesCookieAndLeakyAndExecFlags() {
        for s in [
            "--cookies=x", "--cookies x", "--cookies-from-browser chrome", "--no-cookies",
            "--no-cookies-from-browser", "--print-traffic", "--dump-pages", "--write-pages", "-v",
            "--verbose", "--exec", "--exec=rm", "--exec-before-download x", "--netrc-cmd x",
            "--config-locations x",
        ] { #expect(refused(s), "\(s)") }
    }

    @Test func refusesAbbreviatedLongFlags() {
        for s in [
            "--cookies-from-b chrome", "--cookies-from=chrome", "--cookies-from-browser=chrome",
            "--verb", "--print-tr", "--exec-b x", "--exec-before x", "--cook x", "--dump-p", "--write-p",
        ] { #expect(refused(s), "\(s)") }
    }

    @Test func refusesBundledShortFlags() {
        for s in ["-4v", "-xo", "-xofile", "-qs", "-sv", "-4vq", "-iv"] { #expect(refused(s), "\(s)") }
    }

    @Test func refusesLoneDoubleDash() {
        #expect(refused("--"))
        #expect(ExtraArguments.validate(["--"])?.reason.contains("-- would stop Downer") == true)
        #expect(ExtraArguments.parse("--limit-rate 2M -- -o x").isEmpty)
    }

    @Test func bypassStringsNeverParse() {
        for s in ["--cookies-from-b chrome", "--verb", "--print-tr", "-4v", "-xofile", "--"] {
            #expect(ExtraArguments.parse(s).isEmpty, "\(s)")
        }
    }

    @Test func allowsValuesAttachedToValueTakingShorts() {
        // the rest of the bundle is the value, not more flags
        for s in ["-fbestvideo", "-N4", "-r2M", "-t mp4", "-fbestvideo[height<=720]", "-4", "-x", "--netrc", "--progress", "--no-mtime"] {
            #expect(!refused(s), "\(s)")
        }
    }

    @Test func refusalsHaveReasons() {
        let r = ExtraArguments.validate(["--print-traffic"])?.reason
        #expect(r?.contains("cookies") == true)
        #expect(ExtraArguments.validate(["--cookies"])?.reason.contains("Sign-in") == true)
        #expect(ExtraArguments.validate(["-o"])?.reason.contains("managed by Downer") == true)
    }

    @Test func allowsOrdinaryFlags() {
        for s in [
            "-t mp4", "--limit-rate 2M", "-N 4", "--embed-thumbnail", "--ignore-config",
            "--user-agent 'x -o y'", "-f bestvideo", "--sleep-interval 3",
        ] { #expect(!refused(s), "\(s)") }
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
            for: o, purpose: .download(pathFile: "/tmp/p", ffmpegDirectory: "/tmp/f", only: nil),
            useCookies: false, url: "https://x")
        let extra = args.firstIndex(of: "--limit-rate")!
        #expect(args.firstIndex(of: "-S")! < extra)
        #expect(extra < args.firstIndex(of: "--print-to-file")!)
        #expect(extra < args.firstIndex(of: "--newline")!)
        #expect(args.last == "https://x")
    }

    @Test func probeIncludesExtraArgumentsButNoFormat() {
        let o = options(.both, h264: true, extra: ["--limit-rate", "2M"])
        let args = YtDlpArguments.build(for: o, purpose: .probe(only: nil), useCookies: false, url: "u")
        #expect(args.contains("--limit-rate"))
        #expect(!args.contains("-S"))
    }
}
