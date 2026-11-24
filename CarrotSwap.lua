-- CarrotSwap
-- Mount up -> equip Carrot on a Stick in a trinket slot (remembering what was there).
-- Dismount -> put the remembered trinket back.
-- The game doesn't allow gear swaps in combat, so a swap that comes up mid-fight
-- waits and happens as soon as combat ends.

local ADDON_NAME = ...
local DEFAULT_ITEM = 11122       -- Carrot on a Stick
local DEFAULT_NAME = "Carrot on a Stick"

local db, cdb       -- account settings, per-character state
local wasMounted
local pending       -- "mount" or "dismount" waiting for combat to end
local lastTry = 0
local toldCombat = false

local function Print(msg)
	if db and db.quiet and not msg:find("^|cffff") then return end
	print("|cffff9933CarrotSwap|r: " .. msg)
end

local function Warn(msg)
	print("|cffff9933CarrotSwap|r: |cffff6060" .. msg .. "|r")
end

local function ItemName(id)
	if not id then return "?" end
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
	return name or ("item " .. id)
end

local function ItemLink(id)
	if not id then return "?" end
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local _, link = getInfo(id)
	return link or ItemName(id)
end

-- Is the item in your bags? (equipping needs it there)
local function InBags(itemID)
	local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
	for bag = 0, lastBag do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			if C_Container.GetContainerItemID(bag, slot) == itemID then return true end
		end
	end
	return false
end

local function CarrotID()
	return db.itemID or DEFAULT_ITEM
end

local function Equipped(slot)
	return GetInventoryItemID("player", slot)
end

local function IsMountedNow()
	return IsMounted() and not (UnitOnTaxi and UnitOnTaxi("player"))
end

local function CanSwap()
	return not InCombatLockdown() and not UnitAffectingCombat("player")
		and not UnitIsDeadOrGhost("player") and not (CursorHasItem and CursorHasItem())
end

------------------------------------------------------------------------
-- The swaps
------------------------------------------------------------------------

-- Forever's client moved EquipItemByName into C_Item; older clients have the global.
local EquipFn = (C_Item and C_Item.EquipItemByName) or EquipItemByName
local warnedNoEquip = false

-- Returns true if the equip call went through.
local function Equip(itemID, slot)
	if not EquipFn then
		if not warnedNoEquip then
			warnedNoEquip = true
			Warn("this game client has no way for addons to equip items, so CarrotSwap can't swap.")
		end
		return false
	end
	local ok, err = pcall(EquipFn, itemID, slot)
	if not ok then
		Warn("couldn't equip " .. ItemLink(itemID) .. ": " .. tostring(err))
		return false
	end
	return true
end

local function Debug(msg)
	if db and db.debug then print("|cffff9933CarrotSwap|r |cff888888[debug]|r " .. msg) end
end

local function Trinkets()
	return ("top=%s bottom=%s"):format(ItemName(Equipped(13)), ItemName(Equipped(14)))
end

-- Which trinket slot is the carrot in right now (the game doesn't always use the slot we ask for)?
local function CarrotSlot()
	local c = CarrotID()
	if Equipped(13) == c then return 13 end
	if Equipped(14) == c then return 14 end
end

-- A swap we asked for and are waiting to see happen: { kind = "on"/"off", item, slot, at, tries }
local verify
local nextWatch = 0     -- next time the watchdog looks
local warnedFail = false

local function PutOnCarrot()
	local carrot = CarrotID()
	if CarrotSlot() then
		Debug("already wearing the carrot - nothing to do.")
		return true
	end
	if not InBags(carrot) then
		if not cdb.warnedMissing then
			cdb.warnedMissing = true
			Warn(ItemName(carrot) .. " isn't in your bags, so there's nothing to swap in.")
		end
		return true
	end
	if not CanSwap() then return false end

	-- Remember both trinkets, then see which one the carrot actually replaced.
	cdb.before = { [13] = Equipped(13), [14] = Equipped(14) }
	Debug("mounting: " .. Trinkets() .. " - equipping carrot into slot " .. db.slot)
	if not Equip(carrot, db.slot) then return true end
	verify = { kind = "on", item = carrot, slot = db.slot, at = GetTime(), tries = 1 }
	return true
end

local function PutBackTrinket()
	if not cdb.saved and not cdb.savedSlot then return true end
	local carrot = CarrotID()
	local slot = CarrotSlot()
	if not slot then
		-- Carrot already off (you changed gear yourself, or it's already been swapped back).
		Debug("dismounting: carrot isn't on (" .. Trinkets() .. ") - forgetting saved trinket.")
		cdb.saved, cdb.savedSlot = nil, nil
		return true
	end
	if not cdb.saved then
		-- The slot was empty before; just take the carrot off.
		if not CanSwap() then return false end
		if not (PickupInventoryItem and PutItemInBackpack) then return true end
		pcall(PickupInventoryItem, slot)
		if CursorHasItem() then pcall(PutItemInBackpack) end
		cdb.savedSlot = nil
		Print("dismounted - " .. ItemName(carrot) .. " off.")
		return true
	end
	if not InBags(cdb.saved) then
		Warn("can't find " .. ItemLink(cdb.saved) .. " in your bags to put back. Leaving the carrot on.")
		cdb.saved, cdb.savedSlot = nil, nil
		return true
	end
	if not CanSwap() then return false end
	Debug("dismounting: " .. Trinkets() .. " - putting " .. ItemName(cdb.saved) .. " into slot " .. slot)
	if not Equip(cdb.saved, slot) then return true end
	verify = { kind = "off", item = cdb.saved, slot = slot, at = GetTime(), tries = 1 }
	return true
end

-- Check that a swap we asked for really happened; retry a couple of times if not.
local function CheckVerify()
	if GetTime() - verify.at < 0.6 then return end
	local v = verify
	if v.kind == "on" then
		local slot = CarrotSlot()
		if slot then
			verify = nil
			local replaced = cdb.before and cdb.before[slot]
			cdb.saved, cdb.savedSlot, cdb.before = replaced, slot, nil
			Debug("carrot is on in slot " .. slot .. ", saved " .. ItemName(replaced))
			warnedFail = false
			Print("mounted - " .. ItemLink(v.item) .. " on" .. (replaced and (", " .. ItemLink(replaced) .. " saved.") or "."))
			return
		end
	else
		if Equipped(v.slot) == v.item or (not CarrotSlot() and (Equipped(13) == v.item or Equipped(14) == v.item)) then
			verify = nil
			cdb.saved, cdb.savedSlot = nil, nil
			warnedFail = false
			Debug("put back OK: " .. Trinkets())
			Print("dismounted - " .. ItemLink(v.item) .. " back on.")
			return
		end
	end
	if (v.kind == "on" and not IsMountedNow()) or (v.kind == "off" and IsMountedNow()) then
		verify = nil -- you changed mount state again; Update() will handle it
		return
	end
	if not CanSwap() then
		verify = nil
		pending = v.kind == "on" and "mount" or "dismount"
		return
	end
	if v.tries >= 3 then
		verify = nil
		nextWatch = GetTime() + 15 -- back off before the watchdog tries again
		if warnedFail then return end
		warnedFail = true
		Warn("the game didn't let me swap " .. ItemLink(v.item) .. " yet (" .. Trinkets() .. "). I'll keep trying every few seconds.")
		return
	end
	v.tries, v.at = v.tries + 1, GetTime()
	Debug("swap didn't take yet (" .. Trinkets() .. "), retry " .. v.tries)
	Equip(v.item, v.slot)
end

-- Watchdog: every couple of seconds (out of combat) make sure you're wearing what you
-- should be - carrot while mounted, your normal trinket on foot - and fix it if not.
local function Watchdog()
	if GetTime() < nextWatch then return end
	nextWatch = GetTime() + 2
	if not CanSwap() then return end
	local carrot = CarrotID()
	local cslot = CarrotSlot()
	if IsMountedNow() then
		if not cslot and InBags(carrot) then
			Debug("check: mounted but the carrot isn't on (" .. Trinkets() .. ") - fixing.")
			pending = "mount"
		end
	elseif cslot then
		-- On foot wearing the carrot. If the saved trinket got lost, fall back to the
		-- trinket you normally wear in that slot.
		local normal = cdb.normal and cdb.normal[cslot]
		if not cdb.saved and normal and normal ~= carrot and InBags(normal) then
			cdb.saved, cdb.savedSlot = normal, cslot
		end
		if cdb.saved and InBags(cdb.saved) then
			Debug("check: on foot still wearing the carrot (" .. Trinkets() .. ") - fixing.")
			pending = "dismount"
		end
	else
		-- On foot, carrot off: remember your normal trinkets.
		cdb.normal = { [13] = Equipped(13), [14] = Equipped(14) }
	end
end

local function Update()
	if not db or not db.enabled then return end
	local mounted = IsMountedNow()
	if mounted ~= wasMounted then
		wasMounted = mounted
		pending = mounted and "mount" or "dismount"
		Debug(mounted and "mounted." or "dismounted.")
	end
	if verify then CheckVerify() return end
	if not pending then
		Watchdog()
		if not pending then return end
	end

	-- Don't hammer the server if a swap keeps failing.
	if GetTime() - lastTry < 0.5 then return end
	lastTry = GetTime()

	local done
	if pending == "mount" then
		-- If you dismounted again before it could happen, skip it.
		if not mounted then pending = nil return end
		done = PutOnCarrot()
	else
		if mounted then pending = nil return end
		done = PutBackTrinket()
	end
	if done then
		pending = nil
	elseif InCombatLockdown() or UnitAffectingCombat("player") then
		if not toldCombat then
			toldCombat = true
			Print("in combat - I'll swap your trinket as soon as combat ends.")
		end
	else
		Debug("can't swap right now (dead, or an item on the cursor?) - will keep trying.")
	end
end

------------------------------------------------------------------------
-- Events & polling
------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
f:RegisterUnitEvent("UNIT_AURA", "player")
f:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then return end
		CarrotSwapDB = CarrotSwapDB or {}
		CarrotSwapCharDB = CarrotSwapCharDB or {}
		db, cdb = CarrotSwapDB, CarrotSwapCharDB
		if db.enabled == nil then db.enabled = true end
		if db.slot ~= 13 and db.slot ~= 14 then db.slot = 14 end
		self:UnregisterEvent("ADDON_LOADED")
		return
	end
	if event == "PLAYER_ENTERING_WORLD" then
		-- After a reload/login: if you're on foot but still wearing the carrot from
		-- last time, put the saved trinket back.
		wasMounted = IsMountedNow()
		if not wasMounted and cdb.saved then pending = "dismount" end
	elseif event == "PLAYER_REGEN_ENABLED" then
		toldCombat = false
		lastTry = 0
	end
	Update()
end)

-- Mounting doesn't always fire a clean event, so also check a few times a second.
local elapsed = 0
f:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed < 0.25 then return end
	elapsed = 0
	Update()
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------

SLASH_CARROTSWAP1 = "/carrot"
SLASH_CARROTSWAP2 = "/carrotswap"
SlashCmdList.CARROTSWAP = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()

	if cmd == "on" or cmd == "off" then
		db.enabled = (cmd == "on")
		print("|cffff9933CarrotSwap|r: " .. (db.enabled and "on." or "off."))
	elseif cmd == "slot" then
		local n = tonumber(rest)
		if n == 1 or n == 13 then db.slot = 13
		elseif n == 2 or n == 14 then db.slot = 14
		else print("|cffff9933CarrotSwap|r: usage: /carrot slot 1 (top trinket) or 2 (bottom trinket)") return end
		print("|cffff9933CarrotSwap|r: swapping the " .. (db.slot == 13 and "top (first)" or "bottom (second)") .. " trinket slot.")
	elseif cmd == "item" then
		local id = tonumber(rest:match("item:(%d+)") or rest)
		if rest == "" or rest:lower() == "reset" then
			db.itemID = nil
			print("|cffff9933CarrotSwap|r: back to " .. DEFAULT_NAME .. ".")
		elseif id then
			db.itemID = id
			cdb.warnedMissing = nil
			print("|cffff9933CarrotSwap|r: mount trinket is now " .. ItemLink(id) .. ".")
		else
			print("|cffff9933CarrotSwap|r: usage: /carrot item <shift-click a trinket>   or   /carrot item reset")
		end
	elseif cmd == "back" then
		if IsMountedNow() then print("|cffff9933CarrotSwap|r: dismount first.") return end
		if not cdb.saved then print("|cffff9933CarrotSwap|r: I'm not holding a trinket to put back.") return end
		lastTry, pending = 0, "dismount"
		Update()
	elseif cmd == "debug" then
		db.debug = not db.debug
		print("|cffff9933CarrotSwap|r: debug " .. (db.debug and "on - I'll explain each swap in chat." or "off."))
		if db.debug then print("  now: " .. Trinkets() .. ", holding " .. (cdb.saved and ItemName(cdb.saved) or "nothing") .. (cdb.savedSlot and (" for slot " .. cdb.savedSlot) or "")) end
	elseif cmd == "quiet" then
		db.quiet = not db.quiet
		print("|cffff9933CarrotSwap|r: swap messages " .. (db.quiet and "off." or "on."))
	else
		local saved = cdb.saved and ItemLink(cdb.saved) or "nothing"
		print("|cffff9933CarrotSwap|r: " .. (db.enabled and "|cff40ff40on|r" or "|cffff4040off|r")
			.. " - " .. ItemLink(CarrotID()) .. " goes in the "
			.. (db.slot == 13 and "top" or "bottom") .. " trinket slot. Holding: " .. saved .. ".")
		print("  /carrot on||off   /carrot slot 1||2   /carrot item <link>||reset   /carrot back   /carrot quiet   /carrot debug")
	end
end
