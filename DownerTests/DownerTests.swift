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

    func download(only: [Int]? = nil) -> YtDlpArguments.Purpose {
        .download(pathFile: "/tmp/p.txt", ffmpegDirectory: "/opt/ff", only: only)
    }

    @Test func probeHasNoFormatArgs() {
        let args = YtDlpArguments.build(for: options(), purpose: .probe(only: nil), useCookies: false, url: link)
        #expect(args == probeFlags + [link])
    }

    @Test func downloadOrdering() {
        let o = options()
        let args = YtDlpArguments.build(for: o, purpose: download(), useCookies: false, url: link)
        let expected = YtDlpArguments.formatArguments(for: o)
            + ["--print-to-file", "after_move:filepath", "/tmp/p.txt", "--newline", "--ffmpeg-location", "/opt/ff", link]
        #expect(args == expected)
    }

    @Test func extraArgsSitBetweenFormatAndRequired() {
        let o = options(extra: ["--foo", "bar"])
        let args = YtDlpArguments.build(for: o, purpose: download(), useCookies: false, url: link)
        let format = YtDlpArguments.formatArguments(for: o)
        #expect(Array(args.prefix(format.count)) == format)
        #expect(Array(args[format.count...].prefix(2)) == ["--foo", "bar"])
        #expect(args[format.count + 2] == "--print-to-file")
        let probe = YtDlpArguments.build(for: o, purpose: .probe(only: nil), useCookies: false, url: link)
        #expect(probe == ["--foo", "bar"] + probeFlags + [link])
    }

    @Test func cookiesOnlyWhenRequestedAndSet() {
        let withBrowser = options(cookies: .firefox, extra: ["--x"])
        let pair = ["--cookies-from-browser", "firefox"]
        let on = YtDlpArguments.build(for: withBrowser, purpose: .probe(only: nil), useCookies: true, url: link)
        #expect(on == ["--x"] + pair + probeFlags + [link])
        let off = YtDlpArguments.build(for: withBrowser, purpose: .probe(only: nil), useCookies: false, url: link)
        #expect(!off.contains("--cookies-from-browser"))
        let none = YtDlpArguments.build(for: options(), purpose: download(), useCookies: true, url: link)
        #expect(!none.contains("--cookies-from-browser"))
        let dl = YtDlpArguments.build(for: withBrowser, purpose: download(), useCookies: true, url: link)
        let i = dl.firstIndex(of: "--cookies-from-browser")!
        #expect(dl[i + 1] == "firefox")
        #expect(i < dl.firstIndex(of: "--print-to-file")!)
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
        #expect(probe == probeFlags + ["--playlist-items", "1,3", link])
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
