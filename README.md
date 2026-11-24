# GoldPerHour

[![CI](https://github.com/kejith/GoldPerHour/actions/workflows/ci.yml/badge.svg)](https://github.com/kejith/GoldPerHour/actions/workflows/ci.yml)

Addon for World of Warcraft: Forever (interface 16001). A small meter window shows the gold per hour of the running session and splits the gold into herbs and loot.

- **Herbs** is loot taken from a world object right after Herb Gathering. Everything else counts as **Loot**.
- Items count at their Auctionator price, or at the vendor price without Auctionator. Poor-quality and bind-on-pickup items always count at the vendor price, coins from the loot window count directly.
- Prices are taken when the item is picked up. A later auction house scan does not change old values.

The addon speaks English and German and follows the language of the game client.

## Installation

Unpack the zip of the [latest release](https://github.com/kejith/GoldPerHour/releases/latest) into `World of Warcraft\_forever_\Interface\AddOns`, so that the folder `GoldPerHour` sits there. Then type `/reload` in the game.

The desktop app from [wow-tools-forever](https://github.com/kejith/wow-tools-forever) installs and updates the addon with one click and shows sessions, history and settings.

## The window

A compact meter in the style of Details!, with the tooltip border of the game:

- **Title bar:** the addon icon (grey while the session is not running), "Gold per hour", then play/pause, reset and close. Every button explains itself on hover and names its slash command. Reset asks first and is greyed out while there is nothing to reset.
- **The big number:** the gold per hour of herbs and loot together. During the first minute of a session it shows `--`, because a few early drops would make the rate jump.
- **Below it:** the gold of the session on the left; on the right the clock, green while it runs, or "Paused" with the time so far. Before the first start it says what to do: "Press start to count your gold", or "Loot something or press start" with `autoStart`.
- **Two bars:** herbs (green) and loot (amber), each with icon, name, gold and share. The fill of a bar is its share of the total.
- **Tooltips:** hovering the window lists the most valuable items of both categories, hovering a bar only those of its category (as many per category as `tooltipItems` says).

Drag the window (also by a bar) to move it; the position is saved. `scale` from the desktop app sets its size, `/gph` or the close button hide it.

## Commands

| Command | Effect |
| --- | --- |
| `/gph` | show or hide the window |
| `/gph start`, `/gph stop` | start or pause the session |
| `/gph reset` | move the session to the history and start over |
| `/gph show`, `/gph hide` | show or hide the window |
| `/gph herbid <spellID>` | count another spell as herb gathering |
| `/gph debug` | switch diagnostic chat messages on or off |

The session pauses on logout. After `/reload` it keeps running, after a real login it does not.

## Data for the desktop app

The addon writes to `GoldPerHourDB` (account SavedVariables `GoldPerHour.lua`). The game writes that file only on `/reload` or logout.

- `gold`, `coin`, `items`, `elapsed`: the running session
- `session`: `started`, `lastActive`, `zones`, `chars`, `samples` (gold curve, one point per 5 minutes of session time)
- `history`: finished sessions, at most 100
- `settings`: `scale`, `tooltipItems`, `priceSource` (`auctionator` or `vendor`), `resumeAfterReload`, `autoStart`
- `lastRequest`: result of the last request

Requests arrive through `AppRequest.lua` in the addon folder. The app overwrites the file, the game reads it on the next `/reload`:

```lua
GoldPerHour_AppRequest = { id = 1, action = "reset", settings = { scale = 1.2, autoStart = true } }
```

`action` is `start`, `stop` or `reset` and may be left out. Every `id` runs once. The addon validates the settings itself (scale 0.5 to 2, tooltip 1 to 30 items).

## Development

`tests/test_addon.py` runs the addon in Lua 5.4 against a stubbed WoW API (session, herbs against loot, `/reload`, requests, history, the states of the window, both languages, the `.toc`):

```
uv run tests/test_addon.py
```

`--dump <file>` writes the state at the end of the main scenario as a SavedVariables file. wow-tools-forever uses it as test data (`scripts/fixtures/goldperhour`).

Texts live in `Locales.lua`. English is the default; a language only lists what it translates. To add a language, add a block for its `GetLocale()` code.

Status of 0.3: tested in the simulation, not yet played in the game.

## Releases

Releases are automatic. Raise `## Version:` in `GoldPerHour.toc` and push to `main`:

1. The CI workflow runs the tests and builds the zip.
2. If the version has no tag yet, CI creates the tag `v<version>` and starts the release workflow.
3. The release workflow builds `GoldPerHour-v<version>.zip` with the [BigWigs packager](https://github.com/BigWigsMods/packager), checks it and publishes it as a GitHub release with the commits since the last release as notes.

A tag pushed by hand (`git tag v<version> && git push origin v<version>`) starts the same release workflow. The tag must match the version in the `.toc`. `.pkgmeta` lists what stays out of the zip.

### CurseForge and Wago

The release workflow also uploads to CurseForge and Wago Addons as soon as both the project id and the API token are present. Until then these uploads are skipped.

| Site | One-time setup | Line in `GoldPerHour.toc` | Repository secret |
| --- | --- | --- | --- |
| [CurseForge](https://www.curseforge.com/project/create) | create the project for World of Warcraft, pick a license, wait for approval | `## X-Curse-Project-ID: <id>` (the "Project ID" on the project page) | `CF_API_TOKEN` from <https://authors.curseforge.com/#/settings/api-tokens> |
| [Wago Addons](https://addons.wago.io/developers) | create the project | `## X-Wago-ID: <id>` | `WAGO_API_TOKEN` from <https://addons.wago.io/account/apikeys> |

Set a secret with `gh secret set CF_API_TOKEN --repo kejith/GoldPerHour`. The packager marks the upload as compatible with WoW: Forever from the interface number in the `.toc`. WoWInterface has no category for WoW: Forever.
