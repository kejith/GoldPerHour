-- Always-on historical recording: daily loot & cashflow buckets, shared dungeon gold,
-- auction house invoices, dungeon runs, top drops and transaction ledger.
local _, ns = ...

local Ledger = {}
ns.Ledger = Ledger

local MAX_LEDGER = 1000
local MAX_RUNS = 200
local MAX_DROPS = 200
local MAIL_GRACE = 5
local CLAIM_WINDOW = 0.6
local QUEST_WINDOW = 2.0
local DEPOSIT_WINDOW = 2.0
local REPAIR_WINDOW = 1.5

local db
local hooksInstalled = false

-- Transient interaction state used to classify PLAYER_MONEY deltas accurately.
local ui = {
    merchant = false,
    mail = false,
    ah = false,
    taxi = false,
    trainer = false,
    trade = false,
    accountBank = false,
    guildBank = false,
}

local pendingMail = nil
local pendingSendMail = nil
local pendingQuest = nil
local claimedChatMoney = nil
local recentLootMoney = nil
local ahDepositUntil = 0
local repairUntil = 0

-- Localized currency patterns derived from WoW's own GlobalStrings so parsing works in any client locale.
local function FormatToPattern(fmt, fallback)
    if type(fmt) ~= "string" or fmt == "" then return fallback end
    local escaped = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    escaped = escaped:gsub("%%%%d", "(%%d+)")
    return escaped
end

local function EscapeSplitPattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local escaped = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    escaped = escaped:gsub("%%%%s", ".+")
    return "^" .. escaped .. "$"
end

local GOLD_PAT, SILVER_PAT, COPPER_PAT
local SPLIT_PATS = {}

local function InitPatterns()
    GOLD_PAT = FormatToPattern(_G.GOLD_AMOUNT, "(%d+)%s*[Gg]old")
    SILVER_PAT = FormatToPattern(_G.SILVER_AMOUNT, "(%d+)%s*[Ss]il[bv]er")
    COPPER_PAT = FormatToPattern(_G.COPPER_AMOUNT, "(%d+)%s*[CKck][ou]p[pf]er")
    SPLIT_PATS = {}
    for _, gName in ipairs({ "LOOT_MONEY_SPLIT", "LOOT_MONEY_SPLIT_GUILD", "LOOT_MONEY_REFUND" }) do
        local p = EscapeSplitPattern(_G[gName])
        if p then SPLIT_PATS[#SPLIT_PATS + 1] = p end
    end
end

function Ledger.ParseMoneyText(text)
    if type(text) ~= "string" or text == "" or ns.IsSecret(text) then return 0, false end
    if not GOLD_PAT then InitPatterns() end
    -- Strip texture strings or commas/dots inside formatted numbers if any.
    local clean = text:gsub("|T.-|t", "")
    local g = tonumber(clean:match(GOLD_PAT)) or 0
    local s = tonumber(clean:match(SILVER_PAT)) or 0
    local c = tonumber(clean:match(COPPER_PAT)) or 0
    local copper = g * 10000 + s * 100 + c

    local isSplit = false
    for _, pat in ipairs(SPLIT_PATS) do
        if clean:match(pat) then
            isSplit = true
            break
        end
    end
    if not isSplit then
        local lower = clean:lower()
        if lower:find("share of the loot", 1, true) or lower:find("anteil an der beute", 1, true) then
            isSplit = true
        end
    end
    return copper, isSplit
end

function Ledger.DayKey(ts)
    return date("%Y-%m-%d", ts or time())
end

function Ledger.EnsureDay(dayKey)
    dayKey = dayKey or Ledger.DayKey()
    local d = db.daily[dayKey]
    if not d then
        d = {
            loot = {},
            items = {},
            zones = {},
            chars = {},
            cashflow = { income = {}, expense = {} },
            ah = { sales = 0, gross = 0, cut = 0, deposit = 0, net = 0, buys = 0, buyTotal = 0 },
        }
        db.daily[dayKey] = d
    else
        d.loot = d.loot or {}
        d.items = d.items or {}
        d.zones = d.zones or {}
        d.chars = d.chars or {}
        d.cashflow = d.cashflow or { income = {}, expense = {} }
        d.cashflow.income = d.cashflow.income or {}
        d.cashflow.expense = d.cashflow.expense or {}
        d.ah = d.ah or { sales = 0, gross = 0, cut = 0, deposit = 0, net = 0, buys = 0, buyTotal = 0 }
    end
    return d
end

function Ledger.Today()
    if not db then return nil end
    return Ledger.EnsureDay()
end

function Ledger.TodayTotals()
    if not db then return 0, 0, 0, 0 end
    local d = db.daily[Ledger.DayKey()]
    if not d then return 0, 0, 0, 0 end
    local lootTotal, inc, exp = 0, 0, 0
    for _, bucket in pairs(d.loot or {}) do
        lootTotal = lootTotal + (bucket.v or 0)
    end
    for _, v in pairs((d.cashflow and d.cashflow.income) or {}) do inc = inc + v end
    for _, v in pairs((d.cashflow and d.cashflow.expense) or {}) do exp = exp + v end
    return lootTotal, inc, exp, inc - exp
end

local function PushRing(list, entry, maxLen)
    list[#list + 1] = entry
    while #list > maxLen do
        table.remove(list, 1)
    end
end

local function AddLedgerEntry(dir, kind, amount, extra)
    local zone = ns.Where()
    local charKey = ns.CharKey()
    local entry = {
        t = time(),
        char = charKey,
        zone = zone,
        kind = kind,
        dir = dir,
        amount = math.floor(amount + 0.5),
    }
    if extra then
        for k, v in pairs(extra) do
            if v ~= nil then entry[k] = v end
        end
    end
    PushRing(db.ledger, entry, MAX_LEDGER)
end

function Ledger.RecordCashflow(dir, kind, amount, extra, skipLedger)
    if not db or not ns.Setting("trackAlways") or not amount or amount <= 0 then return end
    amount = math.floor(amount + 0.5)
    local d = Ledger.EnsureDay()
    local bucket = dir == "in" and d.cashflow.income or d.cashflow.expense
    bucket[kind] = (bucket[kind] or 0) + amount
    if not skipLedger then
        AddLedgerEntry(dir, kind, amount, extra)
    end
    if ns.Stats and ns.Stats.RefreshIfShown then ns.Stats.RefreshIfShown() end
end

function Ledger.RecordLootItem(cat, id, link, name, quality, qty, value, vendorValue, source, zone, charKey)
    if not db or not ns.Setting("trackAlways") then return end
    value = math.floor((value or 0) + 0.5)
    vendorValue = math.floor((vendorValue or 0) + 0.5)
    local d = Ledger.EnsureDay()
    local lb = d.loot[cat]
    if not lb then
        lb = { v = 0, vv = 0, c = 0 }
        d.loot[cat] = lb
    end
    lb.v = lb.v + value
    lb.vv = lb.vv + vendorValue

    local itemKey = id or name or "?"
    local it = d.items[itemKey]
    if not it then
        it = { id = id, name = name or (link and link:match("%[(.-)%]")) or "?", q = quality, n = 0, v = 0, vv = 0, cat = cat }
        d.items[itemKey] = it
    end
    it.q = quality or it.q
    it.n = it.n + qty
    it.v = it.v + value
    it.vv = it.vv + vendorValue

    if zone and zone ~= "" then
        local zb = d.zones[zone]
        if not zb then
            zb = { v = 0, c = 0, t = 0 }
            d.zones[zone] = zb
        end
        zb.v = zb.v + value
    end
    if charKey then
        d.chars[charKey] = (d.chars[charKey] or 0) + value
    end

    -- Active dungeon run attribution.
    local run = db.activeRun
    if run then
        run.lootValue = (run.lootValue or 0) + value
        run.vendorValue = (run.vendorValue or 0) + vendorValue
        run.items = run.items or {}
        local ri = run.items[itemKey]
        if not ri then
            ri = { id = id, name = it.name, quality = quality, count = 0, value = 0, vendor = 0 }
            run.items[itemKey] = ri
        end
        ri.count = ri.count + qty
        ri.value = ri.value + value
        ri.vendor = ri.vendor + vendorValue
    end

    -- Top-drops highlight log.
    local minQ = ns.Setting("minDropQuality")
    local minV = ns.Setting("minDropValue")
    if (quality and minQ and quality >= minQ) or (minV and minV > 0 and value >= minV) then
        PushRing(db.drops, {
            t = time(),
            char = charKey or ns.CharKey(),
            zone = zone or ns.Where(),
            cat = cat,
            id = id,
            name = it.name,
            quality = quality,
            count = qty,
            value = value,
            vendor = vendorValue,
            source = source,
        }, MAX_DROPS)
    end
    if ns.Stats and ns.Stats.RefreshIfShown then ns.Stats.RefreshIfShown() end
end

function Ledger.RecordLootMoney(cat, copper, zone, charKey)
    if not db or not ns.Setting("trackAlways") or not copper or copper <= 0 then return end
    copper = math.floor(copper + 0.5)
    local d = Ledger.EnsureDay()
    local lb = d.loot[cat]
    if not lb then
        lb = { v = 0, vv = 0, c = 0 }
        d.loot[cat] = lb
    end
    lb.v = lb.v + copper
    lb.vv = lb.vv + copper
    lb.c = lb.c + copper

    if zone and zone ~= "" then
        local zb = d.zones[zone]
        if not zb then
            zb = { v = 0, c = 0, t = 0 }
            d.zones[zone] = zb
        end
        zb.v = zb.v + copper
        zb.c = zb.c + copper
    end
    if charKey then
        d.chars[charKey] = (d.chars[charKey] or 0) + copper
    end

    -- Book into cashflow income (skip individual mob coin rows in db.ledger to avoid noise).
    local cfKind = (cat == "dungeon") and "dungeon" or "loot"
    Ledger.RecordCashflow("in", cfKind, copper, nil, true)

    local run = db.activeRun
    if run then
        run.coin = (run.coin or 0) + copper
        if cat == "dungeon" then
            run.dungeonCoin = (run.dungeonCoin or 0) + copper
        end
    end
    if ns.Stats and ns.Stats.RefreshIfShown then ns.Stats.RefreshIfShown() end
end

function Ledger.TickZone(dt)
    if not db or not ns.Setting("trackAlways") or not dt or dt <= 0 then return end
    if UnitIsAFK and UnitIsAFK("player") then return end
    local zone = ns.Where()
    if not zone or zone == "" or zone == "?" then return end
    local d = Ledger.EnsureDay()
    local zb = d.zones[zone]
    if not zb then
        zb = { v = 0, c = 0, t = 0 }
        d.zones[zone] = zb
    end
    zb.t = zb.t + dt
end

-- Dungeon / Raid instance run tracking.
local function FinalizeRun()
    local run = db and db.activeRun
    if not run then return end
    db.activeRun = nil
    local ended = time()
    local elapsed = math.max(0, ended - (run.started or ended))
    local total = (run.coin or 0) + (run.lootValue or 0)
    if elapsed < 30 and total == 0 then return end

    local itemList = {}
    for _, it in pairs(run.items or {}) do
        itemList[#itemList + 1] = it
    end
    table.sort(itemList, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return (a.id or 0) < (b.id or 0)
    end)

    PushRing(db.runs, {
        started = run.started,
        ended = ended,
        elapsed = elapsed,
        instance = run.instance,
        instanceID = run.instanceID,
        difficulty = run.difficulty,
        char = run.char,
        coin = run.coin or 0,
        dungeonCoin = run.dungeonCoin or 0,
        lootValue = run.lootValue or 0,
        vendorValue = run.vendorValue or 0,
        total = total,
        rollsWon = run.rollsWon or 0,
        items = itemList,
    }, MAX_RUNS)
end

function Ledger.CheckInstance()
    if not db or not ns.Setting("trackAlways") or not GetInstanceInfo then return end
    local name, instanceType, _, difficultyName, _, _, _, instanceID = GetInstanceInfo()
    if ns.IsSecret(name) or ns.IsSecret(instanceType) then return end
    if instanceType == "party" or instanceType == "raid" then
        if db.activeRun and db.activeRun.instanceID == instanceID then
            return -- still in the same instance (e.g. after /reload)
        end
        if db.activeRun then FinalizeRun() end
        db.activeRun = {
            started = time(),
            instance = name or "?",
            instanceID = instanceID or 0,
            difficulty = difficultyName or "",
            char = ns.CharKey(),
            coin = 0,
            dungeonCoin = 0,
            lootValue = 0,
            vendorValue = 0,
            rollsWon = 0,
            items = {},
        }
    elseif db.activeRun then
        FinalizeRun()
    end
end

-- Handle CHAT_MSG_MONEY (covers both solo loot coins and shared party/dungeon gold).
function Ledger.OnChatMsgMoney(text, lootState, onSessionMoney)
    if not db then return end
    local copper, isSplit = Ledger.ParseMoneyText(text)
    if copper <= 0 then return end

    local now = GetTime()
    local inLootWindow = lootState.open or now <= (lootState.moneyUntil or 0)
    local inGroup = IsInGroup and IsInGroup()
    local inInstance = false
    if GetInstanceInfo then
        local _, itype = GetInstanceInfo()
        inInstance = (itype == "party" or itype == "raid")
    end

    local cat
    if isSplit or (not inLootWindow and (inGroup or inInstance)) then
        cat = "dungeon"
    elseif inLootWindow then
        cat = lootState.category or "loot"
    else
        cat = "loot"
    end

    -- Deduplicate if PLAYER_MONEY already fired a split-second earlier for the exact same loot window coin.
    if recentLootMoney and (now - recentLootMoney.at) <= CLAIM_WINDOW and recentLootMoney.amount == copper then
        recentLootMoney = nil
        return
    end

    claimedChatMoney = { amount = copper, at = now, cat = cat }
    local zone = ns.Where()
    local charKey = ns.CharKey()
    Ledger.RecordLootMoney(cat, copper, zone, charKey)
    if onSessionMoney then onSessionMoney(cat, copper) end
end

-- Handle LOOT_ITEM_ROLL_WON (items won via Need/Greed in dungeons without opening a loot window).
function Ledger.OnLootRollWon(link, qty, onSessionItem)
    if not db or not link or ns.IsSecret(link) then return end
    qty = (type(qty) == "number" and qty > 0) and qty or 1
    local item = Item:CreateFromItemLink(link)
    if item:IsItemEmpty() then return end
    local zone = ns.Where()
    local charKey = ns.CharKey()
    item:ContinueOnItemLoad(function()
        local id = item:GetItemID()
        local name = link:match("%[(.-)%]")
        local unit, vendorUnit, quality, source = ns.ItemValue(link)
        local value = unit * qty
        local vendorValue = vendorUnit * qty
        if db.activeRun then
            db.activeRun.rollsWon = (db.activeRun.rollsWon or 0) + 1
        end
        Ledger.RecordLootItem("dungeon", id, link, name, quality, qty, value, vendorValue, source, zone, charKey)
        if onSessionItem then
            onSessionItem("dungeon", id, link, quality, qty, value, vendorValue, source, zone)
        end
    end)
end

-- Capture mailbox invoice data before TakeInboxMoney / AutoLootMailItem removes the mail.
local function CaptureInboxMail(index)
    if not index or not GetInboxHeaderInfo then return end
    local ok, _, _, sender, subject, money = pcall(GetInboxHeaderInfo, index)
    if not ok then return end
    local info = {
        at = GetTime(),
        sender = (not ns.IsSecret(sender)) and sender or nil,
        subject = (not ns.IsSecret(subject)) and subject or nil,
        money = (type(money) == "number") and money or 0,
    }
    if GetInboxInvoiceInfo then
        local okInv, invoiceType, itemName, playerName, bid, buyout, deposit, consignment, _, _, _, count =
            pcall(GetInboxInvoiceInfo, index)
        if okInv and invoiceType then
            info.invoiceType = invoiceType
            info.itemName = (not ns.IsSecret(itemName)) and itemName or nil
            info.playerName = (not ns.IsSecret(playerName)) and playerName or nil
            info.bid = tonumber(bid) or 0
            info.buyout = tonumber(buyout) or 0
            info.deposit = tonumber(deposit) or 0
            info.consignment = tonumber(consignment) or 0
            info.count = (type(count) == "number" and count > 0) and count or 1
        end
    end
    if GetInboxItemLink then
        local okLink, link = pcall(GetInboxItemLink, index, 1)
        if okLink and link and not ns.IsSecret(link) then
            info.itemLink = link
            info.itemID = tonumber(link:match("item:(%d+)"))
        end
    end
    if info.money > 0 or info.invoiceType == "seller" then
        pendingMail = info
    end
end

function Ledger.ScanPendingInbox()
    if not db or not GetInboxNumItems or not GetInboxInvoiceInfo then return end
    local ok, numItems = pcall(GetInboxNumItems)
    if not ok or type(numItems) ~= "number" then return end
    local pendingCopper = 0
    for i = 1, numItems do
        local okInv, invoiceType, _, _, bid, _, deposit, consignment = pcall(GetInboxInvoiceInfo, i)
        if okInv and (invoiceType == "seller_temp_invoice" or invoiceType == "seller") then
            local payout = (tonumber(bid) or 0) + (tonumber(deposit) or 0) - (tonumber(consignment) or 0)
            if payout > 0 then pendingCopper = pendingCopper + payout end
        end
    end
    local charKey = ns.CharKey()
    db.ahPending[charKey] = db.ahPending[charKey] or {}
    db.ahPending[charKey].pendingMailCopper = pendingCopper
    db.ahPending[charKey].updated = time()
end

function Ledger.ScanOwnedAuctions()
    if not db or not C_AuctionHouse or not C_AuctionHouse.GetNumOwnedAuctions then return end
    local ok, n = pcall(C_AuctionHouse.GetNumOwnedAuctions)
    if not ok or type(n) ~= "number" then return end
    local listedCopper, listedCount = 0, 0
    for i = 1, n do
        local okA, info = pcall(C_AuctionHouse.GetOwnedAuctionInfo, i)
        if okA and type(info) == "table" and info.status ~= 1 then -- status 1 = Sold
            listedCount = listedCount + 1
            local qty = (type(info.quantity) == "number" and info.quantity > 0) and info.quantity or 1
            local price = tonumber(info.buyoutAmount) or tonumber(info.bidAmount) or 0
            listedCopper = listedCopper + price * qty
        end
    end
    local charKey = ns.CharKey()
    db.ahPending[charKey] = db.ahPending[charKey] or {}
    db.ahPending[charKey].listedCount = listedCount
    db.ahPending[charKey].listedCopper = listedCopper
    db.ahPending[charKey].updated = time()
end

function Ledger.OnQuestTurnedIn(questID, _, moneyReward)
    if not db or type(moneyReward) ~= "number" or moneyReward <= 0 then return end
    pendingQuest = { amount = moneyReward, at = GetTime(), questID = questID }
    Ledger.RecordCashflow("in", "quest", moneyReward, { note = questID and ("quest:" .. tostring(questID)) or nil })
end

function Ledger.OnAuctionCreated()
    ahDepositUntil = GetTime() + DEPOSIT_WINDOW
end

function Ledger.SetContext(key, active)
    ui[key] = active and true or false
    if key == "mail" and not active then
        pendingMail = nil
        pendingSendMail = nil
    end
end

function Ledger.OnPlayerInteraction(itype, shown)
    if not Enum or not Enum.PlayerInteractionType then return end
    local PIT = Enum.PlayerInteractionType
    if itype == PIT.AccountBanker then ui.accountBank = shown
    elseif itype == PIT.GuildBanker then ui.guildBank = shown
    elseif itype == PIT.Merchant or itype == PIT.Vendor then ui.merchant = shown
    elseif itype == PIT.Auctioneer then ui.ah = shown
    elseif itype == PIT.MailInfo then ui.mail = shown
    elseif itype == PIT.TaxiNode then ui.taxi = shown
    elseif itype == PIT.Trainer then ui.trainer = shown
    elseif itype == PIT.TradePartner then ui.trade = shown
    end
end

-- Master PLAYER_MONEY classifier. Returns true if the delta was already handled as loot coin.
function Ledger.OnPlayerMoney(delta, lootState, onSessionMoney)
    if not db or not delta or delta == 0 then return false end
    local now = GetTime()

    -- 1. Already handled by CHAT_MSG_MONEY a moment ago.
    if delta > 0 and claimedChatMoney and (now - claimedChatMoney.at) <= CLAIM_WINDOW and claimedChatMoney.amount == delta then
        claimedChatMoney = nil
        return true
    end

    -- 2. Loot window coins (when PLAYER_MONEY fires before or without CHAT_MSG_MONEY).
    if delta > 0 and lootState.category and (lootState.open or now <= (lootState.moneyUntil or 0)) then
        recentLootMoney = { amount = delta, at = now }
        local zone = ns.Where()
        local charKey = ns.CharKey()
        Ledger.RecordLootMoney(lootState.category, delta, zone, charKey)
        if onSessionMoney then onSessionMoney(lootState.category, delta) end
        return true
    end

    -- 3. Quest turn-in reward already recorded by QUEST_TURNED_IN.
    if delta > 0 and pendingQuest and (now - pendingQuest.at) <= QUEST_WINDOW and pendingQuest.amount == delta then
        pendingQuest = nil
        return false
    end

    -- 4. Mailbox incoming money (AH sale, alt transfer or regular mail).
    if delta > 0 and pendingMail and (now - pendingMail.at) <= MAIL_GRACE then
        local m = pendingMail
        pendingMail = nil
        if m.invoiceType == "seller" then
            local d = Ledger.EnsureDay()
            local gross = m.bid > 0 and m.bid or delta
            local cut = m.consignment or 0
            local dep = m.deposit or 0
            d.ah.sales = (d.ah.sales or 0) + 1
            d.ah.gross = (d.ah.gross or 0) + gross
            d.ah.cut = (d.ah.cut or 0) + cut
            d.ah.deposit = (d.ah.deposit or 0) + dep
            d.ah.net = (d.ah.net or 0) + delta
            local itemID = m.itemID
            if not itemID and m.itemName and C_Item and C_Item.GetItemInfoInstant then
                local okId, id = pcall(C_Item.GetItemInfoInstant, m.itemName)
                if okId and type(id) == "number" then itemID = id end
            end
            Ledger.RecordCashflow("in", "ah", delta, {
                item = m.itemName,
                itemID = itemID,
                count = m.count or 1,
                counterparty = m.playerName,
                gross = gross,
                cut = cut,
                deposit = dep,
            })
        elseif ns.Wealth and ns.Wealth.OnMailReceived(m.sender, delta) then
            -- Internal alt-to-alt transfer: neutral for account cashflow.
            return false
        else
            Ledger.RecordCashflow("in", "mail", delta, { counterparty = m.sender, note = m.subject })
        end
        return false
    end

    if delta > 0 and ui.mail then
        Ledger.RecordCashflow("in", "mail", delta)
        return false
    end

    -- 5. Mailbox outgoing money (alt transfer vs external mail + postage).
    if delta < 0 and pendingSendMail and (now - pendingSendMail.at) <= MAIL_GRACE then
        local sm = pendingSendMail
        pendingSendMail = nil
        local spent = -delta
        local sent = math.min(spent, sm.money or 0)
        local postage = math.max(0, spent - sent)
        if postage > 0 then
            Ledger.RecordCashflow("out", "mail", postage, { note = "postage" })
        end
        if sent > 0 then
            local internal = ns.Wealth and ns.Wealth.OnMailSent(sm.recipient, sent)
            if not internal then
                Ledger.RecordCashflow("out", "mail", sent, { counterparty = sm.recipient })
            end
        end
        return false
    end

    -- 6. Auction House spending (deposits vs purchases).
    if delta < 0 and ui.ah then
        if now <= ahDepositUntil then
            ahDepositUntil = 0
            Ledger.RecordCashflow("out", "ahDeposit", -delta)
        else
            local d = Ledger.EnsureDay()
            d.ah.buys = (d.ah.buys or 0) + 1
            d.ah.buyTotal = (d.ah.buyTotal or 0) + (-delta)
            Ledger.RecordCashflow("out", "ahBuy", -delta)
        end
        return false
    end

    -- 7. Merchant & Repair.
    if ui.merchant then
        if delta < 0 and now <= repairUntil then
            repairUntil = 0
            Ledger.RecordCashflow("out", "repair", -delta)
        elseif delta > 0 then
            Ledger.RecordCashflow("in", "vendor", delta)
        else
            Ledger.RecordCashflow("out", "vendor", -delta)
        end
        return false
    end

    -- 8. Account bank transfers are internal (neutral for account cashflow).
    if ui.accountBank then
        return false
    end

    -- 9. Taxi, Trainer, Trade.
    if delta < 0 and ui.taxi then
        Ledger.RecordCashflow("out", "taxi", -delta)
        return false
    end
    if delta < 0 and ui.trainer then
        Ledger.RecordCashflow("out", "trainer", -delta)
        return false
    end
    if ui.trade then
        Ledger.RecordCashflow(delta > 0 and "in" or "out", "trade", math.abs(delta))
        return false
    end

    -- 10. Fallback: never lose track of any money change.
    Ledger.RecordCashflow(delta > 0 and "in" or "out", "other", math.abs(delta),
        ui.guildBank and { note = "guildBank" } or nil)
    return false
end

local function InstallHooks()
    if hooksInstalled or type(hooksecurefunc) ~= "function" then return end
    hooksInstalled = true

    if type(_G.TakeInboxMoney) == "function" then
        hooksecurefunc("TakeInboxMoney", function(index)
            CaptureInboxMail(index)
        end)
    end
    if type(_G.AutoLootMailItem) == "function" then
        hooksecurefunc("AutoLootMailItem", function(index)
            CaptureInboxMail(index)
        end)
    end
    if type(_G.SendMail) == "function" then
        hooksecurefunc("SendMail", function(recipient)
            local sendMoney = GetSendMailMoney and GetSendMailMoney() or 0
            local postage = GetSendMailPrice and GetSendMailPrice() or 0
            pendingSendMail = {
                at = GetTime(),
                recipient = (not ns.IsSecret(recipient)) and recipient or nil,
                money = tonumber(sendMoney) or 0,
                postage = tonumber(postage) or 0,
            }
        end)
    end
    if type(_G.RepairAllItems) == "function" then
        hooksecurefunc("RepairAllItems", function(useGuildBank)
            if not useGuildBank then
                repairUntil = GetTime() + REPAIR_WINDOW
            end
        end)
    end
end

function Ledger.Init(database)
    db = database
    db.daily = db.daily or {}
    db.ledger = db.ledger or {}
    db.runs = db.runs or {}
    db.drops = db.drops or {}
    db.ahPending = db.ahPending or {}
    InitPatterns()
    InstallHooks()
end

-- Exposed for tests to clear transient windows between reloads if needed.
function Ledger.ResetTransient()
    pendingMail, pendingSendMail, pendingQuest = nil, nil, nil
    claimedChatMoney, recentLootMoney = nil, nil
    ahDepositUntil, repairUntil = 0, 0
    for k in pairs(ui) do ui[k] = false end
end
