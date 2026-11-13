//
//  DownerTests.swift
//  DownerTests
//
//  Created by Dumindu Sameendra on 2025-04-17.
//

import Foundation
import Testing
@testable import Downer

struct YtDlpArgumentsTests {
    func options(
        _ type: DownloadType = .both, cookies: CookieBrowser? = nil, extra: [String] = []
    ) -> JobOptions {
        JobOptions(
            type: type, resolution: "1080", container: "mp4", audioQuality: "source",
            audioFormat: "opus", folder: URL(fileURLWithPath: "/tmp"),
            cookiesBrowser: cookies, extraArguments: extra)
    }

    let probeFlags = ["--flat-playlist", "--no-warnings", "--print", "%(playlist_title|)s\t%(title)s"]
    let link = "https://example.com/v"
    /// Downer's own cookie flags with Sign-in off: they cancel any cookie setting from a yt-dlp config file.
    let cookiesOff = ["--no-cookies", "--no-cookies-from-browser"]
    let infoJsonOff = ["--no-write-info-json", "--no-embed-info-json"]

    func download(only: [Int]? = nil) -> YtDlpArguments.Purpose {
        .download(pathFile: "/tmp/p.txt", ffmpegDirectory: "/opt/ff", outputFolder: "/Users/x/Downloads", only: only)
    }

    @Test func probeHasNoFormatArgs() {
        let args = YtDlpArguments.build(for: options(), purpose: .probe(only: nil), useCookies: false, url: link)
        #expect(args == cookiesOff + probeFlags + [link])
    }

    @Test func downloadOrdering() {
        let o = options()
        let args = YtDlpArguments.build(for: o, purpose: download(), useCookies: false, url: link)
        let expected = YtDlpArguments.formatArguments(for: o)
            + cookiesOff
            + infoJsonOff
            + ["-o", "/Users/x/Downloads/%(title)s [%(id)s].%(ext)s"]
            + ["-o", "chapter:/Users/x/Downloads/%(title)s - %(section_number)03d %(section_title)s [%(id)s].%(ext)s"]
            + ["--print-to-file", "after_move:filepath", "/tmp/p.txt", "--newline", "--ffmpeg-location", "/opt/ff", link]
        #expect(args == expected)
    }

    @Test func outputTemplateEscapesPercentInFolder() {
        #expect(YtDlpArguments.outputTemplate(folder: "/Users/x/100% Done")
            == "/Users/x/100%% Done/%(title)s [%(id)s].%(ext)s")
        #expect(YtDlpArguments.outputTemplate(folder: "/Users/x/%(id)s/")
            == "/Users/x/%%(id)s/%(title)s [%(id)s].%(ext)s")
        #expect(YtDlpArguments.outputTemplate(folder: "/").hasPrefix("//") == false)
        // a folder name ending in a space is kept exactly (yt-dlp would trim a -P path)
        #expect(YtDlpArguments.outputTemplate(folder: "/Users/x/Videos ", file: "f")
            == "/Users/x/Videos /f")
    }

    /// yt-dlp runs in a private folder that is deleted afterwards, so every output template must be an
    /// absolute path in the destination. Thumbnails, subtitles and playlist files follow the default
    /// template; chapters from --split-chapters have their own, so it is set too.
    @Test func everyOutputGoesUnderTheDestination() {
        let args = YtDlpArguments.build(
            for: options(extra: ["--split-chapters"]), purpose: download(), useCookies: false, url: link)
        let templates = args.indices.filter { args[$0] == "-o" }.map { args[$0 + 1] }
        #expect(templates == [
            "/Users/x/Downloads/" + YtDlpArguments.defaultFileTemplate,
            "chapter:/Users/x/Downloads/" + YtDlpArguments.chapterFileTemplate,
        ])
        // Downer's templates come after the extra args, so they win over anything before them
        #expect(args.firstIndex(of: "-o")! > args.firstIndex(of: "--split-chapters")!)
        #expect(!args.contains("-P") && !args.contains("--paths"))
    }

    @Test func runDirectoryIsPrivateAndEmpty() throws {
        let dir = try #require(RunDirectory.make())
        defer { RunDirectory.remove(dir) }
        let attrs = try FileManager.default.attributesOfItem(atPath: dir.path)
        #expect((attrs[.posixPermissions] as? Int) == 0o700)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
        RunDirectory.remove(dir)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func extraArgsSitBetweenFormatAndRequired() {
        let o = options(extra: ["--foo", "bar"])
        let args = YtDlpArguments.build(for: o, purpose: download(), useCookies: false, url: link)
        let format = YtDlpArguments.formatArguments(for: o)
        #expect(Array(args.prefix(format.count)) == format)
        #expect(Array(args[format.count...].prefix(2)) == ["--foo", "bar"])
        #expect(Array(args[(format.count + 2)...].prefix(2)) == cookiesOff)
        #expect(Array(args[(format.count + 4)...].prefix(2)) == infoJsonOff)
        #expect(args[format.count + 6] == "-o")  // after the extra args, so nothing can override it
        #expect(args[format.count + 8] == "-o")  // chapters
        #expect(args[format.count + 10] == "--print-to-file")
        // the look-up only gets extra args that change how the site is reached
        let probe = YtDlpArguments.build(for: o, purpose: .probe(only: nil), useCookies: false, url: link)
        #expect(probe == cookiesOff + probeFlags + [link])
    }

    @Test func cookiesOnlyWhenRequestedAndSet() {
        let withBrowser = options(cookies: .firefox, extra: ["--force-ipv4"])
        let pair = ["--cookies-from-browser", "firefox"]
        let on = YtDlpArguments.build(for: withBrowser, purpose: .probe(only: nil), useCookies: true, url: link)
        #expect(on == ["--force-ipv4", "--no-cookies"] + pair + probeFlags + [link])
        let off = YtDlpArguments.build(for: withBrowser, purpose: .probe(only: nil), useCookies: false, url: link)
        #expect(!off.contains("--cookies-from-browser"))
        #expect(off == ["--force-ipv4"] + cookiesOff + probeFlags + [link])
        let none = YtDlpArguments.build(for: options(), purpose: download(), useCookies: true, url: link)
        #expect(!none.contains("--cookies-from-browser"))
        #expect(none.contains("--no-cookies-from-browser"))  // nothing chosen: a config's browser is still cancelled
        let dl = YtDlpArguments.build(for: withBrowser, purpose: download(), useCookies: true, url: link)
        let i = dl.firstIndex(of: "--cookies-from-browser")!
        #expect(dl[i + 1] == "firefox")
        #expect(i < dl.firstIndex(of: "--print-to-file")!)
        // info-json is cancelled after the user's extra args and the cookie flags, for downloads only
        #expect(dl.firstIndex(of: "--no-write-info-json")! > dl.firstIndex(of: "--force-ipv4")!)
        #expect(dl.firstIndex(of: "--no-embed-info-json")! > i)
        #expect(!on.contains("--no-write-info-json"))
        // --no-cookies precedes the browser flag, and a config's cookie jar can never be read or rewritten
        #expect(dl.firstIndex(of: "--no-cookies")! < i)
        #expect(!dl.contains("--no-cookies-from-browser"))
    }

    @Test func urlIsLast() {
        for purpose in [YtDlpArguments.Purpose.probe(only: [2]), download(only: [2])] {
            let args = YtDlpArguments.build(
                for: options(cookies: .chrome, extra: ["-q"]), purpose: purpose, useCookies: true, url: link)
            #expect(args.last == link)
        }
    }

    @Test func playlistItems() {
        let probe = YtDlpArguments.build(for: options(), purpose: .probe(only: [1, 3]), useCookies: false, url: link)
        #expect(probe == cookiesOff + probeFlags + ["--playlist-items", "1,3", link])
        let dl = YtDlpArguments.build(for: options(), purpose: download(only: [4]), useCookies: false, url: link)
        #expect(Array(dl.suffix(3)) == ["--playlist-items", "4", link])
        let all = YtDlpArguments.build(for: options(), purpose: download(), useCookies: false, url: link)
        #expect(!all.contains("--playlist-items"))
    }

    @Test func formatBoth() {
        #expect(YtDlpArguments.formatArguments(for: options(.both)) == [
            "-f", "bestvideo[height<=1080]+bestaudio", "--merge-output-format", "mp4"])
    }

    @Test func formatVideo() {
        #expect(YtDlpArguments.formatArguments(for: options(.video)) == [
            "-f", "bestvideo[height<=1080][acodec=none]", "--remux-video", "mp4"])
    }

    @Test func formatAudio() {
        var o = options(.audio)
        #expect(YtDlpArguments.formatArguments(for: o) == [
            "-f", "bestaudio", "--extract-audio", "--audio-format", "opus"])
        o.audioQuality = "128k"
        #expect(YtDlpArguments.formatArguments(for: o) == [
            "-f", "bestaudio[abr<=128][vcodec=none]", "--extract-audio", "--audio-format", "opus",
            "--audio-quality", "128k"])
        o.audioFormat = "source"
        #expect(YtDlpArguments.formatArguments(for: o) == ["-f", "bestaudio[abr<=128][vcodec=none]"])
    }
}
