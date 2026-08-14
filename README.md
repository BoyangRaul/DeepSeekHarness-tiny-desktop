# DeepSeek Harness — Tiny Desktop

[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-000000?logo=apple)](https://www.apple.com/macos/)
[![Language](https://img.shields.io/badge/language-Swift%20%2B%20WebKit-orange)]()
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A tiny **macOS native desktop wrapper** for [DeepSeek Harness](https://github.com/deepseek-ai/dsh) — the local DeepSeek AI coding environment served at `http://localhost:3080`.

Double-click `DeepSeek Harness.app` → it automatically ensures the backend service is running (starting `npx -y @deepseek-ai/dsh web` and waiting until ready if it isn't) → then shows the DeepSeek Harness UI in a **borderless native WKWebView window**: no browser tabs, no address bar.

> [中文版 README](README.zh-CN.md) · [简体中文说明](README.zh-CN.md)

---

## Features

- **One-click startup** — probes the port first; if the service is down it spawns `npx -y @deepseek-ai/dsh web` in the background and polls until the UI is ready (timeout configurable).
- **Native standalone window** — WKWebView with a hidden title bar; remembers window size and position across launches.
- **Splash screen with live loading feedback** — a native overlay (black background + radial glow + DeepSeek logo + tagline) covers the white-screen boot. Below the logo it shows the **current stage** (`installing plugin…` / `starting server…` / `loading UI…`) and an **animated progress bar in `#4176E5`** — the long first-time install is no longer a silent wait.
- **Bottom loading bar** — if the page is still loading after the splash fades, a thin `#4176E5` progress line appears at the bottom of the window (also visible on ⌘R reload).
- **Built-in default plugin** — auto-installs `dsh-better-sidebar` on first launch (optional, never blocks startup on failure).
- **Frosted-glass sidebar** — translucent sidebar with content shifted below the traffic lights.
- **Fully configurable via environment variables** — port, URL, start command, timeout, plugin name/version (see below).

## Requirements

- macOS **26.0+** (arm64) — the deployment target is pinned to `26.0`
- Xcode Command Line Tools (`swiftc`, `sips`, `iconutil`)
- Node.js 18+ with `npx` on PATH — used to run `@deepseek-ai/dsh`

## Build & Install

```bash
bash build.sh                 # build + install to ~/Applications/DeepSeek Harness.app
bash build.sh --no-install    # build only (output in build/)
open ~/Applications/DeepSeek\ Harness.app
```

The app bundle is self-contained — you can copy `build/DeepSeek Harness.app` anywhere and run it.

## Customize for your machine

> ⚠️ The launcher is hardcoded to the author's machine in a few places. **Before building on your own machine, edit `src/main.swift` → `enum Config`:**

| Setting | Default | Note |
|---|---|---|
| `nodeBin` | `/Users/boyangliu/nodejs/bin` | Directory of your Node.js binary; used for `npx` |
| `port` / `url` | `3080` / `http://localhost:3080` | Also overridable at runtime via env vars |
| bundle id | `com.boyangliu.dsh-web` | In `assets/Info.plist`; change it if you redistribute the app |

### Environment variables (runtime overrides)

| Variable | Default | Description |
|---|---|---|
| `DSH_WEB_PORT` | `3080` | Port the harness listens on |
| `DSH_WEB_URL` | `http://localhost:<port>` | URL loaded in the window |
| `DSH_WEB_CMD` | `npx -y @deepseek-ai/dsh web` | Command used to start the backend |
| `DSH_WEB_TIMEOUT` | `180` | Seconds to wait for the service before showing the failure dialog |
| `DSH_PLUGIN_NAME` | `dsh-better-sidebar` | Default plugin to auto-install |
| `DSH_PLUGIN_VERSION` | `0.10.3` | Version of the default plugin |

Example: `DSH_WEB_PORT=3090 open ~/Applications/DeepSeek\ Harness.app`

## How it works

```
open the app
  └─ SplashView (native overlay: logo + live status + animated progress bar #4176E5)
       ├─ ensurePlugin():  first run → install dsh-better-sidebar (non-blocking)
       ├─ ensureServer():  port down → spawn `npx -y @deepseek-ai/dsh web`, poll until ready
       └─ loadUI():        WKWebView loads the UI → app rendered → splash fades out
```

The backend service keeps running after the app quits — it *is* the DeepSeek Harness session. Closing the window only closes the wrapper.

## Project structure

```
├── src/main.swift       ← all app logic (window / menu / server bootstrap / splash + progress bar)
├── assets/              ← Info.plist, app icon, splash logo, plugin install script
├── build.sh             ← one-shot build & install script
├── tests/               ← window check / dummy HTTP server / splash offscreen render test
└── build/               ← build output (gitignored)
```

## FAQ / Troubleshooting

- **App starts but the window stays blank** → check that port 3080 is free and Node.js is reachable; look at `~/Library/Logs/dsh-web.log`.
- **First launch takes a long time** → that's normal: `npx` downloads `@deepseek-ai/dsh` and the sidebar plugin on first run; the splash shows live progress.
- **I moved/renamed the app** → relaunch from the new location; the window size is remembered via the bundle id.

## Disclaimer

This is an independent community wrapper and is **not affiliated with or endorsed by DeepSeek**. The app icon uses DeepSeek logo assets for personal convenience — replace the icon (`assets/app-icon.png`) if you redistribute the app. All API credentials live in your local `~/.dsh` profile and are never read or uploaded by this launcher.

## License

MIT © 2026 Boyang Liu — see [LICENSE](LICENSE).
