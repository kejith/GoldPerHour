-- Texts of the addon. English is the default; a locale only lists what it translates, everything else
-- falls back to English. To add a language, add a block for its GetLocale() code below.
local _, ns = ...

local L = {
    herb = "Herbs", loot = "Loot", total = "Total", gold = "Gold", perHour = "per hour",
    start = "Start", resume = "Resume", stop = "Stop", reset = "Reset",
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
        herb = "Kräuter", loot = "Loot", total = "Gesamt", gold = "Gold", perHour = "pro Stunde",
        start = "Start", resume = "Weiter", stop = "Stop", reset = "Reset",
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
