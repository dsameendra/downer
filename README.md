<div align="center">

<img src="docs/screenshots/app-icon.png" width="112" height="112" alt="Downer app icon">

# Downer

[![License: MIT](https://img.shields.io/badge/license-MIT-0074e8?style=flat-square)](LICENSE) ![macOS 14+](https://img.shields.io/badge/macOS-14%2B-F0384A?style=flat-square) ![Liquid Glass](https://img.shields.io/badge/Liquid%20Glass-macOS%2026-30d158?style=flat-square) [![CI](https://img.shields.io/github/actions/workflow/status/dsameendra/Downer/ci.yml?branch=main&style=flat-square&label=CI)](https://github.com/dsameendra/Downer/actions/workflows/ci.yml)

### Video and audio downloads, native to your Mac.

Paste a link, add as many more as you like, and let Downer work through them in order.

_No terminal. No browser extension. Just a menu bar icon and a shortcut._

**[Download the latest release](https://github.com/dsameendra/Downer/releases/latest)**

</div>

Downer is a lightweight native app for [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) and
[`ffmpeg`](https://www.ffmpeg.org). Download video and audio, audio only or video only, pick the quality and format,
and queue single videos and playlists while something is already downloading. Built for macOS 26 with Liquid Glass,
and works on macOS 14 and later.

<div align="center">

**[Features](#features) · [Install](#installation) · [Using Downer](#using-downer) · [Settings](#settings) · [Troubleshooting](#troubleshooting) · [Building](#building-from-source) · [Changelog](CHANGELOG.md)**

</div>

https://github.com/user-attachments/assets/ce59fdfd-23f9-4584-b3f4-2466414c2a74

## What's new in 2.1

- **Sign in for videos that need it**: optional, off by default, and it asks first. See [Signing in](#signing-in-for-age-restricted-or-bot-checked-videos).
- **[Best Compatibility](#best-compatibility)**: one switch for MP4s that play everywhere, fixing "sound but no picture" in QuickTime.
- **MOV container**, and WebM downloads that fall back to MKV instead of failing.
- **[Extra yt-dlp arguments](#extra-yt-dlp-arguments)** from a list of common options.
- **Update buttons** for `yt-dlp`, `ffmpeg` and `deno`, and `deno` recommended for YouTube.
- **Downer [updates itself](#updates).** On 2.0.x? Install 2.1 by hand once, and it takes care of the rest.
- Clearer error messages that say what to do next.

Older versions are in the [changelog](CHANGELOG.md).

## Features

### Downloading

- **Video + audio**, **audio only** or **video only**.
- **Resolution** from 240p up to 8K (capped at what the video offers), **container** (MP4, MKV, WebM or MOV),
  **audio quality** (best, or capped at 128, 70 or 50 kbps) and **audio format** (keep the source, or convert to MP3,
  AAC or Opus).
- **[Best Compatibility](#best-compatibility)** for H.264 + AAC MP4s that play everywhere.
- Every choice is remembered, and shared between the window and the menu bar.

### The queue

- **Add links at any time.** Paste and press Return; the field clears for the next one. Pasting several links adds
  them all. Invalid or duplicate links are ignored.
- **Videos and playlists, mixed freely.** A playlist shows one row per video, each with its own progress.
- **One at a time, in order**, so your connection and disk are never hammered. Each link keeps the settings it was
  added with.
- **A tray that comes up from the bottom** shows every link and video. Drag or two-finger swipe it up and down.
- **Control each item**: remove, cancel, retry, reorder (press, hold and drag), or swipe a row sideways.
- **Automatic retry** for network hiccups. Videos that are genuinely unavailable are not retried.
- **Show in Finder** reveals every file the queue produced.

### Menu bar and shortcut

Downer lives in the menu bar. Click the icon for a compact popover, or set a **global shortcut**: copy a link
anywhere, press the shortcut, and the popover opens with the link already filled in.

| Menu bar icon | Meaning |
|---|---|
| Double chevron | Idle |
| Ring with a percentage | Downloading one video |
| Ring with `3/12` | Downloading from a queue or playlist (video 3 of 12) |
| Check mark | Finished |
| Orange dot | Something needs attention: a tool is missing, a download failed, or an update is ready |

### Screenshots

<table align="center">
  <tr>
    <td align="center" valign="top" width="33%"><img src="docs/screenshots/main-dark.png" width="270" alt="The main window"/><br/><b>The main window</b><br/><sub>Paste a link, choose the type, resolution, container and quality.</sub></td>
    <td align="center" valign="top" width="33%"><img src="docs/screenshots/main-light.png" width="270" alt="Light mode"/><br/><b>Light mode</b><br/><sub>The same window in light mode.</sub></td>
    <td align="center" valign="top" width="33%"><img src="docs/screenshots/queue-peek.png" width="270" alt="The tray, tucked away"/><br/><b>The tray, tucked away</b><br/><sub>Overall progress and the current item, while you keep adding links.</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top" width="33%"><img src="docs/screenshots/queue-dark.png" width="270" alt="The queue, open"/><br/><b>The queue, open</b><br/><sub>Every link and every video in a playlist, each with its own progress.</sub></td>
    <td align="center" valign="top" width="33%"><img src="docs/screenshots/queue-light.png" width="270" alt="The queue, in light mode"/><br/><b>The queue, in light mode</b><br/><sub>Pull the tray up to see what is happening to each video.</sub></td>
    <td align="center" valign="top" width="33%"><img src="docs/screenshots/settings-dark.png" width="270" alt="Settings"/><br/><b>Settings</b><br/><sub>Appearance, shortcut, sign-in, the tools Downer needs, and updates.</sub></td>
  </tr>
</table>

<div align="center">

<img src="docs/screenshots/popover-dark.png" width="360" alt="The menu bar popover"/><br/><b>The menu bar popover</b><br/><sub>Copy a link, press your shortcut, and it opens with the link filled in.</sub>

<br/>

<img src="docs/screenshots/menubar-icons.png" width="560" alt="Menu bar icon states on a dark and a light menu bar"/><br/><b>Menu bar icon states</b><br/><sub>Idle, downloading (percentage or item of total), finished, and needs attention.</sub>

</div>

## Installation

**You need** macOS 14 or later. Downer uses `yt-dlp` and `ffmpeg`, and recommends `deno` for YouTube; it can install
them for you.

1. **Download** the latest `.dmg` from [Releases](https://github.com/dsameendra/Downer/releases/latest), open it and
   drag **Downer** onto **Applications**.
2. **Allow it to run.** Downer is signed with its own certificate rather than a paid Apple Developer ID, so macOS may
   say *"Downer.app can't be opened."* Run this once in Terminal:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Downer.app
   ```

   Or, without Terminal: open the app once, then go to **System Settings → Privacy & Security** and press
   **Open Anyway** next to the message about Downer.

   Don't re-sign the app (for example with `codesign --sign -`): macOS would forget the permissions you gave it.
3. **Install the tools.** Open **Settings → Requirements** and press **Install** next to anything missing. `ffmpeg`
   needs [Homebrew](https://brew.sh); you can also run `brew install yt-dlp ffmpeg deno` yourself.
4. **Allow folder access.** The first time Downer saves to a protected folder such as Downloads, macOS asks. Choose
   **Allow**.

From 2.1 on, Downer [updates itself](#updates).

## Using Downer

1. Open **Downer**, or click its menu bar icon.
2. Paste a video or playlist link and press **Return**.
3. Choose **Video + Audio**, **Audio Only** or **Video Only**, and the quality and format you want.
4. Paste more links while it downloads. They join the queue.
5. Drag the tray up to see what is happening to each video.
6. When the queue finishes, press **Show in Finder**.

Closing the window hides it and the Dock icon. Click the menu bar icon to bring it back, or right-click it for
**Open Downer**, **Check for Updates…** and **Quit Downer**.

## Settings

| Section | What it does |
|---|---|
| **Appearance** | Theme (Device, Light or Dark), background glow and haptic feedback |
| **Global Shortcut** | The key combination that opens the quick download popover |
| **Sign-in (browser cookies)** | Optional sign-in through your browser, off by default. See [below](#signing-in-for-age-restricted-or-bot-checked-videos). |
| **Requirements** | Shows `yt-dlp`, `ffmpeg`, `ffprobe` and `deno` with their versions, with **Install**, **Update** and **Browse…** |
| **Updates** | Check for updates automatically (on by default) and **Check now** |
| **Advanced** | [Extra yt-dlp arguments](#extra-yt-dlp-arguments) |

About the tools:

- With Homebrew, Downer installs and updates them with `brew`. Without it, `yt-dlp` and `deno` are downloaded from
  their official releases into Downer's own folder, and only installed if they match their published checksum.
  `ffmpeg` needs Homebrew.
- **Update** is disabled while something is downloading, and downloads wait while a tool is being updated. Tools you
  installed some other way show **Manual**.
- `deno` is a JavaScript runtime, recommended for YouTube: without it some videos may fail or offer fewer formats.
  Downer passes it to `yt-dlp` 2025.11.12 or newer automatically, so update `yt-dlp` if yours is older.

### Signing in for age-restricted or bot-checked videos

Some videos need a signed-in session, such as YouTube's age check and "confirm you're not a bot". Downer can let
`yt-dlp` use your browser's sign-in for those, on YouTube and other sites.

- **Off by default.** Turn on **Settings → Sign-in → Sign in with a browser**, pick a browser and read the consent
  screen. Nothing changes until you press **Turn on**.
- **Only when needed.** Downer always tries without cookies first, and uses the browser's cookies only when a site
  says sign-in is required.
- **Stays on your Mac.** `yt-dlp` reads the cookies locally and sends them only to the site you are downloading from.
  Downer never saves, copies, uploads or logs them, and never sees your password. `yt-dlp` config files can't turn
  cookies on behind Downer's back.
- **Off means off.** Turning it off applies immediately, including to links already queued.
- **What macOS may ask:**
  - **Chrome, Brave, Edge, Chromium, Vivaldi, Opera:** once, for the browser's "Safe Storage" Keychain item, which
    is how the cookies are decrypted. Choose **Allow**.
  - **Safari:** Downer needs Full Disk Access. Settings shows whether it has it and opens the right pane. After
    allowing it, quit and reopen Downer.
  - **Firefox:** nothing.

Using your account with a downloader can lead a site to rate-limit or flag it. A secondary account is safer.

### Best Compatibility

Turn on **Best Compatibility** (under the Container picker) to save H.264 video with AAC audio in an MP4. These files
play in QuickTime, on iPhone and almost anywhere else. It fixes MP4s that play sound but show no picture in
QuickTime, which happens when a YouTube MP4 holds AV1 video or Opus audio.

- The container is MP4 while it is on.
- Most YouTube videos offer H.264 only up to 1080p, so higher resolutions fall back to that.
- Files are usually larger.
- The MOV container always uses H.264 and AAC, since MOV can't hold the other codecs.

### Extra yt-dlp arguments

**Settings → Advanced → Extra yt-dlp arguments** adds your own options to every download, for example
`--limit-rate 2M`, `--embed-subs` or `-t mp4`. Quotes and backslashes work as in a shell, and the field tells you
whether what you typed is accepted.

Only common download options are allowed:

| Kind | Examples |
|---|---|
| Format selection and sorting | `-f`, `-S`, `--merge-output-format`, `-t` with `mp3`, `aac`, `mp4`, `mkv` or `sleep` |
| Audio and containers | `-x`, `--audio-format`, `--remux-video`, `--recode-video` |
| Network | `--limit-rate`, `--retries`, `--proxy`, `--sleep-interval`, `-N`, `-4`, `-6` |
| Subtitles and thumbnails | `--write-subs`, `--embed-subs`, `--sub-langs`, `--embed-thumbnail` |
| Metadata, chapters, SponsorBlock | `--embed-metadata`, `--embed-chapters`, `--split-chapters`, `--sponsorblock-remove` |
| Files | `--restrict-filenames`, `--no-overwrites`, `--no-part` |
| What to download | `--download-sections`, `--match-filters`, `--max-filesize`, the date filters |
| Site settings | `--extractor-args`, only for settings such as `youtube:player_client=web` |

Everything else is refused, with the reason shown. That includes options Downer manages itself (output names and
folders, progress, playlist items), options that run commands or change Downer's tools (`--exec`, `--update`, config
locations), and anything that touches cookies (use the Sign-in setting instead). Write long options in full; an
abbreviation such as `--verb` is refused.

Good to know:

- Your options come after Downer's format options, so they can override them. Downer's own output, cookie and
  progress options always win.
- Extra files, such as split chapters, thumbnails and subtitles, are saved next to the video.
- The quick look-up that reads a link's title only uses connection options (`--proxy`, `--geo-verification-proxy`,
  `--xff`, `--source-address`, `--socket-timeout`, `-4`, `-6`, `--extractor-retries`, `--extractor-args`), so
  filters and waits can't stall it.

### Updates

Downer updates itself with [Sparkle](https://sparkle-project.org).

- It checks when it starts and then once a day (turn this off in Settings). If a new version is out at launch, an
  update window opens; later checks show an **Update available** button and an orange dot on the menu bar icon
  instead.
- Choose **Install Update**, **Remind Me Later** or **Skip This Version**. Downer verifies the update's signature,
  replaces itself and relaunches, and waits for running downloads to finish first.
- **Check now** in Settings, or **Check for Updates…** in the menu bar icon's right-click menu, checks right away.
- Updates are signed, and Downer refuses one whose signature doesn't match.

## Privacy

Downer has no accounts, analytics or tracking. It connects to:

- the sites you download from (through `yt-dlp`),
- GitHub, to check for Downer updates (a small `appcast.xml`, with no information about your Mac), and to download
  `yt-dlp` or `deno` when you press **Install**,
- Homebrew, when you install or update tools with it.

Browser cookies are only used if you turn on [Sign-in](#signing-in-for-age-restricted-or-bot-checked-videos).

## Troubleshooting

| Problem | What to try |
|---|---|
| "Downer.app can't be opened" | See [Installation](#installation), step 2. |
| A "Setup needed" banner | Open **Settings → Requirements** and press **Install** next to what is missing. |
| **Install** is greyed out for ffmpeg | Install [Homebrew](https://brew.sh) first. |
| Downloads suddenly stop working for a site, or "yt-dlp may be out of date" | Press **Update** next to `yt-dlp` in Settings → Requirements. Sites change often. |
| "YouTube wants you signed in" | Turn on [Sign in with a browser](#signing-in-for-age-restricted-or-bot-checked-videos). |
| "Still blocked. Sign in to YouTube in …" | Sign in to the site in that browser, then press **Retry**. |
| "Downer needs Full Disk Access to use Safari's sign-in" | Press **Open Full Disk Access Settings**, allow Downer, then quit and reopen it. Or pick another browser. |
| macOS asks about a "Safe Storage" Keychain item | That is how Chrome-based browsers' cookies are decrypted. Choose **Allow**, then retry. |
| "Couldn't find … cookies" | Open that browser, sign in once, then retry. |
| An MP4 plays sound but no picture | Turn on [Best Compatibility](#best-compatibility). |
| A video failed with an HTTP error | Downer retries once by itself. If it still fails, press **Retry**. |
| "This video is unavailable" | It is private, removed or blocked in your region. Retrying won't help. |
| "The site is limiting requests" | Wait a while and try again. |
| Nothing is saved | Check that the **Save to** folder exists and that Downer may write to it. |
| An extra argument is refused | The field says why. Only [common options](#extra-yt-dlp-arguments) are allowed. |
| An update is waiting | It installs when your downloads finish. |

## Building from source

You need Xcode 26 or later (for the Liquid Glass APIs).

```bash
git clone https://github.com/dsameendra/Downer.git
cd Downer
open Downer.xcodeproj
```

Select the **Downer** target, choose your own team under **Signing & Capabilities**, then build and run. The Swift
packages ([Sparkle](https://sparkle-project.org) and
[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)) are fetched automatically.

To install your build, choose **Product → Archive**, then **Distribute App → Custom → Copy App**, and copy
`Downer.app` into `/Applications`.

Run the tests:

```bash
xcodebuild test -project Downer.xcodeproj -scheme Downer -destination 'platform=macOS' -only-testing:DownerTests
./scripts/test-gestures.sh
```

Making a signed release (certificate, Sparkle key, DMG, appcast and publishing) is described in
[`docs/RELEASING.md`](docs/RELEASING.md).

### How it is put together

| File | Role |
|---|---|
| `DownloadManager.swift` | The queue: looks links up, runs `yt-dlp` one at a time, turns its output into progress |
| `QueueLogic.swift` | The queue's decisions (retry, cancel), the output reader and the cancellable look-up |
| `DownloadJob.swift` | One queued link and the settings it was added with |
| `PlaylistModel.swift` | Follows a playlist run line by line (current video, progress, failures) |
| `QueueTray.swift` | The draggable tray with every link and video |
| `YtDlpArguments.swift` | Builds every `yt-dlp` command line, for look-ups and downloads |
| `ExtraArguments.swift` | Splits and checks your extra `yt-dlp` arguments |
| `CookieBrowser.swift`, `CookieConsentSheet.swift` | The opt-in browser sign-in and its consent screen |
| `FullDiskAccess.swift` | Checks Safari's Full Disk Access and builds `yt-dlp`'s environment |
| `ErrorHints.swift` | Turns `yt-dlp` errors into a next step |
| `UpdateChecker.swift` | Connects Sparkle to Downer's Settings, update button and menu |
| `DependencyManager.swift` | Finds, installs and updates `yt-dlp`, `ffmpeg`, `ffprobe` and `deno` |
| `DesignSystem.swift` | Liquid Glass, materials, motion, buttons and window chrome |
| `MenuBarIcon.swift` | The menu bar icon and its states, drawn in code |
| `scripts/make-dmg.sh` | Builds the installer DMG and the signed `appcast.xml` |

[`PRODUCT.md`](PRODUCT.md) describes who Downer is for, and [`DESIGN.md`](DESIGN.md) the design decisions behind it.

## Contributing

Issues and pull requests are welcome.

- Open pull requests against `main`. CI builds the app, runs the tests and checks the release pipeline; it must pass
  before a merge, and every pull request is reviewed by the maintainer.
- Add tests for new behaviour, and update this README and the [changelog](CHANGELOG.md) when users will notice the
  change.
- Please report security problems privately, as described in [`SECURITY.md`](SECURITY.md), not in a public issue.

## License and disclaimer

Downer is released under the [MIT License](LICENSE).

It is meant for personal use and for educational or research purposes. Downloading from YouTube may break its
[Terms of Service](https://www.youtube.com/t/terms) unless the video has a download button or its license allows it.
**You are responsible** for what you download and how you use it. The developer does not support using Downer to
infringe copyright or break platform rules.

---

Built with ❤️ on [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [ffmpeg](https://www.ffmpeg.org). Huge thanks to
the people behind them.

If Downer is useful to you and you'd like to support it (entirely optional):

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/J5R229G51K)
