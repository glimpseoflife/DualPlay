# DualPlay

Run multiple Roblox instances at once on one Windows PC, with a hotkey to flip between them — no manual handle-closing in Process Explorer every time.

📺 **Usage tutorial:** https://www.youtube.com/watch?v=qRk4H0Y4wEo

## Features

- **Unlock Next Instance** — one click closes Roblox's single-instance lock on every running client, so the next one you launch doesn't kick the others out.
- **Quick Swap** — a hotkey (F9 by default) moves focus to the next Roblox window, cycling in the order you launched them.
- **Close an Instance** — end one chosen instance without taking the others down with it.
- **Keybind** — the small **Key** button next to Quick Swap changes the swap hotkey to anything you want.

## Requirements

- Windows 10 or 11
- [AutoHotkey v2](https://www.autohotkey.com/)

## Install

1. Install AutoHotkey v2.
2. Download this repo (**Code → Download ZIP**) and extract it anywhere.
3. Double-click `DualPlay.ahk` and approve the admin prompt (see [Why admin?](#why-admin)).
4. The first time you click Unlock, DualPlay offers to download Microsoft's free Sysinternals Handle tool from Microsoft's own server. It checks that the file is signed by Microsoft before using it.

## Usage

Each instance signs in with whatever account the Roblox app is currently logged into, and keeps that account for as long as it runs — so you switch the app's account *between* launches:

1. Sign into your first account in the Roblox app and launch the game. Wait until it's in-world.
2. Click **Unlock Next Instance**.
3. Sign into your next account in the Roblox app and launch the game again. It starts alongside the first instead of kicking it.
4. Repeat 2–3 for each extra instance. **Unlock before every launch** — each new instance makes its own lock as soon as it starts, and launching while any instance still holds one kicks that one out. Unlock is safe to click anytime; if nothing's holding a lock, it just says so.

**Quick Swap:** once your instances are in-game, click **Arm Quick Swap**, then press your swap key to cycle focus. It moves to whichever window comes after the one you're in, so clicking into a window manually is respected. While armed, it picks up instances you open or close automatically. The small **Key** button next to it changes the swap hotkey.

**Close one instance:** click **Close an Instance...**, select one (it's brought to the front so you can see which account it is), and confirm — the others keep running.

> **Note:** DualPlay doesn't switch accounts for you. Roblox launches whatever account its app is signed into, ignoring your browser, and switching automatically would mean storing each account's login token — which DualPlay deliberately doesn't do. Sign into each account in the Roblox app yourself before you launch it.

## How it works

Roblox blocks a second client with named single-instance locks — a per-version mutex (`…RobloxPlayerBeta.exe.mtx`) and, on some versions, `ROBLOX_singletonEvent` / `ROBLOX_singletonMutex`. DualPlay uses [Sysinternals Handle](https://learn.microsoft.com/sysinternals/downloads/handle) to close those from outside the process — the same thing people do by hand in Process Explorer (Find Handle → Close Handle), just automated. It closes only those lock objects, never the shared-memory section the running client needs.

- Roblox's files are never modified.
- Nothing is injected into Roblox's process.
- No gameplay input is automated or sent anywhere. Quick Swap only changes which window has focus; you're still the one playing.

The whole thing is one readable script — `DualPlay.ahk` — so you can check exactly what it does before running it.

### Why admin?

Closing a handle that belongs to another process requires administrator rights. DualPlay asks for elevation when it starts.

## Notes

- Each Roblox client uses roughly 2–3 GB of RAM, so how many you can run depends on your PC. If things stutter, close other heavy apps or lower graphics quality on the extra instances.
- While DualPlay is open, the swap key is kept from reaching the game. Pick one your games don't use.
- Settings are stored in `%APPDATA%\DualPlay\settings.ini`.
- Occasionally Roblox may disconnect one account when another joins the same server. That's server-side; just rejoin.

## Disclaimer

DualPlay is not affiliated with or endorsed by Roblox Corporation. Roblox doesn't officially support running multiple clients at once — use it at your own risk. The author isn't responsible for any account action, lost progress, or other consequences.

Sysinternals Handle is © Microsoft and is downloaded directly from Microsoft under its own license; it is not redistributed in this repository.

## License

[MIT](LICENSE)
