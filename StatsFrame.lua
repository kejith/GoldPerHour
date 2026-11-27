-- In-game dashboard (/gph stats) styled to match WoWToolsForever's dark stone & bronze UI:
-- 6 tabs (Overview, Wealth with interactive chart, Loot & Spots, Auction House, Cashflow, Settings),
-- crisp 1px borders, gold-underlined tabs, KPI cards, thin scrollbar, flat buttons & checkboxes, and resize grip.
local _, ns = ...

local Stats = {}
ns.Stats = Stats

local DEFAULT_W, DEFAULT_H = 780, 540
local MIN_W, MIN_H = 660, 440
local MAX_W, MAX_H = 1280, 920

local TITLE_H = 36
local TABS_H = 30
local BAR_H = 30
local FOOT_H = 34
local PAD = 12
local ROW_HEIGHT = 22
local MAX_ROWS = 36
local CHART_H = 148
local CHART_AXIS_W = 68

local LOGO = "Interface\\Icons\\INV_Misc_Coin_01"
local CHECK_TEX = "Interface\\Buttons\\UI-CheckBox-Check"

-- Exact palette of WoWToolsForever (Lists.lua) so both addons share one coherent visual identity.
local THEME = {
    bg            = { 0.055, 0.043, 0.031, 0.97 }, -- #0e0b08
    bar           = { 0.086, 0.071, 0.051, 1.00 }, -- #16120d
    tabs          = { 0.067, 0.055, 0.039, 1.00 }, -- #110e0a
    noteBar       = { 0.078, 0.063, 0.047, 1.00 }, -- #14100c
    panel         = { 0.043, 0.035, 0.027, 0.98 }, -- #0b0907
    card          = { 0.098, 0.078, 0.057, 1.00 }, -- #19140f
    border        = { 0.360, 0.275, 0.157, 1.00 }, -- #5c4628
    borderHi      = { 0.604, 0.471, 0.251, 1.00 }, -- #9a7840
    borderSubtle  = { 0.175, 0.141, 0.106, 1.00 }, -- #2d241b
    outerShadow   = { 0.000, 0.000, 0.000, 0.95 },
    line          = { 0.184, 0.153, 0.118, 0.95 }, -- #2f271e
    lineHi        = { 0.280, 0.225, 0.165, 0.95 }, -- #47392a
    gold          = { 1.000, 0.820, 0.000, 1.00 }, -- #ffd100
    goldSoft      = { 0.830, 0.650, 0.230, 0.95 }, -- #d4a63b
    text          = { 0.945, 0.918, 0.867, 1.00 }, -- #f1eadd
    muted         = { 0.659, 0.600, 0.541, 1.00 }, -- #a8998a
    dim           = { 0.459, 0.412, 0.361, 1.00 }, -- #75695c
    stripe        = { 1.000, 0.960, 0.880, 0.030 },
    hover         = { 1.000, 0.850, 0.450, 0.090 },
    select        = { 1.000, 0.820, 0.000, 0.140 },
    tabActive     = { 0.118, 0.094, 0.067, 1.00 }, -- #1e1811
    tabHover      = { 0.098, 0.078, 0.055, 1.00 },
    primary       = { 0.431, 0.098, 0.082, 1.00 }, -- #6e1915
    primaryHover  = { 0.549, 0.133, 0.106, 1.00 }, -- #8c221b
    primaryBorder = { 0.604, 0.471, 0.251, 1.00 },
    ghost         = { 0.125, 0.102, 0.075, 1.00 }, -- #201a13
    ghostHover    = { 0.180, 0.145, 0.102, 1.00 }, -- #2e251a
    ghostBorder   = { 0.290, 0.224, 0.133, 1.00 }, -- #4a3922
    closeHover    = { 0.560, 0.140, 0.120, 1.00 },
    track         = { 0.027, 0.022, 0.016, 0.95 },
    thumb         = { 0.360, 0.275, 0.157, 0.85 },
    thumbHover    = { 0.604, 0.471, 0.251, 0.95 },
}

local CLASS_COLORS = {
    WARRIOR = "c79c6e", PALADIN = "f58cba", HUNTER = "abd473", ROGUE = "fff569",
    PRIEST = "ffffff", DEATHKNIGHT = "c41f3b", SHAMAN = "0070de", MAGE = "69ccf0",
    WARLOCK = "9482c9", MONK = "00ff96", DRUID = "ff7d0a", DEMONHUNTER = "a330c9",
    EVOKER = "33937f",
}
local QUALITY_COLORS = {
    [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000",
}

local TABS = { "overview", "wealth", "loot", "ah", "cashflow", "settings" }
local TAB_ALIAS = { today = "overview", history = "loot" }
local PERIODS = {
    { key = "today", labelKey = "periodToday" },
    { key = "7d", labelKey = "period7d" },
    { key = "30d", labelKey = "period30d" },
    { key = "all", labelKey = "periodAll" },
}
local WEALTH_PERIODS = {
    { key = "24h", secs = 86400, labelKey = "period24h" },
    { key = "7d", secs = 7 * 86400, labelKey = "period7d" },
    { key = "30d", secs = 30 * 86400, labelKey = "period30d" },
    { key = "all", secs = 0, labelKey = "periodAll" },
}

local db
local frame
local curW, curH = DEFAULT_W, DEFAULT_H
local activeTab = "overview"
local activePeriod = "7d"
local wealthPeriod = "30d"
local wealthChar = nil
local subView = { loot = "items", ah = "sales", cashflow = "cats" }
local scrollOffset = 0
local currentRows = {}

local tabButtons, periodButtons, subButtons, kpiCards, tablePanel, headerBar, headerCols, rowFrames
local scrollTrack, scrollThumb, footLeft, footRight, titleSub, chartBox, settingsBox

---------------------------------------------------------------------------
-- Styling Primitives (matching WoWToolsForever/Lists.lua)
---------------------------------------------------------------------------
local function colorTex(tex, c)
    tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    return tex
end

local function solid(parent, layer, c, sublevel)
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
    return colorTex(tex, c)
end

local function frameBox(parent, bg, border, inset)
    local box = {}
    inset = inset or 0
    if bg then
        box.bg = solid(parent, "BACKGROUND", bg, -6)
        box.bg:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -inset)
        box.bg:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset)
    end
    local edges = {}
    if border then
        local top = solid(parent, "BORDER", border, 2)
        top:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -inset)
        top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -inset, -inset)
        top:SetHeight(1)
        local bottom = solid(parent, "BORDER", border, 2)
        bottom:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", inset, inset)
        bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset)
        bottom:SetHeight(1)
        local left = solid(parent, "BORDER", border, 2)
        left:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -inset - 1)
        left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", inset, inset + 1)
        left:SetWidth(1)
        local right = solid(parent, "BORDER", border, 2)
        right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -inset, -inset - 1)
        right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset + 1)
        right:SetWidth(1)
        edges = { top, bottom, left, right }
    end
    box.edges = edges
    function box:setBorder(c)
        for _, edge in ipairs(self.edges) do colorTex(edge, c) end
    end
    function box:setBg(c)
        if self.bg then colorTex(self.bg, c) end
    end
    return box
end

local function divider(parent, pointA, xA, yA, pointB, xB, yB, c)
    local line = solid(parent, "BORDER", c or THEME.line, 1)
    line:SetPoint(pointA, parent, pointA, xA, yA)
    line:SetPoint(pointB, parent, pointB, xB, yB)
    line:SetHeight(1)
    return line
end

local function flatButton(parent, kind)
    local btn = CreateFrame("Button", nil, parent)
    btn.kind = kind or "ghost"
    btn.box = frameBox(btn, THEME.ghost, THEME.ghostBorder)
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    label:SetWordWrap(false)
    btn.label = label

    function btn:paint()
        local isPrimary = (self.kind == "primary") or self.active
        local bg = isPrimary and THEME.primary or THEME.ghost
        local bgH = isPrimary and THEME.primaryHover or THEME.ghostHover
        local edge = isPrimary and THEME.primaryBorder or THEME.ghostBorder
        local tc = isPrimary and THEME.gold or THEME.text
        if self.hovered then
            self.box:setBg(bgH)
            self.box:setBorder(THEME.borderHi)
            self.label:SetTextColor(THEME.gold[1], THEME.gold[2], THEME.gold[3])
        else
            self.box:setBg(bg)
            self.box:setBorder(edge)
            self.label:SetTextColor(tc[1], tc[2], tc[3])
        end
    end
    function btn:setActive(on)
        self.active = on and true or false
        self:paint()
    end
    btn:SetScript("OnEnter", function(self) self.hovered = true; self:paint() end)
    btn:SetScript("OnLeave", function(self) self.hovered = false; self:paint() end)
    btn:paint()
    return btn
end

local function ColorText(hex, text)
    return ("|cff%s%s|r"):format(hex or "f1eadd", tostring(text or ""))
end

local function SignedMoney(copper)
    if copper == nil then return ColorText("a8998a", "--") end
    if copper == 0 then return ns.Money(0) end
    local prefix = copper > 0 and "+" or "-"
    local hex = copper > 0 and "4ce64c" or "f05454"
    return ColorText(hex, prefix .. ns.Money(math.abs(copper)))
end

local function ShortMoney(copper)
    copper = math.floor((copper or 0) + 0.5)
    local neg = copper < 0
    local a = math.abs(copper)
    local out
    if a >= 1000000 then
        out = ("%.0fg"):format(a / 10000)
    elseif a >= 10000 then
        out = ("%.1fg"):format(a / 10000)
    elseif a >= 100 then
        out = ("%ds"):format(math.floor(a / 100))
    else
        out = ("%dc"):format(a)
    end
    return neg and ("-" .. out) or out
end

local function Duration(sec)
    sec = math.max(0, math.floor(sec or 0))
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    if h > 0 then return ("%dh %02dm"):format(h, m) end
    return ("%dm"):format(m)
end

local function ItemText(id, name, q)
    local hex = QUALITY_COLORS[q or 1] or "f1eadd"
    local icon = id and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
    local prefix = icon and ("|T%s:15:15:0:0:64:64:4:60:4:60|t "):format(tostring(icon)) or ""
    return prefix .. ColorText(hex, name or "?")
end

local function ClampSize(w, h)
    w = math.max(MIN_W, math.min(MAX_W, math.floor((w or DEFAULT_W) + 0.5)))
    h = math.max(MIN_H, math.min(MAX_H, math.floor((h or DEFAULT_H) + 0.5)))
    return w, h
end

local function SavePlace()
    if not db or not frame then return end
    local point, _, rel, x, y = frame:GetPoint()
    if point then db.statsPos = { point, rel or point, x or 0, y or 0 } end
    local w = frame.GetWidth and frame:GetWidth()
    local h = frame.GetHeight and frame:GetHeight()
    if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
        curW, curH = ClampSize(w, h)
        db.statsSize = { curW, curH }
    end
end

---------------------------------------------------------------------------
-- Data Aggregation
---------------------------------------------------------------------------
local function AggregatePeriod(periodKey)
    local out = {
        days = 0, lootTotal = 0, vendorTotal = 0, lootByCat = {},
        income = 0, expense = 0, incomeByKind = {}, expenseByKind = {},
        ah = { sales = 0, gross = 0, cut = 0, deposit = 0, net = 0, buys = 0, buyTotal = 0 },
        items = {}, zones = {},
    }
    if not db or not db.daily then return out end
    local nowTs = time()
    local todayKey = ns.Ledger.DayKey(nowTs)
    local cutoffKey
    if periodKey == "today" then cutoffKey = todayKey
    elseif periodKey == "7d" then cutoffKey = ns.Ledger.DayKey(nowTs - 6 * 86400)
    elseif periodKey == "30d" then cutoffKey = ns.Ledger.DayKey(nowTs - 29 * 86400)
    end

    for dayKey, d in pairs(db.daily) do
        if type(d) == "table" and (not cutoffKey or dayKey >= cutoffKey) then
            out.days = out.days + 1
            for cat, lb in pairs(d.loot or {}) do
                local v, vv = lb.v or 0, lb.vv or 0
                out.lootTotal = out.lootTotal + v
                out.vendorTotal = out.vendorTotal + vv
                out.lootByCat[cat] = (out.lootByCat[cat] or 0) + v
            end
            local cf = d.cashflow or {}
            for k, v in pairs(cf.income or {}) do
                out.income = out.income + v
                out.incomeByKind[k] = (out.incomeByKind[k] or 0) + v
            end
            for k, v in pairs(cf.expense or {}) do
                out.expense = out.expense + v
                out.expenseByKind[k] = (out.expenseByKind[k] or 0) + v
            end
            local ah = d.ah or {}
            out.ah.sales = out.ah.sales + (ah.sales or 0)
            out.ah.gross = out.ah.gross + (ah.gross or 0)
            out.ah.cut = out.ah.cut + (ah.cut or 0)
            out.ah.deposit = out.ah.deposit + (ah.deposit or 0)
            out.ah.net = out.ah.net + (ah.net or 0)
            out.ah.buys = out.ah.buys + (ah.buys or 0)
            out.ah.buyTotal = out.ah.buyTotal + (ah.buyTotal or 0)

            for _, it in pairs(d.items or {}) do
                local key = tostring(it.id or it.name or "?")
                local agg = out.items[key]
                if not agg then
                    agg = { id = it.id, name = it.name or "?", q = it.q, n = 0, v = 0, vv = 0, cat = it.cat }
                    out.items[key] = agg
                end
                agg.n = agg.n + (it.n or 0)
                agg.v = agg.v + (it.v or 0)
                agg.vv = agg.vv + (it.vv or 0)
            end
            for zName, zb in pairs(d.zones or {}) do
                local agg = out.zones[zName]
                if not agg then
                    agg = { zone = zName, v = 0, c = 0, t = 0 }
                    out.zones[zName] = agg
                end
                agg.v = agg.v + (zb.v or 0)
                agg.c = agg.c + (zb.c or 0)
                agg.t = agg.t + (zb.t or 0)
            end
        end
    end
    return out
end

local function SetKpi(idx, title, value, sub)
    local card = kpiCards[idx]
    if not card then return end
    if not title then
        card:Hide()
        return
    end
    card.title:SetText(title)
    card.value:SetText(value or "")
    card.sub:SetText(sub or "")
    card:Show()
end

---------------------------------------------------------------------------
-- Interactive Line Chart (matching WoWToolsForever/History.lua)
---------------------------------------------------------------------------
local function NewPool(createFn)
    local p = { items = {}, used = 0 }
    function p:get()
        self.used = self.used + 1
        local w = self.items[self.used]
        if not w then
            w = createFn()
            self.items[self.used] = w
        end
        if w and w.Show then w:Show() end
        return w
    end
    function p:reset()
        for i = 1, #self.items do
            if self.items[i] and self.items[i].Hide then self.items[i]:Hide() end
        end
        self.used = 0
    end
    return p
end

local function BuildChart(parent)
    local box = CreateFrame("Frame", nil, parent)
    box.box = frameBox(box, THEME.panel, THEME.borderSubtle)

    local headStrip = solid(box, "BACKGROUND", THEME.card, -4)
    headStrip:SetPoint("TOPLEFT", 1, -1)
    headStrip:SetPoint("TOPRIGHT", -1, -1)
    headStrip:SetHeight(24)
    local headAccent = solid(box, "ARTWORK", THEME.goldSoft, 1)
    headAccent:SetPoint("TOPLEFT", 1, -1)
    headAccent:SetSize(2, 24)
    divider(box, "TOPLEFT", 1, -25, "TOPRIGHT", -1, -25, THEME.line)

    box.heading = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    box.heading:SetPoint("TOPLEFT", 10, -7)
    box.heading:SetTextColor(THEME.gold[1], THEME.gold[2], THEME.gold[3])

    box.hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    box.hint:SetPoint("TOPRIGHT", -10, -7)
    box.hint:SetTextColor(THEME.dim[1], THEME.dim[2], THEME.dim[3])

    local plot = CreateFrame("Frame", nil, box)
    plot:SetPoint("TOPLEFT", CHART_AXIS_W, -32)
    plot:SetPoint("BOTTOMRIGHT", -16, 20)
    plot:EnableMouse(true)
    box.plot = plot

    plot.textures = NewPool(function() return plot:CreateTexture(nil, "ARTWORK") end)
    plot.lines = NewPool(function()
        if not plot.CreateLine then return nil end
        local ln = plot:CreateLine(nil, "OVERLAY")
        if ln and ln.SetThickness then ln:SetThickness(2) end
        if ln and ln.SetColorTexture then ln:SetColorTexture(THEME.gold[1], THEME.gold[2], THEME.gold[3], 0.95) end
        return ln
    end)
    plot.labels = NewPool(function()
        local f = plot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f:SetTextColor(THEME.muted[1], THEME.muted[2], THEME.muted[3])
        return f
    end)

    plot.empty = plot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    plot.empty:SetPoint("CENTER")
    plot.empty:SetTextColor(THEME.dim[1], THEME.dim[2], THEME.dim[3])

    plot.marker = solid(plot, "OVERLAY", { THEME.gold[1], THEME.gold[2], THEME.gold[3], 0.45 }, 1)
    plot.marker:Hide()

    plot.hoverDot = solid(plot, "OVERLAY", { 1, 0.90, 0.30, 1 }, 2)
    plot.hoverDot:SetSize(7, 7)
    plot.hoverDot:Hide()

    local function UpdateHover()
        if not plot.pts or #plot.pts < 2 or not plot.plotW or plot.plotW <= 0 then return end
        local left = plot.GetLeft and plot:GetLeft()
        local scale = (plot.GetEffectiveScale and plot:GetEffectiveScale()) or 1
        local cx = GetCursorPosition and select(1, GetCursorPosition())
        if not (left and cx) then return end
        local relX = math.max(0, math.min(plot.plotW, cx / scale - left))
        local best, bestDist
        for _, pt in ipairs(plot.pts) do
            local dist = math.abs(pt.px - relX)
            if not bestDist or dist < bestDist then
                best, bestDist = pt, dist
            end
        end
        if not best or best == plot.hovered then return end
        plot.hovered = best
        plot.marker:ClearAllPoints()
        plot.marker:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", best.px, 0)
        plot.marker:SetSize(1, plot.plotH)
        plot.marker:Show()
        plot.hoverDot:ClearAllPoints()
        plot.hoverDot:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", best.px - 3.5, best.py - 3.5)
        plot.hoverDot:Show()
        GameTooltip:SetOwner(plot, "ANCHOR_RIGHT")
        GameTooltip:SetText(date("%Y-%m-%d %H:%M", best.t))
        GameTooltip:AddDoubleLine(box.seriesLabel or ns.L.accountTotal, ns.Money(best.v), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:Show()
    end

    plot:SetScript("OnEnter", UpdateHover)
    plot:SetScript("OnUpdate", function()
        if plot.IsMouseOver and plot:IsMouseOver() then UpdateHover() end
    end)
    plot:SetScript("OnLeave", function()
        plot.hovered = nil
        plot.marker:Hide()
        plot.hoverDot:Hide()
        GameTooltip:Hide()
    end)
    box:Hide()
    return box
end

local function DrawWealthChart(rawPts, labelText)
    local plot = chartBox.plot
    plot.textures:reset()
    plot.lines:reset()
    plot.labels:reset()
    plot.marker:Hide()
    plot.hoverDot:Hide()
    plot.hovered = nil
    plot.pts = nil
    chartBox.seriesLabel = labelText
    chartBox.heading:SetText(labelText)
    chartBox.hint:SetText(ns.L.chartHint)

    local pts = {}
    if type(rawPts) == "table" and #rawPts > 0 then
        local secs = 0
        for _, p in ipairs(WEALTH_PERIODS) do
            if p.key == wealthPeriod then secs = p.secs break end
        end
        local lastT = rawPts[#rawPts][1] or time()
        local cutoff = secs > 0 and (lastT - secs) or 0
        for _, pt in ipairs(rawPts) do
            if pt[1] >= cutoff then pts[#pts + 1] = pt end
        end
        if #pts < 2 and #rawPts >= 2 then pts = rawPts end
    end

    if #pts < 2 then
        plot.empty:SetText(ns.L.chartEmpty)
        plot.empty:Show()
        return
    end
    plot.empty:Hide()

    local pw = (curW - 2 * PAD) - CHART_AXIS_W - 16
    local ph = CHART_H - 18
    plot.plotW, plot.plotH = pw, ph

    local tMin, tMax = pts[1][1], pts[#pts][1]
    if tMax <= tMin then tMax = tMin + 1 end
    local lo, hi = pts[1][2], pts[1][2]
    for _, pt in ipairs(pts) do
        if pt[2] < lo then lo = pt[2] end
        if pt[2] > hi then hi = pt[2] end
    end
    local pad = (hi - lo) * 0.12
    if pad == 0 then pad = math.max(10000, hi * 0.05) end
    lo = math.max(0, lo - pad)
    hi = hi + pad

    for i = 0, 3 do
        local val = lo + (hi - lo) * i / 3
        local py = (val - lo) / (hi - lo) * ph
        local t = plot.textures:get()
        t:SetColorTexture(0.95, 0.90, 0.80, i == 0 and 0.22 or 0.06)
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, py)
        t:SetSize(pw, 1)
        local lbl = plot.labels:get()
        lbl:ClearAllPoints()
        lbl:SetPoint("RIGHT", plot, "BOTTOMLEFT", -8, py)
        lbl:SetJustifyH("RIGHT")
        lbl:SetText(ShortMoney(val))
    end

    local screenPts = {}
    local step = math.max(1, math.floor(#pts / 80))
    for i = 1, #pts, step do
        local pt = pts[i]
        local px = (pt[1] - tMin) / (tMax - tMin) * pw
        local py = (pt[2] - lo) / (hi - lo) * ph
        screenPts[#screenPts + 1] = { t = pt[1], v = pt[2], px = px, py = py }
    end
    if screenPts[#screenPts].t ~= pts[#pts][1] then
        local pt = pts[#pts]
        screenPts[#screenPts + 1] = {
            t = pt[1], v = pt[2],
            px = pw, py = (pt[2] - lo) / (hi - lo) * ph,
        }
    end

    local prev
    for _, sp in ipairs(screenPts) do
        local dot = plot.textures:get()
        dot:SetColorTexture(1, 0.84, 0.14, 1)
        dot:ClearAllPoints()
        dot:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", sp.px - 2.5, sp.py - 2.5)
        dot:SetSize(5, 5)
        if prev then
            local ln = plot.lines:get()
            if ln and ln.SetStartPoint then
                ln:SetStartPoint("BOTTOMLEFT", plot, prev.px, prev.py)
                ln:SetEndPoint("BOTTOMLEFT", plot, sp.px, sp.py)
            end
        end
        prev = sp
    end

    local fmt = (tMax - tMin) <= 2 * 86400 and "%H:%M" or "%m-%d"
    local lx1 = plot.labels:get()
    lx1:ClearAllPoints()
    lx1:SetPoint("TOPLEFT", plot, "BOTTOMLEFT", 0, -5)
    lx1:SetText(date(fmt, tMin))
    local lx2 = plot.labels:get()
    lx2:ClearAllPoints()
    lx2:SetPoint("TOPRIGHT", plot, "BOTTOMRIGHT", 0, -5)
    lx2:SetText(date(fmt, tMax))

    plot.pts = screenPts
end

---------------------------------------------------------------------------
-- Inset Scrollable Table (matching WoWToolsForever's panel, stripes & thin scrollbar)
---------------------------------------------------------------------------
local function UpdateScrollbar(visibleCount, totalRows)
    if totalRows <= visibleCount then
        scrollTrack:Hide()
        return
    end
    scrollTrack:Show()
    local trackH = math.max(20, (visibleCount * ROW_HEIGHT) - 4)
    local thumbH = math.max(22, math.floor(trackH * (visibleCount / totalRows)))
    local maxOff = math.max(1, totalRows - visibleCount)
    local ratio = scrollOffset / maxOff
    local travel = math.max(0, trackH - thumbH)
    scrollThumb:SetHeight(thumbH)
    scrollThumb:ClearAllPoints()
    scrollThumb:SetPoint("TOPLEFT", scrollTrack, "TOPLEFT", 1, -1 - math.floor(ratio * travel))
    scrollThumb:SetPoint("TOPRIGHT", scrollTrack, "TOPRIGHT", -1, -1 - math.floor(ratio * travel))
end

local function ConfigureTable(topY, cols, dataRows)
    currentRows = dataRows or {}
    local bottomY = FOOT_H + PAD
    local panelH = math.max(96, curH - (-topY) - bottomY)
    local visibleCount = math.max(3, math.min(MAX_ROWS, math.floor((panelH - 28) / ROW_HEIGHT)))

    tablePanel:ClearAllPoints()
    tablePanel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, topY)
    tablePanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, bottomY)
    tablePanel:Show()

    local maxOff = math.max(0, #currentRows - visibleCount)
    if scrollOffset > maxOff then scrollOffset = maxOff end
    if scrollOffset < 0 then scrollOffset = 0 end

    local hasScroll = #currentRows > visibleCount
    local innerW = (curW - 2 * PAD) - (hasScroll and 18 or 8)
    local x = 8
    for c = 1, 5 do
        local h = headerCols[c]
        local def = cols[c]
        if def then
            local w = math.floor(innerW * def.w)
            h:ClearAllPoints()
            h:SetPoint("LEFT", headerBar, "LEFT", x, 0)
            h:SetWidth(w - 8)
            h:SetJustifyH(def.align or "LEFT")
            h:SetText(def.label or "")
            h:Show()
            x = x + w
        else
            h:Hide()
        end
    end

    for i = 1, MAX_ROWS do
        local rf = rowFrames[i]
        local entry = (i <= visibleCount) and currentRows[scrollOffset + i] or nil
        if i <= visibleCount and (entry or (i == 1 and #currentRows == 0)) then
            rf:ClearAllPoints()
            rf:SetPoint("TOPLEFT", tablePanel, "TOPLEFT", 1, -26 - (i - 1) * ROW_HEIGHT)
            rf:SetPoint("TOPRIGHT", tablePanel, "TOPRIGHT", hasScroll and -11 or -1, -26 - (i - 1) * ROW_HEIGHT)
            rf.entry = entry
            if entry then
                rf.stripe:SetShown((scrollOffset + i) % 2 == 0)
                rf.sel:SetShown(entry.selected == true)
                rf.selBar:SetShown(entry.selected == true)
                local cx = 8
                for c = 1, 5 do
                    local fs = rf.cols[c]
                    local def = cols[c]
                    if def then
                        local w = math.floor(innerW * def.w)
                        fs:ClearAllPoints()
                        fs:SetPoint("LEFT", rf, "LEFT", cx, 0)
                        fs:SetWidth(w - 8)
                        fs:SetJustifyH(def.align or "LEFT")
                        fs:SetText(entry.cells[c] or "")
                        fs:Show()
                        cx = cx + w
                    else
                        fs:Hide()
                    end
                end
                if entry.barShare and entry.barShare > 0 then
                    rf.bar:SetWidth(math.max(2, math.floor(innerW * math.min(1, entry.barShare) * 0.24)))
                    local col = entry.barColor or THEME.goldSoft
                    rf.bar:SetColorTexture(col[1], col[2], col[3], 0.16)
                    rf.bar:Show()
                else
                    rf.bar:Hide()
                end
            else
                rf.stripe:Hide()
                rf.sel:Hide()
                rf.selBar:Hide()
                rf.bar:Hide()
                rf.cols[1]:ClearAllPoints()
                rf.cols[1]:SetPoint("LEFT", rf, "LEFT", 10, 0)
                rf.cols[1]:SetWidth(innerW)
                rf.cols[1]:SetJustifyH("LEFT")
                rf.cols[1]:SetText(ColorText("75695c", ns.L.nothing))
                rf.cols[1]:Show()
                for c = 2, 5 do rf.cols[c]:Hide() end
            end
            rf:Show()
        else
            rf.entry = nil
            rf:Hide()
        end
    end

    UpdateScrollbar(visibleCount, #currentRows)
    if hasScroll then
        footLeft:SetText(ns.L.scrollHint:format(scrollOffset + 1, math.min(#currentRows, scrollOffset + visibleCount), #currentRows))
    else
        footLeft:SetText("")
    end
end

local function SetSubButtons(items, activeKey, onPick)
    for i = 1, 5 do
        local btn = subButtons[i]
        local def = items and items[i]
        if def then
            btn.label:SetText(def.label)
            btn:setActive(def.key == activeKey)
            btn:SetScript("OnClick", function()
                scrollOffset = 0
                onPick(def.key)
                Stats.Refresh()
            end)
            btn:Show()
        else
            btn:Hide()
        end
    end
end

local function SetPeriodBar(mode)
    local list = (mode == "wealth") and WEALTH_PERIODS or (mode == "daily" and PERIODS or nil)
    local cur = (mode == "wealth") and wealthPeriod or activePeriod
    for i = 1, 4 do
        local btn = periodButtons[i]
        local def = list and list[i]
        if def then
            btn.label:SetText(ns.L[def.labelKey] or def.key)
            btn:setActive(def.key == cur)
            btn:SetScript("OnClick", function()
                scrollOffset = 0
                if mode == "wealth" then wealthPeriod = def.key else activePeriod = def.key end
                Stats.Refresh()
            end)
            btn:Show()
        else
            btn:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Tab Renderers
---------------------------------------------------------------------------
local CONTENT_TOP = -(TITLE_H + TABS_H + BAR_H + 10)
local KPI_H = 64

local function LayoutKpis(count)
    local n = count or 4
    local gap = 8
    local w = math.floor((curW - 2 * PAD - (n - 1) * gap) / n)
    for i = 1, 4 do
        local card = kpiCards[i]
        if i <= n then
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + (i - 1) * (w + gap), CONTENT_TOP)
            card:SetSize(w, KPI_H)
        end
    end
end

local function RenderOverview()
    local L = ns.L
    chartBox:Hide()
    settingsBox:Hide()
    SetPeriodBar("daily")
    SetSubButtons(nil)
    LayoutKpis(4)

    local p = AggregatePeriod(activePeriod)
    local accTotal = ns.Wealth.Total()
    local dDay = ns.Wealth.Delta(db.wealth.accountHistory, 86400, accTotal)

    SetKpi(1, L.accountTotal, ns.Money(accTotal), L.period24h .. ": " .. SignedMoney(dDay))
    SetKpi(2, L.lootTotal, ns.Money(p.lootTotal), L.vendorGuaranteed .. ": " .. ns.Money(p.vendorTotal))
    SetKpi(3, L.net, SignedMoney(p.income - p.expense), ColorText("4ce64c", "+" .. ShortMoney(p.income)) .. " / " .. ColorText("f05454", "-" .. ShortMoney(p.expense)))
    SetKpi(4, L.ahSales, ns.Money(p.ah.net), L.salesCount:format(p.ah.sales))

    local list = {}
    for _, cat in ipairs(ns.CATEGORIES) do
        local v = p.lootByCat[cat] or 0
        if v > 0 then
            local share = p.lootTotal > 0 and (v / p.lootTotal) or 0
            list[#list + 1] = {
                cells = { (L[cat] or cat), ColorText("a8998a", L.loot), ns.Money(v), ColorText("a8998a", ("%d%%"):format(math.floor(share * 100 + 0.5))) },
                barShare = share,
            }
        end
    end
    for _, pair in ipairs({
        { "ah", L.cfAh }, { "dungeon", L.cfDungeon }, { "loot", L.cfLoot }, { "quest", L.cfQuest },
        { "vendor", L.cfVendor }, { "trade", L.cfTrade }, { "mail", L.cfMail }, { "other", L.cfOther },
    }) do
        local v = p.incomeByKind[pair[1]] or 0
        if v > 0 then
            local share = p.income > 0 and (v / p.income) or 0
            list[#list + 1] = {
                cells = { pair[2], ColorText("4ce64c", L.income), ColorText("4ce64c", "+" .. ns.Money(v)), ColorText("a8998a", ("%d%%"):format(math.floor(share * 100 + 0.5))) },
                barShare = share, barColor = { 0.25, 0.75, 0.30 },
            }
        end
    end
    for _, pair in ipairs({
        { "repair", L.cfRepair }, { "ahBuy", L.cfAhBuy }, { "ahDeposit", L.cfAhDeposit },
        { "vendor", L.cfVendorBuy }, { "taxi", L.cfTaxi }, { "trainer", L.cfTrainer },
        { "mail", L.cfMailOut }, { "trade", L.cfTradeOut }, { "other", L.cfOtherOut },
    }) do
        local v = p.expenseByKind[pair[1]] or 0
        if v > 0 then
            local share = p.expense > 0 and (v / p.expense) or 0
            list[#list + 1] = {
                cells = { pair[2], ColorText("f05454", L.expense), ColorText("f05454", "-" .. ns.Money(v)), ColorText("a8998a", ("%d%%"):format(math.floor(share * 100 + 0.5))) },
                barShare = share, barColor = { 0.85, 0.28, 0.28 },
            }
        end
    end
    local items = {}
    for _, it in pairs(p.items) do items[#items + 1] = it end
    table.sort(items, function(a, b) return a.v > b.v end)
    for i = 1, math.min(#items, 12) do
        local it = items[i]
        list[#list + 1] = {
            itemID = it.id,
            cells = { ItemText(it.id, it.name, it.q) .. ColorText("a8998a", " x" .. tostring(it.n)), L[it.cat] or "", ns.Money(it.v), ColorText("a8998a", ShortMoney(it.vv)) },
        }
    end

    ConfigureTable(CONTENT_TOP - KPI_H - 10, {
        { label = L.statsSource, w = 0.44, align = "LEFT" },
        { label = L.statsCategory, w = 0.18, align = "LEFT" },
        { label = L.statsAmount, w = 0.24, align = "RIGHT" },
        { label = L.statsShare, w = 0.14, align = "RIGHT" },
    }, list)
end

local function RenderWealth()
    local L = ns.L
    settingsBox:Hide()
    SetPeriodBar("wealth")
    SetSubButtons(nil)
    LayoutKpis(4)

    local total, _, bankMoney, transitTotal = ns.Wealth.Total()
    local selectedEntry = wealthChar and db.wealth.chars[wealthChar] or nil
    if wealthChar and not selectedEntry then wealthChar = nil end

    local hist = selectedEntry and selectedEntry.history or db.wealth.accountHistory
    local curVal = selectedEntry and (selectedEntry.money or 0) or total
    local label = selectedEntry and (selectedEntry.name or wealthChar) or L.wholeAccount

    local d24 = ns.Wealth.Delta(hist, 86400, curVal)
    local d7 = ns.Wealth.Delta(hist, 7 * 86400, curVal)
    local d30 = ns.Wealth.Delta(hist, 30 * 86400, curVal)

    local charCount = 0
    for _ in pairs(db.wealth.chars or {}) do charCount = charCount + 1 end
    local sub1 = bankMoney > 0 and (L.accountBank .. ": " .. ShortMoney(bankMoney)) or L.charsCount:format(charCount)
    if transitTotal > 0 then sub1 = sub1 .. " · " .. L.inTransit .. ": " .. ShortMoney(transitTotal) end

    SetKpi(1, label, ns.Money(curVal), sub1)
    SetKpi(2, L.delta24h, SignedMoney(d24), "")
    SetKpi(3, L.delta7d, SignedMoney(d7), "")
    SetKpi(4, L.delta30d, SignedMoney(d30), "")

    local chartTop = CONTENT_TOP - KPI_H - 10
    chartBox:ClearAllPoints()
    chartBox:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, chartTop)
    chartBox:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, chartTop)
    chartBox:SetHeight(CHART_H + 34)
    chartBox:Show()
    DrawWealthChart(hist, label)

    local chars = {}
    for key, c in pairs(db.wealth.chars or {}) do
        if type(c) == "table" then
            chars[#chars + 1] = { key = key, name = c.name or key, realm = c.realm or "", class = c.class, money = c.money or 0, history = c.history }
        end
    end
    table.sort(chars, function(a, b)
        if a.money ~= b.money then return a.money > b.money end
        return a.key < b.key
    end)

    local list = {}
    for _, c in ipairs(chars) do
        local hex = CLASS_COLORS[c.class] or "f1eadd"
        local nameTxt = ColorText(hex, c.name) .. (c.realm ~= "" and ColorText("a8998a", " - " .. c.realm) or "")
        local share = total > 0 and (c.money / total) or 0
        local cd24 = ns.Wealth.Delta(c.history, 86400, c.money)
        local cd7 = ns.Wealth.Delta(c.history, 7 * 86400, c.money)
        list[#list + 1] = {
            selected = (wealthChar == c.key),
            onClick = function()
                wealthChar = (wealthChar == c.key) and nil or c.key
                Stats.Refresh()
            end,
            barShare = share,
            cells = { nameTxt, ns.Money(c.money), ColorText("a8998a", ("%d%%"):format(math.floor(share * 100 + 0.5))), SignedMoney(cd24), SignedMoney(cd7) },
        }
    end
    if bankMoney > 0 then
        list[#list + 1] = {
            cells = { ColorText("ffd100", L.accountBank), ns.Money(bankMoney), ColorText("a8998a", total > 0 and ("%d%%"):format(math.floor(bankMoney / total * 100 + 0.5)) or ""), "", "" },
        }
    end
    for _, tr in ipairs(db.wealth.transit or {}) do
        list[#list + 1] = {
            cells = { ColorText("7fa7e0", L.inTransit .. ": " .. (tr.from or "?") .. " -> " .. (tr.to or "?")), ns.Money(tr.amount or 0), "", "", "" },
        }
    end

    ConfigureTable(chartTop - (CHART_H + 34) - 10, {
        { label = L.statsCharacter, w = 0.34, align = "LEFT" },
        { label = L.statsGold, w = 0.22, align = "RIGHT" },
        { label = L.statsShare, w = 0.10, align = "RIGHT" },
        { label = L.period24h, w = 0.17, align = "RIGHT" },
        { label = L.period7d, w = 0.17, align = "RIGHT" },
    }, list)
end

local function RenderLoot()
    local L = ns.L
    chartBox:Hide()
    settingsBox:Hide()
    SetPeriodBar("daily")
    LayoutKpis(4)
    local view = subView.loot or "items"
    SetSubButtons({
        { key = "items", label = L.subTopItems },
        { key = "zones", label = L.subZones },
        { key = "runs", label = L.subRuns },
        { key = "drops", label = L.subDrops },
        { key = "sessions", label = L.subSessions },
    }, view, function(k) subView.loot = k end)

    local p = AggregatePeriod(activePeriod)
    SetKpi(1, L.lootTotal, ns.Money(p.lootTotal), L.statsDays .. ": " .. tostring(p.days))
    SetKpi(2, L.vendorGuaranteed, ns.Money(p.vendorTotal), "")
    SetKpi(3, L.subRuns, tostring(#(db.runs or {})), "")
    SetKpi(4, L.statsDrops, tostring(#(db.drops or {})), "")

    local list = {}
    local tableTop = CONTENT_TOP - KPI_H - 10
    if view == "items" then
        local items = {}
        for _, it in pairs(p.items) do items[#items + 1] = it end
        table.sort(items, function(a, b) return a.v > b.v end)
        for _, it in ipairs(items) do
            list[#list + 1] = {
                itemID = it.id,
                cells = { ItemText(it.id, it.name, it.q), L[it.cat] or "", tostring(it.n), ns.Money(it.v), ColorText("a8998a", ns.Money(it.vv)) },
            }
        end
        ConfigureTable(tableTop, {
            { label = L.statsItem, w = 0.38, align = "LEFT" },
            { label = L.statsCategory, w = 0.14, align = "LEFT" },
            { label = L.statsCount, w = 0.10, align = "RIGHT" },
            { label = L.statsValue, w = 0.20, align = "RIGHT" },
            { label = L.statsVendor, w = 0.18, align = "RIGHT" },
        }, list)
    elseif view == "zones" then
        local zones = {}
        for _, z in pairs(p.zones) do zones[#zones + 1] = z end
        table.sort(zones, function(a, b) return a.v > b.v end)
        for _, z in ipairs(zones) do
            local gph = (z.t >= 60) and ns.Money(z.v / z.t * 3600) or ColorText("75695c", "--")
            local share = p.lootTotal > 0 and (z.v / p.lootTotal) or 0
            list[#list + 1] = {
                barShare = share,
                cells = { z.zone, ns.Money(z.v), z.c > 0 and ns.Money(z.c) or ColorText("75695c", "-"), z.t > 0 and Duration(z.t) or ColorText("75695c", "-"), gph },
            }
        end
        ConfigureTable(tableTop, {
            { label = L.statsZone, w = 0.34, align = "LEFT" },
            { label = L.statsGold, w = 0.20, align = "RIGHT" },
            { label = L.coins, w = 0.16, align = "RIGHT" },
            { label = L.statsTime, w = 0.12, align = "RIGHT" },
            { label = L.statsPerHour, w = 0.18, align = "RIGHT" },
        }, list)
    elseif view == "runs" then
        for i = #(db.runs or {}), 1, -1 do
            local r = db.runs[i]
            local gph = (r.elapsed and r.elapsed >= 60) and ns.Money((r.total or 0) / r.elapsed * 3600) or ColorText("75695c", "--")
            list[#list + 1] = {
                cells = { ColorText("a8998a", date("%m-%d %H:%M", r.started or 0)), r.instance or "?", Duration(r.elapsed), ns.Money(r.total or 0), gph },
            }
        end
        ConfigureTable(tableTop, {
            { label = L.statsWhen, w = 0.18, align = "LEFT" },
            { label = L.statsInstance, w = 0.34, align = "LEFT" },
            { label = L.statsDuration, w = 0.12, align = "RIGHT" },
            { label = L.statsGold, w = 0.18, align = "RIGHT" },
            { label = L.statsPerHour, w = 0.18, align = "RIGHT" },
        }, list)
    elseif view == "drops" then
        for i = #(db.drops or {}), 1, -1 do
            local dr = db.drops[i]
            list[#list + 1] = {
                itemID = dr.id,
                cells = { ColorText("a8998a", date("%m-%d %H:%M", dr.t or 0)), ItemText(dr.id, dr.name, dr.quality), dr.zone or "?", ColorText("a8998a", dr.char or ""), ns.Money(dr.value or 0) },
            }
        end
        ConfigureTable(tableTop, {
            { label = L.statsWhen, w = 0.16, align = "LEFT" },
            { label = L.statsItem, w = 0.34, align = "LEFT" },
            { label = L.statsZone, w = 0.18, align = "LEFT" },
            { label = L.statsCharacter, w = 0.15, align = "LEFT" },
            { label = L.statsValue, w = 0.17, align = "RIGHT" },
        }, list)
    else
        for i = #(db.history or {}), 1, -1 do
            local h = db.history[i]
            local tot = 0
            for _, v in pairs(h.gold or {}) do tot = tot + v end
            local gph = (h.elapsed and h.elapsed >= 60) and ns.Money(tot / h.elapsed * 3600) or ColorText("75695c", "--")
            local zNames = {}
            for zn in pairs(h.zones or {}) do zNames[#zNames + 1] = zn end
            table.sort(zNames)
            list[#list + 1] = {
                cells = { ColorText("a8998a", date("%m-%d %H:%M", h.started or h.archived or 0)), table.concat(zNames, ", "), Duration(h.elapsed), ns.Money(tot), gph },
            }
        end
        ConfigureTable(tableTop, {
            { label = L.statsWhen, w = 0.18, align = "LEFT" },
            { label = L.zones, w = 0.34, align = "LEFT" },
            { label = L.statsDuration, w = 0.12, align = "RIGHT" },
            { label = L.statsGold, w = 0.18, align = "RIGHT" },
            { label = L.statsPerHour, w = 0.18, align = "RIGHT" },
        }, list)
    end
end

local function RenderAH()
    local L = ns.L
    chartBox:Hide()
    settingsBox:Hide()
    SetPeriodBar("daily")
    LayoutKpis(4)
    local view = subView.ah or "sales"
    SetSubButtons({
        { key = "sales", label = L.subAhSales },
        { key = "top", label = L.subAhTop },
    }, view, function(k) subView.ah = k end)

    local p = AggregatePeriod(activePeriod)
    local pendingMail, listedCopper, listedCount = 0, 0, 0
    for _, ap in pairs(db.ahPending or {}) do
        pendingMail = pendingMail + (ap.pendingMailCopper or 0)
        listedCopper = listedCopper + (ap.listedCopper or 0)
        listedCount = listedCount + (ap.listedCount or 0)
    end

    SetKpi(1, L.ahSales, ColorText("4ce64c", ns.Money(p.ah.net)), L.salesCount:format(p.ah.sales) .. " · " .. L.gross .. ": " .. ShortMoney(p.ah.gross))
    SetKpi(2, L.ahCut, ColorText("f05454", ns.Money(p.ah.cut)), "")
    SetKpi(3, L.ahBuys, ns.Money(p.ah.buyTotal), L.buysCount:format(p.ah.buys))
    SetKpi(4, L.ahPending, ns.Money(pendingMail), L.ahListed:format(listedCount) .. " (" .. ShortMoney(listedCopper) .. ")")

    local list = {}
    local tableTop = CONTENT_TOP - KPI_H - 10
    if view == "sales" then
        for i = #(db.ledger or {}), 1, -1 do
            local e = db.ledger[i]
            if e and e.kind == "ah" and e.dir == "in" then
                local qty = (e.count and e.count > 1) and (" x" .. tostring(e.count)) or ""
                list[#list + 1] = {
                    itemID = e.itemID,
                    cells = {
                        ColorText("a8998a", date("%m-%d %H:%M", e.t or 0)),
                        ItemText(e.itemID, e.item or L.cfAh, 1) .. ColorText("a8998a", qty),
                        ColorText("a8998a", e.counterparty or "-"),
                        ColorText("f05454", e.cut and e.cut > 0 and ("-" .. ShortMoney(e.cut)) or "-"),
                        ColorText("4ce64c", ns.Money(e.amount or 0)),
                    },
                }
            end
        end
        ConfigureTable(tableTop, {
            { label = L.statsWhen, w = 0.16, align = "LEFT" },
            { label = L.statsItem, w = 0.34, align = "LEFT" },
            { label = L.statsBuyer, w = 0.18, align = "LEFT" },
            { label = L.ahCut, w = 0.14, align = "RIGHT" },
            { label = L.net, w = 0.18, align = "RIGHT" },
        }, list)
    else
        local byItem = {}
        for _, e in ipairs(db.ledger or {}) do
            if e and e.kind == "ah" and e.dir == "in" then
                local name = e.item or "?"
                local agg = byItem[name]
                if not agg then
                    agg = { name = name, itemID = e.itemID, sales = 0, count = 0, cut = 0, net = 0 }
                    byItem[name] = agg
                end
                agg.sales = agg.sales + 1
                agg.count = agg.count + (e.count or 1)
                agg.cut = agg.cut + (e.cut or 0)
                agg.net = agg.net + (e.amount or 0)
            end
        end
        local top = {}
        for _, agg in pairs(byItem) do top[#top + 1] = agg end
        table.sort(top, function(a, b) return a.net > b.net end)
        for _, it in ipairs(top) do
            local avg = it.count > 0 and math.floor(it.net / it.count + 0.5) or 0
            list[#list + 1] = {
                itemID = it.itemID,
                cells = { ItemText(it.itemID, it.name, 1), tostring(it.count), ns.Money(avg), ColorText("f05454", ShortMoney(it.cut)), ColorText("4ce64c", ns.Money(it.net)) },
            }
        end
        ConfigureTable(tableTop, {
            { label = L.statsItem, w = 0.40, align = "LEFT" },
            { label = L.statsCount, w = 0.10, align = "RIGHT" },
            { label = L.statsValue, w = 0.18, align = "RIGHT" },
            { label = L.ahCut, w = 0.14, align = "RIGHT" },
            { label = L.net, w = 0.18, align = "RIGHT" },
        }, list)
    end
end

local function RenderCashflow()
    local L = ns.L
    chartBox:Hide()
    settingsBox:Hide()
    SetPeriodBar("daily")
    LayoutKpis(3)
    local view = subView.cashflow or "cats"
    SetSubButtons({
        { key = "cats", label = L.subCfCats },
        { key = "ledger", label = L.subCfLedger },
        { key = "daily", label = L.subCfDaily },
    }, view, function(k) subView.cashflow = k end)

    local p = AggregatePeriod(activePeriod)
    SetKpi(1, L.income, ColorText("4ce64c", ns.Money(p.income)), "")
    SetKpi(2, L.expense, ColorText("f05454", ns.Money(p.expense)), "")
    SetKpi(3, L.net, SignedMoney(p.income - p.expense), "")
    SetKpi(4, nil)

    local inLabels = { ah = L.cfAh, dungeon = L.cfDungeon, loot = L.cfLoot, quest = L.cfQuest, vendor = L.cfVendor, trade = L.cfTrade, mail = L.cfMail, other = L.cfOther }
    local outLabels = { repair = L.cfRepair, ahBuy = L.cfAhBuy, ahDeposit = L.cfAhDeposit, vendor = L.cfVendorBuy, taxi = L.cfTaxi, trainer = L.cfTrainer, mail = L.cfMailOut, trade = L.cfTradeOut, other = L.cfOtherOut }

    local list = {}
    local tableTop = CONTENT_TOP - KPI_H - 10
    if view == "cats" then
        for k, v in pairs(p.incomeByKind) do
            if v > 0 then
                local share = p.income > 0 and (v / p.income) or 0
                list[#list + 1] = {
                    sortV = v, barShare = share, barColor = { 0.25, 0.75, 0.30 },
                    cells = { inLabels[k] or k, ColorText("4ce64c", L.income), ColorText("4ce64c", "+" .. ns.Money(v)), ColorText("a8998a", ("%d%%"):format(math.floor(share * 100 + 0.5))) },
                }
            end
        end
        for k, v in pairs(p.expenseByKind) do
            if v > 0 then
                local share = p.expense > 0 and (v / p.expense) or 0
                list[#list + 1] = {
                    sortV = -v, barShare = share, barColor = { 0.85, 0.28, 0.28 },
                    cells = { outLabels[k] or k, ColorText("f05454", L.expense), ColorText("f05454", "-" .. ns.Money(v)), ColorText("a8998a", ("%d%%"):format(math.floor(share * 100 + 0.5))) },
                }
            end
        end
        table.sort(list, function(a, b) return a.sortV > b.sortV end)
        ConfigureTable(tableTop, {
            { label = L.statsSource, w = 0.42, align = "LEFT" },
            { label = L.statsCategory, w = 0.18, align = "LEFT" },
            { label = L.statsAmount, w = 0.26, align = "RIGHT" },
            { label = L.statsShare, w = 0.14, align = "RIGHT" },
        }, list)
    elseif view == "ledger" then
        for i = #(db.ledger or {}), 1, -1 do
            local e = db.ledger[i]
            local lbl = (e.dir == "in" and inLabels[e.kind] or outLabels[e.kind]) or e.kind or "?"
            local det = e.item and ((e.count and e.count > 1) and (e.item .. " x" .. e.count) or e.item) or e.counterparty or e.note or "-"
            local amt = e.dir == "in" and SignedMoney(e.amount or 0) or SignedMoney(-(e.amount or 0))
            list[#list + 1] = {
                itemID = e.itemID,
                cells = { ColorText("a8998a", date("%m-%d %H:%M", e.t or 0)), lbl, ColorText("a8998a", det), ColorText("a8998a", e.char or ""), amt },
            }
        end
        ConfigureTable(tableTop, {
            { label = L.statsWhen, w = 0.16, align = "LEFT" },
            { label = L.statsCategory, w = 0.22, align = "LEFT" },
            { label = L.statsDetails, w = 0.28, align = "LEFT" },
            { label = L.statsCharacter, w = 0.16, align = "LEFT" },
            { label = L.statsAmount, w = 0.18, align = "RIGHT" },
        }, list)
    else
        local days = {}
        for dayKey, d in pairs(db.daily or {}) do days[#days + 1] = { key = dayKey, d = d } end
        table.sort(days, function(a, b) return a.key > b.key end)
        for _, item in ipairs(days) do
            local d = item.d
            local lootV, inc, exp = 0, 0, 0
            for _, lb in pairs(d.loot or {}) do lootV = lootV + (lb.v or 0) end
            for _, v in pairs((d.cashflow and d.cashflow.income) or {}) do inc = inc + v end
            for _, v in pairs((d.cashflow and d.cashflow.expense) or {}) do exp = exp + v end
            local ahNet = (d.ah and d.ah.net) or 0
            list[#list + 1] = {
                cells = { item.key, ns.Money(lootV), ahNet > 0 and ns.Money(ahNet) or ColorText("75695c", "-"), ColorText("4ce64c", ShortMoney(inc)) .. " / " .. ColorText("f05454", ShortMoney(exp)), SignedMoney(inc - exp) },
            }
        end
        ConfigureTable(tableTop, {
            { label = L.statsDay, w = 0.18, align = "LEFT" },
            { label = L.loot, w = 0.20, align = "RIGHT" },
            { label = L.ahSales, w = 0.18, align = "RIGHT" },
            { label = L.income .. " / " .. L.expense, w = 0.24, align = "RIGHT" },
            { label = L.net, w = 0.20, align = "RIGHT" },
        }, list)
    end
end

local function RenderSettings()
    chartBox:Hide()
    tablePanel:Hide()
    SetPeriodBar(nil)
    SetSubButtons(nil)
    for i = 1, 4 do SetKpi(i, nil) end
    footLeft:SetText("")
    settingsBox:Show()
    settingsBox.refresh()
end

local RENDERERS = {
    overview = RenderOverview,
    wealth = RenderWealth,
    loot = RenderLoot,
    ah = RenderAH,
    cashflow = RenderCashflow,
    settings = RenderSettings,
}

---------------------------------------------------------------------------
-- In-Game Settings Panel (flat WoWToolsForever checkboxes & buttons)
---------------------------------------------------------------------------
local function BuildSettingsBox(parent)
    local L = ns.L
    local box = CreateFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", PAD, CONTENT_TOP)
    box:SetPoint("BOTTOMRIGHT", -PAD, FOOT_H + PAD)
    box.box = frameBox(box, THEME.panel, THEME.borderSubtle)
    box:Hide()

    local updaters = {}
    local y = -18

    local function AddCheck(label, getFn, setFn)
        local cb = CreateFrame("CheckButton", nil, box)
        cb:SetSize(16, 16)
        cb:SetPoint("TOPLEFT", 16, y)
        cb.box = frameBox(cb, THEME.card, THEME.border)
        local check = cb:CreateTexture(nil, "OVERLAY")
        check:SetTexture(CHECK_TEX)
        check:SetSize(18, 18)
        check:SetPoint("CENTER", cb, "CENTER", 0, 0)
        check:SetVertexColor(THEME.gold[1], THEME.gold[2], THEME.gold[3])
        if cb.SetCheckedTexture then cb:SetCheckedTexture(check) end
        cb.checkTex = check

        local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", cb, "RIGHT", 9, 0)
        text:SetText(label)
        text:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
        if cb.SetHitRectInsets then cb:SetHitRectInsets(0, -300, -4, -4) end

        local function sync()
            local on = getFn() and true or false
            if cb.SetChecked then cb:SetChecked(on) end
            check:SetShown(on)
        end
        cb:SetScript("OnClick", function()
            setFn(not getFn())
            sync()
            if ns.ApplyLiveSettings then ns.ApplyLiveSettings() end
        end)
        cb:SetScript("OnEnter", function(self) self.box:setBorder(THEME.borderHi) end)
        cb:SetScript("OnLeave", function(self) self.box:setBorder(THEME.border) end)
        updaters[#updaters + 1] = sync
        y = y - 28
    end

    AddCheck(L.setShown, function() return not db.hidden end, function(v) db.hidden = not v or nil end)
    AddCheck(L.setResume, function() return ns.Setting("resumeAfterReload") end, function(v) db.settings.resumeAfterReload = v end)
    AddCheck(L.setAutoStart, function() return ns.Setting("autoStart") end, function(v) db.settings.autoStart = v end)
    AddCheck(L.setTrackAlways, function() return ns.Setting("trackAlways") end, function(v) db.settings.trackAlways = v end)
    AddCheck(L.setAhCut, function() return ns.Setting("deductAhCut") end, function(v) db.settings.deductAhCut = v end)
    AddCheck(L.setVendorFloor, function() return ns.Setting("vendorFloor") end, function(v) db.settings.vendorFloor = v end)

    local ry = -16
    local function AddCycler(label, valuesList, getFn, setFn, fmtFn)
        local row = CreateFrame("Frame", nil, box)
        row:SetPoint("TOPRIGHT", -16, ry)
        row:SetSize(330, 24)
        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", 0, 0)
        lbl:SetText(label)
        lbl:SetTextColor(THEME.muted[1], THEME.muted[2], THEME.muted[3])

        local btn = flatButton(row, "ghost")
        btn:SetPoint("RIGHT", 0, 0)
        btn:SetSize(156, 22)

        local function sync()
            btn.label:SetText(fmtFn(getFn()))
        end
        btn:SetScript("OnClick", function()
            local cur = getFn()
            local idx = 1
            for i, v in ipairs(valuesList) do
                if v == cur then idx = i break end
            end
            setFn(valuesList[(idx % #valuesList) + 1])
            sync()
            if ns.ApplyLiveSettings then ns.ApplyLiveSettings() end
        end)
        updaters[#updaters + 1] = sync
        ry = ry - 30
    end

    AddCycler(L.setPriceSource, { "auctionator", "vendor" },
        function() return ns.Setting("priceSource") end,
        function(v) db.settings.priceSource = v end,
        function(v) return v == "vendor" and L.setPriceVendor or L.setPriceAh end)

    AddCycler(L.setScale, { 0.8, 0.9, 1, 1.1, 1.25, 1.5 },
        function() return ns.Setting("scale") end,
        function(v) db.settings.scale = v end,
        function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end)

    AddCycler(L.setTooltipItems, { 4, 6, 10, 15, 20 },
        function() return ns.Setting("tooltipItems") end,
        function(v) db.settings.tooltipItems = v end,
        function(v) return tostring(v) end)

    AddCycler(L.setWealthInterval, { 60, 300, 900, 1800 },
        function() return ns.Setting("wealthInterval") end,
        function(v) db.settings.wealthInterval = v end,
        function(v) return L.optMinutes:format(math.floor(v / 60)) end)

    AddCycler(L.setDropQuality, { 2, 3, 4, 5 },
        function() return ns.Setting("minDropQuality") end,
        function(v) db.settings.minDropQuality = v end,
        function(v) return ColorText(QUALITY_COLORS[v], L["q" .. tostring(v)] or tostring(v)) end)

    AddCycler(L.setDropValue, { 0, 10000, 50000, 100000, 500000 },
        function() return ns.Setting("minDropValue") end,
        function(v) db.settings.minDropValue = v end,
        function(v) return v == 0 and L.optOff or ShortMoney(v) end)

    AddCycler(L.setAhMinValue, { 0, 5000, 10000, 50000, 100000 },
        function() return ns.Setting("ahMinValue") end,
        function(v) db.settings.ahMinValue = v end,
        function(v) return v == 0 and L.optOff or ShortMoney(v) end)

    box.refresh = function()
        for _, fn in ipairs(updaters) do fn() end
    end
    return box
end

---------------------------------------------------------------------------
-- Tab Painting & Frame Construction
---------------------------------------------------------------------------
local function PaintTab(tab)
    if tab.active then
        colorTex(tab.bg, THEME.tabActive)
        tab.bg:Show()
        tab.bar:Show()
        tab.label:SetTextColor(THEME.gold[1], THEME.gold[2], THEME.gold[3])
    elseif tab.hovered then
        colorTex(tab.bg, THEME.tabHover)
        tab.bg:Show()
        tab.bar:Hide()
        tab.label:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
    else
        tab.bg:Hide()
        tab.bar:Hide()
        tab.label:SetTextColor(THEME.muted[1], THEME.muted[2], THEME.muted[3])
    end
end

local function UpdateTabVisuals()
    local tabW = math.floor((curW - 2) / #TABS)
    for i, key in ipairs(TABS) do
        local tab = tabButtons[key]
        tab.active = (key == activeTab)
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", frame, "TOPLEFT", 1 + (i - 1) * tabW, -(TITLE_H + 1))
        tab:SetSize(i == #TABS and (curW - 2 - (i - 1) * tabW) or tabW, TABS_H - 1)
        PaintTab(tab)
    end
end

local function BuildGrip()
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    local dots = {}
    for _, pos in ipairs({ { 11, 3 }, { 7, 3 }, { 3, 3 }, { 11, 7 }, { 7, 7 }, { 11, 11 } }) do
        local dot = solid(grip, "ARTWORK", THEME.border, 1)
        dot:SetSize(2, 2)
        dot:SetPoint("BOTTOMLEFT", grip, "BOTTOMLEFT", pos[1], pos[2])
        dots[#dots + 1] = dot
    end
    if grip.RegisterForClicks then grip:RegisterForClicks("RightButtonUp") end
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local left = frame.GetLeft and frame:GetLeft()
        local top = frame.GetTop and frame:GetTop()
        if type(left) == "number" and type(top) == "number" then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        frame.sizing = true
        if frame.StartSizing then frame:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        if not frame.sizing then return end
        frame.sizing = false
        if frame.StopMovingOrSizing then frame:StopMovingOrSizing() end
        SavePlace()
        Stats.Refresh()
    end)
    grip:SetScript("OnClick", function()
        curW, curH = DEFAULT_W, DEFAULT_H
        frame:SetSize(curW, curH)
        if db then db.statsSize = nil end
        Stats.Refresh()
    end)
    grip:SetScript("OnEnter", function()
        for _, dot in ipairs(dots) do colorTex(dot, THEME.gold) end
        if type(SetCursor) == "function" then pcall(SetCursor, "UI_RESIZE_CURSOR") end
    end)
    grip:SetScript("OnLeave", function()
        for _, dot in ipairs(dots) do colorTex(dot, THEME.border) end
        if type(SetCursor) == "function" then pcall(SetCursor, nil) end
    end)
    return grip
end

local function BuildFrame()
    if frame then return end
    local L = ns.L
    if db and type(db.statsSize) == "table" then
        curW, curH = ClampSize(db.statsSize[1], db.statsSize[2])
    end

    frame = CreateFrame("Frame", "GoldPerHourStatsFrame", UIParent)
    frame:SetSize(curW, curH)
    if db and type(db.statsPos) == "table" then
        frame:SetPoint(db.statsPos[1], UIParent, db.statsPos[2], db.statsPos[3], db.statsPos[4])
    else
        frame:SetPoint("CENTER")
    end
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    if frame.SetResizable then frame:SetResizable(true) end
    if frame.SetResizeBounds then frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H) end
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePlace()
    end)
    frame:SetScript("OnSizeChanged", function(_, w, h)
        if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
            curW, curH = ClampSize(w, h)
            Stats.Refresh()
        end
    end)
    frame:SetScript("OnMouseWheel", function(_, delta)
        if activeTab == "settings" then return end
        scrollOffset = math.max(0, scrollOffset + (delta > 0 and -3 or 3))
        Stats.Refresh()
    end)

    -- Outer 1px black edge + crisp 1px bronze frame + warm dark stone canvas.
    frameBox(frame, nil, THEME.outerShadow, -1)
    frameBox(frame, THEME.bg, THEME.border, 0)
    frame:Hide()

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "GoldPerHourStatsFrame")
    end

    -- Title bar (36px)
    local titleBg = solid(frame, "BACKGROUND", THEME.bar, -4)
    titleBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    titleBg:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    titleBg:SetHeight(TITLE_H - 1)
    divider(frame, "TOPLEFT", 1, -TITLE_H, "TOPRIGHT", -1, -TITLE_H)

    local logoFrame = CreateFrame("Frame", nil, frame)
    logoFrame:SetSize(22, 22)
    logoFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -7)
    frameBox(logoFrame, nil, THEME.borderHi, 0)
    local logo = logoFrame:CreateTexture(nil, "ARTWORK")
    logo:SetPoint("TOPLEFT", 1, -1)
    logo:SetPoint("BOTTOMRIGHT", -1, 1)
    logo:SetTexture(LOGO)
    logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", logoFrame, "RIGHT", 9, 0)
    title:SetText(L.statsTitle)
    title:SetTextColor(THEME.gold[1], THEME.gold[2], THEME.gold[3])

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
    close.box = frameBox(close, THEME.ghost, THEME.borderSubtle)
    local xText = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    xText:SetPoint("CENTER", close, "CENTER", 0, 1)
    xText:SetText("\195\151")
    xText:SetTextColor(THEME.muted[1], THEME.muted[2], THEME.muted[3])
    close:SetScript("OnEnter", function()
        close.box:setBg(THEME.closeHover)
        close.box:setBorder(THEME.primaryBorder)
        xText:SetTextColor(1, 1, 1)
    end)
    close:SetScript("OnLeave", function()
        close.box:setBg(THEME.ghost)
        close.box:setBorder(THEME.borderSubtle)
        xText:SetTextColor(THEME.muted[1], THEME.muted[2], THEME.muted[3])
    end)
    close:SetScript("OnClick", function() frame:Hide() end)

    titleSub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    titleSub:SetPoint("LEFT", title, "RIGHT", 12, 0)
    titleSub:SetPoint("RIGHT", close, "LEFT", -10, 0)
    titleSub:SetJustifyH("RIGHT")
    titleSub:SetWordWrap(false)
    titleSub:SetTextColor(THEME.muted[1], THEME.muted[2], THEME.muted[3])

    -- Tab strip (30px) + context/filter bar (30px)
    local tabStripBg = solid(frame, "BACKGROUND", THEME.tabs, -4)
    tabStripBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -(TITLE_H + 1))
    tabStripBg:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -(TITLE_H + 1))
    tabStripBg:SetHeight(TABS_H - 1)
    divider(frame, "TOPLEFT", 1, -(TITLE_H + TABS_H), "TOPRIGHT", -1, -(TITLE_H + TABS_H))

    local barBg = solid(frame, "BACKGROUND", THEME.noteBar, -4)
    barBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -(TITLE_H + TABS_H + 1))
    barBg:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -(TITLE_H + TABS_H + 1))
    barBg:SetHeight(BAR_H - 1)
    divider(frame, "TOPLEFT", 1, -(TITLE_H + TABS_H + BAR_H), "TOPRIGHT", -1, -(TITLE_H + TABS_H + BAR_H))

    tabButtons = {}
    local tabLabels = {
        overview = L.tabOverview, wealth = L.tabWealth, loot = L.tabLoot,
        ah = L.tabAh, cashflow = L.tabCashflow, settings = L.tabSettings,
    }
    for _, key in ipairs(TABS) do
        local tab = CreateFrame("Button", nil, frame)
        tab.bg = solid(tab, "BACKGROUND", THEME.tabActive, -2)
        tab.bg:SetAllPoints()
        tab.bg:Hide()
        tab.bar = solid(tab, "OVERLAY", THEME.gold, 2)
        tab.bar:SetHeight(2)
        tab.bar:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
        tab.bar:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
        tab.bar:Hide()
        tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tab.label:SetPoint("LEFT", tab, "LEFT", 6, 0)
        tab.label:SetPoint("RIGHT", tab, "RIGHT", -6, 0)
        tab.label:SetJustifyH("CENTER")
        tab.label:SetWordWrap(false)
        tab.label:SetText(tabLabels[key] or key)
        tab:SetScript("OnEnter", function(self) self.hovered = true; PaintTab(self) end)
        tab:SetScript("OnLeave", function(self) self.hovered = false; PaintTab(self) end)
        tab:SetScript("OnClick", function()
            activeTab = key
            scrollOffset = 0
            Stats.Refresh()
        end)
        tabButtons[key] = tab
    end

    -- Sub-view buttons (left of context bar)
    subButtons = {}
    local barY = -(TITLE_H + TABS_H + 5)
    for i = 1, 5 do
        local btn = flatButton(frame, "ghost")
        btn:SetSize(96, 20)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + (i - 1) * 100, barY)
        btn:Hide()
        subButtons[i] = btn
    end

    -- Period filter buttons (right of context bar)
    periodButtons = {}
    for i = 1, 4 do
        local btn = flatButton(frame, "ghost")
        btn:SetSize(62, 20)
        btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD - (4 - i) * 66, barY)
        btn:Hide()
        periodButtons[i] = btn
    end

    -- 4 KPI Cards (THEME.card + THEME.borderSubtle + goldSoft top edge)
    kpiCards = {}
    for i = 1, 4 do
        local card = CreateFrame("Frame", nil, frame)
        card.box = frameBox(card, THEME.card, THEME.borderSubtle)
        local topAccent = solid(card, "ARTWORK", THEME.goldSoft, 1)
        topAccent:SetPoint("TOPLEFT", 1, -1)
        topAccent:SetPoint("TOPRIGHT", -1, -1)
        topAccent:SetHeight(1)

        card.title = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        card.title:SetPoint("TOPLEFT", 10, -8)
        card.title:SetPoint("TOPRIGHT", -10, -8)
        card.title:SetJustifyH("LEFT")
        card.title:SetWordWrap(false)
        card.title:SetTextColor(THEME.muted[1], THEME.muted[2], THEME.muted[3])

        card.value = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        card.value:SetPoint("TOPLEFT", 10, -24)
        card.value:SetPoint("TOPRIGHT", -10, -24)
        card.value:SetJustifyH("LEFT")
        card.value:SetWordWrap(false)
        card.value:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])

        card.sub = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        card.sub:SetPoint("TOPLEFT", 10, -45)
        card.sub:SetPoint("TOPRIGHT", -10, -45)
        card.sub:SetJustifyH("LEFT")
        card.sub:SetWordWrap(false)
        card.sub:SetTextColor(THEME.dim[1], THEME.dim[2], THEME.dim[3])
        kpiCards[i] = card
    end

    -- Interactive Wealth Chart container
    chartBox = BuildChart(frame)

    -- Inset table panel (THEME.panel + THEME.borderSubtle) with header strip & thin scrollbar
    tablePanel = CreateFrame("Frame", nil, frame)
    tablePanel.box = frameBox(tablePanel, THEME.panel, THEME.borderSubtle)

    headerBar = CreateFrame("Frame", nil, tablePanel)
    headerBar:SetPoint("TOPLEFT", 1, -1)
    headerBar:SetPoint("TOPRIGHT", -1, -1)
    headerBar:SetHeight(24)
    local hBg = solid(headerBar, "BACKGROUND", THEME.card, -4)
    hBg:SetAllPoints()
    local hAccent = solid(headerBar, "ARTWORK", THEME.goldSoft, 1)
    hAccent:SetPoint("TOPLEFT", 0, 0)
    hAccent:SetSize(2, 24)
    divider(tablePanel, "TOPLEFT", 1, -25, "TOPRIGHT", -1, -25, THEME.line)

    headerCols = {}
    for c = 1, 5 do
        local fs = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetTextColor(THEME.gold[1], THEME.gold[2], THEME.gold[3])
        fs:SetWordWrap(false)
        headerCols[c] = fs
    end

    scrollTrack = CreateFrame("Frame", nil, tablePanel)
    scrollTrack:SetPoint("TOPRIGHT", tablePanel, "TOPRIGHT", -2, -27)
    scrollTrack:SetPoint("BOTTOMRIGHT", tablePanel, "BOTTOMRIGHT", -2, 2)
    scrollTrack:SetWidth(7)
    local trkBg = solid(scrollTrack, "BACKGROUND", THEME.track, -2)
    trkBg:SetAllPoints()
    scrollThumb = solid(scrollTrack, "ARTWORK", THEME.thumb, 1)
    scrollTrack:Hide()

    rowFrames = {}
    for i = 1, MAX_ROWS do
        local rf = CreateFrame("Button", nil, tablePanel)
        rf:SetHeight(ROW_HEIGHT)
        rf.stripe = solid(rf, "BACKGROUND", THEME.stripe, -4)
        rf.stripe:SetAllPoints()
        rf.stripe:Hide()
        rf.sel = solid(rf, "BORDER", THEME.select, -2)
        rf.sel:SetAllPoints()
        rf.sel:Hide()
        rf.selBar = solid(rf, "OVERLAY", THEME.gold, 2)
        rf.selBar:SetPoint("TOPLEFT", rf, "TOPLEFT", 0, -1)
        rf.selBar:SetPoint("BOTTOMLEFT", rf, "BOTTOMLEFT", 0, 1)
        rf.selBar:SetWidth(2)
        rf.selBar:Hide()
        rf.hl = solid(rf, "HIGHLIGHT", THEME.hover, 0)
        rf.hl:SetAllPoints()
        rf.bar = rf:CreateTexture(nil, "BORDER", nil, -1)
        rf.bar:SetPoint("TOPLEFT", rf, "TOPLEFT", 0, -1)
        rf.bar:SetPoint("BOTTOMLEFT", rf, "BOTTOMLEFT", 0, 1)
        rf.bar:Hide()
        rf.cols = {}
        for c = 1, 5 do
            local fs = rf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetWordWrap(false)
            fs:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
            rf.cols[c] = fs
        end
        rf:SetScript("OnClick", function(self)
            if self.entry and self.entry.onClick then self.entry.onClick() end
        end)
        rf:SetScript("OnEnter", function(self)
            if not self.entry then return end
            if self.entry.itemID and GameTooltip and GameTooltip.SetItemByID then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetItemByID, GameTooltip, self.entry.itemID)
                GameTooltip:Show()
            end
        end)
        rf:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        rowFrames[i] = rf
    end

    -- Settings panel
    settingsBox = BuildSettingsBox(frame)

    -- Footer bar (34px) + 6-dot resize grip
    local footBg = solid(frame, "BACKGROUND", THEME.bar, -4)
    footBg:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    footBg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    footBg:SetHeight(FOOT_H - 1)
    divider(frame, "BOTTOMLEFT", 1, FOOT_H, "BOTTOMRIGHT", -1, FOOT_H)

    footLeft = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 11)
    footLeft:SetTextColor(THEME.dim[1], THEME.dim[2], THEME.dim[3])

    footRight = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 11)
    footRight:SetJustifyH("RIGHT")
    footRight:SetTextColor(THEME.muted[1], THEME.muted[2], THEME.muted[3])

    BuildGrip()

    ns.statsUi = {
        frame = frame, tabs = tabButtons, kpis = kpiCards, rows = rowFrames,
        chart = chartBox, settings = settingsBox,
    }
end

function Stats.Init(database)
    db = database
end

function Stats.Refresh()
    if not frame or not db then return end
    activeTab = TAB_ALIAS[activeTab] or activeTab or "overview"
    if not RENDERERS[activeTab] then activeTab = "overview" end
    UpdateTabVisuals()

    local accTotal = ns.Wealth.Total()
    local charMoney = ns.Wealth.CharMoney()
    titleSub:SetText(ns.L.wealthChar .. ": " .. ns.Money(charMoney) .. "   |   " .. ns.L.wealthAccount .. ": " .. ns.Money(accTotal))
    footRight:SetText("GoldPerHour " .. tostring(db.version or ""))

    RENDERERS[activeTab]()
end

function Stats.RefreshIfShown()
    if frame and frame:IsShown() then
        Stats.Refresh()
    end
end

function Stats.Show(tab)
    BuildFrame()
    if tab then
        tab = TAB_ALIAS[tab] or tab
        if RENDERERS[tab] then
            activeTab = tab
            scrollOffset = 0
        end
    end
    frame:Show()
    Stats.Refresh()
end

function Stats.Toggle(tab)
    BuildFrame()
    local target = tab and (TAB_ALIAS[tab] or tab) or nil
    if frame:IsShown() and (not target or target == activeTab) then
        frame:Hide()
    else
        Stats.Show(target)
    end
end
