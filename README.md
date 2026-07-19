<p align="center">
  <img src="Resources/AppIcon.png" width="152" alt="Codex Limit Bar icon">
</p>

<h1 align="center">Codex Limit Bar</h1>

<p align="center">
  A native Codex limit tracker for the macOS menu bar.
</p>

<p align="center">
  <strong>English</strong> · <a href="README.uk.md">Українська</a> · <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-111111?logo=apple">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <a href="https://github.com/Vitashka2001/codex-limit-bar/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/Vitashka2001/codex-limit-bar/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/Vitashka2001/codex-limit-bar/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/Vitashka2001/codex-limit-bar"></a>
</p>

Codex Limit Bar displays your remaining Codex allowance directly in the menu bar. It automatically selects the shortest available window and shows detailed 5-hour and weekly limits in its menu.

## Features

- remaining percentage and a color gauge in the menu bar;
- green at 50–100%, yellow at 20–49%, and red below 20%;
- detailed 5-hour and weekly limits with reset times;
- active account and plan display;
- Codex account switching through the official browser sign-in;
- English, Ukrainian, and Russian interface languages;
- manual refresh, monitoring pause, and launch at login;
- native light and dark appearance.

## Requirements

- macOS 13 Ventura or newer;
- [Codex](https://openai.com/codex/) or the official Codex extension for VS Code/Cursor;
- an active Codex sign-in.

Codex Limit Bar communicates with the local `codex app-server`. It does not need a separate API key.

## Installation

1. Download `Codex-Limit-Bar-1.1.1.dmg` from the [latest release](https://github.com/Vitashka2001/codex-limit-bar/releases/latest).
2. Open the image and drag **Codex Limit Bar** into `Applications`.
3. Launch the app. Its indicator appears on the right side of the menu bar.

The public build is locally signed but not notarized by Apple. If macOS blocks the first launch, right-click the app, choose **Open**, and confirm. This is only required once.

## Language

Open the menu, select **Language**, and choose **English**, **Українська**, or **Русский**. The app restarts automatically and remembers the selection. Before a language is selected manually, the app follows the preferred macOS language.

## Controls

- **Limit monitoring** temporarily stops background updates.
- **Switch Codex account...** opens the official sign-in and changes the active Codex account on this Mac.
- **Launch at login** enables or disables automatic launch.
- **Quit completely** closes the app.

To disable the utility completely, turn off **Launch at login** before choosing **Quit completely**. Open the app from `Applications` to enable it again.

## Privacy

The app does not read or store passwords, tokens, or API keys. It launches the locally installed Codex executable and receives only account and limit information. See [PRIVACY.md](PRIVACY.md) for details.

## Build from source

Xcode Command Line Tools and Swift 6 are required:

```sh
swift test
./scripts/build-app.sh
```

The app is written to `dist/Codex Limit Bar.app`.

Create a Universal DMG and ZIP for Apple Silicon and Intel with:

```sh
./scripts/package-release.sh
```

## Project status

This is an independent open-source utility and is not an official OpenAI product. The local Codex protocol may change between versions, so compatibility reports and pull requests are welcome.

Released under the [MIT License](LICENSE).
