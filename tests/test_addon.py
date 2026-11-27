# /// script
# requires-python = ">=3.11"
# dependencies = ["lupa>=2.0"]
# ///
"""Tests for GoldPerHour without the game: the addon runs in Lua against a stubbed WoW API.

    uv run tests/test_addon.py
    uv run tests/test_addon.py --dump <file>   writes GoldPerHourDB at the end of the main scenario as a
                                               SavedVariables file (test data for the desktop app)
"""

import os
import re
import sys

from lupa.lua54 import LuaRuntime, lua_type

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
NAME = "GoldPerHour"


def read(name):
    with open(os.path.join(ROOT, name), encoding="utf-8") as f:
        return f.read()


def toc():
    """Fields and file list of the .toc."""
    fields, files = {}, []
    for line in read(f"{NAME}.toc").splitlines():
        line = line.strip()
        m = re.match(r"##\s*([^:]+):\s*(.*)$", line)
        if m:
            fields[m.group(1)] = m.group(2)
        elif line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return fields, files


def lua_to_py(x):
    if lua_type(x) != "table":
        return x
    keys = list(x.keys())
    if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        return [lua_to_py(x[k]) for k in sorted(keys)]
    return {k: lua_to_py(x[k]) for k in keys}


def values(x) -> list:
    """Lua tables come back as a list (keys 1..n) or a dict (sparse keys, or empty)."""
    if isinstance(x, list):
        return x
    if isinstance(x, dict):
        return list(x.values())
    return []


# Writes a table the way the client writes SavedVariables, keys sorted so the output is stable.
SERIALIZE = r"""
local function key(k) return type(k) == "number" and ("[" .. k .. "]") or string.format("[%q]", k) end
local function ser(v, indent)
  if type(v) ~= "table" then return type(v) == "string" and string.format("%q", v) or tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) == type(b) then return a < b end
    return type(a) == "number"
  end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = indent .. "\t" .. key(k) .. " = " .. ser(v[k], indent .. "\t") .. "," end
  if #out == 0 then return "{}" end
  return "{\n" .. table.concat(out, "\n") .. "\n" .. indent .. "}"
end
return function(name, v) return name .. " = " .. ser(v, "") .. "\n" end
"""

STUBS = r"""
now, money, zone, locale = 100, 100000, "The Barrens", "enUS"
charName, realmName, charClass = "Tester", "Everlook", "WARLOCK"
inGroup, isFishing, isAFK = false, false, false
instanceInfo = { "Kalimdor", "none", 0, "", 0, 0, false, 0 }
accountBankMoney = 250000
loot = {}
inbox = {}
ownedAuctions = {}
sendMailMoney, sendMailPrice = 0, 30
tickers = {}
timers = {}
handler = nil
local function noop() end
local function record(field) return function(self, v) rawset(self, field, v) end end
local frameMeta = { __index = function(t, k)
  if k == "SetScript" then return function(self, name, fn)
    if name == "OnEvent" then handler = fn end
    local scripts = rawget(self, "scripts") or {}
    scripts[name] = fn
    rawset(self, "scripts", scripts)
  end end
  if k == "SetText" then return record("text") end
  if k == "SetValue" then return record("value") end
  if k == "SetHeight" then return record("height") end
  if k == "SetNormalTexture" then return record("normal") end
  if k == "SetEnabled" then return record("enabled") end
  if k == "Show" then return function(self) self.shown = true end end
  if k == "Hide" then return function(self) self.shown = false end end
  if k == "IsShown" then return function(self) return self.shown ~= false end end
  if k == "SetShown" then return function(self, v) self.shown = v end end
  if k == "SetScale" then return function(self, v) self.scale = v end end
  if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 0, 0 end end
  if k == "GetBottom" then return function() return 300 end end
  if k == "GetFrameLevel" then return function() return 1 end end
  if k == "CreateTexture" or k == "CreateFontString" or k == "CreateLine" then return function() return setmetatable({}, getmetatable(t)) end end
  return noop
end }
function CreateFrame() return setmetatable({}, frameMeta) end
UIParent = CreateFrame()
UISpecialFrames = {}
GameTooltip = setmetatable({ IsOwned = function() return false end }, frameMeta)
function fire(event, ...) handler(nil, event, ...) end
function GetLocale() return locale end
Enum = {
  LootSlotType = { Item = 1 },
  BankType = { Character = 0, Guild = 1, Account = 2 },
  PlayerInteractionType = { TradePartner = 1, Merchant = 5, TaxiNode = 6, Trainer = 7, GuildBanker = 10, Vendor = 12, MailInfo = 17, Auctioneer = 21, AccountBanker = 68 },
}
function GetTime() return now end
function time() return 1763400000 + now end
function date(fmt, ts) return os.date("!" .. fmt, ts or time()) end
function GetMoney() return money end
function GetMoneyString(c) return tostring(c) end
function GetRealZoneText() return zone end
function UnitName() return charName end
function GetRealmName() return realmName end
function UnitClass() return charClass, charClass end
function IsInGroup() return inGroup end
function IsFishingLoot() return isFishing end
function UnitIsAFK() return isAFK end
function GetInstanceInfo() return table.unpack(instanceInfo) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strsplit(sep, s) return s:match("^([^" .. sep .. "]*)") end
StaticPopupDialogs = {}
SlashCmdList = {}
YES, NO = "Yes", "No"
GOLD_AMOUNT = "%d Gold"
SILVER_AMOUNT = "%d Silver"
COPPER_AMOUNT = "%d Copper"
LOOT_MONEY_SPLIT = "Your share of the loot is %s."
LOOT_MONEY_SPLIT_GUILD = "Your share of the loot is %s (%s deposited to guild bank)."
printed = {}
function print(...) printed[#printed + 1] = table.concat({...}, " ") end

-- Hook system matching WoW's hooksecurefunc
function hooksecurefunc(name, hookFn)
  local orig = _G[name]
  _G[name] = function(...)
    local res = { orig(...) }
    hookFn(...)
    return table.unpack(res)
  end
end

C_Timer = {
  NewTicker = function(_, fn) tickers[#tickers + 1] = fn end,
  NewTimer = function(_, fn)
    local handle = { cancelled = false, fn = fn }
    function handle:Cancel() self.cancelled = true end
    timers[#timers + 1] = handle
    return handle
  end,
}
function tick() tickers[#tickers]() end
function flushTimers()
  local cur = timers
  timers = {}
  for _, t in ipairs(cur) do
    if not t.cancelled then t.fn() end
  end
end

C_AddOns = { GetAddOnMetadata = function() return VERSION end }
C_Spell = { GetSpellName = function(id)
  if id == 2366 then return "Herb Gathering" end
  if id == 2575 or id == 32606 then return "Mining" end
  if id == 8613 then return "Skinning" end
  if id == 7620 then return "Fishing" end
  return "Something else"
end }

C_Bank = {
  FetchDepositedMoney = function(bankType)
    if bankType == 2 then return accountBankMoney end
    return 0
  end,
}

-- Item database for valuation tests:
-- 2447 Peacebloom: common herb, vendor 10c, AH 1000c
-- 2770 Copper Ore: common ore, vendor 5c, AH 800c
-- 2318 Light Leather: common leather, vendor 15c, AH 600c
-- 6303 Raw Slitherskin Mackerel: common fish, vendor 4c, AH 400c
-- 9901 Broken Fang: poor grey (q=0), vendor 50c, AH 9999c (must use vendor!)
-- 9902 Boss Soulbound Blade: rare BoP (q=3, bind=1), vendor 15000c, AH 99999c (must use vendor!)
-- 9903 Wolf Pelts Quest: quest item (q=1, class=12, bind=4), vendor 0c, AH 50000c (must use vendor!)
-- 9904 Warbound Token: account-bound (q=3, bind=8), vendor 200c, AH 50000c (must use vendor!)
-- 9905 Cheap BoE Sword: green weapon (q=2, class=2, bind=2), vendor 960c, AH 1000c (effective 950c < 960c -> vendor floor!)
-- 9906 Epic BoE Ring: epic armor (q=4, class=4, bind=2), vendor 20000c, AH 100000c (effective 95000c, triggers top drop!)
ITEMS = {
  [2447] = { name = "Peacebloom", q = 1, sell = 10, cls = 7, bind = 0, ah = 1000 },
  [2770] = { name = "Copper Ore", q = 1, sell = 5, cls = 7, bind = 0, ah = 800 },
  [2318] = { name = "Light Leather", q = 1, sell = 15, cls = 7, bind = 0, ah = 600 },
  [6303] = { name = "Raw Slitherskin Mackerel", q = 1, sell = 4, cls = 7, bind = 0, ah = 400 },
  [9901] = { name = "Broken Fang", q = 0, sell = 50, cls = 15, bind = 0, ah = 9999 },
  [9902] = { name = "Boss Soulbound Blade", q = 3, sell = 15000, cls = 2, bind = 1, ah = 99999 },
  [9903] = { name = "Wolf Pelts Quest", q = 1, sell = 0, cls = 12, bind = 4, ah = 50000 },
  [9904] = { name = "Warbound Token", q = 3, sell = 200, cls = 15, bind = 8, ah = 50000 },
  [9905] = { name = "Cheap BoE Sword", q = 2, sell = 960, cls = 2, bind = 2, ah = 1000 },
  [9906] = { name = "Epic BoE Ring", q = 4, sell = 20000, cls = 4, bind = 2, ah = 100000 },
}

C_Item = {
  GetItemInfo = function(link)
    local id = tonumber(link:match("item:(%d+)"))
    local it = ITEMS[id] or ITEMS[2447]
    return it.name, link, it.q, 5, 0, "", "", 20, "", 0, it.sell, it.cls, 0, it.bind
  end,
  GetItemIconByID = function() return 134400 end,
  GetItemInfoInstant = function(nameOrLink)
    for id, it in pairs(ITEMS) do
      if it.name == nameOrLink then return id end
    end
    return tonumber(tostring(nameOrLink):match("item:(%d+)"))
  end,
}
Item = { CreateFromItemLink = function(_, link)
  return { IsItemEmpty = function() return false end, ContinueOnItemLoad = function(_, fn) fn() end,
           GetItemID = function() return tonumber(link:match("item:(%d+)")) end }
end }
Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function(_, link)
  local id = tonumber(link:match("item:(%d+)"))
  return ITEMS[id] and ITEMS[id].ah or nil
end } } }

function GetNumLootItems() return #loot end
function LootSlotHasItem(i) return loot[i] ~= nil end
function GetLootSourceInfo(i) return loot[i] and loot[i].guid end
function GetLootSlotType(i) return 1 end
function GetLootSlotLink(i) return loot[i] and loot[i].link end
function GetLootSlotInfo(i) return nil, nil, loot[i] and loot[i].qty end

function GetInboxNumItems() return #inbox end
function GetInboxHeaderInfo(i)
  local m = inbox[i]
  if not m then return end
  return nil, nil, m.sender, m.subject, m.money or 0
end
function GetInboxInvoiceInfo(i)
  local m = inbox[i]
  if not m or not m.invoiceType then return nil end
  return m.invoiceType, m.itemName, m.playerName, m.bid or 0, m.buyout or 0, m.deposit or 0, m.consignment or 0, 0, 0, 0, m.count or 1
end
function GetInboxItemLink(i) return inbox[i] and inbox[i].itemLink end
function TakeInboxMoney(i) end
function AutoLootMailItem(i) end
function GetSendMailMoney() return sendMailMoney end
function GetSendMailPrice() return sendMailPrice end
function SendMail(recipient, subject, body) end
function RepairAllItems(useGuild) end

C_AuctionHouse = {
  GetNumOwnedAuctions = function() return #ownedAuctions end,
  GetOwnedAuctionInfo = function(i) return ownedAuctions[i] end,
}
"""


def make_link(item_id, name, color="ffffffff"):
    return f"|c{color}|Hitem:{item_id}::::::::20:::::|h[{name}]|h|r"


LINK = make_link(2447, "Peacebloom")
ORE_LINK = make_link(2770, "Copper Ore")
LEATHER_LINK = make_link(2318, "Light Leather")
FISH_LINK = make_link(6303, "Raw Slitherskin Mackerel")
GREY_LINK = make_link(9901, "Broken Fang", "ff9d9d9d")
BOP_LINK = make_link(9902, "Boss Soulbound Blade", "ff0070dd")
QUEST_LINK = make_link(9903, "Wolf Pelts Quest")
WARBOUND_LINK = make_link(9904, "Warbound Token", "ff0070dd")
FLOOR_LINK = make_link(9905, "Cheap BoE Sword", "ff1eff00")
EPIC_LINK = make_link(9906, "Epic BoE Ring", "ffa335ee")


def new_runtime(locale="enUS"):
    lua = LuaRuntime(register_eval=False)
    lua.execute(STUBS)
    lua.globals().LINK = LINK
    lua.globals().ORE_LINK = ORE_LINK
    lua.globals().LEATHER_LINK = LEATHER_LINK
    lua.globals().FISH_LINK = FISH_LINK
    lua.globals().GREY_LINK = GREY_LINK
    lua.globals().BOP_LINK = BOP_LINK
    lua.globals().QUEST_LINK = QUEST_LINK
    lua.globals().WARBOUND_LINK = WARBOUND_LINK
    lua.globals().FLOOR_LINK = FLOOR_LINK
    lua.globals().EPIC_LINK = EPIC_LINK
    lua.globals().locale = locale
    lua.globals().VERSION = toc()[0]["Version"]
    return lua


def load_addon(lua, request=None):
    """Runs the files of the .toc like the client does on login or /reload: in order, sharing one table."""
    lua.execute("function TakeInboxMoney(i) end; function AutoLootMailItem(i) end; function SendMail(r, s, b) end; function RepairAllItems(u) end")
    load = lua.eval("function(src, name) return assert(load(src, name)) end")
    ns = lua.table()
    for name in toc()[1]:
        if name == "AppRequest.lua":
            lua.execute(f"GoldPerHour_AppRequest = {request or 'nil'}")
        else:
            load(read(name), name)(NAME, ns)
    lua.execute('fire("ADDON_LOADED", "GoldPerHour"); fire("PLAYER_LOGIN")')
    return ns


def printed(lua):
    return values(lua_to_py(lua.globals().printed))


def mob_loot(lua, qty=3, coins=500, link_var="LINK"):
    lua.execute(f"""
      loot = {{ {{ link = {link_var}, qty = {qty}, guid = "Creature-0-1-2-3-4-5" }} }}
      fire("LOOT_READY"); fire("LOOT_OPENED"); fire("LOOT_SLOT_CLEARED", 1)
      money = money + {coins}; fire("PLAYER_MONEY"); loot = {{}}; fire("LOOT_CLOSED")""")


def db(lua):
    return lua_to_py(lua.globals().GoldPerHourDB)


def test_session_reload_request_and_history():
    lua = new_runtime()
    load_addon(lua)
    lua.execute('fire("PLAYER_ENTERING_WORLD", true, false)')
    lua.globals().SlashCmdList.GOLDPERHOUR("start")
    # Default deductAhCut=true: Peacebloom 1000 * 0.95 = 950 -> 3 * 950 + 500 = 3350
    mob_loot(lua)
    # Also do a herb gather and a shared dungeon gold split + epic drop + AH sale + repair + alt transfer
    # so the dumped fixture exercises EVERY dashboard tab in the desktop app!
    lua.execute("""
      fire("UNIT_SPELLCAST_SENT", "player", nil, nil, 2366)
      loot = { { link = LINK, qty = 2, guid = "GameObject-0-1-2-3-4-5" } }
      fire("LOOT_READY"); fire("LOOT_SLOT_CLEARED", 1); loot = {}; fire("LOOT_CLOSED")

      -- Enter a dungeon, get shared gold + roll win + epic BoE drop, then exit
      inGroup = true
      zone = "Shadowfang Keep"
      instanceInfo = { "Shadowfang Keep", "party", 1, "Normal", 5, 0, false, 33 }
      fire("ZONE_CHANGED_NEW_AREA")
      now = now + 120
      fire("CHAT_MSG_MONEY", "Your share of the loot is 1 Gold, 25 Silver.")
      money = money + 12500; fire("PLAYER_MONEY")
      fire("LOOT_ITEM_ROLL_WON", EPIC_LINK, 1)
      now = now + 280; tick()
      inGroup = false
      zone = "The Barrens"
      instanceInfo = { "Kalimdor", "none", 0, "", 0, 0, false, 0 }
      fire("ZONE_CHANGED_NEW_AREA")

      -- Auction House sale collected from mailbox + pending mail + open auctions
      fire("MAIL_SHOW")
      inbox = {
        { sender = "Auction House", subject = "Auction successful: Peacebloom", money = 19000,
          invoiceType = "seller", itemName = "Peacebloom", playerName = "BuyerOne",
          bid = 20000, deposit = 0, consignment = 1000, count = 20 },
        { sender = "Auction House", subject = "Auction pending", money = 0,
          invoiceType = "seller_temp_invoice", itemName = "Copper Ore", playerName = "BuyerTwo",
          bid = 10000, deposit = 0, consignment = 500, count = 10 },
      }
      fire("MAIL_INBOX_UPDATE")
      TakeInboxMoney(1)
      money = money + 19000; fire("PLAYER_MONEY")
      fire("MAIL_CLOSED")

      ownedAuctions = { { quantity = 10, buyoutAmount = 2500, status = 0 } }
      fire("AUCTION_HOUSE_SHOW"); fire("OWNED_AUCTIONS_UPDATED")
      money = money - 4000; fire("PLAYER_MONEY") -- AH purchase
      fire("AUCTION_HOUSE_CLOSED")

      -- Repair at merchant + quest reward
      fire("MERCHANT_SHOW")
      RepairAllItems(false)
      money = money - 1500; fire("PLAYER_MONEY")
      fire("MERCHANT_CLOSED")
      fire("QUEST_TURNED_IN", 42, 500, 3500)
      money = money + 3500; fire("PLAYER_MONEY")
      flushTimers()
    """)

    d = db(lua)
    assert d["gold"]["loot"] == 3 * 950 + 500 and d["coin"]["loot"] == 500, d["gold"]
    assert d["gold"]["herb"] == 2 * 950, d["gold"]
    assert d["gold"]["dungeon"] == 12500 + 95000, d["gold"]
    assert d["session"]["zones"]["The Barrens"] == 3350 + 1900
    assert d["session"]["zones"]["Shadowfang Keep"] == 12500 + 95000
    assert [s[0] for s in values(d["session"]["samples"])] == [0, 400]

    # /reload: PLAYER_LOGOUT pauses and remembers the running session, the new load resumes it.
    lua.execute('fire("PLAYER_LOGOUT")')
    d = db(lua)
    assert d["resume"] is True and d["elapsed"] == 400 and d["updated"]
    load_addon(lua)
    lua.execute('fire("PLAYER_ENTERING_WORLD", false, true); now = now + 100')
    assert any("session continues after /reload" in p for p in printed(lua))
    lua.execute('fire("PLAYER_LOGOUT")')
    assert db(lua)["elapsed"] == 500

    # Add a second character so the wealth dashboard fixture has multiple characters + alt transit!
    lua.execute('charName = "Bankalt"; charClass = "MAGE"; money = 450000; now = now + 60')
    load_addon(lua)
    lua.execute('fire("PLAYER_ENTERING_WORLD", true, false); flushTimers()')
    lua.execute('fire("MAIL_SHOW"); sendMailMoney = 50000; sendMailPrice = 30; SendMail("Tester", "Gold", ""); money = money - 50030; fire("PLAYER_MONEY"); fire("MAIL_CLOSED"); flushTimers()')
    lua.execute('fire("PLAYER_LOGOUT")')

    # Switch back to Tester for request & reset
    lua.execute('charName = "Tester"; charClass = "WARLOCK"; money = 130000; now = now + 60')
    request = '{ id = 7, action = "reset", settings = { scale = 5, tooltipItems = 3, priceSource = "vendor", autoStart = true, shown = false, deductAhCut = false, wealthInterval = 120, herbSpells = { 1234 }, miningSpells = { 9876 }, bogus = 1 } }'
    load_addon(lua, request)
    lua.execute('fire("PLAYER_ENTERING_WORLD", false, true)')
    d = db(lua)
    assert d["lastRequest"]["id"] == 7 and d["lastRequest"]["action"] == "reset" and "error" not in d["lastRequest"]
    assert d["settings"]["scale"] == 2 and d["settings"]["tooltipItems"] == 3 and d["settings"]["priceSource"] == "vendor"
    assert d["settings"]["autoStart"] is True and d["settings"]["deductAhCut"] is False and d["settings"]["wealthInterval"] == 120
    assert d["hidden"] is True and d["herbSpells"] == {1234: True} and d["miningSpells"] == {9876: True}
    assert d["elapsed"] == 0 and d["gold"]["loot"] == 0 and d.get("resume") is None
    hist = values(d["history"])
    assert len(hist) == 1 and hist[0]["elapsed"] == 500 and hist[0]["gold"]["loot"] == 3350
    assert hist[0]["items"]["loot"] == [{"id": 2447, "name": "Peacebloom", "quality": 1, "count": 3, "value": 2850, "vendorValue": 30, "source": "auctionator"}]

    # autoStart: the next loot window starts the session; priceSource vendor values the herb at 10 copper.
    mob_loot(lua, qty=2, coins=0)
    d = db(lua)
    assert d["gold"]["loot"] == 20, d["gold"]

    # The same request id never runs twice, even after another /reload.
    lua.execute('fire("PLAYER_LOGOUT")')
    load_addon(lua, request)
    lua.execute('fire("PLAYER_ENTERING_WORLD", false, true)')
    d = db(lua)
    assert len(values(d["history"])) == 1 and d["gold"]["loot"] == 20

    # Unknown actions are reported back, not raised.
    lua.execute('fire("PLAYER_LOGOUT")')
    load_addon(lua, '{ id = 8, action = "explode" }')
    lua.execute('fire("PLAYER_ENTERING_WORLD", false, true)')
    assert "unknown action" in db(lua)["lastRequest"]["error"]

    lua.execute('flushTimers(); fire("PLAYER_LOGOUT")')
    assert db(lua)["resume"] is True and db(lua)["updated"]
    print("ok test_session_reload_request_and_history")
    return lua


def test_always_on_when_stopped():
    lua = new_runtime()
    load_addon(lua)
    lua.execute('fire("PLAYER_ENTERING_WORLD", true, false)')
    # Session is NOT started! Loot must still go into db.daily and db.drops.
    mob_loot(lua, qty=1, coins=250, link_var="EPIC_LINK")
    d = db(lua)
    assert d["gold"]["loot"] == 0, "live session must stay at 0 when stopped"
    days = d["daily"]
    assert len(days) == 1
    day = next(iter(days.values()))
    assert day["loot"]["loot"]["v"] == 95000 + 250
    assert day["loot"]["loot"]["c"] == 250
    assert day["cashflow"]["income"]["loot"] == 250
    drops = values(d["drops"])
    assert len(drops) == 1 and drops[0]["id"] == 9906 and drops[0]["value"] == 95000
    print("ok test_always_on_when_stopped")


def test_shared_dungeon_gold_and_rolls():
    lua = new_runtime()
    load_addon(lua)
    lua.execute('fire("PLAYER_ENTERING_WORLD", true, false); SlashCmdList.GOLDPERHOUR("start")')
    lua.execute("""
      inGroup = true
      zone = "Deadmines"
      instanceInfo = { "The Deadmines", "party", 1, "Normal", 5, 0, false, 36 }
      fire("ZONE_CHANGED_NEW_AREA")
      now = now + 45
      -- Shared gold: CHAT_MSG_MONEY followed immediately by PLAYER_MONEY -> must count ONCE!
      fire("CHAT_MSG_MONEY", "Your share of the loot is 2 Gold, 10 Silver, 5 Copper.")
      money = money + 21005; fire("PLAYER_MONEY")
      -- Won roll in dungeon (BoP Rare sword -> vendor price 15000c, triggers top drop)
      fire("LOOT_ITEM_ROLL_WON", BOP_LINK, 1)
      -- Leave instance -> archives run
      instanceInfo = { "Westfall", "none", 0, "", 0, 0, false, 0 }
      fire("ZONE_CHANGED_NEW_AREA")
    """)
    d = db(lua)
    assert d["coin"]["dungeon"] == 21005, d["coin"]
    assert d["gold"]["dungeon"] == 21005 + 15000, d["gold"]
    runs = values(d["runs"])
    assert len(runs) == 1
    assert runs[0]["instance"] == "The Deadmines" and runs[0]["dungeonCoin"] == 21005 and runs[0]["rollsWon"] == 1
    assert runs[0]["total"] == 21005 + 15000
    print("ok test_shared_dungeon_gold_and_rolls")


def test_valuation_non_auctionable_and_floor():
    lua = new_runtime()
    ns = load_addon(lua)
    lua.execute('fire("PLAYER_ENTERING_WORLD", true, false)')
    item_value = ns.ItemValue
    # Grey (poor) -> vendor 50c
    v, vv, q, src = item_value(GREY_LINK)
    assert (v, vv, q, src) == (50, 50, 0, "vendor"), (v, vv, q, src)
    # BoP -> vendor 15000c
    v, vv, q, src = item_value(BOP_LINK)
    assert (v, vv, q, src) == (15000, 15000, 3, "vendor"), (v, vv, q, src)
    # Quest item -> vendor 0c (never AH!)
    v, vv, q, src = item_value(QUEST_LINK)
    assert (v, vv, q, src) == (0, 0, 1, "vendor"), (v, vv, q, src)
    # Warbound / account-bound -> vendor 200c
    v, vv, q, src = item_value(WARBOUND_LINK)
    assert (v, vv, q, src) == (200, 200, 3, "vendor"), (v, vv, q, src)
    # Vendor floor: AH 1000 * 0.95 = 950 < vendor 960 -> vendor 960c
    v, vv, q, src = item_value(FLOOR_LINK)
    assert (v, vv, q, src) == (960, 960, 2, "vendor"), (v, vv, q, src)
    # Normal AH item with 5% cut: 1000 * 0.95 = 950c, vendor 10c
    v, vv, q, src = item_value(LINK)
    assert (v, vv, q, src) == (950, 10, 1, "auctionator"), (v, vv, q, src)
    # Disable 5% cut -> full 1000c; Cheap BoE Sword now 1000 > 960 -> auctionator
    lua.execute("GoldPerHourDB.settings.deductAhCut = false")
    v, vv, q, src = item_value(FLOOR_LINK)
    assert (v, vv, q, src) == (1000, 960, 2, "auctionator"), (v, vv, q, src)
    # BoE min value threshold: ahMinValue = 5000 -> Cheap BoE Sword (1000 < 5000) falls back to vendor
    lua.execute("GoldPerHourDB.settings.ahMinValue = 5000")
    v, vv, q, src = item_value(FLOOR_LINK)
    assert (v, vv, q, src) == (960, 960, 2, "vendor"), (v, vv, q, src)
    print("ok test_valuation_non_auctionable_and_floor")


def test_gathering_professions_and_dynamic_bars():
    lua = new_runtime()
    ns = load_addon(lua)
    ui = ns.ui
    lua.execute('fire("PLAYER_ENTERING_WORLD", true, false); SlashCmdList.GOLDPERHOUR("start")')
    # Idle/empty shows 2 default bars (herb, loot)
    assert values(lua_to_py(ui.visibleBars)) == ["herb", "loot"]
    # Herb gathering
    lua.execute("""
      fire("UNIT_SPELLCAST_SENT", "player", nil, nil, 2366)
      loot = { { link = LINK, qty = 2, guid = "GameObject-0-1-2-3-4-5" } }
      fire("LOOT_READY"); fire("LOOT_SLOT_CLEARED", 1); loot = {}; fire("LOOT_CLOSED")
    """)
    assert values(lua_to_py(ui.visibleBars)) == ["herb"]
    # Mining
    lua.execute("""
      fire("UNIT_SPELLCAST_SENT", "player", nil, nil, 2575)
      loot = { { link = ORE_LINK, qty = 2, guid = "GameObject-0-1-2-3-4-5" } }
      fire("LOOT_READY"); fire("LOOT_SLOT_CLEARED", 1); loot = {}; fire("LOOT_CLOSED")
    """)
    # Skinning (Creature source)
    lua.execute("""
      fire("UNIT_SPELLCAST_SENT", "player", nil, nil, 8613)
      loot = { { link = LEATHER_LINK, qty = 1, guid = "Creature-0-1-2-3-4-5" } }
      fire("LOOT_READY"); fire("LOOT_SLOT_CLEARED", 1); loot = {}; fire("LOOT_CLOSED")
    """)
    # Fishing (IsFishingLoot)
    lua.execute("""
      isFishing = true
      loot = { { link = FISH_LINK, qty = 1, guid = "GameObject-0-1-2-3-4-5" } }
      fire("LOOT_READY"); fire("LOOT_SLOT_CLEARED", 1); loot = {}; fire("LOOT_CLOSED")
      isFishing = false
    """)
    d = db(lua)
    assert d["gold"]["herb"] == 2 * 950
    assert d["gold"]["mining"] == 2 * 760
    assert d["gold"]["skinning"] == 570
    assert d["gold"]["fishing"] == 380
    assert values(lua_to_py(ui.visibleBars)) == ["herb", "mining", "skinning", "fishing"]
    print("ok test_gathering_professions_and_dynamic_bars")


def test_auction_house_and_cashflow():
    lua = new_runtime()
    load_addon(lua)
    lua.execute('fire("PLAYER_ENTERING_WORLD", true, false)')
    lua.execute("""
      -- AH sale via mailbox
      fire("MAIL_SHOW")
      inbox = { { sender = "Auction House", subject = "Auction successful", money = 9500,
        invoiceType = "seller", itemName = "Peacebloom", playerName = "Alice",
        bid = 10000, deposit = 0, consignment = 500, count = 10 } }
      TakeInboxMoney(1)
      money = money + 9500; fire("PLAYER_MONEY")
      fire("MAIL_CLOSED")
      -- AH deposit & purchase
      fire("AUCTION_HOUSE_SHOW")
      fire("AUCTION_HOUSE_AUCTION_CREATED")
      money = money - 120; fire("PLAYER_MONEY")
      money = money - 3000; fire("PLAYER_MONEY")
      fire("AUCTION_HOUSE_CLOSED")
      -- Repair + vendor sell + vendor buy
      fire("MERCHANT_SHOW")
      RepairAllItems(false)
      money = money - 800; fire("PLAYER_MONEY")
      money = money + 450; fire("PLAYER_MONEY")
      money = money - 200; fire("PLAYER_MONEY")
      fire("MERCHANT_CLOSED")
      -- Quest + Taxi + Trainer
      fire("QUEST_TURNED_IN", 101, 0, 2000)
      money = money + 2000; fire("PLAYER_MONEY")
      fire("TAXIMAP_OPENED"); money = money - 150; fire("PLAYER_MONEY"); fire("TAXIMAP_CLOSED")
      fire("TRAINER_SHOW"); money = money - 500; fire("PLAYER_MONEY"); fire("TRAINER_CLOSED")
    """)
    d = db(lua)
    day = next(iter(d["daily"].values()))
    assert day["ah"]["sales"] == 1 and day["ah"]["gross"] == 10000 and day["ah"]["cut"] == 500 and day["ah"]["net"] == 9500
    assert day["ah"]["buys"] == 1 and day["ah"]["buyTotal"] == 3000
    inc, exp = day["cashflow"]["income"], day["cashflow"]["expense"]
    assert inc["ah"] == 9500 and inc["vendor"] == 450 and inc["quest"] == 2000
    assert exp["ahDeposit"] == 120 and exp["ahBuy"] == 3000 and exp["repair"] == 800
    assert exp["vendor"] == 200 and exp["taxi"] == 150 and exp["trainer"] == 500
    print("ok test_auction_house_and_cashflow")


def test_wealth_transit_and_compaction():
    lua = new_runtime()
    ns = load_addon(lua)
    lua.execute('fire("PLAYER_ENTERING_WORLD", true, false); flushTimers()')
    # Initial: Tester 100000 + accountBank 250000 = 350000
    assert ns.Wealth.Total()[0] == 350000

    # Login second char Bankalt with 200000 -> total 550000
    lua.execute('fire("PLAYER_LOGOUT"); charName = "Bankalt"; money = 200000; now = now + 60')
    ns = load_addon(lua)
    lua.execute('fire("PLAYER_ENTERING_WORLD", true, false); flushTimers()')
    assert ns.Wealth.Total()[0] == 550000

    # Bankalt mails 50000 (+30c postage) to Tester -> transit holds 50000 so total only drops by 30c postage!
    lua.execute("""
      fire("MAIL_SHOW")
      sendMailMoney = 50000; sendMailPrice = 30
      SendMail("Tester", "Funds", "")
      money = money - 50030; fire("PLAYER_MONEY")
      fire("MAIL_CLOSED")
      flushTimers()
    """)
    d = db(lua)
    assert len(values(d["wealth"]["transit"])) == 1
    assert ns.Wealth.Total()[0] == 549970, ns.Wealth.Total()

    # Tester logs in and collects the 50000 from Bankalt -> transit resolves, total stays 549970, not counted as income!
    lua.execute('fire("PLAYER_LOGOUT"); charName = "Tester"; money = 100000; now = now + 60')
    ns = load_addon(lua)
    lua.execute("""
      fire("PLAYER_ENTERING_WORLD", true, false)
      fire("MAIL_SHOW")
      inbox = { { sender = "Bankalt", subject = "Funds", money = 50000 } }
      TakeInboxMoney(1)
      money = money + 50000; fire("PLAYER_MONEY")
      fire("MAIL_CLOSED")
      flushTimers()
    """)
    d = db(lua)
    assert len(values(d["wealth"]["transit"])) == 0
    assert ns.Wealth.Total()[0] == 549970
    day = next(iter(d["daily"].values()))
    assert day["cashflow"]["income"].get("mail", 0) == 0, "alt transfer must not count as mail income"

    # Compaction test: 3-tier reduction keeps recent fine, 7-30d hourly, >30d daily.
    compact = lua.eval("""function(fn)
      local nowTs = 1763400000
      local pts = {}
      -- 40 days ago: 10 points on same day -> should collapse to 1 (plus first point kept)
      local oldDay = nowTs - 40 * 86400
      for i = 0, 9 do pts[#pts + 1] = { oldDay + i * 600, 1000 + i } end
      -- 15 days ago: 4 points in same hour -> should collapse to 1
      local midHour = math.floor((nowTs - 15 * 86400) / 3600) * 3600
      for i = 0, 3 do pts[#pts + 1] = { midHour + i * 300, 2000 + i } end
      -- 1 day ago: 5 points -> all kept
      local recent = nowTs - 86400
      for i = 0, 4 do pts[#pts + 1] = { recent + i * 60, 3000 + i } end
      return fn(pts, nowTs)
    end""")(ns.Wealth.CompactHistory)
    res = values(lua_to_py(compact))
    assert len(res) < 12 and len(res) >= 7, len(res)
    print("ok test_wealth_transit_and_compaction")


def test_login_does_not_resume():
    lua = new_runtime()
    load_addon(lua)
    lua.execute('fire("PLAYER_ENTERING_WORLD", true, false); SlashCmdList.GOLDPERHOUR("start"); now = now + 60; fire("PLAYER_LOGOUT")')
    load_addon(lua)
    lua.execute('fire("PLAYER_ENTERING_WORLD", true, false); now = now + 60; fire("PLAYER_LOGOUT")')
    d = db(lua)
    assert d["elapsed"] == 60 and d.get("resume") is None
    print("ok test_login_does_not_resume")


def test_locales():
    texts = {}
    for locale in ("enUS", "deDE", "frFR"):
        lua = new_runtime(locale)
        texts[locale] = lua_to_py(load_addon(lua).L)
    assert texts["frFR"] == texts["enUS"], "an unknown locale falls back to English"
    assert texts["deDE"].keys() == texts["enUS"].keys(), (set(texts["enUS"]) ^ set(texts["deDE"]))
    assert texts["deDE"]["perHour"] == "pro Stunde" and texts["enUS"]["perHour"] == "per hour"
    for key, text in texts["enUS"].items():
        assert re.findall(r"%[ds]", text) == re.findall(r"%[ds]", texts["deDE"][key]), key

    lua = new_runtime("deDE")
    load_addon(lua)
    lua.execute('fire("PLAYER_ENTERING_WORLD", true, false)')
    lua.globals().SlashCmdList.GOLDPERHOUR("herbid 99")
    lua.globals().SlashCmdList.GOLDPERHOUR("miningid 88")
    lua.globals().SlashCmdList.GOLDPERHOUR("nonsense")
    out = printed(lua)
    assert any("Zauber 99 zählt jetzt als Kräutersammeln" in p for p in out), out
    assert any("Zauber 88 zählt jetzt als Bergbau" in p for p in out), out
    assert any("<ID>" in p for p in out), out
    print("ok test_locales")


def test_window_and_stats_frame():
    lua = new_runtime()
    ns = load_addon(lua)
    ui = ns.ui
    lua.globals().UI = ui
    lua.execute('fire("PLAYER_ENTERING_WORLD", true, false)')

    def refresh(seconds=0):
        lua.execute(f"now = now + {seconds}; UI.frame.scripts.OnUpdate(UI.frame, 1)")

    refresh()
    assert ui.state == "idle", ui.state
    assert "Press start to count your gold" in ui.session.text and ui.clock.text == ""
    assert "--" in ui.perHour.text and ui.perHourLabel.text == "per hour"
    assert ui.reset.enabled is False and ui.toggle.normal.endswith("NextPage-Up")

    lua.execute("UI.toggle.scripts.OnClick(UI.toggle)")
    mob_loot(lua)
    refresh(30)
    assert ui.state == "running" and db(lua)["elapsed"] == 0
    assert ui.toggle.normal.endswith("PauseButton") and ui.reset.enabled is True
    assert "--" in ui.perHour.text and ui.perHourLabel.text == "per hour after 1 minute"
    assert "0:00:30" in ui.clock.text and "3350" in ui.session.text

    # After 90 s: 3350 / 90 * 3600 = 134000
    refresh(60)
    assert ui.perHour.text == "134000" and ui.perHourLabel.text == "per hour", ui.perHour.text

    # Tooltips, compact footer & 6-tab stats dashboard
    assert "Today:" in ui.footerLeft.text and "Account:" in ui.footerRight.text
    lua.execute("""UI.frame.scripts.OnEnter(UI.frame, true); UI.bars.loot.scripts.OnEnter(UI.bars.loot, true)
      UI.toggle.scripts.OnEnter(UI.toggle, true); UI.reset.scripts.OnEnter(UI.reset, true)
      UI.close.scripts.OnEnter(UI.close, true); UI.stats.scripts.OnEnter(UI.stats, true)""")
    lua.execute('UI.frame.scripts.OnMouseUp(UI.frame, "RightButton")')
    assert ns.statsUi.frame.shown is True
    for tab in ("overview", "wealth", "loot", "ah", "cashflow", "settings"):
        ns.Stats.Show(tab)
    assert ns.statsUi.kpis[1].value.text is not None
    # Scroll wheel + mouseover on first row work without errors
    ns.Stats.Show("overview")
    lua.execute("ns_stats = ...; ns_stats.frame.scripts.OnMouseWheel(ns_stats.frame, -1); ns_stats.rows[1].scripts.OnEnter(ns_stats.rows[1])", ns.statsUi)
    lua.globals().SlashCmdList.GOLDPERHOUR("stats")  # toggle off
    assert ns.statsUi.frame.shown is False

    # Pause, reset, close
    lua.execute("UI.toggle.scripts.OnClick(UI.toggle)")
    refresh(100)
    assert ui.state == "paused" and db(lua)["elapsed"] == 90
    lua.globals().SlashCmdList.GOLDPERHOUR("reset")
    assert ui.state == "idle" and ui.reset.enabled is False and len(values(db(lua)["history"])) == 1
    lua.execute("UI.close.scripts.OnClick(UI.close)")
    assert db(lua)["hidden"] is True and ui.frame.shown is False
    print("ok test_window_and_stats_frame")


def test_toc():
    fields, files = toc()
    assert fields["Interface"] == "16001" and re.fullmatch(r"\d+\.\d+\.\d+", fields["Version"]), fields
    assert files and files[-1] == f"{NAME}.lua"
    for name in files:
        assert os.path.isfile(os.path.join(ROOT, name)), f"{name} is listed in the .toc but missing"
    for name in os.listdir(ROOT):
        if name.endswith((".lua", ".xml")):
            assert name in files, f"{name} is not listed in the .toc"
    print("ok test_toc")


if __name__ == "__main__":
    final = test_session_reload_request_and_history()
    test_always_on_when_stopped()
    test_shared_dungeon_gold_and_rolls()
    test_valuation_non_auctionable_and_floor()
    test_gathering_professions_and_dynamic_bars()
    test_auction_house_and_cashflow()
    test_wealth_transit_and_compaction()
    test_login_does_not_resume()
    test_locales()
    test_window_and_stats_frame()
    test_toc()
    if "--dump" in sys.argv:
        target = sys.argv[sys.argv.index("--dump") + 1]
        text = final.execute(SERIALIZE)("GoldPerHourDB", final.globals().GoldPerHourDB)
        os.makedirs(os.path.dirname(os.path.abspath(target)), exist_ok=True)
        with open(target, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n" + text)
        print(f"written: {target}")
