//
//  PlaylistLinkTests.swift
//  DownerTests
//
//  Video or playlist (#18): reading links, the decision, yt-dlp's flags, and the queue flow.
//

import Foundation
import Testing
@testable import Downer

struct LinkScopeTests {
    @Test(arguments: [
        // one video
        ("https://www.youtube.com/watch?v=sVP0o2eQF2E", LinkKind.video),
        ("https://youtube.com/watch?v=sVP0o2eQF2E&t=42s", .video),
        ("https://m.youtube.com/watch?v=sVP0o2eQF2E&pp=ygUFbXVzaWM%3D", .video),
        ("https://youtu.be/sVP0o2eQF2E?si=abc123", .video),
        ("https://www.youtube.com/shorts/sVP0o2eQF2E", .video),
        ("https://www.youtube.com/live/sVP0o2eQF2E?feature=share", .video),
        ("https://www.youtube-nocookie.com/embed/sVP0o2eQF2E", .video),
        ("https://music.youtube.com/watch?v=sVP0o2eQF2E", .video),
        // a list with no video named
        ("https://www.youtube.com/playlist?list=PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG", .playlist),
        ("https://www.youtube.com/watch?list=PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG", .playlist),
        ("https://music.youtube.com/playlist?list=OLAK5uy_kXo0aGq1vNq2vSkdq8L2s1o4xRL4rG6eA", .playlist),
        // "videoseries" is 11 letters but not a video: the embed of a whole playlist
        ("https://www.youtube.com/embed/videoseries?list=PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG", .playlist),
        // a whole Mix with no video named
        ("https://www.youtube.com/playlist?list=RDsVP0o2eQF2E", .mix),
        ("https://music.youtube.com/playlist?list=RDCLAK5uy_kmPRjHDECIcuVwnKsx2Ng7fyNgFKWNJFs", .playlist),
        // a video inside a list
        ("https://www.youtube.com/watch?v=sVP0o2eQF2E&list=PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG&index=3",
         .videoInList(isMix: false)),
        ("https://youtu.be/sVP0o2eQF2E?list=PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG", .videoInList(isMix: false)),
        ("https://www.youtube.com/watch?v=sVP0o2eQF2E&list=WL", .videoInList(isMix: false)),
        ("https://www.youtube.com/watch?v=sVP0o2eQF2E&list=LL", .videoInList(isMix: false)),
        ("https://www.youtube.com/shorts/sVP0o2eQF2E?list=PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG",
         .videoInList(isMix: false)),
        ("https://music.youtube.com/watch?v=sVP0o2eQF2E&list=OLAK5uy_kXo0aGq1vNq2vSkdq8L2s1o4xRL4rG6eA",
         .videoInList(isMix: false)),
        // an album playlist starts with RD but is not a Mix
        ("https://music.youtube.com/watch?v=sVP0o2eQF2E&list=RDCLAK5uy_kmPRjHDECIcuVwnKsx2Ng7fyNgFKWNJFs",
         .videoInList(isMix: false)),
        // Mixes and radios: the link from issue #18, and others
        ("https://www.youtube.com/watch?v=sVP0o2eQF2E&list=RDsVP0o2eQF2E&start_radio=1", .videoInList(isMix: true)),
        ("https://www.youtube.com/watch?v=sVP0o2eQF2E&list=RDMM&index=2", .videoInList(isMix: true)),
        ("https://music.youtube.com/watch?v=sVP0o2eQF2E&list=RDAMVMsVP0o2eQF2E", .videoInList(isMix: true)),
        // nothing to ask about
        ("https://www.youtube.com/@SomeChannel/videos", .other),
        ("https://www.youtube.com/watch?v=short", .other),
        ("https://www.youtube.com/watch?v=sVP0o2eQF2E&list=", .video),
        ("https://vimeo.com/123456789", .other),
        ("https://www.bilibili.com/video/BV1xx411c7mD?p=2", .other),
        ("https://notyoutube.com/watch?v=sVP0o2eQF2E&list=RDsVP0o2eQF2E", .other),
        ("ytsearch:lofi beats", .other),
        ("not a link", .other),
    ])
    func classify(_ link: String, _ expected: LinkKind) {
        #expect(LinkScope.classify(link) == expected)
    }

    @Test func mixLists() {
        #expect(LinkScope.isMix("RDsVP0o2eQF2E"))
        #expect(LinkScope.isMix("RDMM"))
        #expect(LinkScope.isMix("RDAMVMsVP0o2eQF2E"))
        #expect(!LinkScope.isMix("RDCLAK5uy_kmPRjHDECIcuVwnKsx2Ng7fyNgFKWNJFs"))
        #expect(!LinkScope.isMix("PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG"))
        #expect(!LinkScope.isMix("WL"))
    }

    @Test func onlyAShortInAListIsRewrittenAndOnlyForTheVideo() {
        let short = "https://www.youtube.com/shorts/sVP0o2eQF2E?list=PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG"
        #expect(LinkScope.urlForYtDlp(short, scope: .video) == "https://www.youtube.com/shorts/sVP0o2eQF2E")
        #expect(LinkScope.urlForYtDlp(short, scope: .playlist) == short)
        #expect(LinkScope.urlForYtDlp(short, scope: nil) == short)
        let watch = "https://www.youtube.com/watch?v=sVP0o2eQF2E&list=RDsVP0o2eQF2E&start_radio=1"
        #expect(LinkScope.urlForYtDlp(watch, scope: .video) == watch)  // --no-playlist does the work
        #expect(LinkScope.urlForYtDlp("https://www.youtube.com/shorts/sVP0o2eQF2E", scope: .video)
            == "https://www.youtube.com/shorts/sVP0o2eQF2E")
    }

    @Test func flags() {
        #expect(PlaylistScope.video.flag == "--no-playlist")
        #expect(PlaylistScope.playlist.flag == "--yes-playlist")
        #expect(PlaylistScope.video.other == .playlist)
    }

    @Test func settingDefaultsToAsk() {
        let defaults = UserDefaults(suiteName: "DownerTests.\(UUID().uuidString)")!
        #expect(PlaylistLinkChoice.current(defaults) == .ask)
        defaults.set("video", forKey: PlaylistLinkChoice.storageKey)
        #expect(PlaylistLinkChoice.current(defaults) == .video)
        defaults.set("nonsense", forKey: PlaylistLinkChoice.storageKey)
        #expect(PlaylistLinkChoice.current(defaults) == .ask)
    }
}

struct PlaylistDecisionTests {
    @Test func videoInAPlaylist() {
        let kind = LinkKind.videoInList(isMix: false)
        #expect(QueueLogic.playlistDecision(for: kind, setting: .ask) == .ask)
        #expect(QueueLogic.playlistDecision(for: kind, setting: .video) == .go(.video))
        #expect(QueueLogic.playlistDecision(for: kind, setting: .playlist) == .go(.playlist))
    }

    @Test func aMixIsNeverDownloadedWholeWithoutAsking() {
        let kind = LinkKind.videoInList(isMix: true)
        #expect(QueueLogic.playlistDecision(for: kind, setting: .ask) == .ask)
        #expect(QueueLogic.playlistDecision(for: kind, setting: .video) == .go(.video))
        #expect(QueueLogic.playlistDecision(for: kind, setting: .playlist) == .ask)
    }

    @Test func plainVideosAndPlaylistsNeverAsk() {
        for setting in PlaylistLinkChoice.allCases {
            #expect(QueueLogic.playlistDecision(for: .video, setting: setting) == .go(nil))
            #expect(QueueLogic.playlistDecision(for: .playlist, setting: setting) == .go(nil))
        }
    }

    @Test func aWholeMixAlwaysAsks() {
        for setting in PlaylistLinkChoice.allCases {
            #expect(QueueLogic.playlistDecision(for: .mix, setting: setting) == .ask)
        }
        #expect(DownloadManager.firstQuestion(for: .mix) == .wholeMix)
        #expect(DownloadManager.firstQuestion(for: .videoInList(isMix: false)) == .scope(isMix: false))
        #expect(DownloadManager.firstQuestion(for: .playlist) == nil)
        #expect(LinkKind.mix.listName == "Mix")
        #expect(LinkKind.videoInList(isMix: false).listName == "Playlist")
    }

    @Test func otherSitesFollowAFirmSetting() {
        #expect(QueueLogic.playlistDecision(for: .other, setting: .ask) == .go(nil))
        #expect(QueueLogic.playlistDecision(for: .other, setting: .video) == .go(.video))
        #expect(QueueLogic.playlistDecision(for: .other, setting: .playlist) == .go(.playlist))
    }

    @Test func sizeQuestion() {
        #expect(QueueLogic.sizeQuestion(count: 199, timedOut: false, alreadyConfirmed: false) == nil)
        #expect(QueueLogic.sizeQuestion(count: 200, timedOut: false, alreadyConfirmed: false)
            == .size(count: 200, atLeast: false))
        #expect(QueueLogic.sizeQuestion(count: 312, timedOut: true, alreadyConfirmed: false)
            == .size(count: 312, atLeast: true))
        #expect(QueueLogic.sizeQuestion(count: 5_000, timedOut: false, alreadyConfirmed: true) == nil)
        // a look-up that ran out of time is a long list, however few it had listed
        #expect(QueueLogic.sizeQuestion(count: 150, timedOut: true, alreadyConfirmed: false)
            == .size(count: 150, atLeast: true))
        #expect(QueueLogic.sizeQuestion(count: 0, timedOut: true, alreadyConfirmed: false)
            == .size(count: 0, atLeast: true))
        #expect(QueueLogic.sizeQuestion(count: 150, timedOut: true, alreadyConfirmed: true) == nil)
    }

    func job(_ url: String, _ scope: PlaylistScope?, _ state: DownloadJob.State = .queued) -> DownloadJob {
        var job = DownloadJob(url: url, options: .current(UserDefaults(suiteName: "DownerTests.dup")!))
        job.scope = scope
        job.state = state
        return job
    }

    @Test func duplicatesAreTheSameLinkWithTheSameChoice() {
        let url = "https://www.youtube.com/watch?v=sVP0o2eQF2E&list=RDsVP0o2eQF2E"
        let video = job(url, .video)
        #expect(QueueLogic.isDuplicate(url: url, scope: .video, in: [video]))
        #expect(!QueueLogic.isDuplicate(url: url, scope: .playlist, in: [video]))
        #expect(!QueueLogic.isDuplicate(url: url, scope: nil, in: [video]))
        #expect(!QueueLogic.isDuplicate(url: url, scope: .video, in: [video], except: video.id))
        #expect(!QueueLogic.isDuplicate(url: url, scope: .video, in: [job(url, .video, .done)]))
        #expect(QueueLogic.isDuplicate(url: url, scope: nil, in: [job(url, nil, .needsChoice)]))
        #expect(!QueueLogic.isDuplicate(url: "https://other", scope: .video, in: [video]))
    }
}

struct PlaylistArgumentTests {
    func options(_ scope: PlaylistScope?, extra: [String] = []) -> JobOptions {
        var o = JobOptions(
            type: .both, resolution: "1080", container: "mp4", audioQuality: "source",
            audioFormat: "opus", folder: URL(fileURLWithPath: "/tmp"), extraArguments: extra)
        o.playlistScope = scope
        return o
    }

    let link = "https://www.youtube.com/watch?v=sVP0o2eQF2E&list=RDsVP0o2eQF2E"
    let download = YtDlpArguments.Purpose.download(
        pathFile: "/tmp/p.txt", ffmpegDirectory: "/opt/ff", outputFolder: "/tmp", only: nil)

    @Test func lookUpAndDownloadBothCarryTheChoice() {
        for scope in [PlaylistScope.video, .playlist] {
            let probe = YtDlpArguments.build(for: options(scope), purpose: .probe(only: nil), useCookies: false, url: link)
            let run = YtDlpArguments.build(for: options(scope), purpose: download, useCookies: false, url: link)
            for args in [probe, run] {
                #expect(args.filter { $0 == scope.flag }.count == 1)
                #expect(!args.contains(scope.other.flag))
                #expect(args.last == link)
            }
        }
    }

    @Test func noFlagWhenYtDlpDecides() {
        let run = YtDlpArguments.build(for: options(nil), purpose: download, useCookies: false, url: link)
        #expect(!run.contains("--no-playlist"))
        #expect(!run.contains("--yes-playlist"))
    }

    @Test func theChoiceComesAfterExtraArgumentsAndCookies() {
        let args = YtDlpArguments.build(
            for: options(.video, extra: ["--limit-rate", "2M"]), purpose: download, useCookies: false, url: link)
        let flag = args.firstIndex(of: "--no-playlist")!
        #expect(args.firstIndex(of: "--limit-rate")! < flag)
        #expect(args.firstIndex(of: "--no-cookies-from-browser")! < flag)
    }

    @Test func extraArgumentsRefuseThePlaylistFlags() {
        for flag in ["--no-playlist", "--yes-playlist"] {
            let error = ExtraArguments.validate([flag])
            #expect(error != nil)
            #expect(error?.reason.contains("Settings → Downloads") == true)
        }
        #expect(ExtraArguments.parse("--no-playlist --embed-subs").isEmpty)
    }
}

struct PartialPlaylistTests {
    @Test func titlesFromAShortenedLookUpSurviveTheRealCount() {
        // the look-up listed 3 titles before its time limit; the download finds 5 videos
        let known = PlaylistProgress(
            title: "Mix - Something",
            items: (1...3).map { PlaylistItem(id: $0, title: "Song \($0)") }, current: nil, speed: nil)
        var tracker = PlaylistTracker(keeping: known)
        tracker.consume("[download] Downloading item 1 of 5")
        let p = tracker.progress
        #expect(p?.total == 5)
        #expect(p?.items.map(\.title) == ["Song 1", "Song 2", "Song 3", nil, nil])
        #expect(p?.title == "Mix - Something")
        #expect(p?.current == 1)
    }

    @Test func jobLabels() {
        var job = DownloadJob(
            url: "https://www.youtube.com/watch?v=sVP0o2eQF2E&list=RDsVP0o2eQF2E",
            options: .current(UserDefaults(suiteName: "DownerTests.labels")!))
        job.kind = .videoInList(isMix: true)
        job.state = .needsChoice
        job.question = .scope(isMix: true)
        #expect(job.displayTitle == "Video in a Mix")
        job.state = .queued
        job.question = nil
        job.scope = .video
        #expect(job.fromList == "a Mix")
        job.scope = .playlist
        #expect(job.fromList == nil)
        job.title = "ALESSO LIVE"
        #expect(job.displayTitle == "ALESSO LIVE")
    }
}

/// The queue itself, through the shared manager. Only links that wait for a choice are added, so
/// nothing is looked up and no yt-dlp runs.
@MainActor
@Suite(.serialized)
struct PlaylistQueueFlowTests {
    let mix = "https://www.youtube.com/watch?v=sVP0o2eQF2E&list=RDsVP0o2eQF2E&start_radio=1"
    let list = "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG"

    func clear(_ dl: DownloadManager) {
        for job in dl.jobs { dl.remove(job.id) }
        dl.clearFinished()
    }

    @Test func aVideoInAListWaitsForTheChoiceWithoutStartingAnything() {
        let dl = DownloadManager.shared
        clear(dl)
        defer { clear(dl) }
        #expect(dl.add(mix, setting: .ask) == 1)
        #expect(dl.jobs.count == 1)
        #expect(dl.jobs[0].state == .needsChoice)
        #expect(dl.jobs[0].question == .scope(isMix: true))
        #expect(dl.needsChoice)
        #expect(!dl.isActive)  // not "downloading": the menu bar shows the attention dot instead
        #expect(!dl.isDownloading)
        #expect(dl.status == "Choose what to download.")
        // pasting it again asks once
        #expect(dl.add(mix, setting: .ask) == 0)
        #expect(dl.pendingChoices.count == 1)
    }

    @Test func severalLinksWaitTogether() {
        let dl = DownloadManager.shared
        clear(dl)
        defer { clear(dl) }
        #expect(dl.add("\(mix)\n\(list)", setting: .ask) == 2)
        #expect(dl.pendingChoices.map(\.question) == [.scope(isMix: true), .scope(isMix: false)])
        dl.remove(dl.jobs[0].id)
        #expect(dl.pendingChoices.count == 1)
    }

    @Test func aMixStillAsksWhenTheSettingIsTheWholePlaylist() {
        let dl = DownloadManager.shared
        clear(dl)
        defer { clear(dl) }
        dl.add(mix, setting: .playlist)
        #expect(dl.jobs.first?.state == .needsChoice)
    }

    @Test func cancelAllThenRetryAsksAgain() {
        let dl = DownloadManager.shared
        clear(dl)
        defer { clear(dl) }
        dl.add(list, setting: .ask)
        dl.cancelAll()
        #expect(dl.jobs.first?.state == .cancelled)
        #expect(!dl.needsChoice)
        dl.retry(dl.jobs[0].id)
        // without a choice yt-dlp would fetch the whole list, so it asks again
        #expect(dl.jobs.first?.state == .needsChoice)
        #expect(dl.jobs.first?.question == .scope(isMix: false))
    }

    @Test func aWholeMixLinkAsksAndCancelGivesTheLinkBack() {
        let dl = DownloadManager.shared
        clear(dl)
        defer { clear(dl) }
        let whole = "https://www.youtube.com/playlist?list=RDsVP0o2eQF2E"
        dl.add(whole, setting: .playlist)
        #expect(dl.jobs.first?.question == .wholeMix)
        #expect(dl.jobs.first?.displayTitle == "A YouTube Mix")
        #expect(dl.hasPendingWork)
        dl.choose(dl.jobs[0].id, scope: .video)  // not an answer to "the whole Mix?"
        #expect(dl.jobs.first?.state == .needsChoice)
        #expect(dl.cancelChoice(dl.jobs[0].id) == whole)
        #expect(dl.jobs.isEmpty)
    }

    @Test func removingTheLastQuestionLeavesAnEmptyQueue() {
        let dl = DownloadManager.shared
        clear(dl)
        dl.add(list, setting: .ask)
        dl.remove(dl.jobs[0].id)
        #expect(dl.jobs.isEmpty)
        #expect(dl.status == "Idle")
    }
}
