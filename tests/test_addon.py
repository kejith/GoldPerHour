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

# Just enough of the client for GoldPerHour.lua: frames swallow every method, events go to the frame of
# the last load (a /reload re-runs the file against the same GoldPerHourDB). Widgets remember their scripts,
# texts, bar values, button textures and whether they are enabled, so the tests can read the window.
STUBS = r"""
now, money, zone, locale = 100, 10000, "The Barrens", "enUS"
loot = {}
tickers = {}
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
  if k == "SetNormalTexture" then return record("normal") end
  if k == "SetEnabled" then return record("enabled") end
  if k == "IsShown" then return function(self) return self.shown ~= false end end
  if k == "SetShown" then return function(self, v) self.shown = v end end
  if k == "SetScale" then return function(self, v) self.scale = v end end
  if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 0, 0 end end
  if k == "GetBottom" then return function() return 300 end end
  if k == "GetFrameLevel" then return function() return 1 end end
  if k == "CreateTexture" or k == "CreateFontString" then return function() return setmetatable({}, getmetatable(t)) end end
  return noop
end }
function CreateFrame() return setmetatable({}, frameMeta) end
UIParent = CreateFrame()
GameTooltip = setmetatable({ IsOwned = function() return false end }, frameMeta)
function fire(event, ...) handler(nil, event, ...) end
function GetLocale() return locale end
Enum = { LootSlotType = { Item = 1 } }
function GetTime() return now end
function time() return 1763400000 + now end
function GetMoney() return money end
function GetMoneyString(c) return tostring(c) end
function GetRealZoneText() return zone end
function UnitName() return "Tester" end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strsplit(sep, s) return s:match("^([^" .. sep .. "]*)") end
StaticPopupDialogs = {}
SlashCmdList = {}
YES, NO = "Yes", "No"
printed = {}
function print(...) printed[#printed + 1] = table.concat({...}, " ") end
C_Timer = { NewTicker = function(_, fn) tickers[#tickers + 1] = fn end }
function tick() tickers[#tickers]() end
C_AddOns = { GetAddOnMetadata = function() return VERSION end }
C_Spell = { GetSpellName = function(id) return id == 2366 and "Herb Gathering" or "Something else" end }
-- Item 2447 (Peacebloom): sells for 10 copper, Auctionator says 1000.
C_Item = {
  GetItemInfo = function(link) return "Peacebloom", link, 1, 5, 0, "", "", 20, "", 0, 10, 7, 9, 0 end,
  GetItemIconByID = function() return 134400 end,
}
Item = { CreateFromItemLink = function(_, link)
  return { IsItemEmpty = function() return false end, ContinueOnItemLoad = function(_, fn) fn() end,
           GetItemID = function() return tonumber(link:match("item:(%d+)")) end }
end }
Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function() return 1000 end } } }
function GetNumLootItems() return #loot end
function LootSlotHasItem(i) return loot[i] ~= nil end
function GetLootSourceInfo(i) return loot[i] and loot[i].guid end
function GetLootSlotType(i) return 1 end
function GetLootSlotLink(i) return loot[i] and loot[i].link end
function GetLootSlotInfo(i) return nil, nil, loot[i] and loot[i].qty end
"""

LINK = "|cffffffff|Hitem:2447::::::::20:::::|h[Peacebloom]|h|r"


def new_runtime(locale="enUS"):
    lua = LuaRuntime(register_eval=False)
    lua.execute(STUBS)
    lua.globals().LINK = LINK
    lua.globals().locale = locale
    lua.globals().VERSION = toc()[0]["Version"]
    return lua


def load_addon(lua, request=None):
    """Runs the files of the .toc like the client does on login or /reload: in order, sharing one table."""
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


def mob_loot(lua, qty=3, coins=500):
    lua.execute(f"""
      loot = {{ {{ link = LINK, qty = {qty}, guid = "Creature-0-1-2-3-4-5" }} }}
      fire("LOOT_READY"); fire("LOOT_OPENED"); fire("LOOT_SLOT_CLEARED", 1)
      money = money + {coins}; fire("PLAYER_MONEY"); loot = {{}}; fire("LOOT_CLOSED")""")


def db(lua):
    return lua_to_py(lua.globals().GoldPerHourDB)


def test_session_reload_request_and_history():
    lua = new_runtime()
    load_addon(lua)
    lua.execute('fire("PLAYER_ENTERING_WORLD", true, false)')
    lua.globals().SlashCmdList.GOLDPERHOUR("start")
    mob_loot(lua)
    lua.execute("now = now + 400; tick()")
    d = db(lua)
    assert d["gold"]["loot"] == 3 * 1000 + 500 and d["coin"]["loot"] == 500, d["gold"]
    assert d["session"]["zones"] == {"The Barrens": 3500} and d["session"]["chars"] == {"Tester": True}
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

    # Next /reload carries an app request: settings and a reset, which archives the session.
    request = '{ id = 7, action = "reset", settings = { scale = 5, tooltipItems = 3, priceSource = "vendor", autoStart = true, shown = false, herbSpells = { 1234 }, bogus = 1 } }'
    load_addon(lua, request)
    lua.execute('fire("PLAYER_ENTERING_WORLD", false, true)')
    d = db(lua)
    assert d["lastRequest"]["id"] == 7 and d["lastRequest"]["action"] == "reset" and "error" not in d["lastRequest"]
    assert d["settings"] == {"scale": 2, "tooltipItems": 3, "priceSource": "vendor", "autoStart": True}, d["settings"]
    assert d["hidden"] is True and d["herbSpells"] == {1234: True}
    assert d["elapsed"] == 0 and d["gold"]["loot"] == 0 and d.get("resume") is None
    hist = values(d["history"])
    assert len(hist) == 1 and hist[0]["elapsed"] == 500 and hist[0]["gold"]["loot"] == 3500
    assert hist[0]["items"]["loot"] == [{"id": 2447, "name": "Peacebloom", "quality": 1, "count": 3, "value": 3000}]

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

    # The state the client would now write to disk; --dump saves it as test data for the desktop app.
    lua.execute('fire("PLAYER_LOGOUT")')
    assert db(lua)["resume"] is True and db(lua)["updated"]
    print("ok test_session_reload_request_and_history")
    return lua


def test_herb_gathering():
    lua = new_runtime()
    load_addon(lua)
    lua.execute("""fire("PLAYER_ENTERING_WORLD", true, false)
      SlashCmdList.GOLDPERHOUR("start")
      fire("UNIT_SPELLCAST_SENT", "player", nil, nil, 2366)
      loot = { { link = LINK, qty = 2, guid = "GameObject-0-1-2-3-4-5" } }
      fire("LOOT_READY"); fire("LOOT_SLOT_CLEARED", 1); loot = {}; fire("LOOT_CLOSED")""")
    d = db(lua)
    assert d["gold"]["herb"] == 2000 and d["gold"]["loot"] == 0
    print("ok test_herb_gathering")


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
    # A translation may only use keys that exist in English, with the same %d placeholders.
    texts = {}
    for locale in ("enUS", "deDE", "frFR"):
        lua = new_runtime(locale)
        texts[locale] = lua_to_py(load_addon(lua).L)
    assert texts["frFR"] == texts["enUS"], "an unknown locale falls back to English"
    assert texts["deDE"].keys() == texts["enUS"].keys()
    assert texts["deDE"]["perHour"] == "pro Stunde" and texts["enUS"]["perHour"] == "per hour"
    for key, text in texts["enUS"].items():
        assert re.findall(r"%[ds]", text) == re.findall(r"%[ds]", texts["deDE"][key]), key

    # A German client prints German.
    lua = new_runtime("deDE")
    load_addon(lua)
    lua.execute('fire("PLAYER_ENTERING_WORLD", true, false)')
    lua.globals().SlashCmdList.GOLDPERHOUR("herbid 99")
    lua.globals().SlashCmdList.GOLDPERHOUR("nonsense")
    out = printed(lua)
    assert any("Zauber 99 zählt jetzt als Kräutersammeln" in p for p in out), out
    assert any("<ZauberID>" in p for p in out), out
    print("ok test_locales")


def test_window_states():
    lua = new_runtime()
    ui = load_addon(lua).ui
    lua.globals().UI = ui
    lua.execute('fire("PLAYER_ENTERING_WORLD", true, false)')

    def refresh(seconds=0):
        lua.execute(f"now = now + {seconds}; UI.frame.scripts.OnUpdate(UI.frame, 1)")

    # Not started: a hint instead of the session, nothing to reset, the play button.
    refresh()
    assert ui.state == "idle", ui.state
    assert "Press start to count your gold" in ui.session.text and ui.clock.text == ""
    assert "--" in ui.perHour.text and ui.perHourLabel.text == "per hour"
    assert ui.reset.enabled is False and ui.toggle.normal.endswith("NextPage-Up")
    assert ui.bars.herb.value == 0 and ui.bars.loot.value == 0

    # The play button starts the session; within the first minute the gold per hour waits.
    lua.execute("UI.toggle.scripts.OnClick(UI.toggle)")
    mob_loot(lua)
    refresh(30)
    assert ui.state == "running" and db(lua)["elapsed"] == 0
    assert ui.toggle.normal.endswith("PauseButton") and ui.reset.enabled is True
    assert "--" in ui.perHour.text and ui.perHourLabel.text == "per hour after 1 minute"
    assert "0:00:30" in ui.clock.text and "3500" in ui.session.text
    assert ui.bars.loot.value == 1 and ui.bars.loot.amount.text.startswith("3500 ") and "100%" in ui.bars.loot.amount.text
    assert ui.bars.herb.value == 0 and "-" in ui.bars.herb.amount.text

    # After a minute: 3500 copper in 90 s is 140000 copper per hour.
    refresh(60)
    assert ui.perHour.text == "140000" and ui.perHourLabel.text == "per hour", ui.perHour.text

    # Herbs and loot split the bars by their share of the total.
    lua.execute("""fire("UNIT_SPELLCAST_SENT", "player", nil, nil, 2366)
      loot = { { link = LINK, qty = 1, guid = "GameObject-0-1-2-3-4-5" } }
      fire("LOOT_READY"); fire("LOOT_SLOT_CLEARED", 1); loot = {}; fire("LOOT_CLOSED")""")
    refresh()
    assert abs(ui.bars.herb.value - 1000 / 4500) < 1e-9 and "22%" in ui.bars.herb.amount.text
    assert "78%" in ui.bars.loot.amount.text

    # Tooltips of the window, a bar and the buttons build without errors.
    lua.execute("""UI.frame.scripts.OnEnter(UI.frame, true); UI.bars.herb.scripts.OnEnter(UI.bars.herb, true)
      UI.toggle.scripts.OnEnter(UI.toggle, true); UI.reset.scripts.OnEnter(UI.reset, true)
      UI.close.scripts.OnEnter(UI.close, true)""")

    # The pause button stops the clock; the window says so.
    lua.execute("UI.toggle.scripts.OnClick(UI.toggle)")
    refresh(100)
    assert ui.state == "paused" and db(lua)["elapsed"] == 90
    assert "Paused" in ui.clock.text and "1:30" in ui.clock.text and ui.toggle.normal.endswith("NextPage-Up")

    # Slash commands drive the same window: a reset goes back to idle.
    lua.globals().SlashCmdList.GOLDPERHOUR("reset")
    assert ui.state == "idle" and ui.reset.enabled is False and len(values(db(lua)["history"])) == 1
    lua.globals().SlashCmdList.GOLDPERHOUR("start")
    assert ui.state == "running"

    # The close button hides the window like /gph hide.
    lua.execute("UI.close.scripts.OnClick(UI.close)")
    assert db(lua)["hidden"] is True and ui.frame.shown is False

    # With autoStart the hint says that loot starts the session, in German on a German client.
    lua = new_runtime("deDE")
    lua.execute('GoldPerHourDB = { settings = { autoStart = true } }')
    ui = load_addon(lua).ui
    lua.globals().UI = ui
    lua.execute('fire("PLAYER_ENTERING_WORLD", true, false); UI.frame.scripts.OnUpdate(UI.frame, 1)')
    assert "Etwas looten oder Start drücken" in ui.session.text, ui.session.text
    mob_loot(lua, qty=1, coins=0)
    lua.execute("UI.frame.scripts.OnUpdate(UI.frame, 1)")
    assert ui.state == "running" and "Sitzung" in ui.session.text
    lua.execute("UI.toggle.scripts.OnClick(UI.toggle); UI.frame.scripts.OnUpdate(UI.frame, 1)")
    assert "Pausiert" in ui.clock.text
    print("ok test_window_states")


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
    test_herb_gathering()
    test_login_does_not_resume()
    test_locales()
    test_window_states()
    test_toc()
    if "--dump" in sys.argv:
        target = sys.argv[sys.argv.index("--dump") + 1]
        text = final.execute(SERIALIZE)("GoldPerHourDB", final.globals().GoldPerHourDB)
        os.makedirs(os.path.dirname(os.path.abspath(target)), exist_ok=True)
        with open(target, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n" + text)
        print(f"written: {target}")
