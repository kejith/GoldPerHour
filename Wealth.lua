-- Wealth history per character, Warband/Account bank, in-transit alt mail and 3-tier history compaction.
local _, ns = ...

local Wealth = {}
ns.Wealth = Wealth

local DEBOUNCE_SECONDS = 2
local HEARTBEAT_IDLE_SECONDS = 3600
local FINE_AGE = 7 * 86400
local HOURLY_AGE = 30 * 86400
local TRANSIT_MAX_AGE = 30 * 86400
local COMPACT_THRESHOLD = 300

local db
local debounceTimer
local lastIntervalAt = 0

local function NormalizeName(s)
    if not s or s == "" then return "" end
    return (s:lower():gsub("[%s%-]", ""))
end

-- Returns charKey ("Name-Realm"), name, realm, classToken.
function ns.CharKey()
    local name = UnitName and UnitName("player") or "?"
    if not name or name == "" or ns.IsSecret(name) then name = "?" end
    local realm = GetRealmName and GetRealmName() or ""
    if not realm or ns.IsSecret(realm) then realm = "" end
    local classToken = UnitClass and select(2, UnitClass("player")) or nil
    if ns.IsSecret(classToken) then classToken = nil end
    local key = realm ~= "" and (name .. "-" .. realm) or name
    return key, name, realm, classToken
end

-- 3-tier compaction: <=7d keep all, 7-30d keep last per hour, >30d keep last per calendar day.
function Wealth.CompactHistory(list, nowTs)
    if type(list) ~= "table" or #list <= 2 then return list end
    nowTs = nowTs or time()
    local out = {}
    local lastBucketKey, lastBucketIndex

    local function push(pt, bucketKey)
        if bucketKey and bucketKey == lastBucketKey and lastBucketIndex then
            out[lastBucketIndex] = pt
        else
            out[#out + 1] = pt
            lastBucketKey = bucketKey
            lastBucketIndex = bucketKey and #out or nil
        end
    end

    for i = 1, #list do
        local pt = list[i]
        if type(pt) == "table" and type(pt[1]) == "number" and type(pt[2]) == "number" then
            local age = nowTs - pt[1]
            if i == 1 or i == #list or age <= FINE_AGE then
                -- Keep first, last, and all points within the last 7 days (dedup identical timestamp).
                if #out > 0 and out[#out][1] == pt[1] then
                    out[#out] = pt
                else
                    push(pt, nil)
                end
            elseif age <= HOURLY_AGE then
                push(pt, "h:" .. tostring(math.floor(pt[1] / 3600)))
            else
                local day = date("%Y-%m-%d", pt[1])
                push(pt, "d:" .. tostring(day))
            end
        end
    end
    return out
end

local function AppendPoint(list, ts, money, force)
    local last = list[#list]
    if last then
        if last[1] == ts then
            last[2] = money
            return false
        end
        if not force and last[2] == money and (ts - last[1]) < HEARTBEAT_IDLE_SECONDS then
            return false
        end
    end
    list[#list + 1] = { ts, money }
    return true
end

function Wealth.FetchAccountBank()
    if not (C_Bank and C_Bank.FetchDepositedMoney and Enum and Enum.BankType and Enum.BankType.Account ~= nil) then
        return nil
    end
    local ok, amount = pcall(C_Bank.FetchDepositedMoney, Enum.BankType.Account)
    if ok and type(amount) == "number" and not ns.IsSecret(amount) and amount >= 0 then
        return amount
    end
    return nil
end

local function PruneTransit(nowTs)
    if not db or not db.wealth then return end
    local transit = db.wealth.transit
    local i = 1
    while i <= #transit do
        local entry = transit[i]
        if not entry or (nowTs - (entry.sentAt or 0)) > TRANSIT_MAX_AGE then
            table.remove(transit, i)
        else
            i = i + 1
        end
    end
end

function Wealth.Init(database)
    db = database
    db.wealth = db.wealth or {}
    local w = db.wealth
    w.chars = w.chars or {}
    w.accountBank = w.accountBank or { money = 0, updated = 0, history = {} }
    w.accountBank.history = w.accountBank.history or {}
    w.transit = w.transit or {}
    w.accountHistory = w.accountHistory or {}
    w.nextTransitId = w.nextTransitId or 1

    local nowTs = time()
    PruneTransit(nowTs)
    for _, c in pairs(w.chars) do
        if type(c) == "table" and type(c.history) == "table" and #c.history > COMPACT_THRESHOLD then
            c.history = Wealth.CompactHistory(c.history, nowTs)
        end
    end
    if #w.accountHistory > COMPACT_THRESHOLD then
        w.accountHistory = Wealth.CompactHistory(w.accountHistory, nowTs)
    end
    if #w.accountBank.history > COMPACT_THRESHOLD then
        w.accountBank.history = Wealth.CompactHistory(w.accountBank.history, nowTs)
    end
end

function Wealth.Total()
    if not db or not db.wealth then return 0, 0, 0, 0 end
    local w = db.wealth
    local charsTotal = 0
    for _, c in pairs(w.chars) do
        if type(c) == "table" and type(c.money) == "number" then
            charsTotal = charsTotal + c.money
        end
    end
    local bankMoney = (w.accountBank and type(w.accountBank.money) == "number") and w.accountBank.money or 0
    local transitTotal = 0
    for _, tr in ipairs(w.transit) do
        if type(tr) == "table" and type(tr.amount) == "number" then
            transitTotal = transitTotal + tr.amount
        end
    end
    return charsTotal + bankMoney + transitTotal, charsTotal, bankMoney, transitTotal
end

function Wealth.CharMoney(charKey)
    if not db or not db.wealth then return 0 end
    charKey = charKey or ns.CharKey()
    local c = db.wealth.chars[charKey]
    return (c and c.money) or 0
end

-- Compute wealth change relative to `seconds` ago using a history list `{ {t, money}, ... }`.
function Wealth.Delta(list, seconds, currentVal)
    if type(list) ~= "table" or #list == 0 then return nil end
    local cutoff = time() - seconds
    local baseline = list[1][2]
    for i = #list, 1, -1 do
        if list[i][1] <= cutoff then
            baseline = list[i][2]
            break
        end
    end
    if currentVal == nil then currentVal = list[#list][2] end
    return currentVal - baseline
end

local function EnsureCharEntry(nowTs)
    local key, name, realm, classToken = ns.CharKey()
    local entry = db.wealth.chars[key]
    if not entry then
        entry = { name = name, realm = realm, class = classToken, money = 0, updated = nowTs, history = {} }
        db.wealth.chars[key] = entry
    else
        entry.name = name
        if realm ~= "" then entry.realm = realm end
        if classToken then entry.class = classToken end
        entry.history = entry.history or {}
    end
    return key, entry
end

function Wealth.Record(reason)
    if not db or not db.wealth then return end
    local money = GetMoney and GetMoney() or nil
    if type(money) ~= "number" or ns.IsSecret(money) then return end
    local nowTs = time()
    PruneTransit(nowTs)

    local _, entry = EnsureCharEntry(nowTs)
    entry.money = money
    entry.updated = nowTs
    local force = (reason == "login" and #entry.history == 0)
    if AppendPoint(entry.history, nowTs, money, force) and #entry.history > COMPACT_THRESHOLD then
        entry.history = Wealth.CompactHistory(entry.history, nowTs)
    end

    local bank = Wealth.FetchAccountBank()
    if bank ~= nil then
        db.wealth.accountBank.money = bank
        db.wealth.accountBank.updated = nowTs
        if AppendPoint(db.wealth.accountBank.history, nowTs, bank, false)
            and #db.wealth.accountBank.history > COMPACT_THRESHOLD then
            db.wealth.accountBank.history = Wealth.CompactHistory(db.wealth.accountBank.history, nowTs)
        end
    end

    local total = Wealth.Total()
    local forceAcc = (reason == "login" and #db.wealth.accountHistory == 0)
    if AppendPoint(db.wealth.accountHistory, nowTs, total, forceAcc)
        and #db.wealth.accountHistory > COMPACT_THRESHOLD then
        db.wealth.accountHistory = Wealth.CompactHistory(db.wealth.accountHistory, nowTs)
    end
    lastIntervalAt = nowTs
    if ns.Stats and ns.Stats.RefreshIfShown then ns.Stats.RefreshIfShown() end
end

local function ScheduleRecord()
    if debounceTimer and debounceTimer.Cancel then
        debounceTimer:Cancel()
        debounceTimer = nil
    end
    if C_Timer and C_Timer.NewTimer then
        debounceTimer = C_Timer.NewTimer(DEBOUNCE_SECONDS, function()
            debounceTimer = nil
            Wealth.Record("change")
        end)
    else
        Wealth.Record("change")
    end
end

function Wealth.OnMoneyChanged()
    if not db or not db.wealth then return end
    local money = GetMoney and GetMoney() or nil
    if type(money) == "number" and not ns.IsSecret(money) then
        local nowTs = time()
        local _, entry = EnsureCharEntry(nowTs)
        entry.money = money
        entry.updated = nowTs
    end
    ScheduleRecord()
end

function Wealth.OnAccountMoney()
    if not db or not db.wealth then return end
    local bank = Wealth.FetchAccountBank()
    if bank ~= nil then
        db.wealth.accountBank.money = bank
        db.wealth.accountBank.updated = time()
    end
    ScheduleRecord()
end

function Wealth.OnTicker()
    if not db or not db.wealth then return end
    local interval = ns.Setting("wealthInterval") or 300
    if interval < 60 then interval = 60 end
    if (time() - lastIntervalAt) >= interval then
        Wealth.Record("interval")
    end
end

-- Flush any pending debounced snapshot (called safely before logout only if we already cached money).
function Wealth.FlushPending()
    if debounceTimer and debounceTimer.Cancel then
        debounceTimer:Cancel()
        debounceTimer = nil
    end
end

function Wealth.FindOwnChar(recipient)
    if not db or not db.wealth or not recipient or recipient == "" then return nil end
    local _, _, myRealm = ns.CharKey()
    local target = NormalizeName(recipient)
    local targetWithRealm = recipient:find("-") and target or NormalizeName(recipient .. "-" .. myRealm)
    for key, c in pairs(db.wealth.chars) do
        if NormalizeName(key) == target or NormalizeName(key) == targetWithRealm then
            return key
        end
        if c and c.name and (c.realm or "") == myRealm and NormalizeName(c.name) == target then
            return key
        end
    end
    return nil
end

-- Track gold mailed to another character on the same account so account wealth does not dip.
function Wealth.OnMailSent(recipient, copper)
    if not db or not db.wealth or not copper or copper <= 0 then return false, nil end
    local toKey = Wealth.FindOwnChar(recipient)
    local fromKey = ns.CharKey()
    if not toKey or toKey == fromKey then return false, nil end
    local id = db.wealth.nextTransitId or 1
    db.wealth.nextTransitId = id + 1
    db.wealth.transit[#db.wealth.transit + 1] = {
        id = id,
        from = fromKey,
        to = toKey,
        amount = copper,
        sentAt = time(),
    }
    return true, toKey
end

-- Resolve an in-transit alt transfer when the receiving character loots the mail.
function Wealth.OnMailReceived(sender, copper)
    if not db or not db.wealth or not copper or copper <= 0 then return false end
    local myKey = ns.CharKey()
    local senderKey = sender and Wealth.FindOwnChar(sender) or nil
    local senderNorm = sender and NormalizeName(sender) or ""
    for i, tr in ipairs(db.wealth.transit) do
        if tr.to == myKey and tr.amount == copper then
            local matchSender = (not sender or sender == "")
                or (senderKey and tr.from == senderKey)
                or (NormalizeName(tr.from) == senderNorm)
                or (db.wealth.chars[tr.from] and NormalizeName(db.wealth.chars[tr.from].name) == senderNorm)
            if matchSender then
                table.remove(db.wealth.transit, i)
                return true
            end
        end
    end
    return false
end
