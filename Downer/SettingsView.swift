//
//  SettingsView.swift
//  Downer
//
//  Created by Dumindu Sameendra on 2025-04-17.
//
import AppKit
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    // persisted tool paths
    @AppStorage("backgroundGlow") private var backgroundGlow = true
    @AppStorage(Haptics.storageKey) private var hapticsOn = true
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage("extraArguments") private var extraArgumentsText = ""
    // browser sign-in: off unless the consent sheet's "Turn on" sets it
    @AppStorage("cookiesEnabled") private var cookiesEnabled = false
    @AppStorage("cookiesBrowser") private var cookiesBrowserRaw = ""
    @State private var consent: ConsentMode?
    @ObservedObject private var deps = DependencyManager.shared
    @ObservedObject private var updates = UpdateChecker.shared
    @ObservedObject private var downloads = DownloadManager.shared

    var body: some View {
        ZStack {
            // fix title and colors as soon as it's available to edit
            WindowAccessor { window in
                MainActor.assumeIsolated { DownerWindowChrome.apply(to: window, title: "Settings") }
            }

            AmbientBackground()

            ScrollView {
                VStack(spacing: 14) {
                    appearanceGroup.appear(0)
                    shortcutGroup.appear(1)
                    signInGroup.appear(2)
                    requirementsGroup.appear(3)
                    updatesGroup.appear(4)
                    advancedGroup.appear(5)
                }
                .padding(16)
                .padding(.top, -4)
            }
            .scrollIndicators(.never)

            // drawn last so the scroll view's edge blur never sits on top of the title
            TitleBarRow(title: "Settings") { EmptyView() }
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .tint(Brand.red)
        .frame(width: 400, height: 560)
        .onAppear { deps.refresh() }
    }

    // MARK: Sections
    private var appearanceGroup: some View {
        OptionGroup(title: "Appearance") {
            HStack(spacing: 14) {
                Text("Theme")
                    .font(.system(size: 14))
                Spacer(minLength: 0)
                GlassSegmentedControl(
                    options: AppearanceMode.allCases.map { .init(value: $0, title: $0.title) },
                    selection: Binding(
                        get: { AppearanceMode(rawValue: appearanceRaw) ?? .system },
                        set: { appearanceRaw = $0.rawValue }),
                    height: 32, fontSize: 12, label: "Theme")
                .frame(width: 210)
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .frame(height: 50)
            .overlay(alignment: .bottom) { Divider().opacity(0.6).padding(.horizontal, 14) }
            .onChange(of: appearanceRaw) { _, new in AppearanceMode.apply(new) }

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Background glow")
                        .font(.system(size: 14))
                    Text("Soft colour behind the glass. Off uses a plain window.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle("Background glow", isOn: $backgroundGlow.animation())
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(.vertical, 8)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .frame(minHeight: 58)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Haptic feedback")
                        .font(.system(size: 14))
                    Text("A soft tick on a trackpad when a gesture snaps or completes.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle("Haptic feedback", isOn: $hapticsOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(.vertical, 8)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .frame(minHeight: 58)
            .overlay(alignment: .top) { Divider().opacity(0.6).padding(.horizontal, 14) }
        }
    }

    private var shortcutGroup: some View {
        OptionGroup(title: "Global Shortcut") {
            HStack {
                Text("Open quick download")
                    .font(.system(size: 14))
                Spacer()
                KeyboardShortcuts.Recorder(for: .downloadShortcut)
            }
            .help("Opens the menu bar window from anywhere. A copied link is filled in for you.")
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(height: 46)
        }
    }

    private var advancedGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            OptionGroup(title: "Advanced") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Extra yt-dlp arguments")
                        .font(.system(size: 14))
                    TextField("e.g. -t mp4", text: $extraArgumentsText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                    extraArgumentsStatus
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
            }
            Text("Your arguments come after Downer's format options, so they can override them. Arguments that would break progress tracking or expose cookies are refused.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
        }
    }

    @ViewBuilder
    private var extraArgumentsStatus: some View {
        if extraArgumentsText.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("Optional. Anything yt-dlp accepts, such as --limit-rate 2M.")
                .foregroundStyle(.secondary)
        } else {
            switch ExtraArguments.tokenize(extraArgumentsText) {
            case .failure(let error):
                Text(error.reason).foregroundStyle(Color.red)
            case .success(let tokens):
                if let error = ExtraArguments.validate(tokens) {
                    Text(error.reason).foregroundStyle(Color.red)
                } else {
                    Text("These are added to every download").foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Sign-in (browser cookies)
    private enum ConsentMode: Identifiable {
        case turnOn, explain
        var id: Self { self }
    }

    private var chosenBrowser: CookieBrowser {
        CookieBrowser(rawValue: cookiesBrowserRaw).flatMap { $0.isInstalled ? $0 : nil }
            ?? CookieBrowser.firstInstalled ?? .safari
    }

    private var signInGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            OptionGroup(title: "Sign-in (browser cookies)") {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sign in with a browser")
                            .font(.system(size: 14))
                        Text("For videos that need a signed-in session. Off by default.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    // turning on only asks; the sheet's "Turn on" is what enables it
                    Toggle(
                        "Sign in with a browser",
                        isOn: Binding(
                            get: { cookiesEnabled },
                            set: { on in
                                if on { consent = .turnOn } else { cookiesEnabled = false }
                            })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                .padding(.vertical, 8)
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .frame(minHeight: 58)

                if cookiesEnabled {
                    HStack(spacing: 14) {
                        Text("Browser")
                            .font(.system(size: 14))
                        Spacer(minLength: 0)
                        CookieBrowserMenu(
                            selection: Binding(
                                get: { chosenBrowser }, set: { cookiesBrowserRaw = $0.rawValue }))
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 12)
                    .frame(height: 46)
                    .overlay(alignment: .top) { Divider().opacity(0.6).padding(.horizontal, 14) }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(chosenBrowser.permissionNote)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if chosenBrowser == .safari { FullDiskAccessRow().padding(.vertical, 4) }
                        Button("What does this do?") { consent = .explain }
                            .buttonStyle(.link)
                            .font(.system(size: 12))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) { Divider().opacity(0.6).padding(.horizontal, 14) }
                }
            }
        }
        .sheet(item: $consent) { mode in
            CookieConsentSheet(
                browser: chosenBrowser,
                readOnly: mode == .explain,
                onTurnOn: { browser in
                    cookiesBrowserRaw = browser.rawValue
                    cookiesEnabled = true
                    consent = nil
                },
                onClose: { consent = nil })
        }
    }

    private var updatesGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            OptionGroup(title: "Updates") {
                HStack(spacing: 14) {
                    Text("Check for updates automatically")
                        .font(.system(size: 14))
                    Spacer(minLength: 0)
                    Toggle("Check for updates automatically", isOn: autoCheckBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .frame(height: 46)
                .overlay(alignment: .bottom) { Divider().opacity(0.6).padding(.horizontal, 14) }

                HStack(spacing: 8) {
                    updateStatus
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Check now") { updates.checkForUpdates() }
                        .buttonStyle(PillButtonStyle())
                        .disabled(!updates.isConfigured || !updates.canCheck)
                }
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .frame(minHeight: 44)
            }
            Text("Downer checks GitHub for new releases. Updates are signed and verified before they are installed.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
        }
    }

    private var autoCheckBinding: Binding<Bool> {
        Binding(
            get: { updates.automaticChecks },
            set: { updates.automaticChecks = $0 }
        )
    }

    @ViewBuilder
    private var updateStatus: some View {
        if !updates.isConfigured {
            Text("Downer \(UpdateChecker.currentVersion). Updates are not set up in this build.")
        } else if updates.installWaitingForDownloads {
            Text("Update will install when downloads finish")
        } else if let last = updates.lastChecked {
            Text("Downer \(UpdateChecker.currentVersion). Last checked \(last.formatted(date: .abbreviated, time: .shortened))")
        } else {
            Text("Downer \(UpdateChecker.currentVersion). Not checked yet")
        }
    }

    private var requirementsGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            OptionGroup(title: "Requirements") {
                ForEach(Array(Tool.allCases.enumerated()), id: \.element) { index, tool in
                    requirementRow(tool, showsDivider: index < Tool.allCases.count - 1)
                }
            }
            requirementsFooter
        }
    }

    @ViewBuilder
    private var requirementsFooter: some View {
        let text: String? = {
            if let failure = deps.failure { return failure }
            if !deps.installing.isEmpty { return deps.log.isEmpty ? "Working…" : deps.log }
            if let notice = deps.notice { return notice }
            if deps.brewPath == nil && !deps.missing.isEmpty {
                return deps.missing.contains(where: { $0 != .ytDlp })
                    ? "ffmpeg needs Homebrew. yt-dlp can be installed without it."
                    : nil
            }
            if deps.recommendedMissing.contains(.deno) {
                return "deno is recommended: YouTube downloads can miss formats without it."
            }
            return nil
        }()
        HStack(spacing: 8) {
            if let text {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(deps.failure == nil ? Color.secondary : Color.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if deps.brewPath == nil && deps.missing.contains(where: { $0 != .ytDlp }) {
                Spacer(minLength: 0)
                Button("Get Homebrew") { deps.openHomebrewSite() }
                    .buttonStyle(PillButtonStyle())
            }
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private func requirementRow(_ tool: Tool, showsDivider: Bool) -> some View {
        let st = deps.status[tool]
        let installed = st?.isInstalled ?? false
        let busy = deps.isInstalling(tool)
        let binding = pathBinding(for: tool)

        HStack(spacing: 8) {
            Text(tool.title)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 58, alignment: .leading)

            HStack(spacing: 6) {
                Image(systemName: installed ? "checkmark.circle.fill"
                    : tool.isRequired ? "exclamationmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(installed ? Color.green : tool.isRequired ? Color.orange : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: installed)
                Text(statusText(tool, installed: installed, version: st?.version, busy: busy))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentTransition(.opacity)
                    .help(st?.path ?? tool.subtitle)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 28)
            .background(Color.primary.opacity(0.08), in: Capsule())

            if busy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 70)
                    .transition(.opacity)
            } else if installed {
                if case .manual = deps.updateMethod(for: tool) {
                    Text("Manual")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .help("Installed manually. Update it the way you installed it.")
                } else {
                    Button("Update") { deps.update(tool) }
                        .buttonStyle(PillButtonStyle())
                        .disabled(downloads.isActive)
                        .help(downloads.isActive ? "Wait for the downloads to finish." : "")
                }
                Button("Browse…") { choosePath(for: binding) }
                    .buttonStyle(PillButtonStyle())
            } else {
                Button("Install") { deps.install(tool) }
                    .buttonStyle(PrimaryPillButtonStyle())
                    .disabled(tool.needsHomebrew && deps.brewPath == nil)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 44)
        .motion(value: installed)
        .motion(value: busy)
        .contextMenu {
            Button("Choose file…") { choosePath(for: binding) }
        }
        .overlay(alignment: .bottom) {
            if showsDivider { Divider().opacity(0.6).padding(.horizontal, 14) }
        }
    }

    private func statusText(_ tool: Tool, installed: Bool, version: String?, busy: Bool) -> String {
        if busy { return "Working…" }
        if !installed {
            if !deps.hasCheckedOnce { return "Checking…" }
            return tool.isRequired ? "Not found" : "Recommended"
        }
        return version.map { "Installed · \($0)" } ?? "Installed"
    }

    private func pathBinding(for tool: Tool) -> Binding<String> {
        Binding(
            get: { UserDefaults.standard.string(forKey: tool.defaultsKey) ?? tool.defaultPath },
            set: {
                UserDefaults.standard.set($0, forKey: tool.defaultsKey)
                deps.refresh()
            }
        )
    }

    private func choosePath(for binding: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Choose the executable file"
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                binding.wrappedValue = url.path
            }
        }
    }
}
