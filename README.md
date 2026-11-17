# GoldPerHour

Addon für World of Warcraft: Forever (Interface 16001). Ein kleines Fenster zeigt Gold und Gold pro Stunde der laufenden Sitzung, getrennt nach Kräutern und Loot.

- **Kräuter** ist Loot direkt nach Kräutersammeln aus einem Weltobjekt, alles andere zählt als **Loot**.
- Items zählen zum Auctionator-Preis, ohne Auctionator zum Händlerpreis. Graue und beim Aufheben gebundene Items zählen immer zum Händlerpreis, Münzen aus dem Lootfenster direkt.
- Preise gelten beim Aufheben. Ein späterer AH-Scan ändert alte Werte nicht.

## Installation

Das Zip des [neuesten Release](https://github.com/kejith/GoldPerHour/releases/latest) nach `World of Warcraft\_forever_\Interface\AddOns` entpacken, sodass dort der Ordner `GoldPerHour` liegt. Danach im Spiel `/reload`.

Die Desktop-App aus [wow-forever-tools](https://github.com/kejith/wow-forever-tools) installiert und aktualisiert das Addon per Klick und zeigt Sitzungen, Verlauf und Einstellungen.

## Befehle

| Befehl | Wirkung |
| --- | --- |
| `/gph` | Fenster ein- und ausblenden |
| `/gph start`, `/gph stop` | Sitzung starten, anhalten |
| `/gph reset` | Sitzung in den Verlauf legen und neu beginnen |
| `/gph show`, `/gph hide` | Fenster zeigen, verstecken |
| `/gph herbid <ZauberID>` | weiteren Zauber als Kräutersammeln zählen |
| `/gph debug` | Diagnosemeldungen im Chat ein- und ausschalten |

Die Sitzung pausiert beim Logout. Nach `/reload` läuft sie weiter, nach einem echten Login nicht.

## Daten für die Desktop-App

Das Addon schreibt nach `GoldPerHourDB` (Account-SavedVariables `GoldPerHour.lua`). WoW schreibt die Datei nur bei `/reload` oder Logout.

- `gold`, `coin`, `items`, `elapsed`: laufende Sitzung
- `session`: `started`, `lastActive`, `zones`, `chars`, `samples` (Goldkurve, ein Punkt alle 5 Minuten Sitzungszeit)
- `history`: abgeschlossene Sitzungen, höchstens 100
- `settings`: `scale`, `tooltipItems`, `priceSource` (`auctionator` oder `vendor`), `resumeAfterReload`, `autoStart`
- `lastRequest`: Ergebnis des letzten Auftrags

Aufträge kommen über `AppRequest.lua` im Addon-Ordner. Die App überschreibt die Datei, das Spiel liest sie beim nächsten `/reload`:

```lua
GoldPerHour_AppRequest = { id = 1, action = "reset", settings = { scale = 1.2, autoStart = true } }
```

`action` ist `start`, `stop` oder `reset` und darf fehlen. Jede `id` läuft einmal. Einstellungen prüft das Addon selbst (Skalierung 0,5 bis 2, Tooltip 1 bis 30 Items).

## Entwicklung

`tests/test_addon.py` lässt `GoldPerHour.lua` in Lua 5.4 mit nachgebauter WoW-API laufen (Sitzung, Kräuter gegen Loot, `/reload`, Aufträge, Verlauf):

```
uv run tests/test_addon.py
```

`--dump <Datei>` schreibt den Stand am Ende des Hauptszenarios als SavedVariables-Datei. wow-forever-tools nutzt sie als Testdaten (`scripts/fixtures/goldperhour`).

Stand 0.3.0: in der Simulation getestet, im Spiel noch nicht gelaufen.

## Release

1. `## Version:` in `GoldPerHour.toc` hochzählen und committen.
2. `git tag v<Version>` und `git push origin main v<Version>`.

Die GitHub-Action prüft, dass Tag und Version übereinstimmen, lässt die Tests laufen und hängt `GoldPerHour-v<Version>.zip` an das Release. Das Zip enthält nur den Ordner `GoldPerHour` mit den Dateien aus der `.toc`.
