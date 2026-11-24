-- Texts of the addon. English is the default; a locale only lists what it translates, everything else
-- falls back to English. To add a language, add a block for its GetLocale() code below.
local _, ns = ...

local L = {
    title = "Gold per hour", herb = "Herbs", loot = "Loot", perHour = "per hour",
    warmup = "per hour after 1 minute",
    start = "Start", resume = "Resume", pause = "Pause", reset = "Reset", close = "Close",
    startTip = "Start the session: gold from loot counts from now on.",
    pauseTip = "Pause the session; the clock stops.",
    resetTip = "Move the session to the history and start over.",
    closeTip = "Hide the window.",
    idle = "Press start to count your gold", idleAuto = "Loot something or press start",
    statusPaused = "Paused",
    session = "Session", running = "running", paused = "paused",
    coins = "Coins", nothing = "Nothing yet", more = "+%d more",
    prices = "Prices", auction = "Auctionator, vendor price as fallback",
    vendorOnly = "vendor only (Auctionator not loaded)",
    vendorSetting = "vendor price (setting)",
    applied = "settings from the desktop app applied",
    resumed = "session continues after /reload",
    hint = "Drag to move",
    resetConfirm = "Reset the GoldPerHour session?",
    hidden = "window hidden, /gph shows it again",
    herbAdded = "spell %d now counts as herb gathering",
    debugOn = "debug on", debugOff = "debug off",
    usage = "/gph [start | stop | reset | show | hide | debug | herbid <spellID>]",
}

local translations = {
    deDE = {
        title = "Gold pro Stunde", herb = "Kräuter", loot = "Loot", perHour = "pro Stunde",
        warmup = "pro Stunde ab 1 Minute",
        start = "Start", resume = "Weiter", pause = "Pause", reset = "Zurücksetzen", close = "Schließen",
        startTip = "Startet die Sitzung: Gold aus Beute zählt ab jetzt.",
        pauseTip = "Hält die Sitzung an; die Uhr bleibt stehen.",
        resetTip = "Legt die Sitzung in den Verlauf und beginnt von vorn.",
        closeTip = "Versteckt das Fenster.",
        idle = "Start drücken, um Gold zu zählen", idleAuto = "Etwas looten oder Start drücken",
        statusPaused = "Pausiert",
        session = "Sitzung", running = "läuft", paused = "pausiert",
        coins = "Münzen", nothing = "Noch nichts", more = "+%d weitere",
        prices = "Preise", auction = "Auctionator, sonst Händlerpreis",
        vendorOnly = "nur Händlerpreis (Auctionator nicht geladen)",
        vendorSetting = "Händlerpreis (Einstellung)",
        applied = "Einstellungen aus der Desktop-App übernommen",
        resumed = "Sitzung läuft nach /reload weiter",
        hint = "Ziehen zum Verschieben",
        resetConfirm = "GoldPerHour-Sitzung zurücksetzen?",
        hidden = "Fenster versteckt, /gph zeigt es wieder",
        herbAdded = "Zauber %d zählt jetzt als Kräutersammeln",
        debugOn = "Debug an", debugOff = "Debug aus",
        usage = "/gph [start | stop | reset | show | hide | debug | herbid <ZauberID>]",
    },
}

for key, text in pairs(translations[GetLocale()] or {}) do
    L[key] = text
end

ns.L = L
