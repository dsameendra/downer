//
//  PlaylistChoiceView.swift
//  Downer
//
//  The question asked when a link could mean one video or its whole list, or when a playlist turns
//  out to be very long. Shown as a card rising inside the main window (full) or the menu bar popover
//  (compact). Nothing is looked up or downloaded until it is answered.
//

import SwiftUI

struct PlaylistChoiceCard: View {
    let job: DownloadJob
    /// How many links are waiting on a question, this one included.
    var waiting = 1
    var compact = false
    let onChoose: (PlaylistScope, _ remember: Bool) -> Void
    let onConfirmSize: () -> Void
    /// Removes the link (the view may put it back in its field).
    let onCancel: () -> Void

    @State private var remember = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            header
            if !compact { linkChip }
            buttons
            if !compact, let note { noteRow(note) }
            footer
        }
        .padding(compact ? 12 : 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    // MARK: Text
    private var isMix: Bool { job.kind.isMix }

    private var listName: String { job.kind.listName }

    private var title: String {
        switch job.question {
        case .scope(let isMix): return isMix ? "This video is part of a Mix" : "This video is in a playlist"
        case .wholeMix: return "This link is a whole Mix"
        case .size(let count, let atLeast):
            if !atLeast { return "This playlist has \(count) videos" }
            return count >= 2 ? "This playlist has over \(count) videos" : "This playlist is very long"
        case nil: return job.displayTitle
        }
    }

    private var subtitle: String {
        switch job.question {
        case .scope: return "Download just this video, or the whole \(isMix ? "Mix" : "playlist")?"
        case .wholeMix: return "YouTube makes Mixes on the fly, so one can be 100+ videos. Download all of it?"
        case .size(let count, let atLeast):
            let ask = atLeast && count < 2
                ? "It couldn't be listed in time. Download all of it?" : "Download all of them?"
            return job.title.map { "“\($0)”. \(ask)" } ?? ask
        case nil: return ""
        }
    }

    private var note: String? {
        guard case .scope(true) = job.question else { return nil }
        return "YouTube makes Mixes on the fly, so they can be very long and change each time."
    }

    private var symbol: String {
        switch job.question {
        case .scope(let isMix): return isMix ? "dot.radiowaves.left.and.right" : "music.note.list"
        case .wholeMix: return "dot.radiowaves.left.and.right"
        default: return "square.stack.3d.up"
        }
    }

    // MARK: Pieces
    private var header: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 13 : 15, weight: .semibold))
                .foregroundStyle(Brand.red)
                .frame(width: compact ? 28 : 34, height: compact ? 28 : 34)
                .background(Brand.red.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: compact ? 13.5 : 15, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if waiting > 1 {
                Text("1 of \(waiting)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(waiting) links are waiting for a choice")
            }
        }
    }

    private var linkChip: some View {
        Text(DownloadJob.shortName(of: job.url))
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .help(job.url)
            .accessibilityLabel("Link: \(DownloadJob.shortName(of: job.url))")
    }

    @ViewBuilder
    private var buttons: some View {
        let height: CGFloat = compact ? 34 : 40
        let layout = compact
            ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 8))
        layout {
            switch job.question {
            case .scope:
                Button {
                    onChoose(.video, remember)
                } label: {
                    Label(compact ? "Video" : "Download Video", systemImage: "arrow.down")
                }
                .buttonStyle(DownloadButtonStyle(height: height, flat: compact))
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("Downloads only this video")

                Button {
                    onChoose(.playlist, remember)
                } label: {
                    if compact {
                        Text("Whole \(listName)")
                    } else {
                        HStack(spacing: 6) {
                            Text("Download Whole \(listName)")
                            if isMix {
                                Text("· 100+ videos")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(DownloadButtonStyle(isCancel: true, height: height))
                .accessibilityHint(isMix ? "Mixes can be more than 100 videos" : "Downloads every video in the playlist")
            case .wholeMix:
                Button {
                    onChoose(.playlist, false)
                } label: {
                    Label(compact ? "Whole Mix" : "Download Whole Mix", systemImage: "arrow.down")
                }
                .buttonStyle(DownloadButtonStyle(height: height, flat: compact))
                // no Return shortcut: a whole Mix or a large playlist is only ever a deliberate click
            case .size(let count, let atLeast):
                Button(action: onConfirmSize) {
                    Label(compact || (atLeast && count < 2) ? "Download All"
                          : (atLeast ? "Download All \(count)+" : "Download All \(count)"),
                          systemImage: "arrow.down")
                }
                .buttonStyle(DownloadButtonStyle(height: height, flat: compact))
            case nil:
                EmptyView()
            }
        }
    }

    private func noteRow(_ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.system(size: 12))
        .foregroundStyle(.orange)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if case .scope = job.question {
                Toggle("Remember my choice", isOn: $remember)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .help("Use this answer from now on. Change it in Settings → Downloads.")
            }
            Spacer(minLength: 0)
            Button("Cancel", action: onCancel)
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.cancelAction)
                .help("Remove this link")
        }
    }
}

/// The inline answers on a queue row that is waiting for a choice (used when several links wait).
struct ChoiceRowButtons: View {
    let question: JobQuestion
    let onChoose: (PlaylistScope) -> Void
    let onConfirmSize: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            switch question {
            case .scope(let isMix):
                Button("Video") { onChoose(.video) }
                    .buttonStyle(PrimaryPillButtonStyle())
                    .accessibilityLabel("Download just the video")
                Button(isMix ? "Mix" : "Playlist") { onChoose(.playlist) }
                    .buttonStyle(PillButtonStyle())
                    .accessibilityLabel(isMix ? "Download the whole Mix" : "Download the whole playlist")
            case .wholeMix:
                Button("Download Mix") { onChoose(.playlist) }
                    .buttonStyle(PrimaryPillButtonStyle())
            case .size:
                Button("Download All", action: onConfirmSize)
                    .buttonStyle(PrimaryPillButtonStyle())
            }
        }
    }
}
