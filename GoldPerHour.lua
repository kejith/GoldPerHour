local ADDON, ns = ...

local HERB, MINING, SKINNING, FISHING, LOOT, DUNGEON = "herb", "mining", "skinning", "fishing", "loot", "dungeon"
local CATEGORIES = { HERB, MINING, SKINNING, FISHING, LOOT, DUNGEON }
local DEFAULT_BARS = { HERB, LOOT }
ns.CATEGORIES = CATEGORIES

local CAST_WINDOW = 15        -- seconds between a gathering cast and its loot
local MONEY_GRACE = 1.5       -- seconds after LOOT_CLOSED in which PLAYER_MONEY still counts as loot
local HERB_GATHERING = 2366   -- Herb Gathering; add other spells with /gph herbid <id>
local MINING_SPELLS = { [2575] = true, [2576] = true, [3564] = true, [10248] = true, [29354] = true, [32606] = true, [50310] = true }
local MINING_BASE = 2575
local SKINNING_BASE = 8613
local FISHING_BASE = 7620
local SAMPLE_EVERY = 300      -- seconds of session time between two points of the gold curve
local MAX_SAMPLES = 288       -- 24 h at 5 min; above that every second point is dropped
local MAX_HISTORY = 100       -- finished sessions kept for the desktop app

-- Settings the desktop app can change through AppRequest.lua (window visibility and custom spells live in
-- db.hidden, db.herbSpells and db.miningSpells).
local DEFAULTS = {
    scale = 1,                    -- window scale
    tooltipItems = 6,             -- items listed per category in the tooltip
    priceSource = "auctionator",  -- "auctionator" (vendor price as fallback) or "vendor"
    resumeAfterReload = true,     -- a running session keeps running across /reload
    autoStart = false,            -- the first loot window starts a stopped session
    deductAhCut = true,           -- deduct 5% auction house cut from Auctionator prices
    vendorFloor = true,           -- always use vendor price if it beats effective AH price
    ahMinValue = 0,               -- optional copper floor for BoE weapons/armor (0 = disabled)
    wealthInterval = 300,         -- seconds between periodic wealth snapshots
    minDropQuality = 3,           -- minimum quality (3 = Rare) recorded in top drops
    minDropValue = 50000,         -- minimum copper value (5g) recorded in top drops
    trackAlways = true,           -- always record loot, cashflow, AH & runs in the background
}

local ICON = {
    addon = "Interface\\Icons\\INV_Misc_Coin_01",
    [HERB] = "Interface\\Icons\\Trade_Herbalism",
    [MINING] = "Interface\\Icons\\Trade_Mining",
    [SKINNING] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    [FISHING] = "Interface\\Icons\\Trade_Fishing",
    [LOOT] = "Interface\\Icons\\INV_Misc_Bag_08",
    [DUNGEON] = "Interface\\Icons\\INV_Misc_Coin_02",
}

local L = ns.L

local db
local running, startedAt = false, 0
local debug = false
local lastMoney
local lastCast = { at = 0, kind = nil }
local loot = { open = false, category = nil, moneyUntil = 0, slots = {} }

local SLOT_ITEM = Enum.LootSlotType and Enum.LootSlotType.Item or 1

local function Print(...)
    print("|cffffd100GoldPerHour:|r", ...)
end

local function IsSecret(value)
    return ns.IsSecret(value)
end

local function Elapsed()
    return db.elapsed + (running and (GetTime() - startedAt) or 0)
end

local function Setting(key)
    local value = db and db.settings[key]
    if value == nil then return DEFAULTS[key] end
    return value
end
ns.Setting = Setting

local function TotalGold()
    local sum = 0
    for _, category in ipairs(CATEGORIES) do
        sum = sum + (db.gold[category] or 0)
    end
    return sum
end

-- Metadata of the running session for the app: wall-clock start, zones, characters and the gold curve.
local function NewSession()
    return { zones = {}, chars = {}, samples = {} }
end

local function Sample()
    local s = db.session.samples
    local t = math.floor(Elapsed())
    local gather = (db.gold[MINING] or 0) + (db.gold[SKINNING] or 0) + (db.gold[FISHING] or 0)
    local point = {
        t,
        math.floor((db.gold[HERB] or 0) + 0.5),
        math.floor((db.gold[LOOT] or 0) + 0.5),
        math.floor(gather + 0.5),
        math.floor((db.gold[DUNGEON] or 0) + 0.5),
    }
    if s[#s] and s[#s][1] == t then
        s[#s] = point
    else
        s[#s + 1] = point
    end
    if #s > MAX_SAMPLES then
        local thinned = {}
        for i = 1, #s, 2 do thinned[#thinned + 1] = s[i] end
        if thinned[#thinned] ~= s[#s] then thinned[#thinned + 1] = s[#s] end
        db.session.samples = thinned
    end
end

-- Where and by whom the gold was earned; zone and name are taken when the loot is picked up.
local function Where()
    local zone = GetRealZoneText()
    if not zone or zone == "" or IsSecret(zone) then zone = "?" end
    return zone, (UnitName("player"))
end
ns.Where = Where

local function Attribute(zone, char, copper)
    db.session.zones[zone] = (db.session.zones[zone] or 0) + copper
    if char then db.session.chars[char] = true end
    db.session.lastActive = time()
end

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------
local function Money(copper)
    copper = math.floor((copper or 0) + 0.5)
    if copper >= 10000 then
        copper = copper - copper % 100 -- copper is noise once gold is involved
    end
    return GetMoneyString(copper, true)
end
ns.Money = Money

local function PerHour(copper)
    local elapsed = Elapsed()
    if elapsed < 1 then return 0 end
    return copper / elapsed * 3600
end

local function Clock(seconds)
    seconds = math.floor(seconds)
    return ("%d:%02d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
end

local function IconText(texture)
    return ("|T%s:14|t"):format(tostring(texture))
end

---------------------------------------------------------------------------
-- Window: a compact meter in the style of Details!. A slim title bar with controls, gold per hour as
-- the big number, session total below it, and dynamic bars for active categories.
---------------------------------------------------------------------------
local WIDTH, PAD = 240, 8
local TITLE_HEIGHT, BAR_HEIGHT, BAR_GAP, FOOTER_HEIGHT = 20, 18, 2, 18
local BASE_HEIGHT = TITLE_HEIGHT + 47 + FOOTER_HEIGHT + PAD + 4 -- height above bars + footer + bottom padding
local WARMUP = 60 -- seconds of session time before the gold per hour is shown; earlier it is mostly noise

local TEXTURE = {
    bar = "Interface\\TargetingFrame\\UI-StatusBar",
    play = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
    pause = "Interface\\TimeManager\\PauseButton",
    reset = "Interface\\TimeManager\\ResetButton",
    stats = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
    highlight = "Interface\\Buttons\\UI-Common-MouseHilight",
}
local BAR_COLOR = {
    [HERB] = { 0.18, 0.60, 0.22 },
    [MINING] = { 0.72, 0.42, 0.20 },
    [SKINNING] = { 0.68, 0.52, 0.30 },
    [FISHING] = { 0.20, 0.54, 0.78 },
    [LOOT] = { 0.78, 0.55, 0.15 },
    [DUNGEON] = { 0.52, 0.38, 0.78 },
}
local GREY, GREEN, YELLOW, RED = "|cff9d9d9d%s|r", "|cff4ce64c%s|r", "|cffffd100%s|r", "|cfff05454%s|r"

local modernBorder = TooltipBackdropTemplateMixin ~= nil
local frame = CreateFrame("Frame", "GoldPerHourFrame", UIParent,
    modernBorder and "TooltipBackdropTemplate" or "BackdropTemplate")
frame:SetSize(WIDTH, BASE_HEIGHT + #DEFAULT_BARS * (BAR_HEIGHT + BAR_GAP))
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
if not modernBorder and frame.SetBackdrop then
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
end
if frame.SetBackdropColor then frame:SetBackdropColor(0.03, 0.03, 0.03, 0.88) end

local titleBar = frame:CreateTexture(nil, "ARTWORK", nil, -2)
titleBar:SetPoint("TOPLEFT", 3, -3)
titleBar:SetPoint("TOPRIGHT", -3, -3)
titleBar:SetHeight(TITLE_HEIGHT)
titleBar:SetColorTexture(0, 0, 0, 0.45)

local titleLine = frame:CreateTexture(nil, "ARTWORK", nil, -1)
titleLine:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT")
titleLine:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT")
titleLine:SetHeight(1)
titleLine:SetColorTexture(1, 0.82, 0, 0.25)

local titleIcon = frame:CreateTexture(nil, "OVERLAY")
titleIcon:SetSize(14, 14)
titleIcon:SetPoint("LEFT", titleBar, "LEFT", 4, 0)
titleIcon:SetTexture(ICON.addon)
titleIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeButton:SetSize(18, 18)
closeButton:SetPoint("RIGHT", titleBar, "RIGHT", -1, 0)
closeButton:SetFrameLevel(frame:GetFrameLevel() + 2)

local function IconButton(texture)
    local button = CreateFrame("Button", nil, frame)
    button:SetSize(18, 18)
    button:SetNormalTexture(texture)
    button:SetDisabledTexture(texture)
    button:SetHighlightTexture(TEXTURE.highlight, "ADD")
    button:SetMotionScriptsWhileDisabled(true)
    local disabled = button.GetDisabledTexture and button:GetDisabledTexture()
    if disabled then
        disabled:SetDesaturated(true)
        disabled:SetAlpha(0.35)
    end
    return button
end

local resetButton = IconButton(TEXTURE.reset)
resetButton:SetPoint("RIGHT", closeButton, "LEFT", -1, 0)
local toggleButton = IconButton(TEXTURE.play)
toggleButton:SetPoint("RIGHT", resetButton, "LEFT", 0, 0)
local statsButton = IconButton(TEXTURE.stats)
statsButton:SetSize(15, 15)
statsButton:SetPoint("RIGHT", toggleButton, "LEFT", -2, 0)

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("LEFT", titleIcon, "RIGHT", 4, 0)
title:SetPoint("RIGHT", statsButton, "LEFT", -4, 0)
title:SetJustifyH("LEFT")
title:SetWordWrap(false)
title:SetText(L.title)

local perHourText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
perHourText:SetPoint("TOPLEFT", PAD, -(TITLE_HEIGHT + 11))
perHourText:SetJustifyH("LEFT")
local perHourLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
perHourLabel:SetPoint("BOTTOMLEFT", perHourText, "BOTTOMRIGHT", 5, 1)

local sessionText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
sessionText:SetPoint("TOPLEFT", PAD, -(TITLE_HEIGHT + 31))
sessionText:SetJustifyH("LEFT")
local clockText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
clockText:SetPoint("TOPRIGHT", -PAD, -(TITLE_HEIGHT + 31))
clockText:SetJustifyH("RIGHT")

-- One status bar per category, laid out dynamically depending on which categories have gold > 0.
local bars = {}
for _, category in ipairs(CATEGORIES) do
    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetHeight(BAR_HEIGHT)
    bar:SetStatusBarTexture(TEXTURE.bar)
    local color = BAR_COLOR[category]
    bar:SetStatusBarColor(color[1], color[2], color[3], 0.9)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar.category = category

    local background = bar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(1, 1, 1, 0.06)

    local icon = bar:CreateTexture(nil, "OVERLAY")
    icon:SetSize(BAR_HEIGHT, BAR_HEIGHT)
    icon:SetPoint("LEFT")
    icon:SetTexture(ICON[category])
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local name = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    name:SetText(L[category])

    bar.amount = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.amount:SetPoint("RIGHT", -4, 0)
    bar.amount:SetJustifyH("RIGHT")

    bars[category] = bar
end

-- Subtle footer strip at the bottom of the compact meter: Today loot on the left, Account wealth on the right.
local footerLine = frame:CreateTexture(nil, "ARTWORK")
footerLine:SetPoint("BOTTOMLEFT", PAD, FOOTER_HEIGHT + 4)
footerLine:SetPoint("BOTTOMRIGHT", -PAD, FOOTER_HEIGHT + 4)
footerLine:SetHeight(1)
footerLine:SetColorTexture(1, 0.82, 0, 0.18)

local footerLeft = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
footerLeft:SetPoint("BOTTOMLEFT", PAD, 5)
footerLeft:SetJustifyH("LEFT")

local footerRight = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
footerRight:SetPoint("BOTTOMRIGHT", -PAD, 5)
footerRight:SetJustifyH("RIGHT")

ns.ui = {
    frame = frame, perHour = perHourText, perHourLabel = perHourLabel, session = sessionText,
    clock = clockText, bars = bars, toggle = toggleButton, reset = resetButton,
    close = closeButton, stats = statsButton, footerLeft = footerLeft, footerRight = footerRight,
}

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
local tooltip = { owner = nil, category = nil }

local function SortedItems(category)
    local list = {}
    for _, entry in pairs(db.items[category] or {}) do
        list[#list + 1] = entry
    end
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return (a.id or 0) < (b.id or 0)
    end)
    return list
end

local function AddCategory(category)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(IconText(ICON[category]) .. " " .. L[category], Money(db.gold[category] or 0),
        1, 0.82, 0, 1, 1, 1)

    local items = SortedItems(category)
    local shown = Setting("tooltipItems")
    for i = 1, math.min(#items, shown) do
        local entry = items[i]
        local icon = C_Item.GetItemIconByID(entry.id)
        local tag = entry.source == "vendor" and (" " .. GREY:format("[V]")) or ""
        GameTooltip:AddDoubleLine(("%s %s x%d%s"):format(icon and IconText(icon) or "", entry.link, entry.count, tag),
            Money(entry.value), 1, 1, 1, 1, 1, 1)
    end
    if #items > shown then
        GameTooltip:AddLine(L.more:format(#items - shown), 0.6, 0.6, 0.6)
    end
    if (db.coin[category] or 0) > 0 then
        GameTooltip:AddDoubleLine(L.coins, Money(db.coin[category]), 1, 1, 1, 1, 1, 1)
    end
    if #items == 0 and (db.coin[category] or 0) == 0 then
        GameTooltip:AddLine(L.nothing, 0.6, 0.6, 0.6)
    end
end

local function SessionVendorTotal()
    local vendor = 0
    for _, category in ipairs(CATEGORIES) do
        vendor = vendor + (db.coin[category] or 0)
        for _, entry in pairs(db.items[category] or {}) do
            vendor = vendor + (entry.vendorValue or 0)
        end
    end
    return vendor
end

local function FillTooltip()
    GameTooltip:ClearLines()
    GameTooltip:AddLine("GoldPerHour")
    GameTooltip:AddDoubleLine(L.session, ("%s (%s)"):format(Clock(Elapsed()), running and L.running or L.paused),
        1, 1, 1, 1, 1, 1)

    local anyCat = false
    for _, category in ipairs(CATEGORIES) do
        local showCat = (tooltip.category == category)
            or (not tooltip.category and ((db.gold[category] or 0) > 0 or category == HERB or category == LOOT))
        if showCat then
            AddCategory(category)
            anyCat = true
        end
    end
    if not anyCat then AddCategory(LOOT) end

    local vendorTotal = SessionVendorTotal()
    if vendorTotal > 0 and TotalGold() > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(L.vendorShare, Money(vendorTotal), 0.75, 0.75, 0.75, 0.85, 0.85, 0.85)
    end

    -- Top zones of the running session
    local zList = {}
    for zName, zVal in pairs((db.session and db.session.zones) or {}) do
        if zVal > 0 then zList[#zList + 1] = { name = zName, val = zVal } end
    end
    if #zList > 0 then
        table.sort(zList, function(a, b) return a.val > b.val end)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.zones, 1, 0.82, 0)
        for i = 1, math.min(#zList, 3) do
            GameTooltip:AddDoubleLine(zList[i].name, Money(zList[i].val), 0.9, 0.9, 0.9, 1, 1, 1)
        end
    end

    -- Compact today, AH 7d & wealth summary.
    GameTooltip:AddLine(" ")
    local todayLoot, todayInc, todayExp, todayNet = ns.Ledger.TodayTotals()
    local netStr = todayNet == 0 and Money(0)
        or (todayNet > 0 and GREEN:format("+" .. Money(todayNet)) or RED:format("-" .. Money(-todayNet)))
    GameTooltip:AddDoubleLine(L.today, Money(todayLoot) .. " " .. GREY:format("(") .. netStr .. GREY:format(")"),
        1, 0.82, 0, 1, 1, 1)
    if todayInc > 0 or todayExp > 0 then
        GameTooltip:AddDoubleLine("  " .. L.income .. " / " .. L.expense,
            GREEN:format("+" .. Money(todayInc)) .. " " .. GREY:format("/") .. " " .. RED:format("-" .. Money(todayExp)),
            0.7, 0.7, 0.7, 1, 1, 1)
    end

    -- AH 7-day summary
    local cutoff7 = time() - 7 * 86400
    local ahNet7, ahCount7 = 0, 0
    for _, e in ipairs(db.ledger or {}) do
        if e and e.kind == "ah" and e.dir == "in" and (e.t or 0) >= cutoff7 then
            ahNet7 = ahNet7 + (e.amount or 0)
            ahCount7 = ahCount7 + 1
        end
    end
    if ahCount7 > 0 then
        GameTooltip:AddDoubleLine(L.ahSales .. " (7d)", GREEN:format(Money(ahNet7)) .. " " .. GREY:format("(" .. ahCount7 .. ")"),
            0.75, 0.85, 1, 1, 1, 1)
    end

    local accTotal = ns.Wealth.Total()
    local charGold = ns.Wealth.CharMoney()
    local delta24 = ns.Wealth.Delta(db.wealth and db.wealth.accountHistory, 86400, accTotal)
    local deltaStr = ""
    if delta24 and delta24 ~= 0 then
        deltaStr = " " .. GREY:format("(") .. (delta24 > 0 and GREEN:format("+" .. Money(delta24)) or RED:format("-" .. Money(-delta24))) .. GREY:format(")")
    end
    GameTooltip:AddDoubleLine(L.wealthChar .. " / " .. L.wealthAccount,
        Money(charGold) .. " " .. GREY:format("/") .. " " .. Money(accTotal) .. deltaStr,
        0.75, 0.85, 1, 1, 1, 1)

    GameTooltip:AddLine(" ")
    if Setting("priceSource") == "vendor" then
        GameTooltip:AddDoubleLine(L.prices, L.vendorSetting, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
    elseif ns.AuctionatorAPI() then
        GameTooltip:AddDoubleLine(L.prices, Setting("deductAhCut") and L.auctionCut or L.auction,
            0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
    else
        GameTooltip:AddDoubleLine(L.prices, L.vendorOnly, 0.6, 0.6, 0.6, 1, 0.3, 0.3)
    end
    GameTooltip:AddLine(L.hint, 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function ShowTooltip(owner, category)
    tooltip.owner, tooltip.category = owner, category
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    if (frame:GetBottom() or 0) > 260 then
        GameTooltip:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2)
    else
        GameTooltip:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
    end
    FillTooltip()
end

local function ButtonTooltip(button, heading, text, command)
    tooltip.owner, tooltip.category = nil, nil
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(heading, 1, 1, 1)
    GameTooltip:AddLine(text, 1, 0.82, 0, true)
    if command then GameTooltip:AddLine(command, 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

local function ToggleTooltip(button)
    if running then
        ButtonTooltip(button, L.pause, L.pauseTip, "/gph stop")
    else
        ButtonTooltip(button, db.elapsed > 0 and L.resume or L.start, L.startTip, "/gph start")
    end
end

---------------------------------------------------------------------------
-- Display (dynamic category bars)
---------------------------------------------------------------------------
local function HasSession()
    return running or db.elapsed > 0 or TotalGold() > 0
end

local function State()
    if running then return "running" end
    return HasSession() and "paused" or "idle"
end

local function VisibleCategories()
    local active = {}
    for _, category in ipairs(CATEGORIES) do
        if (db.gold[category] or 0) > 0 then
            active[#active + 1] = category
        end
    end
    if #active == 0 then return DEFAULT_BARS end
    return active
end

local function Refresh()
    if not db then return end
    local total = TotalGold()
    local elapsed = Elapsed()
    local state = State()
    ns.ui.state = state

    if elapsed >= WARMUP then
        perHourText:SetText(Money(PerHour(total)))
        perHourLabel:SetText(L.perHour)
    else
        perHourText:SetText(GREY:format("--"))
        perHourLabel:SetText(state == "idle" and L.perHour or L.warmup)
    end

    if state == "idle" then
        sessionText:SetText(GREY:format(Setting("autoStart") and L.idleAuto or L.idle))
        clockText:SetText("")
    else
        sessionText:SetText(GREY:format(L.session) .. " " .. Money(total))
        if state == "running" then
            clockText:SetText(GREEN:format(Clock(elapsed)))
        else
            clockText:SetText(YELLOW:format(L.statusPaused) .. "  " .. GREY:format(Clock(elapsed)))
        end
    end

    local visible = VisibleCategories()
    local visibleSet = {}
    for i, category in ipairs(visible) do
        visibleSet[category] = true
        local bar, gold = bars[category], db.gold[category] or 0
        local y = -(TITLE_HEIGHT + 47) - (i - 1) * (BAR_HEIGHT + BAR_GAP)
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", PAD, y)
        bar:SetPoint("TOPRIGHT", -PAD, y)
        local share = total > 0 and gold / total or 0
        bar:SetValue(share)
        if gold > 0 then
            bar.amount:SetText(Money(gold) .. " " .. GREY:format(("%d%%"):format(math.floor(share * 100 + 0.5))))
        else
            bar.amount:SetText(GREY:format("-"))
        end
        bar:Show()
    end
    for _, category in ipairs(CATEGORIES) do
        if not visibleSet[category] then
            bars[category]:SetValue(0)
            bars[category]:Hide()
        end
    end
    frame:SetHeight(BASE_HEIGHT + #visible * (BAR_HEIGHT + BAR_GAP))
    ns.ui.visibleBars = visible

    local todayLoot = ns.Ledger.TodayTotals()
    local accTotal = ns.Wealth.Total()
    footerLeft:SetText(GREY:format(L.today .. ":") .. " " .. Money(todayLoot))
    footerRight:SetText(GREY:format(L.wealthAccount .. ":") .. " " .. Money(accTotal))

    toggleButton:SetNormalTexture(running and TEXTURE.pause or TEXTURE.play)
    resetButton:SetEnabled(HasSession())
    titleIcon:SetDesaturated(not running)

    if tooltip.owner and GameTooltip:IsOwned(tooltip.owner) then FillTooltip() end
end

function ns.ApplyLiveSettings()
    if not db then return end
    frame:SetScale(Setting("scale"))
    frame:SetShown(not db.hidden)
    Refresh()
end

local function SetVisible(shown)
    db.hidden = not shown or nil
    frame:SetShown(shown)
    if not shown then Print(L.hidden) end
end

---------------------------------------------------------------------------
-- Session
---------------------------------------------------------------------------
local nextSample = 0

local function Start()
    if running then return end
    running, startedAt = true, GetTime()
    db.session.started = db.session.started or time()
    local _, char = Where()
    if char then db.session.chars[char] = true end
    nextSample = (math.floor(Elapsed() / SAMPLE_EVERY) + 1) * SAMPLE_EVERY
    Sample()
    Refresh()
end

local function Stop()
    if not running then return end
    db.elapsed = Elapsed()
    running = false
    Sample()
    Refresh()
end

-- A finished session goes into db.history for the app; the item links are reduced to name and quality.
local function Archive()
    if db.elapsed < 1 and TotalGold() == 0 then return end
    local entry = {
        started = db.session.started, ended = db.session.lastActive or time(), archived = time(),
        elapsed = math.floor(db.elapsed), gold = {}, coin = {}, items = {},
        zones = db.session.zones, chars = db.session.chars, samples = db.session.samples,
    }
    for _, category in ipairs(CATEGORIES) do
        entry.gold[category] = math.floor((db.gold[category] or 0) + 0.5)
        entry.coin[category] = db.coin[category] or 0
        local list = {}
        for _, item in ipairs(SortedItems(category)) do
            list[#list + 1] = {
                id = item.id, name = item.link:match("%[(.-)%]"), quality = item.quality,
                count = item.count, value = math.floor(item.value + 0.5),
                vendorValue = math.floor((item.vendorValue or 0) + 0.5),
                source = item.source,
            }
        end
        entry.items[category] = list
    end
    table.insert(db.history, entry)
    while #db.history > MAX_HISTORY do table.remove(db.history, 1) end
end

local function Reset()
    if running then
        db.elapsed = Elapsed()
        running = false
    end
    Archive()
    db.elapsed = 0
    db.session = NewSession()
    for _, category in ipairs(CATEGORIES) do
        db.gold[category], db.coin[category] = 0, 0
        wipe(db.items[category])
    end
    Refresh()
end

StaticPopupDialogs["GOLDPERHOUR_RESET"] = {
    text = L.resetConfirm,
    button1 = YES,
    button2 = NO,
    OnAccept = Reset,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

---------------------------------------------------------------------------
-- Crediting (always-on ledger + optional live session)
---------------------------------------------------------------------------
local function CreditSessionMoney(category, copper)
    if not running then return end
    db.coin[category] = (db.coin[category] or 0) + copper
    db.gold[category] = (db.gold[category] or 0) + copper
    local zone, char = Where()
    Attribute(zone, char, copper)
    Refresh()
end

local function CreditSessionItem(category, id, link, quality, quantity, value, vendorValue, source, zone)
    if not running then return end
    local _, char = Where()
    local entry = db.items[category][id]
    if not entry then
        entry = { id = id, link = link, count = 0, value = 0, vendorValue = 0, source = source }
        db.items[category][id] = entry
    end
    entry.quality = quality
    entry.count = entry.count + quantity
    entry.value = entry.value + value
    entry.vendorValue = (entry.vendorValue or 0) + vendorValue
    entry.source = source
    db.gold[category] = (db.gold[category] or 0) + value
    Attribute(zone, char, value)
    Refresh()
end

local function HandleLootItem(category, link, quantity, creditSession)
    local item = Item:CreateFromItemLink(link)
    if item:IsItemEmpty() then return end
    local zone = Where()
    local charKey = ns.CharKey()
    item:ContinueOnItemLoad(function()
        local id = item:GetItemID()
        local name = link:match("%[(.-)%]")
        local unit, vendorUnit, quality, source = ns.ItemValue(link)
        local value = unit * quantity
        local vendorValue = vendorUnit * quantity
        ns.Ledger.RecordLootItem(category, id, link, name, quality, quantity, value, vendorValue, source, zone, charKey)
        if creditSession then
            CreditSessionItem(category, id, link, quality, quantity, value, vendorValue, source, zone)
        end
    end)
end

---------------------------------------------------------------------------
-- Classification (Herbalism, Mining, Skinning, Fishing, Loot)
---------------------------------------------------------------------------
local function SpellMatchesName(spellID, baseSpellID)
    if not C_Spell or not C_Spell.GetSpellName then return false end
    local baseName = C_Spell.GetSpellName(baseSpellID)
    return baseName ~= nil and C_Spell.GetSpellName(spellID) == baseName
end

local function ClassifyGatherSpell(spellID)
    if spellID == HERB_GATHERING or db.herbSpells[spellID] or SpellMatchesName(spellID, HERB_GATHERING) then
        return HERB
    end
    if MINING_SPELLS[spellID] or db.miningSpells[spellID] or SpellMatchesName(spellID, MINING_BASE) then
        return MINING
    end
    if spellID == SKINNING_BASE or SpellMatchesName(spellID, SKINNING_BASE) then
        return SKINNING
    end
    if spellID == FISHING_BASE or SpellMatchesName(spellID, FISHING_BASE) then
        return FISHING
    end
    return nil
end

local function AllSourcesMatch(slotCount, expectedPrefix)
    local seen = false
    for slot = 1, slotCount do
        if LootSlotHasItem(slot) then
            local guid = GetLootSourceInfo(slot)
            if not guid or IsSecret(guid) or strsplit("-", guid) ~= expectedPrefix then return false end
            seen = true
        end
    end
    return seen
end

local function ClassifyLoot(slotCount)
    if IsFishingLoot and IsFishingLoot() then return FISHING end
    local recentCast = lastCast.kind and (GetTime() - lastCast.at <= CAST_WINDOW)
    if not recentCast then return LOOT end
    if lastCast.kind == FISHING then return FISHING end
    if lastCast.kind == HERB and AllSourcesMatch(slotCount, "GameObject") then return HERB end
    if lastCast.kind == MINING and AllSourcesMatch(slotCount, "GameObject") then return MINING end
    if lastCast.kind == SKINNING and AllSourcesMatch(slotCount, "Creature") then return SKINNING end
    return LOOT
end

-- LOOT_READY and LOOT_OPENED both land here and may repeat, so this must be idempotent.
local function SnapshotLoot()
    local slotCount = GetNumLootItems()
    if not loot.open then
        loot.open = true
        wipe(loot.slots)
        if not running and Setting("autoStart") then Start() end
        loot.category = ClassifyLoot(slotCount)
        if debug then
            Print("loot:", loot.category, "slots:", slotCount, "source:", (GetLootSourceInfo(1)))
        end
    end
    for slot = 1, slotCount do
        if not loot.slots[slot] and GetLootSlotType(slot) == SLOT_ITEM then
            local link = GetLootSlotLink(slot)
            local _, _, quantity = GetLootSlotInfo(slot)
            if link then
                loot.slots[slot] = { link = link, quantity = (quantity and quantity > 0) and quantity or 1 }
            end
        end
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local handlers = {}

function handlers.ADDON_LOADED(name)
    if name ~= ADDON then return end
    frame:UnregisterEvent("ADDON_LOADED")

    GoldPerHourDB = GoldPerHourDB or {}
    db = GoldPerHourDB
    db.elapsed = db.elapsed or 0
    db.herbSpells = db.herbSpells or {}
    db.miningSpells = db.miningSpells or {}
    db.gold, db.coin, db.items = db.gold or {}, db.coin or {}, db.items or {}
    for _, category in ipairs(CATEGORIES) do
        db.gold[category] = db.gold[category] or 0
        db.coin[category] = db.coin[category] or 0
        db.items[category] = db.items[category] or {}
    end
    db.settings = db.settings or {}
    db.history = db.history or {}
    db.session = db.session or NewSession()
    db.session.zones = db.session.zones or {}
    db.session.chars = db.session.chars or {}
    db.session.samples = db.session.samples or {}
    db.version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or nil

    ns.Wealth.Init(db)
    ns.Ledger.Init(db)
    ns.Stats.Init(db)

    frame:SetScale(Setting("scale"))
    frame:ClearAllPoints()
    if db.pos then
        frame:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    end
    frame:SetShown(not db.hidden)
    Refresh()
end

function handlers.PLAYER_LOGIN()
    lastMoney = GetMoney()
end

-- Requests from the desktop app (AppRequest.lua in this folder, read by the client on /reload).
local function ApplySettings(s)
    for key, default in pairs(DEFAULTS) do
        local value = s[key]
        if value ~= nil and type(value) == type(default) then db.settings[key] = value end
    end
    db.settings.scale = math.min(2, math.max(0.5, Setting("scale")))
    db.settings.tooltipItems = math.min(30, math.max(1, math.floor(Setting("tooltipItems"))))
    if db.settings.priceSource ~= "vendor" then db.settings.priceSource = "auctionator" end
    if db.settings.ahMinValue ~= nil then
        db.settings.ahMinValue = math.max(0, math.floor(db.settings.ahMinValue))
    end
    if db.settings.wealthInterval ~= nil then
        db.settings.wealthInterval = math.min(3600, math.max(60, math.floor(db.settings.wealthInterval)))
    end
    if db.settings.minDropQuality ~= nil then
        db.settings.minDropQuality = math.min(5, math.max(0, math.floor(db.settings.minDropQuality)))
    end
    if db.settings.minDropValue ~= nil then
        db.settings.minDropValue = math.max(0, math.floor(db.settings.minDropValue))
    end
    if type(s.herbSpells) == "table" then
        wipe(db.herbSpells)
        for _, id in ipairs(s.herbSpells) do
            if tonumber(id) then db.herbSpells[tonumber(id)] = true end
        end
    end
    if type(s.miningSpells) == "table" then
        wipe(db.miningSpells)
        for _, id in ipairs(s.miningSpells) do
            if tonumber(id) then db.miningSpells[tonumber(id)] = true end
        end
    end
    frame:SetScale(Setting("scale"))
    if s.shown ~= nil then
        db.hidden = not s.shown or nil
        frame:SetShown(s.shown and true or false)
    end
end

local ACTIONS = { start = function() Start() end, stop = function() Stop() end, reset = function() Reset() end }

local function RunAppRequest()
    local r = GoldPerHour_AppRequest
    if type(r) ~= "table" or type(r.id) ~= "number" or r.id == db.lastRequestId then return end
    db.lastRequestId = r.id
    local result = { id = r.id, action = r.action, done = time() }
    local ok, err = pcall(function()
        if type(r.settings) == "table" then
            ApplySettings(r.settings)
            result.settings = true
            Print(L.applied)
        end
        if r.action ~= nil then
            local fn = ACTIONS[r.action]
            if not fn then error("unknown action " .. tostring(r.action)) end
            fn()
        end
    end)
    if not ok then result.error = tostring(err) end
    db.lastRequest = result
    Refresh()
end

local entered = false
function handlers.PLAYER_ENTERING_WORLD(_, isReloadingUi)
    ns.Ledger.CheckInstance()
    if entered then return end -- fires again on every loading screen
    entered = true
    lastMoney = GetMoney()
    ns.Wealth.Record("login")
    if isReloadingUi and db.resume and Setting("resumeAfterReload") then
        Start()
        Print(L.resumed)
    end
    db.resume = nil
    RunAppRequest()
end

function handlers.ZONE_CHANGED_NEW_AREA()
    ns.Ledger.CheckInstance()
end

function handlers.PLAYER_LOGOUT()
    -- GetTime() does not survive a logout, so the session pauses. On /reload it continues (resumeAfterReload).
    -- Do NOT call GetMoney() here: WoW Forever tears down character money before PLAYER_LOGOUT.
    ns.Wealth.FlushPending()
    db.resume = running or nil
    Stop()
    db.updated = time()
end

function handlers.UNIT_SPELLCAST_SENT(unit, _, _, spellID)
    if unit ~= "player" then return end
    local secret = IsSecret(spellID)
    lastCast.at = GetTime()
    lastCast.kind = (not secret) and ClassifyGatherSpell(spellID) or nil
    if debug and not secret then
        Print("cast:", spellID, C_Spell.GetSpellName(spellID), lastCast.kind and ("(" .. lastCast.kind .. ")") or "")
    end
end

handlers.LOOT_READY = SnapshotLoot
handlers.LOOT_OPENED = SnapshotLoot

function handlers.LOOT_SLOT_CLEARED(slot)
    local entry = loot.slots[slot]
    if not entry then return end
    loot.slots[slot] = nil
    HandleLootItem(loot.category or LOOT, entry.link, entry.quantity, running)
end

function handlers.LOOT_CLOSED()
    -- Slots are wiped on the next open, so a late LOOT_SLOT_CLEARED still counts.
    loot.open = false
    loot.moneyUntil = GetTime() + MONEY_GRACE
    lastCast.kind = nil
end

function handlers.LOOT_ITEM_ROLL_WON(itemLink, rollQuantity)
    ns.Ledger.OnLootRollWon(itemLink, rollQuantity, CreditSessionItem)
end

function handlers.CHAT_MSG_MONEY(text)
    ns.Ledger.OnChatMsgMoney(text, loot, CreditSessionMoney)
end

function handlers.PLAYER_MONEY()
    local money = GetMoney()
    if type(money) ~= "number" or IsSecret(money) then return end
    local delta = lastMoney and (money - lastMoney) or 0
    lastMoney = money
    if delta ~= 0 then
        ns.Ledger.OnPlayerMoney(delta, loot, CreditSessionMoney)
        ns.Wealth.OnMoneyChanged()
    end
end

function handlers.ACCOUNT_MONEY()
    ns.Wealth.OnAccountMoney()
end

function handlers.QUEST_TURNED_IN(questID, xpReward, moneyReward)
    ns.Ledger.OnQuestTurnedIn(questID, xpReward, moneyReward)
end

function handlers.MERCHANT_SHOW() ns.Ledger.SetContext("merchant", true) end
function handlers.MERCHANT_CLOSED() ns.Ledger.SetContext("merchant", false) end
function handlers.MAIL_SHOW() ns.Ledger.SetContext("mail", true) end
function handlers.MAIL_CLOSED() ns.Ledger.SetContext("mail", false) end
function handlers.MAIL_INBOX_UPDATE() ns.Ledger.ScanPendingInbox() end
function handlers.AUCTION_HOUSE_SHOW() ns.Ledger.SetContext("ah", true) end
function handlers.AUCTION_HOUSE_CLOSED() ns.Ledger.SetContext("ah", false) end
function handlers.AUCTION_HOUSE_AUCTION_CREATED() ns.Ledger.OnAuctionCreated() end
function handlers.OWNED_AUCTIONS_UPDATED() ns.Ledger.ScanOwnedAuctions() end
function handlers.TAXIMAP_OPENED() ns.Ledger.SetContext("taxi", true) end
function handlers.TAXIMAP_CLOSED() ns.Ledger.SetContext("taxi", false) end
function handlers.TRAINER_SHOW() ns.Ledger.SetContext("trainer", true) end
function handlers.TRAINER_CLOSED() ns.Ledger.SetContext("trainer", false) end
function handlers.TRADE_SHOW() ns.Ledger.SetContext("trade", true) end
function handlers.TRADE_CLOSED() ns.Ledger.SetContext("trade", false) end
function handlers.PLAYER_INTERACTION_MANAGER_FRAME_SHOW(itype) ns.Ledger.OnPlayerInteraction(itype, true) end
function handlers.PLAYER_INTERACTION_MANAGER_FRAME_HIDE(itype) ns.Ledger.OnPlayerInteraction(itype, false) end

frame:SetScript("OnEvent", function(_, event, ...)
    local fn = handlers[event]
    if fn then fn(...) end
end)
for event in pairs(handlers) do
    pcall(frame.RegisterEvent, frame, event)
end

---------------------------------------------------------------------------
-- Interaction
---------------------------------------------------------------------------
local function StartMoving()
    frame:StartMoving()
end

local function StopMoving()
    frame:StopMovingOrSizing()
    local point, _, relativePoint, x, y = frame:GetPoint()
    db.pos = { point, relativePoint, x, y }
end

local function HideTooltip()
    GameTooltip:Hide()
end

frame:SetScript("OnDragStart", StartMoving)
frame:SetScript("OnDragStop", StopMoving)
frame:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then ns.Stats.Toggle() end
end)
frame:SetScript("OnEnter", function(self)
    ShowTooltip(self)
end)
frame:SetScript("OnLeave", HideTooltip)

for _, bar in pairs(bars) do
    bar:SetScript("OnDragStart", StartMoving)
    bar:SetScript("OnDragStop", StopMoving)
    bar:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then ns.Stats.Toggle() end
    end)
    bar:SetScript("OnEnter", function(self)
        ShowTooltip(self, self.category)
    end)
    bar:SetScript("OnLeave", HideTooltip)
end

local sinceRefresh = 0
frame:SetScript("OnUpdate", function(_, dt)
    sinceRefresh = sinceRefresh + dt
    if sinceRefresh >= 0.5 then
        sinceRefresh = 0
        Refresh()
    end
end)

-- Periodic ticker (runs even while the window is hidden): session curve, wealth interval & zone time.
local zoneTickAccum = 0
C_Timer.NewTicker(5, function()
    if running and Elapsed() >= nextSample then
        Sample()
        nextSample = nextSample + SAMPLE_EVERY
    end
    ns.Wealth.OnTicker()
    zoneTickAccum = zoneTickAccum + 5
    if zoneTickAccum >= 60 then
        ns.Ledger.TickZone(zoneTickAccum)
        zoneTickAccum = 0
    end
end)

closeButton:SetScript("OnClick", function()
    GameTooltip:Hide()
    SetVisible(false)
end)
closeButton:SetScript("OnEnter", function(self)
    ButtonTooltip(self, L.close, L.closeTip, "/gph hide")
end)
closeButton:SetScript("OnLeave", HideTooltip)

toggleButton:SetScript("OnClick", function(self)
    if running then Stop() else Start() end
    if GameTooltip:IsOwned(self) then ToggleTooltip(self) end
end)
toggleButton:SetScript("OnEnter", ToggleTooltip)
toggleButton:SetScript("OnLeave", HideTooltip)

resetButton:SetScript("OnClick", function()
    if Elapsed() > 0 or TotalGold() > 0 then
        StaticPopup_Show("GOLDPERHOUR_RESET")
    end
end)
resetButton:SetScript("OnEnter", function(self)
    ButtonTooltip(self, L.reset, L.resetTip, "/gph reset")
end)
resetButton:SetScript("OnLeave", HideTooltip)

statsButton:SetScript("OnClick", function()
    ns.Stats.Toggle()
end)
statsButton:SetScript("OnEnter", function(self)
    ButtonTooltip(self, L.stats, L.statsTip, "/gph stats")
end)
statsButton:SetScript("OnLeave", HideTooltip)

function GoldPerHour_OnAddonCompartmentClick()
    SetVisible(not frame:IsShown())
end

SLASH_GOLDPERHOUR1 = "/gph"
SLASH_GOLDPERHOUR2 = "/goldperhour"
SlashCmdList.GOLDPERHOUR = function(msg)
    local cmd, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" then
        SetVisible(not frame:IsShown())
    elseif cmd == "start" then
        Start()
    elseif cmd == "stop" then
        Stop()
    elseif cmd == "reset" then
        Reset()
    elseif cmd == "show" then
        SetVisible(true)
    elseif cmd == "hide" then
        SetVisible(false)
    elseif cmd == "stats" then
        ns.Stats.Toggle()
    elseif cmd == "wealth" then
        ns.Stats.Show("wealth")
    elseif cmd == "ah" then
        ns.Stats.Show("ah")
    elseif cmd == "loot" or cmd == "history" then
        ns.Stats.Show("loot")
    elseif cmd == "cashflow" then
        ns.Stats.Show("cashflow")
    elseif cmd == "settings" then
        ns.Stats.Show("settings")
    elseif cmd == "debug" then
        debug = not debug
        Print(debug and L.debugOn or L.debugOff)
    elseif cmd == "herbid" and tonumber(arg) then
        db.herbSpells[tonumber(arg)] = true
        Print(L.herbAdded:format(tonumber(arg)))
    elseif cmd == "miningid" and tonumber(arg) then
        db.miningSpells[tonumber(arg)] = true
        Print(L.miningAdded:format(tonumber(arg)))
    else
        Print(L.usage)
    end
end
