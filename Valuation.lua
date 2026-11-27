-- Item valuation: non-auctionable detection, Auctionator lookup, 5% AH cut, vendor floor and BoE threshold.
local ADDON, ns = ...

-- Enum.ItemBind values that can never be posted on the auction house:
-- 1 = OnAcquire (BoP), 4 = Quest, 7 = ToWoWAccount, 8 = ToBnetAccount, 9 = ToBnetAccountUntilEquipped
local NON_AUCTIONABLE_BIND = { [1] = true, [4] = true, [7] = true, [8] = true, [9] = true }

-- Enum.ItemClass values that cannot be auctioned: 10 = CurrencyToken, 12 = Questitem, 13 = Key
local NON_AUCTIONABLE_CLASS = { [10] = true, [12] = true, [13] = true }

-- Weapon (2) and Armor (4) for the optional BoE minimum value threshold.
local EQUIP_CLASS = { [2] = true, [4] = true }

local AH_CUT = 0.05

-- Midnight hands some values to addons as opaque "secrets"; never compare those.
function ns.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

function ns.AuctionatorAPI()
    return Auctionator and Auctionator.API and Auctionator.API.v1
end

function ns.AuctionPrice(link)
    local api = ns.AuctionatorAPI()
    if not api then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemLink, ADDON, link)
    if ok and type(price) == "number" and price > 0 then return price end
    return nil
end

function ns.IsAuctionable(link, quality, classID, bindType)
    if quality == 0 then return false end
    if bindType and NON_AUCTIONABLE_BIND[bindType] then return false end
    if classID and NON_AUCTIONABLE_CLASS[classID] then return false end
    if C_Item then
        if C_Item.IsItemBindToAccount then
            local ok, bound = pcall(C_Item.IsItemBindToAccount, link)
            if ok and bound then return false end
        end
        if C_Item.IsItemBindToAccountUntilEquipped then
            local ok, bound = pcall(C_Item.IsItemBindToAccountUntilEquipped, link)
            if ok and bound then return false end
        end
    end
    return true
end

-- Only call once the item data is loaded.
-- Returns: value (copper), vendorPrice (copper), quality, source ("auctionator" | "vendor").
function ns.ItemValue(link)
    local _, _, quality, _, _, _, _, _, _, _, sellPrice, classID, _, bindType = C_Item.GetItemInfo(link)
    sellPrice = sellPrice or 0
    if ns.Setting("priceSource") == "vendor" or not ns.IsAuctionable(link, quality, classID, bindType) then
        return sellPrice, sellPrice, quality, "vendor"
    end
    local ah = ns.AuctionPrice(link)
    if not ah then
        return sellPrice, sellPrice, quality, "vendor"
    end
    local minVal = ns.Setting("ahMinValue") or 0
    if minVal > 0 and classID and EQUIP_CLASS[classID] and ah < minVal then
        return sellPrice, sellPrice, quality, "vendor"
    end
    local effective = ns.Setting("deductAhCut") and math.floor(ah * (1 - AH_CUT) + 0.5) or ah
    if ns.Setting("vendorFloor") and sellPrice >= effective then
        return sellPrice, sellPrice, quality, "vendor"
    end
    return effective, sellPrice, quality, "auctionator"
end
